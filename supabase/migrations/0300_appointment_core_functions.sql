-- ===============================================
-- Migration: 0300_appointment_core_functions.sql (FIXED)
-- Purpose: Funciones RPC CORE para gestión de citas desde el bot
-- Dependencies: 0207_update_functions_multitenancy.sql
-- Author: Axonic Assistant - Sistema Completo
-- FIX: DROP funciones existentes antes de recrear
-- ===============================================

BEGIN;

-- ===============================================
-- DROP FUNCIONES EXISTENTES (si existen)
-- ===============================================

DROP FUNCTION IF EXISTS public.create_appointment_bot(uuid, uuid, timestamptz) CASCADE;
DROP FUNCTION IF EXISTS public.cancel_appointment(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.reschedule_appointment(uuid, timestamptz) CASCADE;
DROP FUNCTION IF EXISTS public.confirm_appointment(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_appointment_details(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_client_appointments(uuid, boolean) CASCADE;
DROP FUNCTION IF EXISTS public.get_next_appointment(uuid) CASCADE;

-- ===============================================
-- 1. create_appointment_bot
-- Crear cita desde la interacción del bot
-- ===============================================
CREATE OR REPLACE FUNCTION public.create_appointment_bot(
  p_profile_id uuid,
  p_service_id uuid,
  p_datetime timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_appointment_id uuid;
  v_service RECORD;
  v_role text;
BEGIN
  -- Obtener contexto
  v_business_id := public.get_user_business_id();
  v_role := auth.jwt()->>'user_role';
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  -- Verificar permisos
  IF v_role NOT IN ('owner', 'lead') THEN
    RAISE EXCEPTION 'Insufficient privileges';
  END IF;
  
  -- Obtener información del servicio
  SELECT duration_minutes, base_price 
  INTO v_service
  FROM public.services
  WHERE id = p_service_id
    AND business_id = v_business_id
    AND is_active = true;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service not found or inactive';
  END IF;
  
  -- Verificar que el perfil pertenece al negocio
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_profile_id
      AND business_id = v_business_id
  ) THEN
    RAISE EXCEPTION 'Profile not found in this business';
  END IF;
  
  -- Verificar disponibilidad del slot
  IF EXISTS (
    SELECT 1 FROM public.appointments
    WHERE service_id = p_service_id
      AND business_id = v_business_id
      AND status = 'confirmed'
      AND tstzrange(start_time, end_time, '[)') && 
          tstzrange(p_datetime, p_datetime + (v_service.duration_minutes || ' minutes')::interval, '[)')
  ) THEN
    RAISE EXCEPTION 'Time slot not available';
  END IF;
  
  -- Crear la cita
  INSERT INTO public.appointments (
    business_id,
    profile_id,
    service_id,
    start_time,
    end_time,
    status,
    total_price
  ) VALUES (
    v_business_id,
    p_profile_id,
    p_service_id,
    p_datetime,
    p_datetime + (v_service.duration_minutes || ' minutes')::interval,
    'confirmed',
    v_service.base_price
  )
  RETURNING id INTO v_appointment_id;
  
  -- Log de auditoría
  INSERT INTO public.audit_logs (business_id, profile_id, action, payload)
  VALUES (
    v_business_id,
    p_profile_id,
    'appointment_created_bot',
    jsonb_build_object(
      'appointment_id', v_appointment_id,
      'service_id', p_service_id,
      'datetime', p_datetime
    )
  );
  
  RETURN v_appointment_id;
END;
$$;

COMMENT ON FUNCTION public.create_appointment_bot IS
  'Crear cita desde el bot con validaciones completas';

-- ===============================================
-- 2. cancel_appointment
-- Cancelar una cita existente
-- ===============================================
CREATE OR REPLACE FUNCTION public.cancel_appointment(
  p_appointment_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_appointment RECORD;
  v_role text;
  v_user_id uuid;
BEGIN
  v_business_id := public.get_user_business_id();
  v_role := auth.jwt()->>'user_role';
  
  BEGIN
    v_user_id := (auth.jwt()->>'sub')::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_id := NULL;
  END;
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  -- Obtener cita con lock
  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_appointment_id
    AND business_id = v_business_id
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;
  
  -- Verificar permisos
  IF v_role = 'lead' AND v_appointment.profile_id != v_user_id THEN
    RAISE EXCEPTION 'Cannot cancel appointments of other clients';
  END IF;
  
  IF v_appointment.status = 'cancelled' THEN
    RAISE EXCEPTION 'Appointment already cancelled';
  END IF;
  
  IF v_appointment.status = 'completed' THEN
    RAISE EXCEPTION 'Cannot cancel completed appointment';
  END IF;
  
  -- Cancelar la cita
  UPDATE public.appointments
  SET 
    status = 'cancelled',
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'cancellation_reason', COALESCE(p_reason, 'No reason provided'),
      'cancelled_at', now(),
      'cancelled_by', v_user_id
    )
  WHERE id = p_appointment_id;
  
  -- Log de auditoría
  INSERT INTO public.audit_logs (business_id, profile_id, action, payload)
  VALUES (
    v_business_id,
    v_appointment.profile_id,
    'appointment_cancelled',
    jsonb_build_object(
      'appointment_id', p_appointment_id,
      'reason', p_reason,
      'original_datetime', v_appointment.start_time
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', p_appointment_id,
    'status', 'cancelled',
    'message', 'Appointment cancelled successfully'
  );
END;
$$;

COMMENT ON FUNCTION public.cancel_appointment IS
  'Cancelar cita con validaciones de permisos y auditoría';

-- ===============================================
-- 3. reschedule_appointment
-- Reagendar una cita a nueva fecha/hora
-- ===============================================
CREATE OR REPLACE FUNCTION public.reschedule_appointment(
  p_appointment_id uuid,
  p_new_datetime timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_appointment RECORD;
  v_service_duration int;
  v_role text;
  v_user_id uuid;
  v_new_end_time timestamptz;
BEGIN
  v_business_id := public.get_user_business_id();
  v_role := auth.jwt()->>'user_role';
  
  BEGIN
    v_user_id := (auth.jwt()->>'sub')::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_id := NULL;
  END;
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  -- Obtener cita con lock
  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_appointment_id
    AND business_id = v_business_id
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;
  
  -- Verificar permisos
  IF v_role = 'lead' AND v_appointment.profile_id != v_user_id THEN
    RAISE EXCEPTION 'Cannot reschedule appointments of other clients';
  END IF;
  
  IF v_appointment.status != 'confirmed' THEN
    RAISE EXCEPTION 'Can only reschedule confirmed appointments';
  END IF;
  
  -- Obtener duración del servicio
  SELECT duration_minutes INTO v_service_duration
  FROM public.services
  WHERE id = v_appointment.service_id;
  
  v_new_end_time := p_new_datetime + (v_service_duration || ' minutes')::interval;
  
  -- Verificar disponibilidad del nuevo slot
  IF EXISTS (
    SELECT 1 FROM public.appointments
    WHERE service_id = v_appointment.service_id
      AND business_id = v_business_id
      AND status = 'confirmed'
      AND id != p_appointment_id
      AND tstzrange(start_time, end_time, '[)') && 
          tstzrange(p_new_datetime, v_new_end_time, '[)')
  ) THEN
    RAISE EXCEPTION 'New time slot not available';
  END IF;
  
  -- Actualizar la cita
  UPDATE public.appointments
  SET 
    start_time = p_new_datetime,
    end_time = v_new_end_time,
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'rescheduled_from', v_appointment.start_time,
      'rescheduled_at', now(),
      'rescheduled_by', v_user_id
    )
  WHERE id = p_appointment_id;
  
  -- Log de auditoría
  INSERT INTO public.audit_logs (business_id, profile_id, action, payload)
  VALUES (
    v_business_id,
    v_appointment.profile_id,
    'appointment_rescheduled',
    jsonb_build_object(
      'appointment_id', p_appointment_id,
      'old_datetime', v_appointment.start_time,
      'new_datetime', p_new_datetime
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', p_appointment_id,
    'old_datetime', v_appointment.start_time,
    'new_datetime', p_new_datetime,
    'message', 'Appointment rescheduled successfully'
  );
END;
$$;

COMMENT ON FUNCTION public.reschedule_appointment IS
  'Reagendar cita verificando disponibilidad del nuevo slot';

-- ===============================================
-- 4. confirm_appointment
-- Confirmar asistencia a una cita
-- ===============================================
CREATE OR REPLACE FUNCTION public.confirm_appointment(
  p_appointment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_appointment RECORD;
  v_role text;
BEGIN
  v_business_id := public.get_user_business_id();
  v_role := auth.jwt()->>'user_role';
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  -- Obtener cita
  SELECT * INTO v_appointment
  FROM public.appointments
  WHERE id = p_appointment_id
    AND business_id = v_business_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;
  
  -- Actualizar metadata con confirmación
  UPDATE public.appointments
  SET 
    metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
      'confirmed_at', now(),
      'confirmation_method', 'bot'
    )
  WHERE id = p_appointment_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'appointment_id', p_appointment_id,
    'message', 'Appointment confirmed'
  );
END;
$$;

COMMENT ON FUNCTION public.confirm_appointment IS
  'Confirmar asistencia a una cita programada';

-- ===============================================
-- 5. get_appointment_details
-- Ver detalles completos de una cita
-- ===============================================
CREATE OR REPLACE FUNCTION public.get_appointment_details(
  p_appointment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_result jsonb;
  v_role text;
BEGIN
  v_business_id := public.get_user_business_id();
  v_role := auth.jwt()->>'user_role';
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  SELECT jsonb_build_object(
    'appointment_id', a.id,
    'start_time', a.start_time,
    'end_time', a.end_time,
    'status', a.status,
    'total_price', a.total_price,
    'service', jsonb_build_object(
      'id', s.id,
      'name', s.name,
      'description', s.description,
      'duration_minutes', s.duration_minutes
    ),
    'client', jsonb_build_object(
      'id', p.id,
      'name', p.full_name,
      'phone', p.phone_number
    ),
    'metadata', a.metadata,
    'created_at', a.created_at
  )
  INTO v_result
  FROM public.appointments a
  JOIN public.services s ON s.id = a.service_id
  JOIN public.profiles p ON p.id = a.profile_id
  WHERE a.id = p_appointment_id
    AND a.business_id = v_business_id;
  
  IF v_result IS NULL THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;
  
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_appointment_details IS
  'Obtener detalles completos de una cita específica';

-- ===============================================
-- 6. get_client_appointments
-- Ver historial de citas de un cliente
-- ===============================================
CREATE OR REPLACE FUNCTION public.get_client_appointments(
  p_profile_id uuid,
  p_include_past boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_result jsonb;
  v_role text;
BEGIN
  v_business_id := public.get_user_business_id();
  v_role := auth.jwt()->>'user_role';
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  SELECT jsonb_agg(
    jsonb_build_object(
      'appointment_id', a.id,
      'start_time', a.start_time,
      'end_time', a.end_time,
      'status', a.status,
      'service_name', s.name,
      'service_id', s.id,
      'total_price', a.total_price
    ) ORDER BY a.start_time DESC
  )
  INTO v_result
  FROM public.appointments a
  JOIN public.services s ON s.id = a.service_id
  WHERE a.profile_id = p_profile_id
    AND a.business_id = v_business_id
    AND (p_include_past OR a.start_time >= now());
  
  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.get_client_appointments IS
  'Obtener historial de citas de un cliente';

-- ===============================================
-- 7. get_next_appointment
-- Obtener próxima cita del cliente
-- ===============================================
CREATE OR REPLACE FUNCTION public.get_next_appointment(
  p_profile_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_result jsonb;
BEGIN
  v_business_id := public.get_user_business_id();
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  SELECT jsonb_build_object(
    'appointment_id', a.id,
    'start_time', a.start_time,
    'end_time', a.end_time,
    'status', a.status,
    'service', jsonb_build_object(
      'id', s.id,
      'name', s.name,
      'description', s.description
    ),
    'total_price', a.total_price
  )
  INTO v_result
  FROM public.appointments a
  JOIN public.services s ON s.id = a.service_id
  WHERE a.profile_id = p_profile_id
    AND a.business_id = v_business_id
    AND a.start_time >= now()
    AND a.status = 'confirmed'
  ORDER BY a.start_time ASC
  LIMIT 1;
  
  RETURN COALESCE(v_result, 'null'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.get_next_appointment IS
  'Obtener la próxima cita programada del cliente';

-- ===============================================
-- GRANTS
-- ===============================================
GRANT EXECUTE ON FUNCTION public.create_appointment_bot(uuid, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_appointment(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_appointment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_appointment_details(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_appointments(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_appointment(uuid) TO authenticated;

COMMIT;

-- Verificación
DO $$
BEGIN
  RAISE NOTICE '✅ Migration 0300 completed successfully (FIXED)';
  RAISE NOTICE '📦 Functions created: 7';
  RAISE NOTICE '   - create_appointment_bot';
  RAISE NOTICE '   - cancel_appointment';
  RAISE NOTICE '   - reschedule_appointment';
  RAISE NOTICE '   - confirm_appointment';
  RAISE NOTICE '   - get_appointment_details';
  RAISE NOTICE '   - get_client_appointments';
  RAISE NOTICE '   - get_next_appointment';
END $$;
