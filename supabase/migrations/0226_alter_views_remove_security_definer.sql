-- ===============================================
-- Migration: 0226_alter_views_remove_security_definer.sql
-- Purpose: Cambiar propiedades de vistas existentes
-- ===============================================

BEGIN;

-- Cambiar las opciones de las vistas para quitar SECURITY DEFINER
-- y agregar SECURITY BARRIER

ALTER VIEW public.owner_dashboard_metrics SET (security_barrier = true);
ALTER VIEW public.inventory_low_stock SET (security_barrier = true);
ALTER VIEW public.client_reliability_score SET (security_barrier = true);
ALTER VIEW public.metrics_daily SET (security_barrier = true);
ALTER VIEW public.knowledge_popular_questions SET (security_barrier = true);
ALTER VIEW public.tetris_optimization_stats SET (security_barrier = true);
ALTER VIEW public.metrics_top_services_global SET (security_barrier = true);

-- Verificar que funcionó
DO $$
DECLARE
  v_view_name text;
  v_options text[];
BEGIN
  FOR v_view_name IN 
    SELECT viewname 
    FROM pg_views 
    WHERE schemaname = 'public' 
      AND viewname IN (
        'owner_dashboard_metrics',
        'inventory_low_stock', 
        'client_reliability_score',
        'metrics_daily',
        'knowledge_popular_questions',
        'tetris_optimization_stats',
        'metrics_top_services_global'
      )
  LOOP
    SELECT reloptions INTO v_options
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = v_view_name
      AND n.nspname = 'public';
    
    RAISE NOTICE 'Vista %: opciones = %', v_view_name, v_options;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ Migración completada';
  RAISE NOTICE '🔍 Ejecuta el Linter para verificar';
END $$;

COMMIT;
