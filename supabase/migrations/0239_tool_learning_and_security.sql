-- ===============================================
-- Migration: 0239_tool_learning_and_security.sql
-- Purpose: Sistema de aprendizaje inteligente + Seguridad avanzada
-- Dependencies: 0238_tool_discovery_hybrid_system.sql
-- ===============================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'global_tool_definitions') THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: 0238';
  END IF;
  RAISE NOTICE '✅ Dependencia verificada';
END $$;

BEGIN;

-- ===================================================
-- SEGURIDAD: Rate Limiting
-- ===================================================

CREATE TABLE IF NOT EXISTS public.tool_api_rate_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  
  -- Contadores
  calls_last_minute int NOT NULL DEFAULT 0,
  calls_last_hour int NOT NULL DEFAULT 0,
  
  -- Ventanas
  minute_window_start timestamptz NOT NULL DEFAULT now(),
  hour_window_start timestamptz NOT NULL DEFAULT now(),
  
  -- Bloqueo
  blocked_until timestamptz,
  block_reason text,
  
  last_call_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  
  CONSTRAINT rate_limits_unique UNIQUE (user_id, business_id, endpoint)
);

COMMENT ON TABLE public.tool_api_rate_limits IS
  '🔒 Rate limiting para prevenir abuso. Límites: 60/min, 1000/hora.';

CREATE INDEX idx_rate_limits_user ON public.tool_api_rate_limits(user_id, business_id);

-- Función: Check rate limit
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_business_id uuid,
  p_endpoint text,
  p_limit_per_minute int DEFAULT 60,
  p_limit_per_hour int DEFAULT 1000
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_record record;
  v_now timestamptz := now();
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '42501';
  END IF;
  
  -- Crear o actualizar registro
  INSERT INTO public.tool_api_rate_limits (user_id, business_id, endpoint)
  VALUES (v_user_id, p_business_id, p_endpoint)
  ON CONFLICT (user_id, business_id, endpoint) DO NOTHING;
  
  SELECT * INTO v_record
  FROM public.tool_api_rate_limits
  WHERE user_id = v_user_id AND business_id = p_business_id AND endpoint = p_endpoint
  FOR UPDATE;
  
  -- Verificar bloqueo
  IF v_record.blocked_until IS NOT NULL AND v_record.blocked_until > v_now THEN
    RAISE EXCEPTION 'BLOQUEADO hasta %', v_record.blocked_until
      USING ERRCODE = '54000';
  END IF;
  
  -- Resetear ventanas
  IF v_now - v_record.minute_window_start > interval '1 minute' THEN
    UPDATE public.tool_api_rate_limits
    SET calls_last_minute = 0, minute_window_start = v_now
    WHERE id = v_record.id;
    v_record.calls_last_minute := 0;
  END IF;
  
  IF v_now - v_record.hour_window_start > interval '1 hour' THEN
    UPDATE public.tool_api_rate_limits
    SET calls_last_hour = 0, hour_window_start = v_now
    WHERE id = v_record.id;
    v_record.calls_last_hour := 0;
  END IF;
  
  -- Verificar límites
  IF v_record.calls_last_minute >= p_limit_per_minute THEN
    UPDATE public.tool_api_rate_limits
    SET blocked_until = v_now + interval '1 minute',
        block_reason = 'Límite por minuto'
    WHERE id = v_record.id;
    RAISE EXCEPTION 'Máximo % llamadas/min excedido', p_limit_per_minute USING ERRCODE = '54000';
  END IF;
  
  IF v_record.calls_last_hour >= p_limit_per_hour THEN
    UPDATE public.tool_api_rate_limits
    SET blocked_until = v_now + interval '10 minutes',
        block_reason = 'Límite por hora'
    WHERE id = v_record.id;
    RAISE EXCEPTION 'Máximo % llamadas/hora excedido', p_limit_per_hour USING ERRCODE = '54000';
  END IF;
  
  -- Incrementar
  UPDATE public.tool_api_rate_limits
  SET calls_last_minute = calls_last_minute + 1,
      calls_last_hour = calls_last_hour + 1,
      last_call_at = v_now
  WHERE id = v_record.id;
  
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, int, int) TO authenticated;

