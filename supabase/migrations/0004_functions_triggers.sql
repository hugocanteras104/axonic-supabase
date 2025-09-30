-- Función helper para actualizar 'updated_at'
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
new.updated_at := now();
return new;
end $$;

-- Triggers para set_updated_at en tablas con columna 'updated_at'
drop trigger if exists trg_upd_profiles on public.profiles;
create trigger trg_upd_profiles before update on public.profiles for each row execute function public.set_updated_at();

drop trigger if exists trg_upd_services on public.services;
create trigger trg_upd_services before update on public.services for each row execute function public.set_updated_at();

drop trigger if exists trg_upd_appts on public.appointments;
create trigger trg_upd_appts before update on public.appointments for each row execute function public.set_updated_at();

drop trigger if exists trg_upd_inv on public.inventory;
create trigger trg_upd_inv before update on public.inventory for each row execute function public.set_updated_at();

drop trigger if exists trg_upd_kb on public.knowledge_base;
create trigger trg_upd_kb before update on public.knowledge_base for each row execute function public.set_updated_at();

drop trigger if exists trg_upd_resources on public.resources;
create trigger trg_upd_resources before update on public.resources for each row execute function public.set_updated_at();

-- Trigger de cancelación de cita a cola de notificaciones
create or replace function public.on_appointment_cancelled()
returns trigger language plpgsql as $$
begin
if new.status = 'cancelled' and old.status <> 'cancelled' then
insert into public.notifications_queue (event_type, payload)
values (
'appointment_cancelled',
jsonb_build_object(
'appointment_id', new.id,
'service_id', new.service_id,
'start_time', new.start_time,
'end_time', new.end_time
)
);
end if;
return new;
end $$;

drop trigger if exists trg_on_appointment_cancelled on public.appointments;
create trigger trg_on_appointment_cancelled after update on public.appointments for each row execute function public.on_appointment_cancelled();

-- RPC: Obtener huecos disponibles (versión básica sin recursos)
create or replace function public.get_available_slots(p_service_id uuid, p_start timestamptz, p_end timestamptz, p_step_minutes int default 15)
returns table(slot_start timestamptz, slot_end timestamptz)
language plpgsql stable as $$
declare v_dur int; v_cursor timestamptz;
begin
select duration_minutes into v_dur from public.services where id = p_service_id;
if v_dur is null then raise exception 'Service not found'; end if;
if p_start >= p_end then raise exception 'Invalid window'; end if;
v_cursor := p_start;
while v_cursor + (v_dur || ' minutes')::interval <= p_end loop
if not exists (select 1 from public.appointments a where a.service_id = p_service_id and a.status = 'confirmed' and tstzrange(a.start_time, a.end_time, '[)') && tstzrange(v_cursor, v_cursor + (v_dur || ' minutes')::interval, '[)')) then
slot_start := v_cursor;
slot_end := v_cursor + (v_dur || ' minutes')::interval;
return next;
end if;
v_cursor := v_cursor + make_interval(mins => p_step_minutes);
end loop;
end $$;

