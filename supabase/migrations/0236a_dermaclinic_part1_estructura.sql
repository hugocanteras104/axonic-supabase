-- ===============================================
-- Migration: 0236a_dermaclinic_part1_estructura.sql
-- Purpose: PARTE 1 - Crear negocio, servicios y clientes
-- Dependencies: 0200-0226
-- ===============================================
-- 
-- INSTRUCCIONES:
-- 1. Ejecuta este archivo primero
-- 2. Verifica que se ejecutó bien (verás mensajes ✅)
-- 3. Copia el Business ID que aparece al final
-- 4. Ejecuta 0236b_dermaclinic_part2_conocimiento.sql
-- ===============================================

BEGIN;

DO $$
DECLARE
  v_business_id uuid;
  v_owner_id uuid;
BEGIN
  
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '🚀 INICIANDO CONFIGURACIÓN DERMACLINIC - PARTE 1';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';

  -- ===============================================
  -- PASO 1: Crear Negocio
  -- ===============================================
  INSERT INTO public.businesses (
    name,
    slug,
    phone,
    email,
    address,
    metadata,
    is_active
  ) VALUES (
    'Dermaclinic',
    'dermaclinic-madrid',
    '+34643558483',
    'holaeternalbeauty23@gmail.com',
    'Madrid',
    jsonb_build_object(
      'propietaria', 'Lucía Triana Herrero',
      'sector', 'belleza'
    ),
    true
  ) RETURNING id INTO v_business_id;

  RAISE NOTICE '✅ [1/5] Negocio creado - ID: %', v_business_id;


  -- ===============================================
  -- PASO 2: Configurar Horarios
  -- ===============================================
  INSERT INTO public.business_settings (
    business_id,
    setting_key,
    setting_value,
    description
  ) VALUES (
    v_business_id,
    'business_hours',
    jsonb_build_object(
      'timezone', 'Europe/Madrid',
      'schedule', jsonb_build_object(
        'monday', jsonb_build_object('open', '10:00', 'close', '20:00', 'closed', false),
        'tuesday', jsonb_build_object('open', '10:00', 'close', '20:00', 'closed', false),
        'wednesday', jsonb_build_object('open', '10:00', 'close', '20:00', 'closed', false),
        'thursday', jsonb_build_object('open', '10:00', 'close', '20:00', 'closed', false),
        'friday', jsonb_build_object('open', '10:00', 'close', '20:00', 'closed', false),
        'saturday', jsonb_build_object('closed', true),
        'sunday', jsonb_build_object('closed', true)
      ),
      'holidays', jsonb_build_array()
    ),
    'Horario: Lunes a Viernes 10:00-20:00'
  );

  RAISE NOTICE '✅ [2/5] Horarios configurados (Lun-Vie 10:00-20:00)';


  -- ===============================================
  -- PASO 3: Crear Perfil Owner
  -- ===============================================
  INSERT INTO public.profiles (
    business_id,
    phone_number,
    role,
    name,
    email,
    metadata
  ) VALUES (
    v_business_id,
    '+34643558483',
    'owner',
    'Lucía Triana Herrero',
    'holaeternalbeauty23@gmail.com',
    jsonb_build_object('is_admin', true, 'cargo', 'Propietaria')
  ) RETURNING id INTO v_owner_id;

  RAISE NOTICE '✅ [3/5] Perfil owner creado';


  -- ===============================================
  -- PASO 4: Insertar Servicios (31 servicios)
  -- ===============================================
  
  -- Láser sesiones sueltas
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Depilación Láser XS', 'Zonas: labio superior, entrecejo, areolas, dedos manos/pies, orejas, nariz', 12.00, 10, 10, '{"categoria": "depilacion_laser", "tamano": "XS"}'),
  (v_business_id, 'Depilación Láser S', 'Zonas: axilas, mentón, cuello, nuca, ingles básicas, manos, pies, patillas, mejillas, línea alba', 25.00, 20, 10, '{"categoria": "depilacion_laser", "tamano": "S"}'),
  (v_business_id, 'Depilación Láser M', 'Zonas: medios brazos, medias piernas, muslos, facial completo, ingles brasileñas, pubis, glúteos, pecho, abdomen, dorsales, lumbares, perianal', 50.00, 30, 15, '{"categoria": "depilacion_laser", "tamano": "M"}'),
  (v_business_id, 'Depilación Láser L', 'Zonas: piernas completas, brazos completos, espalda completa, pecho+abdomen completo', 90.00, 45, 15, '{"categoria": "depilacion_laser", "tamano": "L"}'),
  (v_business_id, 'Depilación Láser XL', 'Cuerpo entero (todas las zonas)', 150.00, 90, 15, '{"categoria": "depilacion_laser", "tamano": "XL"}');

  -- Bonos 6 sesiones
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Bono 6 Sesiones Láser XS', 'Pack 6 sesiones XS (25% dto) - Validez 6 meses', 54.00, 10, 10, '{"tipo": "bono", "sesiones": 6, "descuento": 25, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser S', 'Pack 6 sesiones S (25% dto) - Validez 6 meses', 112.00, 20, 10, '{"tipo": "bono", "sesiones": 6, "descuento": 25, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser M', 'Pack 6 sesiones M (25% dto) - Validez 6 meses', 225.00, 30, 15, '{"tipo": "bono", "sesiones": 6, "descuento": 25, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser L', 'Pack 6 sesiones L (25% dto) - Validez 6 meses', 405.00, 45, 15, '{"tipo": "bono", "sesiones": 6, "descuento": 25, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser XL', 'Pack 6 sesiones XL (25% dto) - Validez 6 meses', 675.00, 90, 15, '{"tipo": "bono", "sesiones": 6, "descuento": 25, "validez_meses": 6}');

  -- Bonos 10 sesiones
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Bono 10 Sesiones Láser XS', 'Pack 10 sesiones XS (40% dto) - Validez 12 meses', 72.00, 10, 10, '{"tipo": "bono", "sesiones": 10, "descuento": 40, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser S', 'Pack 10 sesiones S (40% dto) - Validez 12 meses', 150.00, 20, 10, '{"tipo": "bono", "sesiones": 10, "descuento": 40, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser M', 'Pack 10 sesiones M (40% dto) - Validez 12 meses', 300.00, 30, 15, '{"tipo": "bono", "sesiones": 10, "descuento": 40, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser L', 'Pack 10 sesiones L (40% dto) - Validez 12 meses', 540.00, 45, 15, '{"tipo": "bono", "sesiones": 10, "descuento": 40, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser XL', 'Pack 10 sesiones XL (40% dto) - Validez 12 meses', 900.00, 90, 15, '{"tipo": "bono", "sesiones": 10, "descuento": 40, "validez_meses": 12}');

  -- Faciales
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Peeling Químico Antiacné Eberlin', 'Limpia, regula sebo, mejora textura. Producto gancho para vender cremas.', 55.00, 60, 15, '{"categoria": "facial", "marca": "Eberlin", "producto_gancho": true}'),
  (v_business_id, 'Peeling Despigmentante Ácido Kójico', 'Manchas, hiperpigmentación, tono irregular. Producto gancho.', 55.00, 60, 15, '{"categoria": "facial", "marca": "Eberlin", "producto_gancho": true}'),
  (v_business_id, 'Peeling Hollywood - Carbon Peel', 'Piel luminosa, poros reducidos, sin recuperación', 95.00, 45, 15, '{"categoria": "facial"}'),
  (v_business_id, 'Dioderma Facial - Soft Láser', 'Reafirma, estimula colágeno sin recuperación', 60.00, 40, 15, '{"categoria": "facial"}'),
  (v_business_id, 'Tratamiento Facial Biológico Ringana', 'Natural 100% vegano, 0 químicos', 75.00, 60, 15, '{"categoria": "facial", "marca": "Ringana", "filosofia": "0_quimicos"}');

  -- Bonos faciales
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Bono 5 Sesiones Peeling Acné', 'Pack 5 (10% dto) - Validez 6 meses', 247.00, 60, 15, '{"tipo": "bono", "sesiones": 5, "validez_meses": 6}'),
  (v_business_id, 'Bono 5 Sesiones Peeling Kójico', 'Pack 5 (10% dto) - Validez 6 meses', 247.00, 60, 15, '{"tipo": "bono", "sesiones": 5, "validez_meses": 6}'),
  (v_business_id, 'Bono 3 Sesiones Hollywood', 'Pack 3 (11% dto) - Validez 6 meses', 255.00, 45, 15, '{"tipo": "bono", "sesiones": 3, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Dioderma', 'Pack 6 (11% dto) - Validez 6 meses', 320.00, 40, 15, '{"tipo": "bono", "sesiones": 6, "validez_meses": 6}'),
  (v_business_id, 'Bono 4 Sesiones Ringana', 'Pack 4 (10% dto) - Validez 6 meses', 270.00, 60, 15, '{"tipo": "bono", "sesiones": 4, "validez_meses": 6}');

  -- Otros servicios
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Depilación Eléctrica 30 min', 'Método pelo a pelo para vello canoso/claro', 60.00, 30, 10, '{"categoria": "depilacion_electrica"}'),
  (v_business_id, 'Eliminación Tatuaje hasta 25cm²', 'NanoLáser SPT Q-Switched. Hasta 5x5cm', 60.00, 30, 10, '{"categoria": "eliminacion_tatuajes", "rango": "0-25cm2"}'),
  (v_business_id, 'Eliminación Tatuaje 26-50cm²', 'NanoLáser SPT Q-Switched. Hasta 7x7cm', 120.00, 40, 10, '{"categoria": "eliminacion_tatuajes", "rango": "26-50cm2"}'),
  (v_business_id, 'Eliminación Tatuaje 51-100cm²', 'NanoLáser SPT Q-Switched. Hasta 10x10cm', 220.00, 60, 15, '{"categoria": "eliminacion_tatuajes", "rango": "51-100cm2"}'),
  (v_business_id, 'Eliminación Tatuaje más de 100cm²', 'NanoLáser SPT Q-Switched. 8€ por cm²', 8.00, 90, 15, '{"categoria": "eliminacion_tatuajes", "rango": "100+cm2", "precio_por_cm2": true}'),
  (v_business_id, 'Bono Anual Cuerpo Entero 590€ [LEGACY]', 'Depilación cuerpo entero ilimitada 12 meses. YA NO SE VENDE.', 590.00, 90, 15, '{"tipo": "bono_legacy", "descontinuado": true, "sesiones": "ilimitadas"}');

  RAISE NOTICE '✅ [4/5] Servicios insertados (31 servicios)';


  -- ===============================================
  -- PASO 5: Insertar Clientes (10 leads)
  -- ===============================================
  INSERT INTO public.profiles (business_id, phone_number, name, role, metadata) VALUES
  (v_business_id, '+34685125084', 'Aaron', 'lead', '{"ocupacion": "bombero", "tratamientos": ["bono_anual_590"], "notas": "Tatuaje eliminado - cuidado al pasar láser en zona sensible"}'),
  (v_business_id, '+34639007296', 'José Pajaroto', 'lead', '{"ocupacion": "bombero", "tratamientos": ["bono_anual_590"], "notas": "Amigo personal, tiene tatuajes"}'),
  (v_business_id, '+34638910004', 'Gladys Buldrini', 'lead', '{"tratamientos": ["depilacion_electrica", "laser", "peeling_hollywood"]}'),
  (v_business_id, '+34697632334', 'Iván', 'lead', '{"tratamientos": ["laser_piernas", "laser_espalda", "laser_hombros"]}'),
  (v_business_id, '+34653616101', 'Javi', 'lead', '{"tratamientos": ["laser_espalda", "laser_hombros"]}'),
  (v_business_id, '+34636870873', 'Marga', 'lead', '{"piel": "mulata", "preocupaciones": ["acne"], "tratamientos": ["depilacion_facial"]}'),
  (v_business_id, '+34623313730', 'Jamiyet', 'lead', '{"tratamientos": ["acne", "peeling_quimico", "hollywood"], "compras": ["cremas_acne"]}'),
  (v_business_id, '+34673022016', 'Lucía', 'lead', '{"ocupacion": "medico", "tratamientos": ["bono_anual_590"], "notas": "Lunares que hay que tapar"}'),
  (v_business_id, '+34689417731', 'Alba', 'lead', '{"ocupacion": "nutricionista", "tratamientos": ["bono_anual_590"]}'),
  (v_business_id, '+34665681661', 'Juan', 'lead', '{"ocupacion": "bombero", "tratamientos": ["bono_anual_590"], "notas": "Tatuaje eliminado en axila molesto con láser, molestia dedos pies"}');

  RAISE NOTICE '✅ [5/5] Clientes insertados (10 clientes)';

  -- ===============================================
  -- FIN PARTE 1
  -- ===============================================
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '✅ PARTE 1 COMPLETADA EXITOSAMENTE';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';
  RAISE NOTICE '📊 RESUMEN:';
  RAISE NOTICE '  Business ID: %', v_business_id;
  RAISE NOTICE '  Owner: Lucía Triana Herrero';
  RAISE NOTICE '  Servicios: 31';
  RAISE NOTICE '  Clientes: 10';
  RAISE NOTICE '';
  RAISE NOTICE '🔧 SIGUIENTE PASO:';
  RAISE NOTICE '  Ejecuta ahora: 0236b_dermaclinic_part2_conocimiento.sql';
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

END $$;

COMMIT;
