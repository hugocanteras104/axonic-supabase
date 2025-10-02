-- ===============================================
-- Migration: 0231_revoke_anon_dangerous_functions.sql
-- Purpose: Revocar permisos de anon en funciones críticas
-- Security: Prevenir acceso no autenticado a operaciones sensibles
-- ===============================================

BEGIN;

-- Revocar permisos de anon en funciones críticas de negocio
REVOKE ALL ON FUNCTION public.decrement_inventory(text, int) FROM anon;
REVOKE ALL ON FUNCTION public.mark_appointment_as_no_show(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.soft_delete(text, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.register_payment(uuid, numeric, text, text, text) FROM anon;

-- Revocar en otras funciones sensibles
REVOKE ALL ON FUNCTION public.confirm_appointment_with_resources(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.advance_appointment(uuid, timestamptz, text) FROM anon;

COMMIT;

-- Verificación
DO $$
BEGIN
  RAISE NOTICE '✅ Permisos de anon revocados en funciones críticas';
  RAISE NOTICE '';
  RAISE NOTICE 'Funciones protegidas:';
  RAISE NOTICE '  - decrement_inventory';
  RAISE NOTICE '  - mark_appointment_as_no_show';
  RAISE NOTICE '  - soft_delete';
  RAISE NOTICE '  - register_payment';
  RAISE NOTICE '  - confirm_appointment_with_resources';
  RAISE NOTICE '  - advance_appointment';
  RAISE NOTICE '';
  RAISE NOTICE 'Solo usuarios autenticados pueden ejecutarlas';
END $$;
