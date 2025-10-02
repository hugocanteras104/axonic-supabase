-- ===============================================
-- Migration: 0226_auto_notification_templates.sql
-- Purpose: Crear plantillas automáticamente al crear un negocio
-- Dependencies: 0221_notification_templates.sql
-- ===============================================

BEGIN;

-- Función para crear plantillas por defecto en un negocio
CREATE OR REPLACE FUNCTION public.create_default_notification_templates(p_business_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Plantilla: Confirmación de cita (Email)
  INSERT INTO public.notification_templates (
    business_id, template_key, channel, subject, body_template, variables
  ) VALUES (
    p_business_id,
    'appointment_confirmation',
    'email',
    'Confirmación de tu cita - {{business_name}}',
    'Hola {{client_name}},
Tu cita ha sido confirmada:

Servicio: {{service_name}}
Fecha: {{appointment_date}}
Hora: {{appointment_time}}
Precio: {{service_price}}€

¡Te esperamos!
{{business_name}}

{{cancellation_policy}}',
    jsonb_build_object(
      'business_name', 'Tu Negocio',
      'client_name', 'Cliente',
      'service_name', 'Servicio',
      'appointment_date', '2024-01-01',
      'appointment_time', '10:00',
      'service_price', '50',
      'cancellation_policy', 'Puedes cancelar con 24h de anticipación sin cargo'
    )
  ) ON CONFLICT (business_id, template_key, channel) DO NOTHING;

  -- Plantilla: Advertencia no-show (WhatsApp)
  INSERT INTO public.notification_templates (
    business_id, template_key, channel, subject, body_template, variables
  ) VALUES (
    p_business_id,
    'no_show_warning',
    'whatsapp',
    NULL,
    'Hola {{client_name}},

Notamos que no pudiste asistir a tu cita del {{appointment_date}} para {{service_name}}.

Entendemos que pueden surgir imprevistos. Te recordamos que puedes cancelar con anticipación para que otros clientes puedan aprovechar el horario.

¿Te gustaría reagendar?

Saludos,
{{business_name}}',
    jsonb_build_object(
      'client_name', 'Cliente',
      'appointment_date', '2024-01-01',
      'service_name', 'Servicio',
      'business_name', 'Tu Negocio'
    )
  ) ON CONFLICT (business_id, template_key, channel) DO NOTHING;

  -- Plantilla: Recordatorio (WhatsApp)
  INSERT INTO public.notification_templates (
    business_id, template_key, channel, subject, body_template, variables
  ) VALUES (
    p_business_id,
    'appointment_reminder',
    'whatsapp',
    NULL,
    'Hola {{client_name}}! 👋

Te recordamos tu cita de mañana:

📅 {{appointment_date}} a las {{appointment_time}}
💆‍♀️ {{service_name}}
💰 {{service_price}}€

{{cancellation_policy}}

¡Te esperamos!
{{business_name}}',
    jsonb_build_object(
      'client_name', 'Cliente',
      'appointment_date', '2024-01-01',
      'appointment_time', '10:00',
      'service_name', 'Servicio',
      'service_price', '50',
      'cancellation_policy', 'Puedes cancelar con 24h de anticipación sin cargo',
      'business_name', 'Tu Negocio'
    )
  ) ON CONFLICT (business_id, template_key, channel) DO NOTHING;

END $$;

COMMENT ON FUNCTION public.create_default_notification_templates IS
  'Crea plantillas de notificación por defecto para un negocio nuevo';

-- Trigger para crear plantillas automáticamente
CREATE OR REPLACE FUNCTION public.on_business_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.create_default_notification_templates(NEW.id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_business_created ON public.businesses;
CREATE TRIGGER trg_business_created
  AFTER INSERT ON public.businesses
  FOR EACH ROW
  EXECUTE FUNCTION public.on_business_created();

COMMIT;

-- Crear plantillas para negocios existentes (si los hay)
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.businesses;
  
  IF v_count > 0 THEN
    PERFORM public.create_default_notification_templates(id)
    FROM public.businesses;
    
    RAISE NOTICE '✅ Plantillas creadas para % negocios existentes', v_count;
  ELSE
    RAISE NOTICE 'ℹ️  No hay negocios existentes. Las plantillas se crearán automáticamente al insertar negocios.';
  END IF;
END $$;
