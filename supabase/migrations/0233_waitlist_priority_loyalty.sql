-- Migration 0233: Waitlist priority and loyalty tracking
DO $$
BEGIN
  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'waitlists' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.waitlists does not exist';
  END IF;

  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'profiles' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.profiles does not exist';
  END IF;

  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'appointments' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.appointments does not exist';
  END IF;
END;
$$;

BEGIN;

ALTER TABLE waitlists 
  ADD COLUMN IF NOT EXISTS priority int DEFAULT 0;

ALTER TABLE profiles 
  ADD COLUMN IF NOT EXISTS loyalty_points int DEFAULT 0 CHECK (loyalty_points >= 0);

COMMENT ON COLUMN waitlists.priority IS 
  'Prioridad manual asignada por owner. Mayor número = mayor prioridad.';
COMMENT ON COLUMN profiles.loyalty_points IS 
  'Puntos acumulados (+10 por cada cita confirmada). Usado para ordenar lista de espera.';

CREATE OR REPLACE FUNCTION update_loyalty_points()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'confirmed' AND (OLD.status IS NULL OR OLD.status != 'confirmed') THEN
    UPDATE profiles 
    SET loyalty_points = loyalty_points + 10
    WHERE id = NEW.profile_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_loyalty_points ON appointments;
CREATE TRIGGER trg_loyalty_points
  AFTER INSERT OR UPDATE ON appointments
  FOR EACH ROW
  EXECUTE FUNCTION update_loyalty_points();

CREATE INDEX IF NOT EXISTS idx_waitlists_priority 
  ON waitlists(business_id, service_id, priority DESC, created_at);

COMMIT;
