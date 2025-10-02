-- ===============================================
-- Migration: 0225_add_table_comments.sql
-- Purpose: Documentar tablas faltantes
-- ===============================================

BEGIN;

COMMENT ON TABLE public.appointment_resources IS 
  'Recursos asignados a cada cita (salas, equipos, personal). Relación N:M entre appointments y resources.';

COMMENT ON TABLE public.audit_logs IS 
  'Registro de auditoría de acciones críticas: cancelaciones, pagos, cambios de estado, no-shows.';

COMMENT ON TABLE public.cross_sell_rules IS 
  'Reglas de venta cruzada: qué servicios recomendar automáticamente después de completar otro servicio.';

COMMENT ON TABLE public.notifications_queue IS 
  'Cola de notificaciones pendientes de envío vía WhatsApp, email o SMS. Procesada por workers externos.';

COMMENT ON TABLE public.resource_blocks IS 
  'Bloqueos temporales de recursos por mantenimiento, vacaciones, reparaciones u otros motivos.';

COMMENT ON TABLE public.service_resource_requirements IS 
  'Define qué recursos (salas, equipos, personal) necesita cada servicio. Ejemplo: Láser requiere sala + equipo láser + técnico certificado.';

COMMIT;

DO $$
BEGIN
  RAISE NOTICE '✅ Documentación completada en 6 tablas';
END $$;
