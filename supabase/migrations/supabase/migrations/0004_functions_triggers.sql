-- 0004_functions_triggers.sql
-- Funciones y triggers de uso general (idempotentes)

-- ==========================================
-- 1) Trigger helper: actualizar updated_at
-- ==========================================
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  -- Asume que la tabla tiene columna updated_at
  new.updated_at := now();
  return new;
end;
$$;

-- Triggers updated_at (solo en tablas que lo tienen)
drop trigger if exists trg_profiles_touch_updated_at on public.profiles;
create trigger trg_profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists trg_services_touch_updated_at on public.services;
create trigger trg_services_touch_updated_at
before update on public.services
for each row execute function public.touch_updated_at();

drop trigger if exists trg_appointments_touch_updated_at on public.appointments;
create trigger trg_appointments_touch_updated_at
before update on public.appointments
for each row execute function public.touch_updated_at();

drop trigger if exists trg_inventory_touch_updated_at on public.inventory;
create trigger trg_inventory_touch_updated_at
before update on public.inventory
for each row execute function public.touch_updated_at();

drop trigger if exists trg_resources_touch_updated_at on public.resources;
create trigger trg_resources_touch_updated_at
before update on public.resources
for each row execute function public.touch_updated_at();

drop trigger if exists trg_resource_blocks_touch_updated_at on public.resource_blocks;
create trigger trg_resource_blocks_touch_updated_at
before update on public.resource_blocks
for each row execute function public.touch_updated_at();

drop trigger if exists trg_kb_touch_updated_at on public.knowledge_base;
create trigger trg_kb_touch_updated_at
before update on public.knowledge_base
for each row execute function public.touch_updated_at();

-- ======================================================
-- 2) Notificaciones por cambios de estado en CITAS
--    Inserta en notifications_queue para que el orquestador (n8n) lo recoja
-- ======================================================
create or replace function public.enqueue_appointment_status_notification()
returns trigger
language plpgsql
as $$
declare
  v_event text;
begin
  if (tg_op = 'UPDATE') and (new.status is distinct from old.status) then
    if new.status = 'cancelled' then
      v_event := 'appointment_cancelled';
    elsif new.status = 'confirmed' then
      v_event := 'appointment_confirmed';
    else
      -- Otros estados no generan evento
      return new;
    end if;

    insert into public.notifications_queue(event_type, payload)
    values(
      v_event,
      jsonb_build_object(
        'appointment_id', new.id,
        'profile_id', new.profile_id,
        'service_id', new.service_id,
        'previous_status', old.status,
        'current_status', new.status,
        'start_time', new.start_time,
        'end_time', new.end_time,
        'at', now()
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_appt_status_notify on public.appointments;
create trigger trg_appt_status_notify
after update of status on public.appointments
for each row execute function public.enqueue_appointment_status_notification();

-- ======================================================
-- 3) RPC get_available_slots: huecos por día (simple)
--    - Filtra solapes con citas CONFIRMED
--    - Ventana horaria configurable (por defecto 09:00–19:00)
--    - Granularidad configurable (por defecto 30 min)
--    Nota: no tiene en cuenta el módulo de recursos (eso va en 0006).
-- ======================================================
create or replace function public.get_available_slots(
  p_service_id uuid,
  p_day date,
  p_slot_minutes int default 30,
  p_open time without time zone default '09:00',
  p_close time without time zone default '19:00'
)
returns table (start_time timestamptz, end_time timestamptz)
language sql
stable
as $$
  with params as (
    select
      (p_day + p_open) at time zone 'UTC' as day_open_utc,
      (p_day + p_close) at time zone 'UTC' as day_close_utc
  ),
  grid as (
    select
      generate_series(
        (select day_open_utc from params),
        (select day_close_utc from params) - make_interval(mins => p_slot_minutes),
        make_interval(mins => p_slot_minutes)
      ) as slot_start
  ),
  slots as (
    select
      g.slot_start as start_time,
      g.slot_start + make_interval(mins => p_slot_minutes) as end_time
    from grid g
  ),
  busy as (
    select a.start_time, a.end_time
    from public.appointments a
    where a.status = 'confirmed'
      and a.start_time::date = p_day
  )
  select s.start_time, s.end_time
  from slots s
  where not exists (
    select 1
    from busy b
    where tstzrange(b.start_time, b.end_time, '[)') &&
          tstzrange(s.start_time, s.end_time, '[)')
  )
  order by s.start_time;
$$;

-- ======================================================
-- 4) RPC decrement_inventory: resta stock por SKU
-- ======================================================
create or replace function public.decrement_inventory(p_sku text, p_units int)
returns public.inventory
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.inventory;
begin
  if p_units is null or p_units <= 0 then
    raise exception 'p_units debe ser > 0';
  end if;

  update public.inventory
  set quantity = greatest(0, quantity - p_units),
      updated_at = now()
  where sku = p_sku
  returning * into v_row;

  if v_row.id is null then
    raise exception 'SKU % no encontrado en inventory', p_sku
      using errcode = 'NO_DATA_FOUND';
  end if;

  return v_row;
end;
$$;

-- ======================================================
-- 5) Permisos de funciones (GRANT/REVOKE)
--    Ajusta según tus roles de Supabase (anon/authenticated/service_role)
-- ======================================================
revoke all on function public.get_available_slots(uuid, date, int, time without time zone, time without time zone) from public;
revoke all on function public.decrement_inventory(text, int) from public;

grant execute on function public.get_available_slots(uuid, date, int, time without time zone, time without time zone) to authenticated;
grant execute on function public.decrement_inventory(text, int) to authenticated;

-- Fin 0004
