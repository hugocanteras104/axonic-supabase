-- ===============================================
-- Migration: 0236b_dermaclinic_part2_conocimiento.sql
-- Purpose: PARTE 2 - Base de conocimiento, productos y configuración
-- Dependencies: 0236a_dermaclinic_part1_estructura.sql (DEBE ejecutarse primero)
-- ===============================================

BEGIN;

DO $$
DECLARE
  v_business_id uuid;
BEGIN
  
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '🚀 INICIANDO PARTE 2 - BASE DE CONOCIMIENTO Y CONFIGURACIÓN';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';

  -- Obtener business_id de Dermaclinic
  SELECT id INTO v_business_id FROM public.businesses WHERE slug = 'dermaclinic-madrid';
  
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'ERROR: No se encontró Dermaclinic. Ejecuta primero 0236a_dermaclinic_part1_estructura.sql';
  END IF;

  RAISE NOTICE 'Business ID encontrado: %', v_business_id;


  -- ===============================================
  -- PASO 1: Insertar Productos Eberlin
  -- ===============================================
  INSERT INTO public.inventory (business_id, sku, name, quantity, reorder_threshold, price, metadata) VALUES
  (v_business_id, 'EBR-BOOSTER-LB', 'Booster Le Blanche Eberlin', 10, 3, 50.00, '{"marca": "Eberlin", "categoria": "despigmentante"}'),
  (v_business_id, 'EBR-CREMA-LB', 'Crema Le Blanche Eberlin', 12, 4, 45.00, '{"marca": "Eberlin", "categoria": "despigmentante"}'),
  (v_business_id, 'EBR-SERUM-ENZ', 'Sérum Enzimático Eberlin', 8, 3, 42.00, '{"marca": "Eberlin", "categoria": "facial"}'),
  (v_business_id, 'EBR-CREMA-CS', 'Crema Control Sebo Eberlin', 10, 3, 44.00, '{"marca": "Eberlin", "categoria": "acne"}'),
  (v_business_id, 'EBR-SPF50', 'Protector Solar SPF50 Eberlin', 20, 8, 26.00, '{"marca": "Eberlin", "categoria": "proteccion"}'),
  (v_business_id, 'EBR-DESOD-NAT', 'Desodorante Natural sin Aluminio', 15, 5, 12.00, '{"marca": "Eberlin", "categoria": "post_laser"}');

  RAISE NOTICE '✅ [1/3] Productos insertados (6 productos Eberlin)';


  -- ===============================================
  -- PASO 2: Base de Conocimiento Completa
  -- ===============================================
  
  -- Servicios - Láser
  INSERT INTO public.knowledge_base (business_id, category, question, answer, metadata) VALUES
  (v_business_id, 'servicios', '¿En qué consiste la depilación láser?',
   'La depilación láser utiliza un haz de luz que penetra en la piel y es absorbido por la melanina del vello. Esta energía destruye el folículo piloso desde la raíz.

Cómo funciona:
- La luz busca el pigmento oscuro del vello
- El folículo se calienta y destruye
- Solo afecta vello en fase de crecimiento
- Por eso se necesitan varias sesiones (cada 4-6 semanas)

Es doloroso: Ligero calor o pequeños pinchazos, muy tolerable.

Precios: XS 12€ | S 25€ | M 50€ | L 90€ | XL 150€', '{"keywords": ["laser", "depilacion"]}'),

  (v_business_id, 'servicios', '¿Cuántas sesiones de láser necesito?',
   'Entre 6-10 sesiones para resultados óptimos, dependiendo de:
- Tipo de vello: Grueso responde mejor
- Zona: Axilas/ingles 6-8, piernas/espalda 8-10
- Tipo de piel y factores hormonales

Frecuencia: Cada 4-6 semanas
Resultados: Desde sesión 1 notarás reducción

BONOS: 6 sesiones (25% dto, 6 meses) | 10 sesiones (40% dto, 12 meses)', '{"keywords": ["sesiones", "necesito"]}'),

  (v_business_id, 'servicios', '¿Qué es la depilación eléctrica?',
   'Método complementario para vello que el láser no capta:
- Vello canoso o muy claro
- Pelos finos post-láser
- Zonas pequeñas
- Retoques finales

Aguja finísima en cada folículo + corriente eléctrica que destruye raíz.
Duración: 30 minutos | Precio: 60€', '{"keywords": ["electrica", "pelo a pelo"]}');

  -- Faciales
  INSERT INTO public.knowledge_base (business_id, category, question, answer, metadata) VALUES
  (v_business_id, 'tratamientos', '¿Qué es el Peeling Antiacné?',
   'Tratamiento facial con ácidos para piel con acné. Limpia profundidad, regula sebo, mejora textura.

Incluye: Limpieza + Peeling + Mascarilla + Hidratación + SPF50
Beneficios: Limpia poros, reduce granitos, controla grasa, mejora textura

Duración: 60 min | Precio: 55€

Pack Post-Acné 99€: Sérum Enzimático + Crema Control Sebo + SPF50 (ahorras 13€)', '{"keywords": ["peeling", "acne"]}'),

  (v_business_id, 'tratamientos', '¿Qué es el Peeling Kójico?',
   'Tratamiento Eberlin para manchas oscuras: solares, hiperpigmentación, melasma.

Ácido kójico inhibe melanina:
- Aclara manchas
- Unifica tono
- Previene nuevas manchas

Duración: 60 min | Precio: 55€
OBLIGATORIO SPF50 diario después

Pack Post-Kójico 109€: Booster + Crema Le Blanche + SPF50 (ahorras 12€)', '{"keywords": ["kojico", "manchas"]}'),

  (v_business_id, 'tratamientos', '¿Qué es el Peeling Hollywood?',
   'El preferido de celebrities. Carbon Peel con efecto alfombra roja inmediato.

Máscara de carbón + NanoLáser que limpia poros y estimula colágeno.

Beneficios inmediatos:
- Piel luminosa
- Poros reducidos
- Textura suave
- Glow natural
- Sin recuperación

Duración: 45 min | Precio: 95€', '{"keywords": ["hollywood", "carbon"]}'),

  (v_business_id, 'tratamientos', '¿Qué es Dioderma?',
   'Láser suave que reafirma y estimula colágeno sin recuperación.

Beneficios:
- Reafirma
- Mejora textura
- Reduce líneas finas
- Estimula colágeno
- Sin recuperación

Duración: 40 min | Precio: 60€', '{"keywords": ["dioderma", "reafirmante"]}'),

  (v_business_id, 'tratamientos', '¿Qué es el facial Ringana?',
   'Tratamiento 100% natural y vegano Ringana.

FILOSOFÍA 0 QUÍMICOS
- Ingredientes frescos naturales
- Sin parabenos, siliconas, microplásticos
- Cruelty-free
- Respeta equilibrio natural

Ideal para pieles sensibles o quienes prefieren cosmética natural.

Duración: 60 min | Precio: 75€', '{"keywords": ["ringana", "natural", "vegano"]}'),

  (v_business_id, 'productos', '¿Qué productos Ringana hay?',
   'Productos línea Ringana para continuar cuidado en casa.

IMPORTANTE: Filosofía 0 QUÍMICOS
Solo recomendamos productos Ringana para mantener coherencia.

NO mezclar con productos con químicos sintéticos.

Tenemos diferentes opciones según tu piel.
Pregúntanos en cabina o WhatsApp para asesoramiento personalizado.', '{"keywords": ["ringana", "productos", "cremas"]}');

  -- Tatuajes
  INSERT INTO public.knowledge_base (business_id, category, question, answer, metadata) VALUES
  (v_business_id, 'servicios', '¿Cómo eliminan tatuajes?',
   'NanoLáser SPT Q-Switched fragmenta partículas de tinta para que tu cuerpo las elimine.

Sesiones: Negros 5-8 | Colores 8-12 | Entre sesiones: 6-8 semanas

Precios según tamaño:
- Hasta 25cm² (5x5cm): 60€
- 26-50cm² (7x7cm): 120€
- 51-100cm² (10x10cm): 220€
- Más de 100cm²: 8€/cm²

Cálculo: Largo por Ancho en cm', '{"keywords": ["tatuajes", "eliminar"]}'),

  (v_business_id, 'servicios', '¿NanoLáser sirve para manchas?',
   'SÍ para manchas específicas:
- Léntigos solares (puntuales)
- Manchas superficiales
- Pecas

NO para melasma
NanoLáser puede EMPEORAR melasma

Melasma: mejillas/frente, relacionado con hormonas/sol

Para manchas puntuales: NanoLáser
Para melasma: Peeling Kójico 55€', '{"keywords": ["nanolaser", "manchas", "melasma"]}');

  -- Preparación y Cuidados
  INSERT INTO public.knowledge_base (business_id, category, question, answer, metadata) VALUES
  (v_business_id, 'preparacion', '¿Cómo prepararse para láser?',
   '24-48h ANTES:
- Afeita la zona
- NO cera/pinzas
- NO sol/autobronceador

DÍA DE SESIÓN:
- Piel limpia sin cremas
- Sin perfumes en zona
- Ropa cómoda

DESPUÉS:
- Evita sol 48-72h
- Usa SPF50
- Desodorante sin alcohol 24h (axilas)
- Recomendamos: Desodorante Natural 12€', '{"keywords": ["preparacion", "laser", "antes"]}'),

  (v_business_id, 'preparacion', '¿Preparación faciales?',
   'ANTES:
- Piel limpia (mejor sin maquillaje)
- No exfoliantes 48h antes
- No ácidos 48h antes

DESPUÉS Peelings:
- SPF50 obligatorio diario
- Evita sol 72h
- No maquillaje 24h
- Puede haber descamación leve

DESPUÉS Hollywood/Dioderma/Ringana:
- Vida normal inmediata
- SPF50 recomendado', '{"keywords": ["preparacion", "facial"]}'),

  (v_business_id, 'servicios', '¿Láser con tatuajes?',
   'SÍ con precauciones:
- Protegemos tatuaje con material blanco
- No pasamos láser sobre él
- Depilamos alrededor sin problema

Láser puede alterar colores del tatuaje
Por eso lo cubrimos completamente.

Lunares: También protegidos.', '{"keywords": ["laser", "tatuajes", "lunares"]}');

  -- Política y Logística
  INSERT INTO public.knowledge_base (business_id, category, question, answer, metadata) VALUES
  (v_business_id, 'politica', '¿Validez de bonos?',
   'LÁSER:
- 6 sesiones: 6 meses
- 10 sesiones: 12 meses

FACIALES:
- Todos: 6 meses

Si caduca: Sesiones no usadas se pierden

Tiempo suficiente:
- Bono 6 láser: 1 sesión/mes
- Bono 10 láser: 1 cada 5-6 semanas

No hay devoluciones', '{"keywords": ["bonos", "validez", "caducidad"]}'),

  (v_business_id, 'citas', '¿Cómo agendar cita?',
   'Por WhatsApp: +34 643 558 483

Horario: Lun-Vie 10:00-20:00

Agendar con mínimo 24h anticipación
Recordatorio 24h antes de cita', '{"keywords": ["agendar", "cita", "reserva"]}'),

  (v_business_id, 'citas', '¿Política cancelación?',
   'Cancela/reprograma con 24h anticipación sin cargo.

Menos de 24h aviso: 50% del servicio

Si imprevisto, avisa pronto para que otro cliente aproveche horario.', '{"keywords": ["cancelacion", "reprogramar"]}'),

  (v_business_id, 'ubicacion', '¿Dónde están?',
   'Madrid

Dirección exacta: Solicitar por WhatsApp
WhatsApp: +34 643 558 483
Email: holaeternalbeauty23@gmail.com

Horario: Lun-Vie 10:00-20:00
Sáb-Dom: Cerrado', '{"keywords": ["ubicacion", "direccion", "madrid"]}'),

  (v_business_id, 'pago', '¿Métodos de pago?',
   'Aceptamos:
- Efectivo
- Tarjeta crédito/débito
- Transferencia
- Bizum

Bonos se pagan en el momento.
Puedes pagar a plazos con tu tarjeta (según banco).', '{"keywords": ["pago", "metodos", "tarjeta"]}');

  RAISE NOTICE '✅ [2/3] Base conocimiento insertada (14 preguntas)';


  -- ===============================================
  -- PASO 3: Plantillas de Notificación
  -- ===============================================
  
  -- Crear plantillas por defecto
  PERFORM public.create_default_notification_templates(v_business_id);
  
  -- Personalizar para Dermaclinic
  UPDATE public.notification_templates
  SET body_template = 'Hola {{client_name}}!

Tu cita confirmada en Dermaclinic:

📅 {{appointment_date}}
🕐 {{appointment_time}}
💆‍♀️ {{service_name}}
💰 {{service_price}}€

📍 Madrid
📱 +34 643 558 483

⚠️ Puedes cancelar con 24h anticipación sin cargo
Recordatorio 24h antes

Te esperamos!
Dermaclinic',
    variables = jsonb_build_object(
      'business_name', 'Dermaclinic',
      'client_name', 'Cliente',
      'service_name', 'Servicio',
      'appointment_date', '2025-01-15',
      'appointment_time', '11:00',
      'service_price', '50'
    )
  WHERE business_id = v_business_id
    AND template_key = 'appointment_confirmation'
    AND channel = 'email';

  RAISE NOTICE '✅ [3/3] Plantillas creadas y personalizadas';


  -- ===============================================
  -- FIN CONFIGURACIÓN
  -- ===============================================
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '🎉 DERMACLINIC CONFIGURADO COMPLETAMENTE';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';
  RAISE NOTICE '📊 CONFIGURACIÓN FINAL:';
  RAISE NOTICE '  Business ID: %', v_business_id;
  RAISE NOTICE '  Servicios: 31';
  RAISE NOTICE '  Clientes: 10';
  RAISE NOTICE '  Productos: 6 (Eberlin)';
  RAISE NOTICE '  Base conocimiento: 14 preguntas';
  RAISE NOTICE '  Horario: Lun-Vie 10:00-20:00';
  RAISE NOTICE '';
  RAISE NOTICE '🔧 PRÓXIMOS PASOS:';
  RAISE NOTICE '  1. Verifica en Supabase Dashboard';
  RAISE NOTICE '  2. Configura N8N con business_id: %', v_business_id;
  RAISE NOTICE '  3. Prueba bot con cliente';
  RAISE NOTICE '  4. ¡A operar!';
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

END $$;

COMMIT;
