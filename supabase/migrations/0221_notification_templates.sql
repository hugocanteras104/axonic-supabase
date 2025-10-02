-- ===============================================
-- Migration: 0221_notification_templates.sql
-- Purpose: Sistema de plantillas personalizables para notificaciones
-- Dependencies: 0004_functions_triggers.sql, 0006_policies_rls_grants.sql
-- ===============================================

-- Validar dependencias indispensables
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'businesses'
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: tabla businesses.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'set_updated_at'
      AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función public.set_updated_at()';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'get_user_business_id'
      AND n.nspname = 'public'
      AND p.proargtypes = ''::oidvector
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función public.get_user_business_id()';
  END IF;

  RAISE NOTICE '✅ Dependencias verificadas';
END $$;

BEGIN;

-- Tabla de plantillas de notificación
CREATE TABLE IF NOT EXISTS public.notification_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
  template_key text NOT NULL,
  channel text NOT NULL CHECK (channel IN ('email', 'whatsapp')),
  subject text,
  body_template text NOT NULL,
  variables jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_templates_unique_key UNIQUE (business_id, template_key, channel),
  CONSTRAINT notification_templates_subject_required CHECK (
    (channel = 'email' AND subject IS NOT NULL) OR channel <> 'email'
  )
);

COMMENT ON TABLE public.notification_templates IS
  'Plantillas dinámicas para emails y WhatsApp personalizables por negocio.';
COMMENT ON COLUMN public.notification_templates.business_id IS
  'Negocio propietario de la plantilla de notificación.';
COMMENT ON COLUMN public.notification_templates.template_key IS
  'Identificador lógico de la plantilla (appointment_confirmation, reminder, etc.).';
COMMENT ON COLUMN public.notification_templates.channel IS
  'Canal de envío soportado: email o whatsapp.';
COMMENT ON COLUMN public.notification_templates.body_template IS
  'Contenido de la notificación con variables {{variable}} reemplazables.';
COMMENT ON COLUMN public.notification_templates.variables IS
  'Diccionario JSON con variables disponibles y ejemplos de uso.';
COMMENT ON COLUMN public.notification_templates.subject IS
  'Asunto del correo electrónico; solo aplicable para canal email.';

-- Índices
CREATE INDEX IF NOT EXISTS idx_templates_business
  ON public.notification_templates(business_id);

CREATE INDEX IF NOT EXISTS idx_templates_active
  ON public.notification_templates(business_id, is_active)
  WHERE is_active = true;

-- Trigger de actualización automática de updated_at
DROP TRIGGER IF EXISTS trg_notification_templates_updated_at ON public.notification_templates;
CREATE TRIGGER trg_notification_templates_updated_at
  BEFORE UPDATE ON public.notification_templates
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- RLS: solo owners del negocio
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_templates_owner_all ON public.notification_templates;
CREATE POLICY notification_templates_owner_all ON public.notification_templates
  FOR ALL TO authenticated
  USING (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  )
  WITH CHECK (
    auth.jwt()->>'user_role' = 'owner'
    AND business_id = public.get_user_business_id()
  );

-- Seed de plantilla por defecto
INSERT INTO public.notification_templates (
  business_id,
  template_key,
  channel,
  subject,
  body_template,
  variables
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'appointment_confirmation',
  'email',
  'Confirmación de tu cita - {{business_name}}',
  'Hola {{client_name}},\nTu cita ha sido confirmada:\n\nServicio: {{service_name}}\nFecha: {{appointment_date}}\nHora: {{appointment_time}}\nPrecio: {{service_price}}€\n\nPolítica de cancelación: Puedes cancelar con 24h de anticipación sin cargo.\n¡Te esperamos!\n{{business_name}}',
  jsonb_build_object(
    'business_name', 'Axonic Wellness',
    'client_name', 'María García',
    'service_name', 'Masaje relajante',
    'appointment_date', '2024-05-18',
    'appointment_time', '17:30',
    'service_price', '60'
  )
)
ON CONFLICT (business_id, template_key, channel) DO NOTHING;

COMMIT;

RAISE NOTICE '✅ Migración 0221_notification_templates aplicada correctamente';
