-- 0223_update_notification_templates.sql (CORREGIDO)

BEGIN;

UPDATE public.notification_templates
SET
  body_template = 'Hola {{client_name}},
Tu cita ha sido confirmada:

Servicio: {{service_name}}
Fecha: {{appointment_date}}
Hora: {{appointment_time}}
Precio: {{service_price}}€

¡Te esperamos!
{{business_name}}

{{cancellation_policy}}',
  variables = COALESCE(variables, '{}'::jsonb) || jsonb_build_object(
    'cancellation_policy', 'Puedes cancelar con 24h de anticipación sin cargo'
  )
WHERE business_id = '00000000-0000-0000-0000-000000000000'
  AND template_key = 'appointment_confirmation'
  AND channel = 'email';

INSERT INTO public.notification_templates (
  business_id, template_key, channel, subject, body_template, variables
) VALUES (
  '00000000-0000-0000-0000-000000000000',
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
    'client_name', 'María García',
    'appointment_date', '2024-05-18',
    'service_name', 'Masaje relajante',
    'business_name', 'Axonic Wellness'
  )
) ON CONFLICT (business_id, template_key, channel) DO NOTHING;

INSERT INTO public.notification_templates (
  business_id, template_key, channel, subject, body_template, variables
) VALUES (
  '00000000-0000-0000-0000-000000000000',
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
    'client_name', 'María García',
    'appointment_date', '2024-05-18',
    'appointment_time', '17:30',
    'service_name', 'Masaje relajante',
    'service_price', '60',
    'cancellation_policy', 'Puedes cancelar con 24h de anticipación sin cargo',
    'business_name', 'Axonic Wellness'
  )
) ON CONFLICT (business_id, template_key, channel) DO NOTHING;

COMMIT;
