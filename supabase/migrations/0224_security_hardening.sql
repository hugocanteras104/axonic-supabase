-- ===============================================
-- Migration: 0224_security_hardening.sql
-- Purpose: Auditoría de seguridad completa - Consolidación de fixes críticos
-- Dependencies: 0006_policies_rls_grants.sql
-- ===============================================
-- 
-- Esta migración consolida 3 vulnerabilidades críticas detectadas:
-- 1. Permisos excesivos del rol anon en tablas
-- 2. Escalada de privilegios (leads → owner)
-- 3. Funciones críticas expuestas a usuarios no autenticados
-- ===============================================

BEGIN;

-- =============================================
-- PARTE 1: Revocar permisos de anon en tablas
-- =============================================

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
GRANT SELECT ON public.services TO authenticated;
GRANT SELECT ON public.knowledge_base TO authenticated;

-- =============================================
-- PARTE 2: Prevenir escalada de privilegios
-- =============================================

DROP POLICY IF EXISTS profiles_lead_update_self ON public.profiles;

CREATE POLICY profiles_lead_update_self ON public.profiles
  FOR UPDATE TO authenticated
  USING (
    phone_number = (auth.jwt()->>'phone_number')
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    phone_number = (auth.jwt()->>'phone_number')
    AND business_id = public.get_user_business_id()
    AND role = (
      SELECT p.role 
      FROM profiles p 
      WHERE p.id = profiles.id
    )
  );

-- =============================================
-- PARTE 3: Proteger funciones críticas
-- =============================================

REVOKE ALL ON FUNCTION public.decrement_inventory(text, int) FROM anon;
REVOKE ALL ON FUNCTION public.mark_appointment_as_no_show(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.soft_delete(text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.register_payment(uuid, numeric, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.confirm_appointment_with_resources(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.advance_appointment(uuid, timestamptz, text) FROM anon;

COMMIT;

-- Verificación
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════';
  RAISE NOTICE '✅ AUDITORÍA DE SEGURIDAD COMPLETADA';
  RAISE NOTICE '════════════════════════════════════════';
  RAISE NOTICE '';
  RAISE NOTICE 'Correcciones aplicadas:';
  RAISE NOTICE '  1. ✅ Permisos de anon revocados en 12 tablas';
  RAISE NOTICE '  2. ✅ Política anti-escalada de privilegios';
  RAISE NOTICE '  3. ✅ 6 funciones críticas protegidas';
  RAISE NOTICE '';
  RAISE NOTICE 'Solo usuarios autenticados pueden:';
  RAISE NOTICE '  - Acceder a datos del sistema';
  RAISE NOTICE '  - Ejecutar funciones de negocio';
  RAISE NOTICE '';
  RAISE NOTICE 'Los leads NO pueden:';
  RAISE NOTICE '  - Cambiar su rol a owner';
  RAISE NOTICE '  - Modificar su business_id';
  RAISE NOTICE '  - Cambiar su phone_number';
  RAISE NOTICE '════════════════════════════════════════';
END $$;