-- RPC: Decremento de inventario seguro
create or replace function public.decrement_inventory(p_sku text, p_qty int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_item record;
begin
if p_qty is null or p_qty <= 0 then raise exception 'Quantity must be positive, got: %', p_qty; end if;
select * into v_item from public.inventory where sku = p_sku for update;
if not found then raise exception 'SKU % not found', p_sku; end if;
if v_item.quantity < p_qty then raise exception 'Insufficient stock for % (have %, need %)', p_sku, v_item.quantity, p_qty; end if;
update public.inventory set quantity = quantity - p_qty, updated_at = now() where id = v_item.id;
end $$;

-- RPC: Refrescar la Vista Materializada (sin CONCURRENTLY, para transacciones)
create or replace function public.refresh_metrics_historical()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
refresh materialized view public.metrics_historical; -- sin concurrently
end $$;

-- RPCs de Recursos
create or replace function public.get_available_slots_with_resources(p_service_id uuid, p_start timestamptz, p_end timestamptz, p_step_minutes int default 15)
returns table(slot_start timestamptz, slot_end timestamptz, available_resources jsonb)
language plpgsql stable as $$
declare v_dur int; v_cursor timestamptz; v_slot_end timestamptz; v_required_resources uuid[]; v_available_resources jsonb; v_all_available boolean;
begin
select duration_minutes into v_dur from public.services where id = p_service_id;
if v_dur is null then raise exception 'Service not found'; end if;
if p_start >= p_end then raise exception 'Invalid time window'; end if;
select array_agg(resource_id) into v_required_resources from public.service_resource_requirements where service_id = p_service_id and is_optional = false;

if v_required_resources is null or array_length(v_required_resources, 1) = 0 then
return query select * from public.get_available_slots(p_service_id, p_start, p_end, p_step_minutes);
return;
end if;

v_cursor := p_start;
while v_cursor + (v_dur || ' minutes')::interval <= p_end loop
v_slot_end := v_cursor + (v_dur || ' minutes')::interval;
v_all_available := true;
v_available_resources := '[]'::jsonb;
for i in 1..array_length(v_required_resources, 1) loop
if exists (select 1 from public.resource_blocks rb where rb.resource_id = v_required_resources[i] and tstzrange(rb.start_time, rb.end_time, '[)') && tstzrange(v_cursor, v_slot_end, '[)'))
or exists (select 1 from public.appointment_resources ar join public.appointments a on a.id = ar.appointment_id where ar.resource_id = v_required_resources[i] and a.status = 'confirmed' and tstzrange(a.start_time, a.end_time, '[)') && tstzrange(v_cursor, v_slot_end, '[)')) then
v_all_available := false;
exit;
else
select v_available_resources || jsonb_build_object('resource_id', r.id, 'name', r.name, 'type', r.type) into v_available_resources from public.resources r where r.id = v_required_resources[i];
end if;
end loop;

if v_all_available then
slot_start := v_cursor;
slot_end := v_slot_end;
available_resources := v_available_resources;
return next;
end if;
v_cursor := v_cursor + make_interval(mins => p_step_minutes);
end loop;
end $$;

create or replace function public.confirm_appointment_with_resources(p_appointment_id uuid, p_strategy text default 'first_available')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_appointment record; v_required record; v_assigned_resources jsonb := '[]'::jsonb;
begin
select * into v_appointment from public.appointments where id = p_appointment_id for update;
if not found then raise exception 'Appointment not found'; end if;
if v_appointment.status = 'confirmed' then raise exception 'Appointment already confirmed'; end if;

for v_required in select srr.resource_id, srr.quantity, r.name, r.type from public.service_resource_requirements srr join public.resources r on r.id = srr.resource_id where srr.service_id = v_appointment.service_id and srr.is_optional = false loop

if exists (select 1 from public.resource_blocks rb where rb.resource_id = v_required.resource_id and tstzrange(rb.start_time, rb.end_time, '[)') && tstzrange(v_appointment.start_time, v_appointment.end_time, '[)'))
or exists (select 1 from public.appointment_resources ar join public.appointments a on a.id = ar.appointment_id where ar.resource_id = v_required.resource_id and a.status = 'confirmed' and a.id != p_appointment_id and tstzrange(a.start_time, a.end_time, '[)') && tstzrange(v_appointment.start_time, v_appointment.end_time, '[)')) then
raise exception 'Resource % (%) is not available for the requested time slot', v_required.name, v_required.type;
end if;

insert into public.appointment_resources (appointment_id, resource_id) values (p_appointment_id, v_required.resource_id);
v_assigned_resources := v_assigned_resources || jsonb_build_object('resource_id', v_required.resource_id, 'name', v_required.name, 'type', v_required.type);
end loop;

update public.appointments set status = 'confirmed', updated_at = now() where id = p_appointment_id;
return jsonb_build_object('appointment_id', p_appointment_id, 'status', 'confirmed', 'assigned_resources', v_assigned_resources);
end $$;
