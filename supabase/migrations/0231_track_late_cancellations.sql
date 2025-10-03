-- Migration 0231: Track late cancellations
DO $$
BEGIN
  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'appointments' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.appointments does not exist';
  END IF;

  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'profiles' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.profiles does not exist';
  END IF;
END;
$$;

BEGIN;

ALTER TABLE appointments 
  ADD COLUMN IF NOT EXISTS cancelled_hours_before numeric;

COMMENT ON COLUMN appointments.cancelled_hours_before IS
  'Horas de anticipación con que se canceló. NULL si no cancelada. Negativo = canceló después de la hora programada.';

CREATE OR REPLACE FUNCTION calculate_cancellation_timing()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'cancelled' AND (OLD.status IS NULL OR OLD.status != 'cancelled') THEN
    NEW.cancelled_hours_before := EXTRACT(EPOCH FROM (NEW.start_time - now())) / 3600;
  ELSE
    NEW.cancelled_hours_before := COALESCE(NEW.cancelled_hours_before, OLD.cancelled_hours_before);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cancellation_timing ON appointments;
CREATE TRIGGER trg_cancellation_timing
  BEFORE UPDATE ON appointments
  FOR EACH ROW
  EXECUTE FUNCTION calculate_cancellation_timing();

CREATE OR REPLACE VIEW late_cancellers AS
SELECT 
  p.id,
  p.name,
  p.phone_number,
  COUNT(*) FILTER (WHERE a.cancelled_hours_before < 24) as late_cancellations,
  COUNT(*) FILTER (WHERE a.cancelled_hours_before < 2) as very_late_cancellations,
  AVG(a.cancelled_hours_before) as avg_cancellation_notice
FROM profiles p
JOIN appointments a ON a.profile_id = p.id
WHERE a.status = 'cancelled'
  AND a.cancelled_hours_before IS NOT NULL
GROUP BY p.id, p.name, p.phone_number
HAVING COUNT(*) FILTER (WHERE a.cancelled_hours_before < 24) > 0
ORDER BY very_late_cancellations DESC, late_cancellations DESC;

GRANT SELECT ON late_cancellers TO authenticated;

COMMIT;
