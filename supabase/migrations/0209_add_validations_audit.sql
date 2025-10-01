-- ===============================================
-- Migration: 0209_add_validations_audit.sql
-- Purpose: Agregar validaciones de negocio y auditoría de cancelaciones
-- Dependencies: 0208_business_settings.sql
-- ===============================================

-- Verificar dependencias
do $$
begin
  if not exists (select 1 from pg_tables where tablename = 'business_settings') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: tabla business_settings\nAplicar primero: 0208_business_settings.sql';
  end if;
  
  raise notice '✅ Dependencias verificadas';
end $$;

begin;

alter table public.appointments 
  drop constraint if exists appt_future_only;

alter table public.appointments 
  add constraint appt_future_only 
  check (start_time >= current_timestamp - interval '1 hour');

comment on constraint appt_future_only on public.appointments is
  'Las citas deben agendarse para el futuro (con 1 hora de margen)';

raise notice '[1/6] Validación: citas futuras';

alter table public.services 
  drop constraint if exists services_price_reasonable;

alter table public.services 
  add constraint services_price_reasonable 
  check (base_price between 0.01 and 10000);

comment on constraint services_price_reasonable on public.services is
  'Precio debe estar entre 0.01 y 10,000 para evitar errores';

raise notice '[2/6] Validación: precios de servicios';

alter table public.appointments 
  add column if not exists cancelled_by uuid references public.profiles(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;

comment on column public.appointments.cancelled_by is 'Usuario que canceló la cita';
comment on column public.appointments.cancelled_at is 'Fecha y hora de cancelación';
comment on column public.appointments.cancellation_reason is 'Motivo de cancelación';

create index if not exists idx_appointments_cancelled 
  on public.appointments(cancelled_at desc) 
  where cancelled_at is not null;

raise notice '[3/6] Columnas de auditoría agregadas';

create or replace function public.log_cancellation() 
returns trigger 
language plpgsql 
security definer 
set search_path = public
as $$
declare
  v_user_id uuid;
  v_claims jsonb;
begin
  if new.status = 'cancelled' and old.status != 'cancelled' then
    v_claims := auth.jwt();

    begin
      if v_claims is not null and v_claims ? 'sub' then
        v_user_id := nullif(v_claims->>'sub', '')::uuid;
      else
        v_user_id := null;
      end if;
    exception when others then
      v_user_id := null;
    end;

    new.cancelled_at := now();
    new.cancelled_by := v_user_id;
    
    if new.cancellation_reason is null or trim(new.cancellation_reason) = '' then
      new.cancellation_reason := 'No especificada';
    end if;
    
    insert into public.audit_logs (
      business_id,
      profile_id,
      action,
      payload
    ) values (
      new.business_id,
      v_user_id,
      'appointment_cancelled',
      jsonb_build_object(
        'appointment_id', new.id,
        'service_id', new.service_id,
        'start_time', new.start_time,
        'cancelled_at', now(),
        'reason', new.cancellation_reason
      )
    );
  end if;
  
  return new;
end;
$$;

drop trigger if exists on_appointment_cancelled on public.appointments;
create trigger on_appointment_cancelled
  before update on public.appointments
  for each row
  execute function public.log_cancellation();

comment on function public.log_cancellation is
  'Registra automáticamente quién canceló una cita y cuándo';

raise notice '[4/6] Trigger de auditoría de cancelaciones creado';

alter table public.appointments 
  add column if not exists deposit_required numeric(10,2) default 0 check (deposit_required >= 0),
  add column if not exists deposit_paid numeric(10,2) default 0 check (deposit_paid >= 0);

comment on column public.appointments.deposit_required is 'Monto de depósito requerido';
comment on column public.appointments.deposit_paid is 'Monto de depósito pagado';

alter table public.appointments 
  drop constraint if exists appt_deposit_not_exceed;

alter table public.appointments 
  add constraint appt_deposit_not_exceed 
  check (deposit_paid <= deposit_required);

raise notice '[5/6] Columnas de depósito agregadas';

create or replace function public.calculate_deposit_required()
returns trigger
language plpgsql
as $$
declare
  v_service_price numeric(10,2);
  v_pricing_rules jsonb;
  v_deposit_threshold numeric(10,2);
  v_deposit_percentage numeric;
begin
  select base_price into v_service_price
  from public.services
  where id = new.service_id
    and business_id = new.business_id;
  
  if v_service_price is null then
    new.deposit_required := 0;
    return new;
  end if;
  
  select setting_value into v_pricing_rules
  from public.business_settings
  where business_id = new.business_id
    and setting_key = 'pricing_rules';
  
  if v_pricing_rules is null then
    new.deposit_required := 0;
    return new;
  end if;
  
  v_deposit_threshold := coalesce((v_pricing_rules->>'deposit_required_above')::numeric, 100);
  v_deposit_percentage := coalesce((v_pricing_rules->>'deposit_percentage')::numeric, 30);
  
  if v_service_price >= v_deposit_threshold then
    new.deposit_required := round((v_service_price * v_deposit_percentage / 100), 2);
  else
    new.deposit_required := 0;
  end if;
  
  return new;
end;
$$;

drop trigger if exists trg_calculate_deposit on public.appointments;
create trigger trg_calculate_deposit
  before insert or update of service_id on public.appointments
  for each row
  execute function public.calculate_deposit_required();

comment on function public.calculate_deposit_required is
  'Calcula automáticamente el depósito requerido basándose en las reglas de pricing del negocio';

raise notice '[6/6] Trigger de cálculo de depósitos creado';

commit;

raise notice '========================================';
raise notice 'Migración 0204_add_validations_audit completada';
raise notice 'Validaciones y auditoría implementadas';
raise notice '========================================';
