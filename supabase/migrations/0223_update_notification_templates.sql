-- ===============================================
-- Migration: 0223_update_notification_templates.sql
-- Purpose: Actualizar plantillas con política de cancelación variable y nuevas notificaciones
-- Dependencies: 0221_notification_templates.sql
-- ===============================================

-- Validar dependencias
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'notification_templates'
  ) THEN
    RAISE EXCEPTION '❌ Falta tabla notification_templates. Aplicar migración 0221 primero.';
  END IF;

  RAISE NOTICE '✅ Dependencias verificadas';
END $$;

BEGIN;

-- Actualizar plantilla de confirmación existente
UPDATE public.notification_templates
SET
  body_template = 'Hola {{client_name}},\nTu cita ha sido confirmada:\n\nServicio: {{service_name}}\nFecha: {{appointment_date}}\nHora: {{appointment_time}}\nPrecio: {{service_price}}€\n\n¡Te esperamos!\n{{business_name}}\n\n{{cancellation_policy}}',
  variables = COALESCE(variables, '{}'::jsonb) || jsonb_build_object(
    'cancellation_policy', 'Puedes cancelar con 24h de anticipación sin cargo'
  )
WHERE business_id = '11111111-1111-1111-1111-111111111111'
  AND template_key = 'appointment_confirmation'
  AND channel = 'email';

-- Insertar plantilla para advertencia de no-show (WhatsApp)
INSERT INTO public.notification_templates (
  business_id,
  template_key,
  channel,
  subject,
  body_template,
  variables
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'no_show_warning',
  'whatsapp',
  NULL,
  'Hola {{client_name}},\n\nNotamos que no pudiste asistir a tu cita del {{appointment_date}} para {{service_name}}.\n\nEntendemos que pueden surgir imprevistos. Te recordamos que puedes cancelar con anticipación para que otros clientes puedan aprovechar el horario.\n\n¿Te gustaría reagendar?\n\nSaludos,\n{{business_name}}',
  jsonb_build_object(
    'client_name', 'María García',
    'appointment_date', '2024-05-18',
    'service_name', 'Masaje relajante',
    'business_name', 'Axonic Wellness'
  )
)
ON CONFLICT (business_id, template_key, channel) DO NOTHING;

-- Insertar plantilla para recordatorio de cita (WhatsApp)
INSERT INTO public.notification_templates (
  business_id,
  template_key,
  channel,
  subject,
  body_template,
  variables
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'appointment_reminder',
  'whatsapp',
  NULL,
  'Hola {{client_name}}! 👋\n\nTe recordamos tu cita de mañana:\n\n📅 {{appointment_date}} a las {{appointment_time}}\n💆‍♀️ {{service_name}}\n💰 {{service_price}}€\n\n{{cancellation_policy}}\n\n¡Te esperamos!\n{{business_name}}',
  jsonb_build_object(
    'client_name', 'María García',
    'appointment_date', '2024-05-18',
    'appointment_time', '17:30',
    'service_name', 'Masaje relajante',
    'service_price', '60',
    'cancellation_policy', 'Puedes cancelar con 24h de anticipación sin cargo',
    'business_name', 'Axonic Wellness'
  )
)
ON CONFLICT (business_id, template_key, channel) DO NOTHING;

COMMIT;

RAISE NOTICE '✅ Migración 0223_update_notification_templates aplicada correctamente';
