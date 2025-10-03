-- Migration 0234: Staff availability schedules
DO $$
BEGIN
  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'resources' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.resources does not exist';
  END IF;

  PERFORM 1 FROM pg_catalog.pg_class c
   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'businesses' AND c.relkind = 'r';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required table public.businesses does not exist';
  END IF;

  IF to_regclass('public.service_resource_requirements') IS NULL THEN
    RAISE EXCEPTION 'Required table public.service_resource_requirements does not exist';
  END IF;
END;
$$;

BEGIN;

-- Eliminar función anterior (cambió estructura de retorno)
DROP FUNCTION IF EXISTS public.get_available_slots_with_resources(uuid, timestamptz, timestamptz, int);

CREATE TABLE IF NOT EXISTS staff_availability (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_resource_id uuid NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  day_of_week int NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time time NOT NULL,
  is_available boolean DEFAULT true,
  CONSTRAINT staff_time_valid CHECK (start_time < end_time)
);

CREATE INDEX IF NOT EXISTS idx_staff_availability_resource 
  ON staff_availability(staff_resource_id, day_of_week);

COMMENT ON TABLE staff_availability IS
  'Horario semanal de cada empleado. day_of_week: 0=domingo, 6=sábado.';

ALTER TABLE staff_availability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_availability_read ON staff_availability;
CREATE POLICY staff_availability_read ON staff_availability
  FOR SELECT TO authenticated
  USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS staff_availability_owner_write ON staff_availability;
CREATE POLICY staff_availability_owner_write ON staff_availability
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

CREATE OR REPLACE FUNCTION public.get_available_slots_with_resources(
    p_service_id uuid,
    p_start timestamptz,
    p_end timestamptz,
    p_step_minutes int DEFAULT 15
)
RETURNS TABLE(
    resource_id uuid,
    slot_start timestamptz,
    slot_end timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_business_id uuid;
    v_role text;
    v_dur int;
    v_buffer int;
    v_buffer_interval interval;
    v_resource_id uuid;
    v_has_resource_column boolean;
    slot_rec record;
    v_conflict boolean;
    v_day_of_week int;
    v_local_start time;
    v_local_end time;
BEGIN
    v_business_id := public.get_user_business_id();
    v_role := auth.jwt()->>'user_role';

    IF v_business_id IS NULL THEN
        RAISE EXCEPTION 'Business context not found';
    END IF;

    IF v_role NOT IN ('owner', 'lead') THEN
        RAISE EXCEPTION 'Insufficient privileges';
    END IF;

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

    v_buffer_interval := make_interval(mins => v_buffer);

    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'appointments'
          AND column_name = 'resource_id'
    ) INTO v_has_resource_column;

    FOR v_resource_id IN
        SELECT sr.resource_id
        FROM public.service_resource_requirements sr
        JOIN public.resources r ON r.id = sr.resource_id
        WHERE sr.service_id = p_service_id
          AND r.business_id = v_business_id
    LOOP
        FOR slot_rec IN
            SELECT slot_start, slot_end
            FROM public.get_available_slots(p_service_id, p_start, p_end, p_step_minutes)
        LOOP
            v_day_of_week := EXTRACT(DOW FROM (slot_rec.slot_start AT TIME ZONE 'Europe/Madrid'))::int;
            v_local_start := (slot_rec.slot_start AT TIME ZONE 'Europe/Madrid')::time;
            v_local_end := (slot_rec.slot_end AT TIME ZONE 'Europe/Madrid')::time;

            IF NOT EXISTS (
                SELECT 1
                FROM public.staff_availability sa
                WHERE sa.staff_resource_id = v_resource_id
                  AND sa.business_id = v_business_id
                  AND sa.day_of_week = v_day_of_week
                  AND sa.is_available
                  AND sa.start_time <= v_local_start
                  AND sa.end_time >= v_local_end
            ) THEN
                CONTINUE;
            END IF;

            IF v_has_resource_column THEN
                EXECUTE 'SELECT EXISTS (
                    SELECT 1
                    FROM public.appointments a
                    WHERE a.business_id = $1
                      AND a.status = ''confirmed''
                      AND a.start_time < $3
                      AND (a.end_time + $4) > $2
                      AND a.resource_id = $5
                )' INTO v_conflict
                USING v_business_id, slot_rec.slot_start, slot_rec.slot_end, v_buffer_interval, v_resource_id;
            ELSE
                SELECT EXISTS (
                    SELECT 1
                    FROM public.appointments a
                    WHERE a.business_id = v_business_id
                      AND a.status = 'confirmed'
                      AND a.start_time < slot_rec.slot_end
                      AND (a.end_time + v_buffer_interval) > slot_rec.slot_start
                ) INTO v_conflict;
            END IF;

            IF NOT v_conflict THEN
                resource_id := v_resource_id;
                slot_start := slot_rec.slot_start;
                slot_end := slot_rec.slot_end;
                RETURN NEXT;
            END IF;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$;

COMMIT;
