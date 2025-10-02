-- ===============================================
-- Migration: 0220_google_calendar_sync.sql
-- Purpose: Sincronización bidireccional con Google Calendar
-- Dependencies: 0004_functions_triggers.sql, 0215_payment_tracking.sql
-- ===============================================

-- Verificar dependencias necesarias
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'appointments'
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: tabla appointments\nAplicar migraciones iniciales de base de datos.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'get_user_business_id'
      AND n.nspname = 'public'
      AND p.proargtypes = ''::oidvector
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función public.get_user_business_id()';
  END IF;

  RAISE NOTICE '✅ Dependencias verificadas';
END $$;

BEGIN;

-- Tabla de sincronización con Google Calendar
CREATE TABLE IF NOT EXISTS public.calendar_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE CASCADE,
  google_event_id text NOT NULL,
  calendar_id text NOT NULL,
  last_synced_at timestamptz DEFAULT now(),
  sync_status text DEFAULT 'synced' CHECK (sync_status IN ('synced', 'pending', 'failed')),
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.calendar_events IS
  'Sincronización de citas con Google Calendar. Mantiene mapping entre appointments y eventos de Google.';
COMMENT ON COLUMN public.calendar_events.business_id IS
  'Identificador del negocio al que pertenece el evento sincronizado.';
COMMENT ON COLUMN public.calendar_events.appointment_id IS
  'Referencia a la cita interna sincronizada con Google Calendar.';
COMMENT ON COLUMN public.calendar_events.google_event_id IS
  'ID del evento en Google Calendar usado para sincronización bidireccional.';
COMMENT ON COLUMN public.calendar_events.calendar_id IS
  'Cuenta o calendario de Google (generalmente un email) donde vive el evento.';
COMMENT ON COLUMN public.calendar_events.sync_status IS
  'Estado de sincronización: synced, pending o failed.';

-- Índices requeridos (incluyen restricciones únicas)
CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_events_appointment
  ON public.calendar_events(appointment_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'calendar_events_appointment_unique'
      AND conrelid = 'public.calendar_events'::regclass
  ) THEN
    ALTER TABLE public.calendar_events
      ADD CONSTRAINT calendar_events_appointment_unique
      UNIQUE USING INDEX idx_calendar_events_appointment;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_calendar_events_google
  ON public.calendar_events(google_event_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'calendar_events_google_event_unique'
      AND conrelid = 'public.calendar_events'::regclass
  ) THEN
    ALTER TABLE public.calendar_events
      ADD CONSTRAINT calendar_events_google_event_unique
      UNIQUE USING INDEX idx_calendar_events_google;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_calendar_events_status
  ON public.calendar_events(sync_status)
  WHERE sync_status <> 'synced';

-- RLS
ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS calendar_events_owner_all ON public.calendar_events;
CREATE POLICY calendar_events_owner_all ON public.calendar_events
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

DROP POLICY IF EXISTS calendar_events_lead_read ON public.calendar_events;
CREATE POLICY calendar_events_lead_read ON public.calendar_events
  FOR SELECT TO authenticated
  USING (
    business_id = public.get_user_business_id()
    AND EXISTS (
      SELECT 1
      FROM public.appointments a
      JOIN public.profiles p ON p.id = a.profile_id
      WHERE a.id = calendar_events.appointment_id
        AND a.business_id = calendar_events.business_id
        AND p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

COMMIT;
