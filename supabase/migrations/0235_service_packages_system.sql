-- ===============================================
-- Migration: 0235_service_packages_system.sql
-- Purpose: Sistema completo de gestión de bonos/paquetes de servicios
-- Dependencies: 0002_create_core_tables.sql, 0200_create_businesses_table.sql
-- ===============================================

-- Validar dependencias
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'services' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Required table public.services does not exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'businesses' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Required table public.businesses does not exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'profiles' AND c.relkind = 'r'
  ) THEN
    RAISE EXCEPTION 'Required table public.profiles does not exist';
  END IF;
END;
$$;

BEGIN;

-- ===============================================
-- ENUM: Estado de paquetes comprados
-- ===============================================
DO $$ BEGIN
  CREATE TYPE public.package_status AS ENUM (
    'active',      -- Activo y con sesiones disponibles
    'expired',     -- Caducado por fecha
    'depleted',    -- Agotado (sin sesiones)
    'cancelled'    -- Cancelado manualmente
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ===============================================
-- TABLA 1: CATÁLOGO DE PAQUETES/BONOS
-- ===============================================
CREATE TABLE IF NOT EXISTS public.service_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  
  -- Información básica
  name text NOT NULL,
  description text,
  
  -- Configuración del paquete
  service_id uuid REFERENCES public.services(id) ON DELETE RESTRICT,
  total_sessions int NOT NULL CHECK (total_sessions > 0),
  validity_months int NOT NULL CHECK (validity_months > 0),
  
  -- Precio
  price numeric(10,2) NOT NULL CHECK (price >= 0),
  
  -- Control de disponibilidad
  is_active boolean NOT NULL DEFAULT true,
  is_legacy boolean NOT NULL DEFAULT false,
  
  -- Metadatos
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  
  -- Auditoría
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.service_packages IS
  'Catálogo de bonos/paquetes de servicios disponibles para compra';

COMMENT ON COLUMN public.service_packages.service_id IS
  'Servicio incluido en el paquete. NULL = paquete multiservicio';

COMMENT ON COLUMN public.service_packages.total_sessions IS
  'Número total de sesiones incluidas en el paquete';

COMMENT ON COLUMN public.service_packages.validity_months IS
  'Meses de validez desde la fecha de compra';

COMMENT ON COLUMN public.service_packages.is_legacy IS
  'TRUE = paquete antiguo que ya no se vende pero sigue activo para clientes existentes';

-- Índices
CREATE INDEX IF NOT EXISTS idx_packages_business ON public.service_packages(business_id);
CREATE INDEX IF NOT EXISTS idx_packages_service ON public.service_packages(service_id);
CREATE INDEX IF NOT EXISTS idx_packages_active ON public.service_packages(business_id, is_active) 
  WHERE is_active = true AND is_legacy = false;

-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_upd_service_packages ON public.service_packages;
CREATE TRIGGER trg_upd_service_packages
  BEFORE UPDATE ON public.service_packages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ===============================================
-- TABLA 2: PAQUETES COMPRADOS POR CLIENTES
-- ===============================================
CREATE TABLE IF NOT EXISTS public.client_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  
  -- Referencias
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  package_id uuid NOT NULL REFERENCES public.service_packages(id) ON DELETE RESTRICT,
  
  -- Fechas críticas
  purchased_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  
  -- Control de sesiones
  total_sessions int NOT NULL CHECK (total_sessions > 0),
  sessions_used int NOT NULL DEFAULT 0 CHECK (sessions_used >= 0),
  sessions_remaining int GENERATED ALWAYS AS (total_sessions - sessions_used) STORED,
  
  -- Estado
  status public.package_status NOT NULL DEFAULT 'active',
  
  -- Precio pagado (puede diferir del catálogo por descuentos)
  price_paid numeric(10,2) NOT NULL CHECK (price_paid >= 0),
  
  -- Metadatos
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  
  -- Auditoría
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  -- Constraints
  CONSTRAINT sessions_used_not_exceed_total CHECK (sessions_used <= total_sessions)
);

COMMENT ON TABLE public.client_packages IS
  'Paquetes/bonos comprados por clientes con control de caducidad y sesiones';

COMMENT ON COLUMN public.client_packages.expires_at IS
  'Fecha de caducidad calculada automáticamente al comprar';

COMMENT ON COLUMN public.client_packages.sessions_remaining IS
  'Columna calculada automáticamente: total_sessions - sessions_used';

