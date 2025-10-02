-- ===============================================
-- Migration: 0222_fix_rls_security_and_no_shows.sql
-- Purpose: Corregir política vulnerable y habilitar sistema de no-shows
-- Dependencies: 0004_functions_triggers.sql, 0206_update_rls_deep.sql
-- ===============================================

-- Validar dependencias críticas
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
  ) THEN
    RAISE EXCEPTION '❌ Falta tabla profiles. Aplicar migraciones base.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'appointments'
  ) THEN
    RAISE EXCEPTION '❌ Falta tabla appointments. Aplicar migraciones base.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'services'
  ) THEN
    RAISE EXCEPTION '❌ Falta tabla services. Aplicar migraciones base.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'businesses'
  ) THEN
    RAISE EXCEPTION '❌ Falta tabla businesses. Aplicar migraciones base.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'get_user_business_id'
      AND n.nspname = 'public'
      AND p.proargtypes = ''::oidvector
  ) THEN
    RAISE EXCEPTION '❌ Dependencia faltante: función public.get_user_business_id()';
  END IF;

  RAISE NOTICE '✅ Dependencias verificadas';
END $$;

BEGIN;

-- ===============================================
-- Parte A: Política segura para perfiles
-- ===============================================
DROP POLICY IF EXISTS profiles_read ON public.profiles;
CREATE POLICY profiles_read ON public.profiles
  FOR SELECT TO authenticated
  USING (
    business_id = public.get_user_business_id()
    AND (
      auth.jwt()->>'user_role' = 'owner'
      OR phone_number = (auth.jwt()->>'phone_number')
    )
  );

-- ===============================================
-- Parte B: Campos de no-show en appointments
-- ===============================================
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS no_show boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS marked_no_show_at timestamptz,
  ADD COLUMN IF NOT EXISTS marked_no_show_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.appointments.no_show IS
  'Indica si la cita fue marcada como no-show.';
COMMENT ON COLUMN public.appointments.marked_no_show_at IS
  'Fecha en la que se marcó la cita como no-show.';
COMMENT ON COLUMN public.appointments.marked_no_show_by IS
  'Perfil del equipo que marcó la cita como no-show.';

CREATE INDEX IF NOT EXISTS idx_appointments_no_show
  ON public.appointments (business_id, no_show)
  WHERE no_show = true;

-- ===============================================
-- Historial de no-shows por cliente
-- ===============================================
CREATE TABLE IF NOT EXISTS public.client_no_show_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL,
  service_id uuid REFERENCES public.services(id) ON DELETE SET NULL,
  scheduled_time timestamptz NOT NULL,
  marked_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.client_no_show_history IS
  'Registro histórico de no-shows para identificar clientes de alto riesgo, definir depósitos obligatorios y decidir futuras reservas.';
COMMENT ON COLUMN public.client_no_show_history.profile_id IS
  'Cliente afectado por el no-show.';
COMMENT ON COLUMN public.client_no_show_history.business_id IS
  'Negocio propietario del historial.';
COMMENT ON COLUMN public.client_no_show_history.appointment_id IS
  'Cita relacionada con el evento de no-show.';
COMMENT ON COLUMN public.client_no_show_history.service_id IS
  'Servicio originalmente reservado en la cita.';
COMMENT ON COLUMN public.client_no_show_history.scheduled_time IS
  'Horario planificado de la cita marcada como no-show.';
COMMENT ON COLUMN public.client_no_show_history.notes IS
  'Notas internas con contexto del no-show.';

CREATE INDEX IF NOT EXISTS idx_no_show_history_profile
  ON public.client_no_show_history (profile_id, marked_at DESC);

CREATE INDEX IF NOT EXISTS idx_no_show_history_business
  ON public.client_no_show_history (business_id, marked_at DESC);

-- ===============================================
-- Vista de fiabilidad de clientes
-- ===============================================
DROP VIEW IF EXISTS public.client_reliability_score;
CREATE OR REPLACE VIEW public.client_reliability_score
WITH (security_barrier = true)
AS
WITH base AS (
  SELECT
    a.profile_id,
    a.business_id,
    COUNT(*) AS total_appointments,
    COUNT(*) FILTER (
      WHERE a.status = 'confirmed'
        AND COALESCE(a.no_show, false) = false
        AND a.start_time < now()
    ) AS completed_appointments,
    COUNT(*) FILTER (
      WHERE COALESCE(a.no_show, false) = true
    ) AS no_show_count,
    COUNT(*) FILTER (
      WHERE a.status = 'cancelled'
    ) AS cancellation_count
  FROM public.appointments a
  WHERE a.deleted_at IS NULL
  GROUP BY a.profile_id, a.business_id
), enriched AS (
  SELECT
    b.profile_id,
    b.business_id,
    b.total_appointments,
    b.completed_appointments,
    b.no_show_count,
    b.cancellation_count,
    CASE
      WHEN b.total_appointments = 0 THEN 100::numeric
      ELSE ROUND((b.completed_appointments::numeric / b.total_appointments::numeric) * 100, 2)
    END AS reliability_score,
    ns.last_no_show_date,
    CASE
      WHEN b.total_appointments = 0 THEN 'low'
      ELSE (
        CASE
          WHEN (b.no_show_count::numeric / NULLIF(b.total_appointments::numeric, 0)) * 100 > 25 THEN 'high'
          WHEN (b.no_show_count::numeric / NULLIF(b.total_appointments::numeric, 0)) * 100 >= 10 THEN 'medium'
          ELSE 'low'
        END
      )
    END AS risk_level
  FROM base b
  LEFT JOIN (
    SELECT profile_id, business_id, MAX(marked_at) AS last_no_show_date
    FROM public.client_no_show_history
    GROUP BY profile_id, business_id
  ) ns
    ON ns.profile_id = b.profile_id
   AND ns.business_id = b.business_id
)
SELECT
  e.profile_id,
  e.business_id,
  e.total_appointments,
  e.completed_appointments,
  e.no_show_count,
  e.cancellation_count,
  e.reliability_score,
  e.last_no_show_date,
  e.risk_level
