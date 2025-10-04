-- ===============================================
-- Migration: 0236a_dermaclinic_part1_estructura.sql
-- Purpose: PARTE 1 - Estructura básica de Dermaclinic
-- Dependencies: 0200-0226 (multitenancy completo)
-- ===============================================
--
-- INSTRUCCIONES:
-- 1. Ejecuta este archivo primero
-- 2. Verifica los mensajes ✅
-- 3. Luego ejecuta 0236b
-- ===============================================

BEGIN;

DO $$
DECLARE
  v_business_id uuid;
  v_owner_profile_id uuid;
BEGIN
  
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '🚀 INICIANDO CONFIGURACIÓN DERMACLINIC - PARTE 1';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';

  -- ===============================================
  -- PASO 1: Crear Negocio
  -- ===============================================
  INSERT INTO public.businesses (name, slug, phone, email, metadata, is_active)
  VALUES (
    'Dermaclinic Madrid',
    'dermaclinic-madrid',
    '+34643558483',
    'holaeternalbeauty23@gmail.com',
    jsonb_build_object(
      'direccion', 'Madrid',
      'whatsapp', '+34643558483',
      'instagram', '@dermaclinic_madrid',
      'especialidad', 'Depilación láser y tratamientos faciales',
      'marcas', ARRAY['Eberlin', 'Ringana']
    ),
    true
  )
  RETURNING id INTO v_business_id;

  RAISE NOTICE '✅ [1/4] Negocio creado - ID: %', v_business_id;


  -- ===============================================
  -- PASO 2: Configuración de Horarios
  -- ===============================================
  INSERT INTO public.business_settings (business_id, setting_key, setting_value, description)
  VALUES (
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
      'holidays', jsonb_build_object()
    ),
    'Horario: Lun-Vie 10:00-20:00'
  );

  INSERT INTO public.business_settings (business_id, setting_key, setting_value, description)
  VALUES (
    v_business_id,
    'pricing_rules',
    jsonb_build_object(
      'deposit_required_above', 100,
      'deposit_percentage', 30,
      'cancellation_fee_percentage', 50
    ),
    'Depósito 30% para servicios >100€, cargo 50% si cancela <24h'
  );

  RAISE NOTICE '✅ [2/4] Configuración insertada (horarios + políticas)';


  -- ===============================================
  -- PASO 3: Perfil Owner
  -- ===============================================
  INSERT INTO public.profiles (business_id, phone_number, role, name, email, metadata)
  VALUES (
    v_business_id,
    '+34643558483',
    'owner',
    'Dermaclinic Admin',
    'holaeternalbeauty23@gmail.com',
    jsonb_build_object('is_admin', true, 'department', 'administracion')
  )
  RETURNING id INTO v_owner_profile_id;

  RAISE NOTICE '✅ [3/4] Perfil owner creado';


  -- ===============================================
  -- PASO 4: Servicios (31 servicios)
  -- ===============================================
  
  -- DEPILACIÓN LÁSER (5 tamaños)
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Depilación Láser XS', 'Zonas: labio superior, entrecejo, areolas, dedos manos/pies, orejas, nariz', 12.00, 15, 10, '{"categoria": "depilacion_laser", "tamano": "XS"}'),
  (v_business_id, 'Depilación Láser S', 'Zonas: axilas, mentón, cuello, nuca, ingles básicas, manos, pies, patillas, mejillas, línea alba', 25.00, 20, 10, '{"categoria": "depilacion_laser", "tamano": "S"}'),
  (v_business_id, 'Depilación Láser M', 'Zonas: medios brazos, medias piernas, muslos, facial completo, ingles brasileñas, pubis, glúteos, pecho, abdomen, dorsales, lumbares, perianal', 50.00, 30, 15, '{"categoria": "depilacion_laser", "tamano": "M"}'),
  (v_business_id, 'Depilación Láser L', 'Zonas: piernas completas, brazos completos, espalda completa, pecho+abdomen completo', 90.00, 45, 15, '{"categoria": "depilacion_laser", "tamano": "L"}'),
  (v_business_id, 'Depilación Láser XL', 'Cuerpo entero (todas las zonas)', 150.00, 90, 15, '{"categoria": "depilacion_laser", "tamano": "XL"}');

  -- BONOS LÁSER 6 SESIONES (5 bonos)
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Bono 6 Sesiones Láser XS', '6 sesiones tamaño XS (25% dto, validez 6 meses)', 54.00, 15, 10, '{"categoria": "bono_laser", "tamano": "XS", "sesiones": 6, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser S', '6 sesiones tamaño S (25% dto, validez 6 meses)', 112.50, 20, 10, '{"categoria": "bono_laser", "tamano": "S", "sesiones": 6, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser M', '6 sesiones tamaño M (25% dto, validez 6 meses)', 225.00, 30, 15, '{"categoria": "bono_laser", "tamano": "M", "sesiones": 6, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser L', '6 sesiones tamaño L (25% dto, validez 6 meses)', 405.00, 45, 15, '{"categoria": "bono_laser", "tamano": "L", "sesiones": 6, "validez_meses": 6}'),
  (v_business_id, 'Bono 6 Sesiones Láser XL', '6 sesiones tamaño XL (25% dto, validez 6 meses)', 675.00, 90, 15, '{"categoria": "bono_laser", "tamano": "XL", "sesiones": 6, "validez_meses": 6}');

  -- BONOS LÁSER 10 SESIONES (5 bonos)
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Bono 10 Sesiones Láser XS', '10 sesiones tamaño XS (40% dto, validez 12 meses)', 72.00, 15, 10, '{"categoria": "bono_laser", "tamano": "XS", "sesiones": 10, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser S', '10 sesiones tamaño S (40% dto, validez 12 meses)', 150.00, 20, 10, '{"categoria": "bono_laser", "tamano": "S", "sesiones": 10, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser M', '10 sesiones tamaño M (40% dto, validez 12 meses)', 300.00, 30, 15, '{"categoria": "bono_laser", "tamano": "M", "sesiones": 10, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser L', '10 sesiones tamaño L (40% dto, validez 12 meses)', 540.00, 45, 15, '{"categoria": "bono_laser", "tamano": "L", "sesiones": 10, "validez_meses": 12}'),
  (v_business_id, 'Bono 10 Sesiones Láser XL', '10 sesiones tamaño XL (40% dto, validez 12 meses)', 900.00, 90, 15, '{"categoria": "bono_laser", "tamano": "XL", "sesiones": 10, "validez_meses": 12}');

  -- DEPILACIÓN ELÉCTRICA
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Depilación Eléctrica 30 min', 'Pelo a pelo con aguja. Ideal para vellos que el láser no capta (canosos, muy claros)', 60.00, 30, 15, '{"categoria": "depilacion_electrica"}');

  -- TRATAMIENTOS FACIALES (6 tratamientos)
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Peeling Antiacné', 'Peeling + Limpieza profunda + Mascarilla + Hidratación + SPF50. Para pieles con acné, grasa, puntos negros', 55.00, 60, 15, '{"categoria": "tratamiento_facial", "marca": "Eberlin"}'),
  (v_business_id, 'Peeling Kójico (Despigmentante)', 'Peeling ácido kójico para manchas solares, melasma, hiperpigmentación. Unifica tono', 55.00, 60, 15, '{"categoria": "tratamiento_facial", "marca": "Eberlin"}'),
  (v_business_id, 'Peeling Hollywood (Carbon Peel)', 'Máscara carbón + NanoLáser. Efecto alfombra roja inmediato: piel luminosa, poros reducidos, sin recuperación', 95.00, 45, 15, '{"categoria": "tratamiento_facial", "marca": "NanoLaser"}'),
  (v_business_id, 'Dioderma', 'Láser reafirmante suave. Estimula colágeno, mejora textura, reduce líneas finas. Sin recuperación', 60.00, 40, 15, '{"categoria": "tratamiento_facial", "marca": "Dioderma"}'),
  (v_business_id, 'Facial Ringana', 'Tratamiento 100% natural y vegano Ringana. 0 químicos, ingredientes frescos naturales', 75.00, 60, 15, '{"categoria": "tratamiento_facial", "marca": "Ringana"}'),
  (v_business_id, 'Bono 6 Faciales', '6 sesiones faciales (excepto Hollywood). 25% dto, validez 6 meses', 247.50, 60, 15, '{"categoria": "bono_facial", "sesiones": 6, "validez_meses": 6}');

  -- NANOLASER TATUAJES Y MANCHAS (4 tamaños)
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'NanoLáser Tatuajes hasta 25cm²', 'Eliminación tatuajes hasta 25cm² (5x5cm). NanoLáser SPT Q-Switched', 60.00, 30, 15, '{"categoria": "nanolaser_tatuajes", "tamano_max_cm2": 25}'),
  (v_business_id, 'NanoLáser Tatuajes 26-50cm²', 'Eliminación tatuajes 26-50cm² (7x7cm). NanoLáser SPT Q-Switched', 120.00, 40, 15, '{"categoria": "nanolaser_tatuajes", "tamano_max_cm2": 50}'),
  (v_business_id, 'NanoLáser Tatuajes 51-100cm²', 'Eliminación tatuajes 51-100cm² (10x10cm). NanoLáser SPT Q-Switched', 220.00, 50, 15, '{"categoria": "nanolaser_tatuajes", "tamano_max_cm2": 100}'),
  (v_business_id, 'NanoLáser Tatuajes >100cm²', 'Eliminación tatuajes grandes (8€/cm²). NanoLáser SPT Q-Switched', 8.00, 60, 15, '{"categoria": "nanolaser_tatuajes", "precio_por_cm2": true}');

  -- PACKS POST-TRATAMIENTO (2 packs)
  INSERT INTO public.services (business_id, name, description, base_price, duration_minutes, buffer_minutes, metadata) VALUES
  (v_business_id, 'Pack Post-Acné', 'Sérum Enzimático + Crema Control Sebo + SPF50 Eberlin (ahorras 13€)', 99.00, 15, 0, '{"categoria": "pack_productos", "productos": ["serum_enzimatico", "crema_control_sebo", "spf50"]}'),
  (v_business_id, 'Pack Post-Kójico', 'Booster Le Blanche + Crema Le Blanche + SPF50 Eberlin (ahorras 12€)', 109.00, 15, 0, '{"categoria": "pack_productos", "productos": ["booster_le_blanche", "crema_le_blanche", "spf50"]}');

  RAISE NOTICE '✅ [4/4] Servicios insertados (31 servicios)';


  -- ===============================================
  -- PASO 5: Clientes de Prueba
  -- ===============================================
  INSERT INTO public.profiles (business_id, phone_number, role, name, email, metadata) VALUES
  (v_business_id, '+34600111001', 'lead', 'María García', 'maria.g@email.com', '{"preferred_contact": "whatsapp", "notas": "Cliente regular láser"}'),
  (v_business_id, '+34600111002', 'lead', 'Laura Martínez', 'laura.m@email.com', '{"preferred_contact": "whatsapp"}'),
  (v_business_id, '+34600111003', 'lead', 'Carmen López', 'carmen.l@email.com', '{"preferred_contact": "whatsapp"}'),
  (v_business_id, '+34600111004', 'lead', 'Ana Rodríguez', 'ana.r@email.com', '{"preferred_contact": "email"}'),
  (v_business_id, '+34600111005', 'lead', 'Isabel Sánchez', 'isabel.s@email.com', '{"preferred_contact": "whatsapp"}'),
  (v_business_id, '+34600111006', 'lead', 'Paula Fernández', 'paula.f@email.com', '{"preferred_contact": "whatsapp"}'),
  (v_business_id, '+34600111007', 'lead', 'Elena Ruiz', 'elena.r@email.com', '{"preferred_contact": "whatsapp"}'),
  (v_business_id, '+34600111008', 'lead', 'Rocío Torres', 'rocio.t@email.com', '{"preferred_contact": "email"}'),
  (v_business_id, '+34600111009', 'lead', 'Marta Jiménez', 'marta.j@email.com', '{"preferred_contact": "whatsapp"}'),
  (v_business_id, '+34600111010', 'lead', 'Sofía Moreno', 'sofia.m@email.com', '{"preferred_contact": "whatsapp"}');

  RAISE NOTICE '✅ Clientes de prueba insertados (10 clientes)';


  -- ===============================================
  -- RESUMEN FINAL
  -- ===============================================
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '✅ PARTE 1 COMPLETADA - ESTRUCTURA BÁSICA';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';
  RAISE NOTICE '📊 RESUMEN:';
  RAISE NOTICE '  Business ID: %', v_business_id;
  RAISE NOTICE '  Negocio: Dermaclinic Madrid';
  RAISE NOTICE '  Servicios: 31';
  RAISE NOTICE '  Clientes: 10';
  RAISE NOTICE '  Horario: Lun-Vie 10:00-20:00';
  RAISE NOTICE '';
  RAISE NOTICE '🔜 SIGUIENTE PASO:';
  RAISE NOTICE '  Ejecuta ahora: 0236b_dermaclinic_part2_conocimiento.sql';
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

END $$;

COMMIT;


-- ===============================================
-- VERIFICACIÓN POST-MIGRACIÓN
-- ===============================================
-- Ejecuta esto después para verificar:
/*
SELECT 
  b.name,
  b.slug,
  b.phone,
  (SELECT count(*) FROM services WHERE business_id = b.id) as servicios,
  (SELECT count(*) FROM profiles WHERE business_id = b.id) as usuarios
FROM businesses b
WHERE b.slug = 'dermaclinic-madrid';

-- Debe mostrar: 31 servicios, 11 usuarios (1 owner + 10 leads)
*/
