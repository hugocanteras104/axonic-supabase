-- 0221_notification_templates.sql (CORREGIDO)

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'businesses'
  ) THEN
    RAISE EXCEPTION '❌ Falta tabla businesses';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'set_updated_at' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION '❌ Falta función set_updated_at()';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'get_user_business_id' AND n.nspname = 'public'
  ) THEN
    RAISE EXCEPTION '❌ Falta función get_user_business_id()';
  END IF;
END $$;

BEGIN;

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

CREATE INDEX IF NOT EXISTS idx_templates_business ON public.notification_templates(business_id);
CREATE INDEX IF NOT EXISTS idx_templates_active ON public.notification_templates(business_id, is_active) WHERE is_active = true;

DROP TRIGGER IF EXISTS trg_notification_templates_updated_at ON public.notification_templates;
CREATE TRIGGER trg_notification_templates_updated_at
  BEFORE UPDATE ON public.notification_templates
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

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

-- Plantilla por defecto (usando negocio por defecto)
INSERT INTO public.notification_templates (
  business_id,
  template_key,
  channel,
  subject,
  body_template,
  variables
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'appointment_confirmation',
  'email',
  'Confirmación de tu cita - {{business_name}}',
  'Hola {{client_name}},

Tu cita ha sido confirmada:

Servicio: {{service_name}}
Fecha: {{appointment_date}}
Hora: {{appointment_time}}
Precio: {{service_price}}€

Política de cancelación: Puedes cancelar con 24h de anticipación sin cargo.
¡Te esperamos!
{{business_name}}',
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