-- ===================================================
-- SEGURIDAD: Auditoría
-- ===================================================

CREATE TABLE IF NOT EXISTS public.tool_security_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  business_id uuid,
  event_type text NOT NULL,
  endpoint text NOT NULL,
  success boolean NOT NULL,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.tool_security_audit_log IS
  '🔒 Log de auditoría de seguridad.';

CREATE INDEX idx_security_audit_user ON public.tool_security_audit_log(user_id, created_at DESC);
CREATE INDEX idx_security_audit_failed ON public.tool_security_audit_log(success) WHERE success = false;

-- Función: Log de seguridad
CREATE OR REPLACE FUNCTION public.log_security_event(
  p_event_type text,
  p_endpoint text,
  p_success boolean,
  p_error_message text DEFAULT NULL,
  p_business_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.tool_security_audit_log (
    user_id, business_id, event_type, endpoint, success, error_message
  ) VALUES (
    auth.uid(), p_business_id, p_event_type, p_endpoint, p_success, p_error_message
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_security_event(text, text, boolean, text, uuid) TO authenticated;

-- ===================================================
-- APRENDIZAJE GLOBAL: Análisis de patrones
-- ===================================================

CREATE OR REPLACE FUNCTION public.learn_global_keywords(
  p_min_occurrences int DEFAULT 5,
  p_days_lookback int DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_candidates_created int := 0;
  v_pattern record;
BEGIN
  -- 🔒 SOLO owner puede ejecutar (función global)
  IF (auth.jwt()->>'user_role') != 'owner' THEN
    RAISE EXCEPTION 'Solo owners pueden ejecutar aprendizaje global' USING ERRCODE = '42501';
  END IF;
  
  -- Analizar patrones GLOBALES (de todos los negocios)
  FOR v_pattern IN
    WITH usage_patterns AS (
      SELECT 
        tul.tool_name,
        unnest(public.extract_keywords(tul.user_query)) AS keyword,
        COUNT(*) AS occurrences,
        COUNT(DISTINCT tul.business_id) AS businesses_using,
        SUM(CASE WHEN tul.success THEN 1 ELSE 0 END) AS success_count
      FROM public.tool_usage_log tul
      WHERE tul.created_at >= now() - (p_days_lookback || ' days')::interval
        AND tul.success = true
      GROUP BY tul.tool_name, keyword
    )
    SELECT 
      up.tool_name,
      up.keyword,
      up.occurrences,
      up.businesses_using,
      up.success_count,
      round((up.success_count::numeric / up.occurrences) * 
            (up.businesses_using::numeric / 5.0) * -- Peso por # de negocios
            LEAST(1.0, up.occurrences::numeric / 10.0), 3) AS confidence
    FROM usage_patterns up
    WHERE up.occurrences >= p_min_occurrences
      AND NOT EXISTS (
        SELECT 1 FROM public.global_tool_definitions gtd
        WHERE gtd.tool_name = up.tool_name
          AND up.keyword = ANY(gtd.keywords)
      )
    ORDER BY confidence DESC, occurrences DESC
    LIMIT 100
  LOOP
    -- Crear candidato global
    INSERT INTO public.global_keyword_learning (
      keyword, tool_name, occurrences, success_count,
      days_appeared, confidence_score, status
    ) VALUES (
      v_pattern.keyword,
      v_pattern.tool_name,
      v_pattern.occurrences,
      v_pattern.success_count,
      p_days_lookback,
      v_pattern.confidence,
      CASE WHEN v_pattern.confidence >= 0.7 THEN 'approved' ELSE 'pending' END
    )
    ON CONFLICT (tool_name, keyword) 
    DO UPDATE SET
      occurrences = global_keyword_learning.occurrences + v_pattern.occurrences,
      success_count = global_keyword_learning.success_count + v_pattern.success_count,
      confidence_score = v_pattern.confidence,
      last_seen_at = now(),
      status = CASE 
        WHEN v_pattern.confidence >= 0.7 THEN 'approved'
        ELSE global_keyword_learning.status
      END;
    
    v_candidates_created := v_candidates_created + 1;
    
    -- Auto-aplicar si confianza es muy alta
    IF v_pattern.confidence >= 0.8 THEN
      UPDATE public.global_tool_definitions
      SET keywords = array_append(keywords, v_pattern.keyword),
          keywords_version = keywords_version + 1,
          last_learned_at = now()
      WHERE tool_name = v_pattern.tool_name
        AND NOT (v_pattern.keyword = ANY(keywords));
      
      UPDATE public.global_keyword_learning
      SET status = 'applied', approved_at = now()
      WHERE tool_name = v_pattern.tool_name AND keyword = v_pattern.keyword;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'candidates_created', v_candidates_created,
    'period_days', p_days_lookback,
    'message', 'Revisar global_keyword_learning para aprobar candidatos'
  );
END;
$$;

COMMENT ON FUNCTION public.learn_global_keywords IS
  '🧠 Aprendizaje GLOBAL: Analiza patrones de TODOS los negocios. Solo owners.';

GRANT EXECUTE ON FUNCTION public.learn_global_keywords(int, int) TO authenticated;

-- ===================================================
-- FUNCIÓN: Aprobar keyword aprendida
-- ===================================================

CREATE OR REPLACE FUNCTION public.approve_global_keyword(
  p_tool_name text,
  p_keyword text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 🔒 Solo owner
  IF (auth.jwt()->>'user_role') != 'owner' THEN
    RAISE EXCEPTION 'Solo owners' USING ERRCODE = '42501';
  END IF;
  
  -- Aplicar
  UPDATE public.global_tool_definitions
  SET keywords = array_append(keywords, p_keyword),
      keywords_version = keywords_version + 1,
      last_learned_at = now()
  WHERE tool_name = p_tool_name
    AND NOT (p_keyword = ANY(keywords));
  
  UPDATE public.global_keyword_learning
  SET status = 'applied', approved_by = auth.uid(), approved_at = now()
  WHERE tool_name = p_tool_name AND keyword = p_keyword;
  
  RETURN jsonb_build_object('success', true, 'keyword', p_keyword);
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_global_keyword(text, text) TO authenticated;

-- ===================================================
-- VISTAS DE MONITOREO
-- ===================================================

-- Vista: Estadísticas por herramienta
CREATE OR REPLACE VIEW public.tool_usage_stats AS
SELECT 
  tul.business_id,
  tul.tool_name,
  COUNT(*) AS total_uses,
  COUNT(*) FILTER (WHERE tul.success) AS successful_uses,
  round(COUNT(*) FILTER (WHERE tul.success)::numeric / COUNT(*) * 100, 1) AS success_rate,
  AVG(tul.execution_time_ms) FILTER (WHERE tul.success) AS avg_execution_ms,
  MAX(tul.created_at) AS last_used_at
FROM public.tool_usage_log tul
WHERE tul.created_at >= now() - interval '30 days'
GROUP BY tul.business_id, tul.tool_name;

COMMENT ON VIEW public.tool_usage_stats IS
  '📊 Estadísticas de uso por negocio y herramienta (últimos 30 días).';

-- Vista: Keywords candidatas globales
CREATE OR REPLACE VIEW public.pending_global_keywords AS
SELECT 
  gkl.tool_name,
  gkl.keyword,
  gkl.occurrences,
  gkl.confidence_score,
  CASE 
    WHEN gkl.confidence_score >= 0.8 THEN 'high'
    WHEN gkl.confidence_score >= 0.6 THEN 'medium'
    ELSE 'low'
  END AS confidence_level,
  gkl.first_seen_at,
  gkl.last_seen_at
FROM public.global_keyword_learning gkl
WHERE gkl.status = 'pending'
ORDER BY gkl.confidence_score DESC;

COMMENT ON VIEW public.pending_global_keywords IS
  '🔍 Keywords globales pendientes de aprobación.';

GRANT SELECT ON public.tool_usage_stats TO authenticated;
GRANT SELECT ON public.pending_global_keywords TO authenticated;

-- ===================================================
-- RE-CREAR search_available_tools CON SEGURIDAD
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
BEGIN
  -- 🔒 SEGURIDAD 1: Validar acceso
  PERFORM public.validate_user_business_access(p_business_id);
  
  -- 🔒 SEGURIDAD 2: Rate limiting
  PERFORM public.check_rate_limit(p_business_id, 'search_tools', 60, 1000);
  
  -- 🔒 SEGURIDAD 3: Validar input
  IF p_user_query IS NULL OR length(p_user_query) = 0 OR length(p_user_query) > 1000 THEN
    PERFORM public.log_security_event('invalid_input', 'search_tools', false, 'Query inválido', p_business_id);
    RETURN jsonb_build_object('tools', '[]'::jsonb, 'count', 0, 'error', 'Query inválido');
  END IF;
  
  -- Limitar max_results
  p_max_results := LEAST(p_max_results, 20);
  
  -- Extraer keywords
  v_keywords := public.extract_keywords(p_user_query);
  
  IF array_length(v_keywords, 1) IS NULL THEN
    RETURN jsonb_build_object('tools', '[]'::jsonb, 'count', 0);
  END IF;
  
  -- Buscar (híbrido: global + local)
  FOR v_tool IN
    SELECT 
      gtd.tool_name,
      gtd.tool_category,
      COALESCE(btc.custom_description, gtd.description) AS description,
      gtd.keywords,
      COALESCE(btc.custom_parameters, gtd.parameters) AS parameters,
      gtd.rpc_function_name,
      gtd.requires_role,
      (
        SELECT COUNT(*)::numeric 
        FROM unnest(v_keywords) AS uk
        WHERE uk = ANY(gtd.keywords)
      ) / array_length(v_keywords, 1)::numeric AS match_score
    FROM public.global_tool_definitions gtd
    LEFT JOIN public.business_tool_config btc 
      ON btc.tool_name = gtd.tool_name AND btc.business_id = p_business_id
    WHERE (btc.enabled IS NULL OR btc.enabled = true)
      AND p_user_role = ANY(gtd.requires_role)
      AND EXISTS (
        SELECT 1 FROM unnest(v_keywords) AS uk WHERE uk = ANY(gtd.keywords)
      )
    ORDER BY match_score DESC, gtd.global_usage_count DESC
    LIMIT p_max_results
  LOOP
    SELECT array_agg(uk) INTO v_matched_keywords
    FROM unnest(v_keywords) AS uk
    WHERE uk = ANY(v_tool.keywords);
    
    v_result := v_result || jsonb_build_object(
      'tool_name', v_tool.tool_name,
      'category', v_tool.tool_category,
      'description', v_tool.description,
      'rpc_function', v_tool.rpc_function_name,
      'parameters', v_tool.parameters,
      'match_score', round(v_tool.match_score, 2),
      'matched_keywords', v_matched_keywords
    );
  END LOOP;
  
  -- Log éxito
  PERFORM public.log_security_event('success', 'search_tools', true, NULL, p_business_id);
  
  RETURN jsonb_build_object(
    'tools', v_result,
    'count', jsonb_array_length(v_result),
    'keywords_detected', v_keywords
  );
  
EXCEPTION
  WHEN insufficient_privilege THEN
    PERFORM public.log_security_event('access_denied', 'search_tools', false, SQLERRM, p_business_id);
    RAISE;
  WHEN program_limit_exceeded THEN
    PERFORM public.log_security_event('rate_limit', 'search_tools', false, SQLERRM, p_business_id);
    RAISE;
  WHEN OTHERS THEN
    PERFORM public.log_security_event('error', 'search_tools', false, SQLERRM, p_business_id);
    RAISE;
END;
$$;

-- ===================================================
-- RLS
-- ===================================================

ALTER TABLE public.tool_api_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tool_security_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rate_limits_own ON public.tool_api_rate_limits;
CREATE POLICY rate_limits_own ON public.tool_api_rate_limits
  FOR ALL TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS audit_log_owner ON public.tool_security_audit_log;
CREATE POLICY audit_log_owner ON public.tool_security_audit_log
  FOR SELECT TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

COMMIT;

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅ MIGRACIÓN 0239 APLICADA';
  RAISE NOTICE '🔒 Seguridad: Rate limiting + Auditoría';
  RAISE NOTICE '🧠 Aprendizaje: learn_global_keywords()';
  RAISE NOTICE '📊 Vistas: tool_usage_stats, pending_global_keywords';
  RAISE NOTICE '';
END $$;
