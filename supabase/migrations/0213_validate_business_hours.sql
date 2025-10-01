-- ===============================================
-- Migration: 0213_validate_business_hours.sql
-- Purpose: Enforce business-hour scheduling for appointments
-- Dependencies: 0208_business_settings.sql
-- ===============================================

-- Verificar dependencias
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'is_within_business_hours') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función is_within_business_hours()\nAplicar primero: 0208_business_settings.sql';
  end if;
  
  if not exists (select 1 from pg_tables where tablename = 'business_settings') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: tabla business_settings\nAplicar primero: 0208_business_settings.sql';
  end if;
  
  raise notice '✅ Dependencias verificadas';
end $$;

begin;

-- Ensure appointments respect configured business hours
alter table public.appointments
  drop constraint if exists appt_within_business_hours;

alter table public.appointments
  add constraint appt_within_business_hours
  check (
    public.is_within_business_hours(business_id, start_time)
    and public.is_within_business_hours(
      business_id,
      case
        when end_time is null or end_time <= start_time then start_time
        else end_time - interval '1 second'
      end
    )
  );

comment on constraint appt_within_business_hours on public.appointments is
  'Las citas deben comenzar y finalizar dentro del horario laboral configurado del negocio.';

commit;

