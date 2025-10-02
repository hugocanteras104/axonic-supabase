-- ===============================================
-- Migration: 0225_fix_views_without_security_definer.sql
-- Purpose: Recrear vistas eliminando SECURITY DEFINER heredado
-- Dependencies: 0224_fix_security_issues.sql
-- ===============================================

BEGIN;

-- ===============================================
-- Eliminar vistas existentes
-- ===============================================

DROP VIEW IF EXISTS public.owner_dashboard_metrics CASCADE;
DROP VIEW IF EXISTS public.inventory_low_stock CASCADE;
DROP VIEW IF EXISTS public.client_reliability_score CASCADE;
DROP VIEW IF EXISTS public.metrics_daily CASCADE;
DROP VIEW IF EXISTS public.knowledge_popular_questions CASCADE;
DROP VIEW IF EXISTS public.tetris_optimization_stats CASCADE;
DROP VIEW IF EXISTS public.metrics_top_services_global CASCADE;

-- ===============================================
-- Recrear vistas SIN security_definer
-- ===============================================

-- owner_dashboard_metrics
CREATE VIEW public.owner_dashboard_metrics
WITH (security_barrier = true)
AS
WITH daily_appointments AS (
    SELECT
        a.business_id,
        date_trunc('day', a.start_time) AS day,
        count(*) FILTER (WHERE a.status = 'confirmed') AS confirmed_appointments,
        sum(s.base_price) FILTER (WHERE a.status = 'confirmed') AS estimated_revenue
    FROM public.appointments a
    JOIN public.services s ON s.id = a.service_id AND s.business_id = a.business_id
    WHERE a.business_id IS NOT NULL
      AND COALESCE(a.deleted_at, NULL) IS NULL
      AND COALESCE(s.deleted_at, NULL) IS NULL
    GROUP BY a.business_id, day
),
top_services AS (
    SELECT DISTINCT ON (a.business_id, date_trunc('day', a.start_time))
        a.business_id,
        date_trunc('day', a.start_time) AS day,
        s.name AS top_service
    FROM public.appointments a
    JOIN public.services s ON s.id = a.service_id AND s.business_id = a.business_id
    WHERE a.status = 'confirmed'
      AND a.business_id IS NOT NULL
      AND COALESCE(a.deleted_at, NULL) IS NULL
      AND COALESCE(s.deleted_at, NULL) IS NULL
    GROUP BY a.business_id, day, s.id, s.name
    ORDER BY a.business_id, day, count(*) DESC
)
SELECT
    da.business_id,
    da.day,
    da.confirmed_appointments,
    da.estimated_revenue,
    COALESCE(ts.top_service, '') AS top_service
FROM daily_appointments da
LEFT JOIN top_services ts 
  ON ts.business_id = da.business_id 
  AND ts.day = da.day
ORDER BY da.business_id, da.day DESC;


-- inventory_low_stock
CREATE VIEW public.inventory_low_stock
WITH (security_barrier = true)
AS
SELECT
    business_id,
    id, 
    sku, 
    name, 
    quantity, 
    reorder_threshold, 
    price,
    (reorder_threshold - quantity) AS units_needed
FROM public.inventory
WHERE quantity <= reorder_threshold
  AND COALESCE(deleted_at, NULL) IS NULL
ORDER BY business_id, (reorder_threshold - quantity) DESC;


-- client_reliability_score
CREATE VIEW public.client_reliability_score
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
  WHERE COALESCE(a.deleted_at, NULL) IS NULL
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
WHERE COALESCE(p.deleted_at, NULL) IS NULL;


