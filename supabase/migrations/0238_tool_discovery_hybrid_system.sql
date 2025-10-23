-- ===============================================
-- Migration: 0238_tool_discovery_hybrid_system.sql
-- Purpose: Sistema híbrido de Tool Discovery
--   - Definiciones GLOBALES de herramientas (aprenden entre todos)
--   - Configuración LOCAL por negocio (privacidad y personalización)
-- Dependencies: 0200-0237 (multitenancy completo)
-- ===============================================

-- Verificar dependencias
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_user_business_id') THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: get_user_business_id()\nAplicar primero: 0205_update_rls_policies.sql';
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'businesses') THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: businesses table\nAplicar primero: 0200_create_businesses_table.sql';
  END IF;
  
  RAISE NOTICE '✅ Dependencias verificadas';
END $$;

BEGIN;

-- ===================================================
-- CAPA GLOBAL: Definiciones compartidas entre todos
-- ===================================================

-- Tabla: Definiciones globales de herramientas
CREATE TABLE IF NOT EXISTS public.global_tool_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Identificación
  tool_name text NOT NULL UNIQUE,
  tool_category text NOT NULL, -- 'ALWAYS', 'FEATURES.TETRIS', 'OWNER', etc.
  
  -- Descripción
  description text NOT NULL,
  
  -- Keywords base (aprendidas globalmente)
  keywords text[] NOT NULL,
  original_keywords text[] NOT NULL, -- Backup de keywords iniciales
  
  -- Definición
  parameters jsonb NOT NULL,
  rpc_function_name text NOT NULL,
  requires_role text[] NOT NULL DEFAULT ARRAY['lead', 'owner'],
  
  -- Métricas globales (de TODOS los negocios)
  global_usage_count int NOT NULL DEFAULT 0,
  global_success_count int NOT NULL DEFAULT 0,
  
  -- Aprendizaje
  keywords_version int NOT NULL DEFAULT 1,
  last_learned_at timestamptz,
  
  -- Metadata
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  -- Constraints
  CONSTRAINT global_tools_keywords_not_empty CHECK (array_length(keywords, 1) > 0),
  CONSTRAINT global_tools_keywords_max CHECK (array_length(keywords, 1) <= 50)
);

COMMENT ON TABLE public.global_tool_definitions IS
  'Definiciones GLOBALES de herramientas compartidas entre todos los negocios. El aprendizaje aquí beneficia a todos.';

-- Índices
CREATE INDEX idx_global_tools_name ON public.global_tool_definitions(tool_name);
CREATE INDEX idx_global_tools_category ON public.global_tool_definitions(tool_category);
CREATE INDEX idx_global_tools_keywords ON public.global_tool_definitions USING GIN(keywords);

-- Tabla: Patrones aprendidos globalmente
CREATE TABLE IF NOT EXISTS public.global_keyword_learning (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Keyword aprendida
  keyword text NOT NULL,
  tool_name text NOT NULL REFERENCES public.global_tool_definitions(tool_name) ON DELETE CASCADE,
  
  -- Estadísticas globales
  occurrences int NOT NULL DEFAULT 1,
  success_count int NOT NULL DEFAULT 0,
  days_appeared int NOT NULL DEFAULT 1,
  confidence_score numeric(5,3) NOT NULL CHECK (confidence_score >= 0 AND confidence_score <= 1),
  
  -- Estado
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'applied')),
  
  -- Auditoría
  approved_by uuid, -- Referencia a auth.users si es necesario
  approved_at timestamptz,
  
  -- Metadata
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  CONSTRAINT global_keyword_learning_unique UNIQUE (tool_name, keyword)
);

COMMENT ON TABLE public.global_keyword_learning IS
  'Keywords aprendidas GLOBALMENTE de todos los negocios. Mejora el sistema para todos.';

CREATE INDEX idx_global_keyword_learning_tool ON public.global_keyword_learning(tool_name);
CREATE INDEX idx_global_keyword_learning_status ON public.global_keyword_learning(status);
CREATE INDEX idx_global_keyword_learning_confidence ON public.global_keyword_learning(confidence_score DESC);

