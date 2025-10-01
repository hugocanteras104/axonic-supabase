-- ===============================================
-- Migration: 0213_validate_business_hours.sql
-- Purpose: Validar horarios de negocio solo para citas nuevas
-- Dependencies: 0208_business_settings.sql
-- ===============================================

do $$
begin
  if not exists (select 1 from pg_tables where tablename = 'business_settings') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: tabla business_settings\nAplicar primero: 0208_business_settings.sql';
  end if;
  
  if not exists (select 1 from pg_proc where proname = 'is_within_business_hours') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función is_within_business_hours()\nAplicar primero: 0208_business_settings.sql';
  end if;
  
  raise notice '✅ Dependencias verificadas';
end $$;

begin;

-- NO usar constraint porque valida datos históricos
-- En su lugar, usar trigger que solo valida INSERT/UPDATE

create or replace function public.validate_appointment_business_hours_trigger()
returns trigger
language plpgsql
as $$
begin
  -- Solo validar en INSERT o si cambian los horarios
  if (TG_OP = 'INSERT') or (NEW.start_time != OLD.start_time) or (NEW.end_time != OLD.end_time) then
    
    -- Validar que start_time esté dentro del horario
    if not public.is_within_business_hours(NEW.business_id, NEW.start_time) then
      raise exception 'La hora de inicio (%) está fuera del horario de negocio', NEW.start_time;
    end if;
    
    -- Validar que end_time esté dentro del horario
    if not public.is_within_business_hours(
      NEW.business_id,
      NEW.end_time - interval '1 second'
    ) then
      raise exception 'La hora de fin (%) está fuera del horario de negocio', NEW.end_time;
    end if;
    
  end if;
  
  return NEW;
end;
$$;

drop trigger if exists trg_validate_business_hours on public.appointments;
create trigger trg_validate_business_hours
  before insert or update on public.appointments
  for each row
  execute function public.validate_appointment_business_hours_trigger();

comment on function public.validate_appointment_business_hours_trigger is
  'Valida que las citas nuevas o reagendadas estén dentro del horario configurado. No afecta datos históricos.';

commit;
