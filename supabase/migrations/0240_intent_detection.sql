-- ===============================================
-- Migration: 0240_intent_detection.sql
-- Purpose: Sistema de detección de múltiples intenciones en queries
-- Dependencies: 0239_tool_learning_and_security.sql
-- ===============================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'tool_security_audit_log') THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: 0239';
  END IF;
  RAISE NOTICE '✅ Dependencia verificada';
END $$;

BEGIN;

-- ===================================================
-- FUNCIÓN: Detectar múltiples intenciones
-- ===================================================

CREATE OR REPLACE FUNCTION public.detect_multiple_intents(
  p_tools jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_top_score numeric;
  v_similar_count int := 0;
  v_intent_groups jsonb := '[]'::jsonb;
  v_tool jsonb;
  v_tool_name text;
  v_intents text[] := '{}';
BEGIN
  -- Si no hay herramientas, retornar metadata vacía
  IF jsonb_array_length(p_tools) = 0 THEN
    RETURN jsonb_build_object(
      'multiple_intents', false,
      'intent_count', 0,
      'intent_groups', '[]'::jsonb,
      'suggestion', NULL,
      'top_score', 0
    );
  END IF;
  
  -- Obtener el score más alto
  v_top_score := COALESCE((p_tools->0->>'match_score')::numeric, 0);
  
  -- Contar herramientas con score similar (dentro del 10% del top)
  FOR v_tool IN SELECT * FROM jsonb_array_elements(p_tools)
  LOOP
    IF (v_tool->>'match_score')::numeric >= (v_top_score * 0.9) THEN
      v_similar_count := v_similar_count + 1;
      
      -- Extraer nombre de la herramienta
      v_tool_name := v_tool->>'tool_name';
      
      -- Clasificar por tipo de intención
      IF v_tool_name LIKE '%cancelar%' THEN
        v_intents := array_append(v_intents, 'cancelar');
      ELSIF v_tool_name LIKE '%reagendar%' OR v_tool_name LIKE '%mover%' OR v_tool_name LIKE '%cambiar%' THEN
        v_intents := array_append(v_intents, 'reagendar');
      ELSIF v_tool_name LIKE '%agendar%' OR v_tool_name LIKE '%crear_cita%' OR v_tool_name LIKE '%reservar%' THEN
        v_intents := array_append(v_intents, 'agendar');
      ELSIF v_tool_name LIKE '%consultar%' OR v_tool_name LIKE '%ver%' OR v_tool_name LIKE '%obtener%' THEN
        v_intents := array_append(v_intents, 'consultar');
      ELSIF v_tool_name LIKE '%confirmar%' THEN
        v_intents := array_append(v_intents, 'confirmar');
      ELSIF v_tool_name LIKE '%eliminar%' OR v_tool_name LIKE '%borrar%' THEN
        v_intents := array_append(v_intents, 'eliminar');
      ELSIF v_tool_name LIKE '%modificar%' OR v_tool_name LIKE '%actualizar%' OR v_tool_name LIKE '%editar%' THEN
        v_intents := array_append(v_intents, 'modificar');
      ELSIF v_tool_name LIKE '%buscar%' THEN
        v_intents := array_append(v_intents, 'buscar');
      ELSE
        v_intents := array_append(v_intents, 'otro');
      END IF;
    END IF;
  END LOOP;
  
  -- Remover duplicados y convertir a jsonb
  SELECT jsonb_agg(DISTINCT intent) 
  INTO v_intent_groups
  FROM unnest(v_intents) AS intent
  WHERE intent IS NOT NULL;
  
  -- Construir respuesta
  RETURN jsonb_build_object(
    'multiple_intents', v_similar_count >= 2,
    'intent_count', v_similar_count,
    'intent_groups', COALESCE(v_intent_groups, '[]'::jsonb),
    'top_score', v_top_score,
    'suggestion', CASE 
      WHEN v_similar_count >= 3 THEN 
        'El usuario parece querer hacer varias acciones. Considera mostrar opciones o preguntar qué hacer primero.'
      WHEN v_similar_count = 2 THEN 
        'El usuario podría querer hacer 2 acciones. Considera confirmar la intención principal.'
      ELSE NULL
    END
  );
END;
$$;

COMMENT ON FUNCTION public.detect_multiple_intents IS
  '🎯 Detecta si el query del usuario tiene múltiples intenciones (ej: cancelar Y reagendar).
  
  Retorna:
  - multiple_intents: boolean (true si hay 2+ herramientas con score similar)
  - intent_count: número de herramientas con score similar
  - intent_groups: array de categorías de intención detectadas
  - top_score: score más alto encontrado
  - suggestion: texto sugerido para el bot';

GRANT EXECUTE ON FUNCTION public.detect_multiple_intents(jsonb) TO authenticated;

-- ===================================================
-- ACTUALIZAR: search_available_tools con intent detection
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
  v_intent_metadata jsonb;
BEGIN
  -- 🔒 SEGURIDAD 1: Validar acceso
  PERFORM public.validate_user_business_access(p_business_id);
  
  -- 🔒 SEGURIDAD 2: Rate limiting
  PERFORM public.check_rate_limit(p_business_id, 'search_tools', 60, 1000);
  
  -- 🔒 SEGURIDAD 3: Validar input
  IF p_user_query IS NULL OR length(p_user_query) = 0 OR length(p_user_query) > 1000 THEN
    PERFORM public.log_security_event('invalid_input', 'search_tools', false, 'Query inválido', p_business_id);
    RETURN jsonb_build_object(
      'tools', '[]'::jsonb, 
      'count', 0, 
      'error', 'Query inválido',
      'intent_analysis', jsonb_build_object('multiple_intents', false)
    );
  END IF;
  
  -- Limitar max_results
  p_max_results := LEAST(p_max_results, 20);
  
  -- Extraer keywords
  v_keywords := public.extract_keywords(p_user_query);
  
  IF array_length(v_keywords, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'tools', '[]'::jsonb, 
      'count', 0,
      'intent_analysis', jsonb_build_object('multiple_intents', false)
    );
  END IF;
  
  -- Buscar herramientas (híbrido: global + local)
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
  
  -- 🎯 NUEVO: Detectar múltiples intenciones
  v_intent_metadata := public.detect_multiple_intents(v_result);
  
  -- Log éxito
  PERFORM public.log_security_event('success', 'search_tools', true, NULL, p_business_id);
  
  RETURN jsonb_build_object(
    'tools', v_result,
    'count', jsonb_array_length(v_result),
    'keywords_detected', v_keywords,
    'intent_analysis', v_intent_metadata  -- 🎯 NUEVO CAMPO
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

COMMENT ON FUNCTION public.search_available_tools IS
  '🔍 Busca herramientas disponibles según el query del usuario.
  
  NUEVO en 0240: Incluye análisis de intenciones múltiples.
  
  Retorna:
  - tools: array de herramientas encontradas
  - count: número de herramientas
  - keywords_detected: keywords extraídas del query
  - intent_analysis: análisis de intenciones múltiples (NUEVO)';

-- ===================================================
-- FUNCIÓN HELPER: Generar mensaje conversacional
-- ===================================================

CREATE OR REPLACE FUNCTION public.generate_intent_clarification(
  p_intent_groups jsonb,
  p_top_tools jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_intents text[];
  v_message text;
  v_tool jsonb;
BEGIN
  -- Convertir intent_groups a array
  SELECT array_agg(intent::text)
  INTO v_intents
  FROM jsonb_array_elements_text(p_intent_groups) AS intent;
  
  -- Si no hay intenciones, no generar mensaje
  IF array_length(v_intents, 1) IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Generar mensaje según las intenciones detectadas
  IF array_length(v_intents, 1) = 1 THEN
    -- Una sola intención clara
    RETURN NULL;
  ELSIF array_length(v_intents, 1) = 2 THEN
    -- Dos intenciones
    v_message := format(
      'Entiendo que quieres %s y %s. ¿Empezamos por %s?',
      v_intents[1],
      v_intents[2],
      v_intents[1]
    );
  ELSE
    -- Múltiples intenciones
    v_message := format(
      'Veo que quieres hacer varias cosas: %s. ¿Qué hacemos primero?',
      array_to_string(v_intents, ', ')
    );
  END IF;
  
  RETURN v_message;
END;
$$;

COMMENT ON FUNCTION public.generate_intent_clarification IS
  '💬 Genera un mensaje conversacional para clarificar intenciones múltiples.
  
  Útil para bots de WhatsApp que necesitan preguntar al usuario qué acción priorizar.';

GRANT EXECUTE ON FUNCTION public.generate_intent_clarification(jsonb, jsonb) TO authenticated;

-- ===================================================
-- VISTA: Análisis de patrones de intenciones múltiples
-- ===================================================

CREATE OR REPLACE VIEW public.multi_intent_patterns AS
SELECT 
  tul.user_query,
  tul.tool_name,
  COUNT(*) OVER (PARTITION BY tul.user_query) AS tools_triggered,
  tul.success,
  tul.created_at
FROM public.tool_usage_log tul
WHERE tul.created_at >= now() - interval '30 days'
  AND EXISTS (
    SELECT 1 
    FROM public.tool_usage_log tul2
    WHERE tul2.user_query = tul.user_query
      AND tul2.tool_name != tul.tool_name
      AND tul2.created_at BETWEEN tul.created_at - interval '5 seconds' 
                               AND tul.created_at + interval '5 seconds'
  )
ORDER BY tul.created_at DESC;

COMMENT ON VIEW public.multi_intent_patterns IS
  '📊 Analiza patrones de queries que disparan múltiples herramientas.
  
  Útil para mejorar el sistema de intent detection y entrenar el modelo.';

GRANT SELECT ON public.multi_intent_patterns TO authenticated;

COMMIT;

-- ===================================================
-- VERIFICACIÓN Y EJEMPLOS
-- ===================================================

DO $$
DECLARE
  v_test_result jsonb;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅ ========================================';
  RAISE NOTICE '✅ MIGRACIÓN 0240 APLICADA';
  RAISE NOTICE '✅ ========================================';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 NUEVAS FUNCIONALIDADES:';
  RAISE NOTICE '   • detect_multiple_intents() - Detecta intenciones múltiples';
  RAISE NOTICE '   • search_available_tools() - Actualizada con intent_analysis';
  RAISE NOTICE '   • generate_intent_clarification() - Genera mensajes conversacionales';
  RAISE NOTICE '   • multi_intent_patterns VIEW - Analiza patrones';
  RAISE NOTICE '';
  RAISE NOTICE '📝 EJEMPLO DE USO:';
  RAISE NOTICE '';
  RAISE NOTICE '   -- Buscar con intent detection:';
  RAISE NOTICE '   SELECT * FROM search_available_tools(';
  RAISE NOTICE '     ''tu-business-id''::uuid,';
  RAISE NOTICE '     ''necesito cancelar y reagendar mi cita'',';
  RAISE NOTICE '     ''lead'',';
  RAISE NOTICE '     10';
  RAISE NOTICE '   );';
  RAISE NOTICE '';
  RAISE NOTICE '   -- La respuesta ahora incluye:';
  RAISE NOTICE '   {';
  RAISE NOTICE '     "tools": [...],';
  RAISE NOTICE '     "count": 3,';
  RAISE NOTICE '     "keywords_detected": ["cancelar", "reagendar", "cita"],';
  RAISE NOTICE '     "intent_analysis": {';
  RAISE NOTICE '       "multiple_intents": true,';
  RAISE NOTICE '       "intent_count": 2,';
  RAISE NOTICE '       "intent_groups": ["cancelar", "reagendar"],';
  RAISE NOTICE '       "top_score": 0.33,';
  RAISE NOTICE '       "suggestion": "El usuario podría querer hacer 2 acciones..."';
  RAISE NOTICE '     }';
  RAISE NOTICE '   }';
  RAISE NOTICE '';
  
  -- Test de la función detect_multiple_intents
  SELECT public.detect_multiple_intents(
    '[
      {"tool_name": "cancelar_cita", "match_score": 0.5},
      {"tool_name": "reagendar_cita", "match_score": 0.5}
    ]'::jsonb
  ) INTO v_test_result;
  
  RAISE NOTICE '🧪 TEST DE detect_multiple_intents:';
  RAISE NOTICE '   Input: 2 herramientas con score 0.5';
  RAISE NOTICE '   Output: %', v_test_result::text;
  RAISE NOTICE '';
  RAISE NOTICE '✅ Sistema de Intent Detection listo para producción';
  RAISE NOTICE '';
END $$;
