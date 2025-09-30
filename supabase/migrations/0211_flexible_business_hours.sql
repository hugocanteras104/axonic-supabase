-- ===============================================
-- Migration: 0211_flexible_business_hours.sql
-- Purpose: Validación flexible de horarios - solo aplica al crear citas
-- Dependencies: 0208_validate_business_hours.sql
-- ===============================================

begin;

-- Eliminar la restricción rígida anterior
alter table public.appointments
  drop constraint if exists appt_within_business_hours;

-- Crear nueva función de validación que solo aplica a citas nuevas
create or replace function public.validate_appointment_business_hours()
returns trigger
language plpgsql
as $$
begin
  -- Solo validar si es una cita completamente nueva (INSERT)
  -- O si están cambiando start_time/end_time explícitamente
  if (TG_OP = 'INSERT') or (NEW.start_time != OLD.start_time) or (NEW.end_time != OLD.end_time) then
    
    -- Validar que start_time esté dentro del horario
    if not public.is_within_business_hours(NEW.business_id, NEW.start_time) then
      raise exception 'La hora de inicio (%) está fuera del horario de negocio', NEW.start_time;
    end if;
    
    -- Validar que end_time esté dentro del horario
    -- Restamos 1 segundo porque end_time es exclusivo en los rangos
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

comment on function public.validate_appointment_business_hours is
  'Valida que las citas nuevas o reagendadas estén dentro del horario configurado. No afecta citas existentes cuando se cambia la configuración del negocio.';

-- Crear trigger
drop trigger if exists trg_validate_business_hours on public.appointments;
create trigger trg_validate_business_hours
  before insert or update on public.appointments
  for each row
  execute function public.validate_appointment_business_hours();

commit;

raise notice '========================================';
raise notice 'Validación flexible de horarios implementada';
raise notice 'Las citas existentes no se invalidan al cambiar horarios';
raise notice '========================================';