-- metrics_daily
CREATE VIEW public.metrics_daily
WITH (security_barrier = true)
AS
WITH daily_stats AS (
    SELECT
        a.business_id,
        date_trunc('day', a.start_time)::date AS day,
        count(*) FILTER (WHERE a.status = 'confirmed') AS confirmed_today,
        count(*) FILTER (WHERE a.status = 'pending') AS pending_today,
        count(*) FILTER (WHERE a.status = 'cancelled') AS cancelled_today,
        sum(s.base_price) FILTER (WHERE a.status = 'confirmed') AS revenue_today
    FROM public.appointments a
    JOIN public.services s ON s.id = a.service_id AND s.business_id = a.business_id
    WHERE a.business_id IS NOT NULL
      AND COALESCE(a.deleted_at, NULL) IS NULL
      AND COALESCE(s.deleted_at, NULL) IS NULL
    GROUP BY a.business_id, date_trunc('day', a.start_time)::date
),
top_service_per_day AS (
    SELECT DISTINCT ON (a.business_id, date_trunc('day', a.start_time)::date)
        a.business_id,
        date_trunc('day', a.start_time)::date AS day,
        s.name AS top_service_today,
        count(*) AS top_service_count
    FROM public.appointments a
    JOIN public.services s ON s.id = a.service_id AND s.business_id = a.business_id
    WHERE a.status = 'confirmed'
      AND a.business_id IS NOT NULL
      AND COALESCE(a.deleted_at, NULL) IS NULL
      AND COALESCE(s.deleted_at, NULL) IS NULL
    GROUP BY a.business_id, date_trunc('day', a.start_time)::date, s.id, s.name
    ORDER BY a.business_id, date_trunc('day', a.start_time)::date, count(*) DESC
)
SELECT
    ds.business_id,
    ds.day, 
    ds.confirmed_today, 
    ds.pending_today, 
    ds.cancelled_today, 
    ds.revenue_today,
    COALESCE(ts.top_service_today, '') AS top_service_today,
    COALESCE(ts.top_service_count, 0) AS top_service_count
FROM daily_stats ds
LEFT JOIN top_service_per_day ts 
  ON ts.business_id = ds.business_id 
  AND ts.day = ds.day
ORDER BY ds.business_id, ds.day DESC;


-- knowledge_popular_questions
CREATE VIEW public.knowledge_popular_questions
WITH (security_barrier = true)
AS
SELECT
    business_id,
    id, 
    category, 
    question, 
    view_count, 
    created_at
FROM public.knowledge_base
WHERE view_count > 0
ORDER BY business_id, view_count DESC, created_at DESC;


-- tetris_optimization_stats
CREATE VIEW public.tetris_optimization_stats
WITH (security_barrier = true)
AS
SELECT
  business_id,
  date_trunc('day', created_at)::date AS day,
  count(*) AS total_optimizations,
  sum(candidates_found) AS total_candidates_found,
  sum(notifications_sent) AS total_notifications_sent,
  sum(appointments_moved) AS total_appointments_moved,
  count(*) FILTER (WHERE processed) AS processed_count,
  count(*) FILTER (WHERE NOT processed) AS pending_count,
  avg(candidates_found) AS avg_candidates_per_optimization
FROM public.agenda_optimizations
GROUP BY business_id, day
ORDER BY day DESC;


-- metrics_top_services_global
CREATE VIEW public.metrics_top_services_global
WITH (security_barrier = true)
AS
SELECT
    s.business_id,
    s.id AS service_id,
    s.name AS service_name,
    count(a.id) AS total_appointments,
    count(a.id) FILTER (WHERE a.status = 'confirmed') AS confirmed_appointments,
    sum(s.base_price) FILTER (WHERE a.status = 'confirmed') AS total_revenue,
    avg(s.base_price) FILTER (WHERE a.status = 'confirmed') AS avg_revenue,
    min(a.start_time) AS first_appointment,
    max(a.start_time) AS last_appointment
FROM public.services s
LEFT JOIN public.appointments a 
  ON a.service_id = s.id 
  AND a.business_id = s.business_id
  AND COALESCE(a.deleted_at, NULL) IS NULL
WHERE s.business_id IS NOT NULL
  AND COALESCE(s.deleted_at, NULL) IS NULL
GROUP BY s.business_id, s.id, s.name
ORDER BY s.business_id, confirmed_appointments DESC;

COMMIT;

-- Mensaje final
DO $$
BEGIN
  RAISE NOTICE '✅ Migración 0225 completada';
  RAISE NOTICE '   - 7 vistas recreadas sin security_definer';
  RAISE NOTICE '   - Todas con security_barrier = true';
  RAISE NOTICE '';
  RAISE NOTICE '🔍 Ejecuta el Linter para verificar';
END $$;
