-- Migration 0228: Add reminder tracking to appointments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'appointments' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Required table public.appointments does not exist';
  END IF;
END;
$$;

BEGIN;

ALTER TABLE appointments 
  ADD COLUMN IF NOT EXISTS reminder_sent_at timestamptz;

COMMENT ON COLUMN appointments.reminder_sent_at IS 
  'Timestamp del recordatorio enviado por n8n. NULL = pendiente de envío.';

CREATE INDEX IF NOT EXISTS idx_appointments_reminder_pending
  ON appointments(start_time, reminder_sent_at)
  WHERE status = 'confirmed' AND reminder_sent_at IS NULL;

COMMIT;