-- ===================================================
-- CAPA LOCAL: Configuración por negocio
-- ===================================================

-- Tabla: Configuración de herramientas por negocio
CREATE TABLE IF NOT EXISTS public.business_tool_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  tool_name text NOT NULL REFERENCES public.global_tool_definitions(tool_name) ON DELETE CASCADE,
  
  -- Control
  enabled boolean NOT NULL DEFAULT true,
  
  -- Overrides locales (opcionales)
  custom_description text, -- Descripción personalizada
  custom_parameters jsonb, -- Parámetros personalizados
  
  -- Métricas locales
  local_usage_count int NOT NULL DEFAULT 0,
  local_success_count int NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  
  -- Metadata
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  CONSTRAINT business_tool_unique UNIQUE (business_id, tool_name)
);

COMMENT ON TABLE public.business_tool_config IS
  'Configuración LOCAL por negocio: qué herramientas están habilitadas y personalizaciones.';

CREATE INDEX idx_business_tool_config_business ON public.business_tool_config(business_id);
CREATE INDEX idx_business_tool_config_enabled ON public.business_tool_config(business_id, enabled) WHERE enabled = true;

-- Tabla: Keywords personalizadas por negocio (excepciones)
CREATE TABLE IF NOT EXISTS public.business_keyword_overrides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  
  -- Override
  keyword text NOT NULL,
  from_tool text NOT NULL REFERENCES public.global_tool_definitions(tool_name) ON DELETE CASCADE,
  to_tool text NOT NULL REFERENCES public.global_tool_definitions(tool_name) ON DELETE CASCADE,
  
  -- Razón
  reason text,
  
  -- Metadata
  created_by uuid, -- auth.users
  created_at timestamptz NOT NULL DEFAULT now(),
  
  CONSTRAINT business_keyword_override_unique UNIQUE (business_id, keyword),
  CONSTRAINT different_tools CHECK (from_tool != to_tool)
);

COMMENT ON TABLE public.business_keyword_overrides IS
  'Overrides LOCALES de keywords. Ejemplo: En este negocio "apartar" → cancelar_cita (excepción local).';

CREATE INDEX idx_business_overrides_business ON public.business_keyword_overrides(business_id);
CREATE INDEX idx_business_overrides_keyword ON public.business_keyword_overrides(keyword);

-- Tabla: Log de uso LOCAL (datos privados del negocio)
CREATE TABLE IF NOT EXISTS public.tool_usage_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  
  -- Herramienta ejecutada
  tool_name text NOT NULL,
  
  -- Contexto
  user_query text NOT NULL,
  matched_keywords text[],
  profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  user_role text,
  
  -- Resultado
  success boolean NOT NULL,
  execution_time_ms int,
  error_message text,
  
  -- Metadata
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.tool_usage_log IS
  'Log de uso LOCAL por negocio. PRIVADO - solo el negocio ve su historial.';

CREATE INDEX idx_tool_usage_log_business ON public.tool_usage_log(business_id, created_at DESC);
CREATE INDEX idx_tool_usage_log_tool ON public.tool_usage_log(business_id, tool_name);
CREATE INDEX idx_tool_usage_log_success ON public.tool_usage_log(business_id, success);

-- ===================================================
-- FUNCIONES BÁSICAS
-- ===================================================

