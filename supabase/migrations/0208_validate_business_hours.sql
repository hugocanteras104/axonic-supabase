-- ===============================================
-- Migration: 0208_validate_business_hours.sql
-- Purpose: Enforce business-hour scheduling for appointments
-- Dependencies: 0203_business_settings.sql
-- ===============================================

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

raise notice '========================================';
raise notice 'Migración 0208_validate_business_hours completada';
raise notice '========================================';