FROM enriched e
JOIN public.profiles p ON p.id = e.profile_id
WHERE
  p.deleted_at IS NULL
  AND (
    (
      auth.jwt()->>'user_role' = 'owner'
      AND e.business_id = public.get_user_business_id()
    )
    OR (
      auth.jwt()->>'user_role' = 'lead'
      AND e.business_id = public.get_user_business_id()
      AND p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

COMMENT ON VIEW public.client_reliability_score IS
  'Mide el desempeño de asistencia de cada cliente por negocio, incluyendo puntuación, últimos no-shows y nivel de riesgo.';

-- ===============================================
-- Función para marcar no-shows
-- ===============================================
DROP FUNCTION IF EXISTS public.mark_appointment_as_no_show(uuid, text);
CREATE OR REPLACE FUNCTION public.mark_appointment_as_no_show(
  p_appointment_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid := public.get_user_business_id();
  v_user_role text := auth.jwt()->>'user_role';
  v_marker_profile uuid;
  v_now timestamptz := now();
  v_appointment RECORD;
  v_history_id uuid;
BEGIN
  IF v_user_role IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'Solo los owners pueden marcar no-shows';
  END IF;

  SELECT
    a.id,
    a.profile_id,
    a.service_id,
    a.start_time,
    a.status,
    a.no_show,
    a.deleted_at
  INTO v_appointment
  FROM public.appointments a
  WHERE a.id = p_appointment_id
    AND a.business_id = v_business_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cita no encontrada para el negocio actual';
  END IF;

  IF v_appointment.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'No se pueden marcar citas eliminadas';
  END IF;

  IF COALESCE(v_appointment.no_show, false) THEN
    RAISE EXCEPTION 'La cita ya estaba marcada como no-show';
  END IF;

  IF v_appointment.start_time >= v_now THEN
    RAISE EXCEPTION 'La cita aún no ha sucedido';
  END IF;

  IF v_appointment.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Solo se pueden marcar como no-show citas confirmadas';
  END IF;

  SELECT id
  INTO v_marker_profile
  FROM public.profiles
  WHERE business_id = v_business_id
    AND phone_number = (auth.jwt()->>'phone_number')
  LIMIT 1;

  UPDATE public.appointments
  SET
    no_show = true,
    marked_no_show_at = v_now,
    marked_no_show_by = v_marker_profile,
    updated_at = v_now
  WHERE id = v_appointment.id;

  INSERT INTO public.client_no_show_history (
    profile_id,
    business_id,
    appointment_id,
    service_id,
    scheduled_time,
    notes
  ) VALUES (
    v_appointment.profile_id,
    v_business_id,
    v_appointment.id,
    v_appointment.service_id,
    v_appointment.start_time,
    p_notes
  )
  RETURNING id INTO v_history_id;

  INSERT INTO public.audit_logs (business_id, profile_id, action, payload)
  VALUES (
    v_business_id,
    v_marker_profile,
    'appointment_marked_no_show',
    jsonb_build_object(
      'appointment_id', v_appointment.id,
      'profile_id', v_appointment.profile_id,
      'service_id', v_appointment.service_id,
      'scheduled_time', v_appointment.start_time,
      'notes', p_notes,
      'marked_at', v_now
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', v_appointment.id,
    'history_id', v_history_id,
    'marked_at', v_now
  );
END;
$$;

COMMENT ON FUNCTION public.mark_appointment_as_no_show(uuid, text) IS
  'Marca una cita confirmada como no-show, registra historial y crea auditoría.';

GRANT EXECUTE ON FUNCTION public.mark_appointment_as_no_show(uuid, text) TO authenticated;

-- ===============================================
-- RLS para historial de no-shows
-- ===============================================
ALTER TABLE public.client_no_show_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS client_no_show_history_owner_all ON public.client_no_show_history;
CREATE POLICY client_no_show_history_owner_all ON public.client_no_show_history
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

COMMIT;