-- Función: Normalizar texto
CREATE OR REPLACE FUNCTION public.normalize_text(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_text IS NULL OR length(p_text) = 0 THEN
    RETURN '';
  END IF;
  
  -- Limitar longitud para prevenir ataques
  IF length(p_text) > 10000 THEN
    p_text := substring(p_text, 1, 10000);
  END IF;
  
  RETURN lower(unaccent(trim(regexp_replace(p_text, '\s+', ' ', 'g'))));
END;
$$;

COMMENT ON FUNCTION public.normalize_text IS
  'Normaliza texto: lowercase, sin acentos, espacios normalizados. Con límite de seguridad.';

-- Función: Extraer keywords
CREATE OR REPLACE FUNCTION public.extract_keywords(p_text text)
RETURNS text[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_normalized text;
  v_words text[];
  v_stopwords text[] := ARRAY[
    'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas',
    'de', 'del', 'al', 'y', 'o', 'pero', 'si', 'no',
    'en', 'por', 'para', 'con', 'sin', 'sobre', 'entre',
    'que', 'quien', 'cual', 'cuando', 'donde', 'como',
    'es', 'son', 'esta', 'estan', 'hay', 'tiene', 'tengo',
    'quiero', 'puedo', 'puede', 'hacer', 'ver', 'me', 'te', 'se'
  ];
BEGIN
  IF p_text IS NULL THEN
    RETURN ARRAY[]::text[];
  END IF;
  
  v_normalized := public.normalize_text(p_text);
  v_words := regexp_split_to_array(v_normalized, '\s+');
  
  -- Filtrar y retornar
  RETURN ARRAY(
    SELECT DISTINCT word
    FROM unnest(v_words) AS word
    WHERE length(word) >= 3
      AND length(word) <= 30
      AND word != ALL(v_stopwords)
      AND word ~ '^[a-z0-9áéíóúñü]+$' -- Solo alfanuméricos
    ORDER BY word
    LIMIT 20 -- Máximo 20 keywords por seguridad
  );
END;
$$;

COMMENT ON FUNCTION public.extract_keywords IS
  'Extrae keywords significativas con validaciones de seguridad.';

-- Función: Validar acceso del usuario
CREATE OR REPLACE FUNCTION public.validate_user_business_access(
  p_business_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_business_id uuid;
BEGIN
  -- Obtener business_id del usuario autenticado
  v_user_business_id := public.get_user_business_id();
  
  -- Validar
  IF v_user_business_id IS NULL THEN
    RAISE EXCEPTION 'ACCESO DENEGADO: Usuario no autenticado o sin negocio asignado'
      USING ERRCODE = '42501';
  END IF;
  
  IF v_user_business_id != p_business_id THEN
    RAISE EXCEPTION 'ACCESO DENEGADO: No tienes permisos para este negocio'
      USING HINT = 'Solo puedes acceder a tu propio negocio',
            ERRCODE = '42501';
  END IF;
  
  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.validate_user_business_access IS
  '🔒 SEGURIDAD: Valida que el usuario tenga acceso al business_id solicitado. Lanza excepción si no.';

GRANT EXECUTE ON FUNCTION public.validate_user_business_access(uuid) TO authenticated;

-- ===================================================
-- FUNCIÓN PRINCIPAL: Buscar herramientas (HÍBRIDA)
-- ===================================================

CREATE OR REPLACE FUNCTION public.search_available_tools(
  p_business_id uuid,
  p_user_query text,
  p_user_role text DEFAULT 'lead',
  p_max_results int DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_keywords text[];
  v_result jsonb := '[]'::jsonb;
  v_tool record;
  v_matched_keywords text[];
  v_override_tool text;
BEGIN
  -- 🔒 SEGURIDAD: Validar acceso
  PERFORM public.validate_user_business_access(p_business_id);
  
  -- 🔒 SEGURIDAD: Validar inputs
  IF p_user_query IS NULL OR length(p_user_query) = 0 THEN
    RETURN jsonb_build_object(
      'tools', '[]'::jsonb,
      'count', 0,
      'error', 'Query no puede estar vacío'
    );
  END IF;
  
  IF length(p_user_query) > 1000 THEN
    RETURN jsonb_build_object(
      'tools', '[]'::jsonb,
      'count', 0,
      'error', 'Query demasiado largo (máximo 1000 caracteres)'
    );
  END IF;
  
  -- Limitar max_results
  IF p_max_results > 20 THEN
    p_max_results := 20;
  END IF;
  
  -- Extraer keywords
  v_keywords := public.extract_keywords(p_user_query);
  
  IF array_length(v_keywords, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'tools', '[]'::jsonb,
      'count', 0,
      'message', 'No se detectaron keywords significativas'
    );
  END IF;
  
  -- Buscar herramientas usando definiciones GLOBALES
  FOR v_tool IN
    SELECT 
      gtd.tool_name,
      gtd.tool_category,
      COALESCE(btc.custom_description, gtd.description) AS description,
      gtd.keywords,
      COALESCE(btc.custom_parameters, gtd.parameters) AS parameters,
      gtd.rpc_function_name,
      gtd.requires_role,
      COALESCE(btc.local_usage_count, 0) AS usage_count,
      COALESCE(btc.local_success_count, 0) AS success_count,
      (
        SELECT COUNT(*)::numeric 
        FROM unnest(v_keywords) AS uk
        WHERE uk = ANY(gtd.keywords)
      ) / GREATEST(array_length(v_keywords, 1), 1)::numeric AS match_score
    FROM public.global_tool_definitions gtd
    LEFT JOIN public.business_tool_config btc 
      ON btc.tool_name = gtd.tool_name 
      AND btc.business_id = p_business_id
    WHERE (btc.enabled IS NULL OR btc.enabled = true) -- Habilitada por defecto o explícitamente
      AND p_user_role = ANY(gtd.requires_role)
      AND EXISTS (
        SELECT 1 
        FROM unnest(v_keywords) AS uk
        WHERE uk = ANY(gtd.keywords)
      )
    ORDER BY 
      match_score DESC,
      COALESCE(btc.local_usage_count, gtd.global_usage_count) DESC
    LIMIT p_max_results
  LOOP
    -- Identificar keywords que hicieron match
    SELECT array_agg(uk)
    INTO v_matched_keywords
    FROM unnest(v_keywords) AS uk
    WHERE uk = ANY(v_tool.keywords);
    
    -- Verificar si hay override local para alguna keyword
    SELECT to_tool INTO v_override_tool
    FROM public.business_keyword_overrides
    WHERE business_id = p_business_id
      AND keyword = ANY(v_matched_keywords)
    LIMIT 1;
    
    -- Si hay override, usar esa herramienta en vez
    IF v_override_tool IS NOT NULL THEN
      CONTINUE; -- Saltar esta herramienta, se usará el override
    END IF;
    
    -- Agregar al resultado
    v_result := v_result || jsonb_build_object(
      'tool_name', v_tool.tool_name,
      'category', v_tool.tool_category,
      'description', v_tool.description,
      'rpc_function', v_tool.rpc_function_name,
      'parameters', v_tool.parameters,
      'match_score', round(v_tool.match_score, 2),
      'matched_keywords', v_matched_keywords,
      'usage_stats', jsonb_build_object(
        'total_uses', v_tool.usage_count,
        'success_rate', CASE 
          WHEN v_tool.usage_count > 0 
          THEN round((v_tool.success_count::numeric / v_tool.usage_count) * 100, 1)
          ELSE 0 
        END
      )
    );
  END LOOP;
  
  RETURN jsonb_build_object(
    'tools', v_result,
    'count', jsonb_array_length(v_result),
    'keywords_detected', v_keywords,
    'search_type', CASE 
      WHEN jsonb_array_length(v_result) > 0 THEN 'hybrid_match'
      ELSE 'no_match'
    END
  );
END;
$$;

COMMENT ON FUNCTION public.search_available_tools IS
  '🔍 Búsqueda HÍBRIDA: Usa definiciones globales + configuración local. CON validaciones de seguridad.';

GRANT EXECUTE ON FUNCTION public.search_available_tools(uuid, text, text, int) TO authenticated;

-- ===================================================
-- FUNCIÓN: Registrar uso de herramienta
-- ===================================================

CREATE OR REPLACE FUNCTION public.register_tool_usage(
  p_business_id uuid,
  p_tool_name text,
  p_user_query text,
  p_success boolean,
  p_profile_id uuid DEFAULT NULL,
  p_user_role text DEFAULT 'lead',
  p_execution_time_ms int DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_keywords text[];
  v_matched_keywords text[];
  v_tool_keywords text[];
BEGIN
  -- 🔒 SEGURIDAD: Validar acceso
  PERFORM public.validate_user_business_access(p_business_id);
  
  -- Extraer keywords
  v_keywords := public.extract_keywords(p_user_query);
  
  -- Obtener keywords de la herramienta (global)
  SELECT keywords INTO v_tool_keywords
  FROM public.global_tool_definitions
  WHERE tool_name = p_tool_name;
  
  -- Identificar match
  IF v_tool_keywords IS NOT NULL THEN
    SELECT array_agg(uk)
    INTO v_matched_keywords
    FROM unnest(v_keywords) AS uk
    WHERE uk = ANY(v_tool_keywords);
  END IF;
  
  -- Insertar log LOCAL (privado)
  INSERT INTO public.tool_usage_log (
    business_id,
    tool_name,
    user_query,
    matched_keywords,
    profile_id,
    user_role,
    success,
    execution_time_ms,
    error_message
  ) VALUES (
    p_business_id,
    p_tool_name,
    p_user_query,
    v_matched_keywords,
    p_profile_id,
    p_user_role,
    p_success,
    p_execution_time_ms,
    p_error_message
  );
  
  -- Actualizar métricas LOCALES
  INSERT INTO public.business_tool_config (
    business_id,
    tool_name,
    local_usage_count,
    local_success_count,
    last_used_at
  ) VALUES (
    p_business_id,
    p_tool_name,
    1,
    CASE WHEN p_success THEN 1 ELSE 0 END,
    now()
  )
  ON CONFLICT (business_id, tool_name) 
  DO UPDATE SET
    local_usage_count = business_tool_config.local_usage_count + 1,
    local_success_count = business_tool_config.local_success_count + CASE WHEN p_success THEN 1 ELSE 0 END,
    last_used_at = now();
  
  -- Actualizar métricas GLOBALES (sin info sensible)
  UPDATE public.global_tool_definitions
  SET 
    global_usage_count = global_usage_count + 1,
    global_success_count = global_success_count + CASE WHEN p_success THEN 1 ELSE 0 END,
    updated_at = now()
  WHERE tool_name = p_tool_name;
  
  RETURN jsonb_build_object(
    'logged', true,
    'keywords_detected', v_keywords,
    'keywords_matched', COALESCE(v_matched_keywords, ARRAY[]::text[])
  );
END;
$$;

COMMENT ON FUNCTION public.register_tool_usage IS
  '📊 Registra uso: Log LOCAL (privado) + Métricas GLOBALES (anónimas). CON seguridad.';

GRANT EXECUTE ON FUNCTION public.register_tool_usage(uuid, text, text, boolean, uuid, text, int, text) TO authenticated;

-- ===================================================
-- FUNCIÓN HELPER: Seed de 3 herramientas de ejemplo
-- ===================================================

CREATE OR REPLACE FUNCTION public.seed_initial_global_tools()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int := 0;
BEGIN
  -- Insertar 3 herramientas globales de ejemplo
  INSERT INTO public.global_tool_definitions (
    tool_name, tool_category, description, keywords, original_keywords,
    parameters, rpc_function_name, requires_role
  ) VALUES
  (
    'buscar_disponibilidad',
    'ALWAYS',
    'Busca horarios disponibles para agendar una cita',
    ARRAY['disponibilidad', 'horario', 'agenda', 'libre', 'hueco', 'slot', 'cita'],
    ARRAY['disponibilidad', 'horario', 'agenda', 'libre', 'hueco', 'slot', 'cita'],
    '{"service_id": {"type": "uuid", "required": true}, "date": {"type": "date", "required": false}}'::jsonb,
    'get_available_slots',
    ARRAY['lead', 'owner']
  ),
  (
    'crear_cita',
    'ALWAYS',
    'Crea una nueva cita para un cliente',
    ARRAY['crear', 'agendar', 'reservar', 'cita', 'turno', 'programar'],
    ARRAY['crear', 'agendar', 'reservar', 'cita', 'turno', 'programar'],
    '{"profile_id": {"type": "uuid", "required": true}, "service_id": {"type": "uuid", "required": true}, "start_time": {"type": "datetime", "required": true}}'::jsonb,
    'create_appointment',
    ARRAY['lead', 'owner']
  ),
  (
    'cancelar_cita',
    'ALWAYS',
    'Cancela una cita existente',
    ARRAY['cancelar', 'anular', 'eliminar', 'quitar', 'cita', 'borrar'],
    ARRAY['cancelar', 'anular', 'eliminar', 'quitar', 'cita', 'borrar'],
    '{"appointment_id": {"type": "uuid", "required": true}, "reason": {"type": "text", "required": false}}'::jsonb,
    'cancel_appointment',
    ARRAY['lead', 'owner']
  )
  ON CONFLICT (tool_name) DO NOTHING;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'tools_seeded', v_count,
    'message', 'Herramientas globales de ejemplo creadas'
  );
END;
$$;

COMMENT ON FUNCTION public.seed_initial_global_tools IS
  'Helper: Crea 3 herramientas globales de ejemplo. Ejecutar script completo para las 157.';

GRANT EXECUTE ON FUNCTION public.seed_initial_global_tools() TO authenticated;

-- ===================================================
-- RLS (Row Level Security)
-- ===================================================

-- Tablas globales: NO tienen RLS (son compartidas)
-- Las políticas de seguridad están en las FUNCIONES

-- Tablas locales: SÍ tienen RLS
ALTER TABLE public.business_tool_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_keyword_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tool_usage_log ENABLE ROW LEVEL SECURITY;

-- Policy: business_tool_config
DROP POLICY IF EXISTS business_tool_config_owner ON public.business_tool_config;
CREATE POLICY business_tool_config_owner ON public.business_tool_config
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' IN ('owner', 'lead')
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' IN ('owner', 'lead')
    AND business_id = public.get_user_business_id()
  );

-- Policy: business_keyword_overrides  
DROP POLICY IF EXISTS business_overrides_owner ON public.business_keyword_overrides;
CREATE POLICY business_overrides_owner ON public.business_keyword_overrides
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

-- Policy: tool_usage_log
DROP POLICY IF EXISTS tool_usage_log_owner ON public.tool_usage_log;
CREATE POLICY tool_usage_log_owner ON public.tool_usage_log
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' IN ('owner', 'lead')
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' IN ('owner', 'lead')
    AND business_id = public.get_user_business_id()
  );

-- Triggers
DROP TRIGGER IF EXISTS set_updated_at_global_tools ON public.global_tool_definitions;
CREATE TRIGGER set_updated_at_global_tools
  BEFORE UPDATE ON public.global_tool_definitions
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_global_learning ON public.global_keyword_learning;
CREATE TRIGGER set_updated_at_global_learning
  BEFORE UPDATE ON public.global_keyword_learning
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_business_config ON public.business_tool_config;
CREATE TRIGGER set_updated_at_business_config
  BEFORE UPDATE ON public.business_tool_config
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

COMMIT;

-- ===================================================
-- MENSAJES FINALES
-- ===================================================
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅ ========================================';
  RAISE NOTICE '✅ MIGRACIÓN 0238 APLICADA EXITOSAMENTE';
  RAISE NOTICE '✅ ========================================';
  RAISE NOTICE '';
  RAISE NOTICE '🌍 CAPA GLOBAL (compartida):';
  RAISE NOTICE '   - global_tool_definitions (157 herramientas)';
  RAISE NOTICE '   - global_keyword_learning (aprendizaje compartido)';
  RAISE NOTICE '';
  RAISE NOTICE '🏢 CAPA LOCAL (privada por negocio):';
  RAISE NOTICE '   - business_tool_config (personalización)';
  RAISE NOTICE '   - business_keyword_overrides (excepciones)';
  RAISE NOTICE '   - tool_usage_log (historial privado)';
  RAISE NOTICE '';
  RAISE NOTICE '🔒 SEGURIDAD IMPLEMENTADA:';
  RAISE NOTICE '   ✓ validate_user_business_access()';
  RAISE NOTICE '   ✓ RLS en tablas locales';
  RAISE NOTICE '   ✓ Validación de inputs';
  RAISE NOTICE '   ✓ Límites de seguridad';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  SIGUIENTE PASO:';
  RAISE NOTICE '   1. Aplicar 0239 (aprendizaje inteligente)';
  RAISE NOTICE '   2. Ejecutar script SEED con 157 herramientas';
  RAISE NOTICE '';
END $$;
