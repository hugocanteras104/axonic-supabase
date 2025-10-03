-- Migration 0229: Validate holidays and prevent same-day appointments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'get_user_business_id' AND pg_function_is_visible(oid)
  ) THEN
    RAISE EXCEPTION 'Required function public.get_user_business_id() does not exist';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'services' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Required table public.services does not exist';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'business_settings' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Required table public.business_settings does not exist';
  END IF;
END;
$$;

BEGIN;

CREATE OR REPLACE FUNCTION public.get_available_slots(
    p_service_id uuid,
    p_start timestamptz,
    p_end timestamptz,
    p_step_minutes int default 15
)
RETURNS TABLE(slot_start timestamptz, slot_end timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_dur int;
    v_buffer int;
    v_cursor timestamptz;
    v_slot_end timestamptz;
    v_role text;
    v_business_id uuid;
    v_holidays jsonb;
    v_current_date date;
BEGIN
    v_business_id := public.get_user_business_id();
    v_role := auth.jwt()->>'user_role';

    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Business context not found';
    END IF;

    IF v_role NOT IN ('owner', 'lead') THEN
        RAISE EXCEPTION 'Insufficient privileges';
    END IF;

    -- Prevent booking same-day appointments
    IF p_start < now() + interval '1 day' THEN
        p_start := date_trunc('day', now() + interval '1 day');
    END IF;

    -- Obtener duración y buffer
    SELECT duration_minutes, COALESCE(buffer_minutes, 0)
    INTO v_dur, v_buffer
    FROM public.services 
    WHERE id = p_service_id AND business_id = v_business_id;
    
    IF v_dur IS NULL THEN
        RAISE EXCEPTION 'Service not found';
    END IF;
    
    IF p_start >= p_end THEN
        RAISE EXCEPTION 'Invalid time window';
    END IF;

    -- Obtener holidays del negocio
    SELECT (setting_value->'holidays') INTO v_holidays
    FROM public.business_settings 
    WHERE business_id = v_business_id 
      AND setting_key = 'business_hours';

    v_cursor := p_start;
    WHILE v_cursor < p_end LOOP
        v_slot_end := v_cursor + make_interval(mins => v_dur);
        
        EXIT WHEN v_slot_end > p_end;
        
        v_current_date := (v_cursor AT TIME ZONE 'Europe/Madrid')::date;
        
        -- Saltar día si está en holidays
        IF v_holidays IS NOT NULL AND v_holidays ? v_current_date::text THEN
            v_cursor := date_trunc('day', v_cursor) + interval '1 day';
            CONTINUE;
        END IF;

        -- Verificar conflictos incluyendo buffer
        IF NOT EXISTS (
            SELECT 1
            FROM public.appointments a
            JOIN public.services s ON s.id = a.service_id
            WHERE s.business_id = v_business_id
              AND a.service_id = p_service_id
              AND a.status = 'confirmed'
              AND a.start_time < v_slot_end
              AND (a.end_time + make_interval(mins => COALESCE(s.buffer_minutes, 0))) > v_cursor
        ) THEN
            slot_start := v_cursor;
            slot_end := v_slot_end;
            RETURN NEXT;
        END IF;
        
        v_cursor := v_cursor + make_interval(mins => p_step_minutes);
    END LOOP;
END;
$$;

COMMIT;