COMMENT ON COLUMN public.client_packages.price_paid IS
  'Precio real pagado (puede incluir descuentos)';

-- Índices
CREATE INDEX IF NOT EXISTS idx_client_packages_business ON public.client_packages(business_id);
CREATE INDEX IF NOT EXISTS idx_client_packages_profile ON public.client_packages(profile_id);
CREATE INDEX IF NOT EXISTS idx_client_packages_status ON public.client_packages(business_id, status);
CREATE INDEX IF NOT EXISTS idx_client_packages_expires ON public.client_packages(expires_at) 
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_client_packages_active_profile ON public.client_packages(profile_id, status)
  WHERE status = 'active';

-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_upd_client_packages ON public.client_packages;
CREATE TRIGGER trg_upd_client_packages
  BEFORE UPDATE ON public.client_packages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ===============================================
-- TABLA 3: CONSUMO DE SESIONES
-- ===============================================
CREATE TABLE IF NOT EXISTS public.package_session_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  
  -- Referencias
  client_package_id uuid NOT NULL REFERENCES public.client_packages(id) ON DELETE CASCADE,
  appointment_id uuid NOT NULL REFERENCES public.appointments(id) ON DELETE RESTRICT,
  
  -- Auditoría
  used_at timestamptz NOT NULL DEFAULT now(),
  used_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  
  -- Metadatos
  notes text,
  
  -- Constraint: una cita solo puede consumir una sesión de un paquete
  CONSTRAINT unique_appointment_package UNIQUE (appointment_id, client_package_id)
);

COMMENT ON TABLE public.package_session_usage IS
  'Registro de consumo de sesiones de bonos/paquetes';

COMMENT ON COLUMN public.package_session_usage.used_by IS
  'Staff/owner que registró el uso de la sesión';

-- Índices
CREATE INDEX IF NOT EXISTS idx_usage_business ON public.package_session_usage(business_id);
CREATE INDEX IF NOT EXISTS idx_usage_package ON public.package_session_usage(client_package_id);
CREATE INDEX IF NOT EXISTS idx_usage_appointment ON public.package_session_usage(appointment_id);
CREATE INDEX IF NOT EXISTS idx_usage_date ON public.package_session_usage(used_at DESC);

