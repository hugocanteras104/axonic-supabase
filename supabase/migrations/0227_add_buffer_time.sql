-- 0227_add_buffer_time.sql
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'services'
  ) THEN
    RAISE EXCEPTION 'Tabla services no existe';
  END IF;
END $$;

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS buffer_minutes int DEFAULT 15
  CHECK (buffer_minutes >= 0 AND buffer_minutes <= 120);

COMMENT ON COLUMN public.services.buffer_minutes IS
  'Tiempo de limpieza/preparación después del servicio (minutos)';

CREATE OR REPLACE FUNCTION public.get_available_slots(
  p_service_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_step_minutes int DEFAULT 15
) RETURNS TABLE(slot_start timestamptz, slot_end timestamptz)
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
  v_business_id uuid;
BEGIN
  SELECT duration_minutes,
         COALESCE(buffer_minutes, 0),
         business_id
  INTO v_dur,
       v_buffer,
       v_business_id
  FROM services
  WHERE id = p_service_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Servicio no existe';
  END IF;

  IF v_dur <= 0 THEN
    RAISE EXCEPTION 'La duración del servicio debe ser mayor que cero';
  END IF;

  IF p_step_minutes IS NULL OR p_step_minutes <= 0 THEN
    RAISE EXCEPTION 'El parámetro p_step_minutes debe ser mayor que cero';
  END IF;

  v_cursor := p_start;

  WHILE v_cursor < p_end LOOP
    v_slot_end := v_cursor + make_interval(mins => v_dur);

    EXIT WHEN v_slot_end > p_end;

    IF NOT EXISTS (
      SELECT 1
      FROM appointments a
      JOIN services s ON s.id = a.service_id
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

  RETURN;
END;
$$;

COMMIT;
