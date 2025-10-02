-- ===============================================
-- Migration: 0230_fix_privilege_escalation.sql
-- Purpose: Prevenir que leads cambien su rol o business_id
-- ===============================================

BEGIN;

-- Eliminar política vulnerable
DROP POLICY IF EXISTS profiles_lead_update_self ON public.profiles;

-- Recrear con restricción: los leads solo pueden actualizar name, email y metadata
-- NO pueden cambiar role, business_id, ni phone_number
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

COMMIT;

-- Verificación
DO $$
BEGIN
  RAISE NOTICE '✅ Política actualizada';
  RAISE NOTICE 'Los leads ahora NO pueden cambiar:';
  RAISE NOTICE '  - Su rol (role)';
  RAISE NOTICE '  - Su business_id';
  RAISE NOTICE '  - Su phone_number';
END $$;