-- ===============================================
-- FUNCIÓN: Crear paquete comprado con cálculo automático de caducidad
-- ===============================================
CREATE OR REPLACE FUNCTION public.purchase_package(
  p_profile_id uuid,
  p_package_id uuid,
  p_price_paid numeric DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_package RECORD;
  v_client_package_id uuid;
  v_expires_at timestamptz;
BEGIN
  -- Obtener contexto de negocio
  v_business_id := public.get_user_business_id();
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  -- Obtener información del paquete
  SELECT * INTO v_package
  FROM public.service_packages
  WHERE id = p_package_id
    AND business_id = v_business_id
    AND is_active = true;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Package not found or inactive';
  END IF;
  
  -- Calcular fecha de caducidad
  v_expires_at := now() + make_interval(months => v_package.validity_months);
  
  -- Crear registro de paquete comprado
  INSERT INTO public.client_packages (
    business_id,
    profile_id,
    package_id,
    purchased_at,
    expires_at,
    total_sessions,
    sessions_used,
    status,
    price_paid
  ) VALUES (
    v_business_id,
    p_profile_id,
    p_package_id,
    now(),
    v_expires_at,
    v_package.total_sessions,
    0,
    'active',
    COALESCE(p_price_paid, v_package.price)
  )
  RETURNING id INTO v_client_package_id;
  
  -- Registrar en auditoría
  INSERT INTO public.audit_logs (business_id, profile_id, action, payload)
  VALUES (
    v_business_id,
    p_profile_id,
    'package_purchased',
    jsonb_build_object(
      'client_package_id', v_client_package_id,
      'package_id', p_package_id,
      'package_name', v_package.name,
      'total_sessions', v_package.total_sessions,
      'expires_at', v_expires_at,
      'price_paid', COALESCE(p_price_paid, v_package.price)
    )
  );
  
  RETURN v_client_package_id;
END;
$$;

COMMENT ON FUNCTION public.purchase_package IS
  'Registra la compra de un paquete con cálculo automático de caducidad';

GRANT EXECUTE ON FUNCTION public.purchase_package(uuid, uuid, numeric) TO authenticated;

-- ===============================================
-- FUNCIÓN: Usar sesión de un paquete
-- ===============================================
CREATE OR REPLACE FUNCTION public.use_package_session(
  p_client_package_id uuid,
  p_appointment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_id uuid;
  v_package RECORD;
  v_user_id uuid;
BEGIN
  v_business_id := public.get_user_business_id();
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Business context not found';
  END IF;
  
  -- Obtener información del paquete con lock
  SELECT * INTO v_package
  FROM public.client_packages
  WHERE id = p_client_package_id
    AND business_id = v_business_id
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Package not found';
  END IF;
  
  -- Validaciones
  IF v_package.status != 'active' THEN
    RAISE EXCEPTION 'Package is not active (status: %)', v_package.status;
  END IF;
  
  IF v_package.expires_at < now() THEN
    -- Auto-expirar
    UPDATE public.client_packages
    SET status = 'expired'
    WHERE id = p_client_package_id;
    
    RAISE EXCEPTION 'Package has expired on %', v_package.expires_at;
  END IF;
  
  IF v_package.sessions_remaining <= 0 THEN
    -- Auto-agotar
    UPDATE public.client_packages
    SET status = 'depleted'
    WHERE id = p_client_package_id;
    
    RAISE EXCEPTION 'Package has no remaining sessions';
  END IF;
  
  -- Obtener usuario actual
  BEGIN
    v_user_id := (auth.jwt()->>'sub')::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_user_id := NULL;
  END;
  
  -- Registrar uso de sesión
  INSERT INTO public.package_session_usage (
    business_id,
    client_package_id,
    appointment_id,
    used_at,
    used_by
  ) VALUES (
    v_business_id,
    p_client_package_id,
    p_appointment_id,
    now(),
    v_user_id
  );
  
  -- Incrementar contador de sesiones usadas
  UPDATE public.client_packages
  SET sessions_used = sessions_used + 1
  WHERE id = p_client_package_id;
  
  -- Si era la última sesión, marcar como agotado
  IF v_package.sessions_remaining = 1 THEN
    UPDATE public.client_packages
    SET status = 'depleted'
    WHERE id = p_client_package_id;
  END IF;
  
  -- Retornar información actualizada
  RETURN jsonb_build_object(
    'success', true,
    'client_package_id', p_client_package_id,
    'sessions_used', v_package.sessions_used + 1,
    'sessions_remaining', v_package.sessions_remaining - 1,
    'status', CASE 
      WHEN v_package.sessions_remaining = 1 THEN 'depleted'
      ELSE 'active'
    END
  );
END;
$$;

COMMENT ON FUNCTION public.use_package_session IS
  'Registra el uso de una sesión de un paquete en una cita';

GRANT EXECUTE ON FUNCTION public.use_package_session(uuid, uuid) TO authenticated;

-- ===============================================
-- FUNCIÓN: Auto-expirar paquetes caducados
-- ===============================================
CREATE OR REPLACE FUNCTION public.expire_packages()
RETURNS TABLE(expired_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  UPDATE public.client_packages
  SET 
    status = 'expired',
    updated_at = now()
  WHERE status = 'active'
    AND expires_at < now();
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN QUERY SELECT v_count;
END;
$$;

COMMENT ON FUNCTION public.expire_packages IS
  'Marca como expirados todos los paquetes que superaron su fecha de caducidad';

GRANT EXECUTE ON FUNCTION public.expire_packages() TO authenticated;

-- ===============================================
-- VISTA: Paquetes activos por cliente
-- ===============================================
CREATE OR REPLACE VIEW public.client_active_packages AS
SELECT
  cp.id,
  cp.business_id,
  cp.profile_id,
  p.name as client_name,
  p.phone_number,
  sp.name as package_name,
  sp.service_id,
  s.name as service_name,
  cp.purchased_at,
  cp.expires_at,
  cp.total_sessions,
  cp.sessions_used,
  cp.sessions_remaining,
  cp.status,
  EXTRACT(days FROM (cp.expires_at - now()))::int as days_until_expiry
FROM public.client_packages cp
JOIN public.profiles p ON p.id = cp.profile_id
JOIN public.service_packages sp ON sp.id = cp.package_id
LEFT JOIN public.services s ON s.id = sp.service_id
WHERE cp.status = 'active'
ORDER BY cp.expires_at ASC;

COMMENT ON VIEW public.client_active_packages IS
  'Paquetes activos con información del cliente y días restantes hasta caducidad';

GRANT SELECT ON public.client_active_packages TO authenticated;

-- ===============================================
-- VISTA: Alertas de paquetes próximos a caducar
-- ===============================================
CREATE OR REPLACE VIEW public.package_expiry_alerts AS
SELECT
  cp.id,
  cp.business_id,
  cp.profile_id,
  p.name as client_name,
  p.phone_number,
  sp.name as package_name,
  cp.expires_at,
  cp.sessions_remaining,
  EXTRACT(days FROM (cp.expires_at - now()))::int as days_remaining,
  CASE
    WHEN cp.expires_at < now() THEN 'expired'
    WHEN cp.expires_at < now() + interval '7 days' THEN 'critical'
    WHEN cp.expires_at < now() + interval '30 days' THEN 'warning'
    ELSE 'ok'
  END as alert_level
FROM public.client_packages cp
JOIN public.profiles p ON p.id = cp.profile_id
JOIN public.service_packages sp ON sp.id = cp.package_id
WHERE cp.status = 'active'
  AND (
    cp.expires_at < now() + interval '30 days'
    OR cp.sessions_remaining <= 2
  )
ORDER BY cp.expires_at ASC;

COMMENT ON VIEW public.package_expiry_alerts IS
  'Alertas de paquetes próximos a caducar o con pocas sesiones restantes';

GRANT SELECT ON public.package_expiry_alerts TO authenticated;

-- ===============================================
-- VISTA: Estadísticas de paquetes por negocio
-- ===============================================
CREATE OR REPLACE VIEW public.package_business_stats AS
SELECT
  sp.business_id,
  sp.id as package_id,
  sp.name as package_name,
  sp.price,
  sp.total_sessions,
  sp.validity_months,
  sp.is_active,
  sp.is_legacy,
  COUNT(cp.id) as total_sold,
  COUNT(cp.id) FILTER (WHERE cp.status = 'active') as currently_active,
  COUNT(cp.id) FILTER (WHERE cp.status = 'expired') as expired,
  COUNT(cp.id) FILTER (WHERE cp.status = 'depleted') as depleted,
  SUM(cp.price_paid) as total_revenue,
  AVG(cp.sessions_used) as avg_sessions_used,
  SUM(cp.sessions_remaining) FILTER (WHERE cp.status = 'active') as total_sessions_remaining
FROM public.service_packages sp
LEFT JOIN public.client_packages cp ON cp.package_id = sp.id
GROUP BY sp.business_id, sp.id, sp.name, sp.price, sp.total_sessions, sp.validity_months, sp.is_active, sp.is_legacy
ORDER BY total_sold DESC;

COMMENT ON VIEW public.package_business_stats IS
  'Estadísticas de ventas y uso de paquetes por negocio';

GRANT SELECT ON public.package_business_stats TO authenticated;

-- ===============================================
-- RLS: Row Level Security
-- ===============================================

-- service_packages
ALTER TABLE public.service_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS packages_read ON public.service_packages;
CREATE POLICY packages_read ON public.service_packages
  FOR SELECT TO authenticated
  USING (business_id = public.get_user_business_id());

DROP POLICY IF EXISTS packages_owner_write ON public.service_packages;
CREATE POLICY packages_owner_write ON public.service_packages
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

-- client_packages
ALTER TABLE public.client_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS client_packages_owner_all ON public.client_packages;
CREATE POLICY client_packages_owner_all ON public.client_packages
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

DROP POLICY IF EXISTS client_packages_lead_read ON public.client_packages;
CREATE POLICY client_packages_lead_read ON public.client_packages
  FOR SELECT TO authenticated
  USING (
    business_id = public.get_user_business_id()
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = client_packages.profile_id
        AND p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

-- package_session_usage
ALTER TABLE public.package_session_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS usage_owner_all ON public.package_session_usage;
CREATE POLICY usage_owner_all ON public.package_session_usage
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

DROP POLICY IF EXISTS usage_lead_read ON public.package_session_usage;
CREATE POLICY usage_lead_read ON public.package_session_usage
  FOR SELECT TO authenticated
  USING (
    business_id = public.get_user_business_id()
    AND EXISTS (
      SELECT 1 
      FROM public.client_packages cp
      JOIN public.profiles p ON p.id = cp.profile_id
      WHERE cp.id = package_session_usage.client_package_id
        AND p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

COMMIT;
