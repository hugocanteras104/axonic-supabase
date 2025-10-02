-- ===============================================
-- Migration: 0229_fix_anon_permissions.sql
-- Purpose: Revocar permisos excesivos del rol anon en tablas críticas
-- Dependencies: 0006_policies_rls_grants.sql
-- ===============================================

BEGIN;

-- Revocar TODOS los permisos de anon en tablas críticas
REVOKE ALL ON public.profiles FROM anon;
REVOKE ALL ON public.appointments FROM anon;
REVOKE ALL ON public.services FROM anon;
REVOKE ALL ON public.inventory FROM anon;
REVOKE ALL ON public.knowledge_base FROM anon;
REVOKE ALL ON public.resources FROM anon;
REVOKE ALL ON public.waitlists FROM anon;
REVOKE ALL ON public.audit_logs FROM anon;
REVOKE ALL ON public.cross_sell_rules FROM anon;
REVOKE ALL ON public.notifications_queue FROM anon;
REVOKE ALL ON public.businesses FROM anon;
REVOKE ALL ON public.business_settings FROM anon;

-- Dar solo SELECT a authenticated donde sea necesario
-- (servicios y KB deben ser legibles para mostrar catálogo)
GRANT SELECT ON public.services TO authenticated;
GRANT SELECT ON public.knowledge_base TO authenticated;

COMMIT;

-- Verificación
DO $$
BEGIN
  RAISE NOTICE '✅ Permisos de anon revocados';
  RAISE NOTICE '✅ Solo authenticated puede acceder a datos sensibles';
  RAISE NOTICE '';
  RAISE NOTICE 'Las tablas ahora dependen 100%% de RLS para control de acceso';
END $$;
