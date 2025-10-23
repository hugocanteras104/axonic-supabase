-- ===============================================
-- Migration: 0241_tetris_trigger_activation.sql
-- Purpose: Activar trigger de Tetris para optimización automática de agenda
-- Dependencies: 0218_tetris_optimizer.sql
-- ===============================================

-- Verificar dependencias
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'on_appointment_cancelled_tetris'
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función on_appointment_cancelled_tetris()\nAplicar primero: 0218_tetris_optimizer.sql';
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'notifications_queue'
  ) THEN
    RAISE EXCEPTION E'❌ DEPENDENCIA FALTANTE\n\nRequiere: tabla notifications_queue\nAplicar primero: 0237_n8n_bot_and_notifications.sql';
  END IF;
  
  RAISE NOTICE '✅ Dependencias verificadas';
END $$;

BEGIN;

-- ===============================================
-- TRIGGER: Tetris automático al cancelar cita
-- ===============================================

-- Eliminar trigger si existe (para re-crear)
DROP TRIGGER IF EXISTS trg_appointment_cancelled_tetris ON appointments;

-- Crear trigger
CREATE TRIGGER trg_appointment_cancelled_tetris
  AFTER UPDATE ON appointments
  FOR EACH ROW
  WHEN (
    OLD.status != 'cancelled' 
    AND NEW.status = 'cancelled'
  )
  EXECUTE FUNCTION on_appointment_cancelled_tetris();

COMMENT ON TRIGGER trg_appointment_cancelled_tetris ON appointments IS
  'Trigger que ejecuta Tetris automáticamente cuando una cita pasa a estado cancelled.
  Busca oportunidades de optimización en waitlist y genera notificaciones.';

-- ===============================================
-- VERIFICACIÓN
-- ===============================================

DO $$
DECLARE
  v_trigger_exists boolean;
BEGIN
  -- Verificar que el trigger fue creado
  SELECT EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE trigger_name = 'trg_appointment_cancelled_tetris'
      AND event_object_table = 'appointments'
  ) INTO v_trigger_exists;
  
  IF NOT v_trigger_exists THEN
    RAISE EXCEPTION 'Error: Trigger no fue creado correctamente';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '✅ MIGRACIÓN 0241 COMPLETADA';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 TETRIS ACTIVADO';
  RAISE NOTICE '';
  RAISE NOTICE 'Trigger configurado:';
  RAISE NOTICE '  Nombre: trg_appointment_cancelled_tetris';
  RAISE NOTICE '  Tabla: appointments';
  RAISE NOTICE '  Evento: AFTER UPDATE';
  RAISE NOTICE '  Condición: status cambia a cancelled';
  RAISE NOTICE '';
  RAISE NOTICE '📋 FUNCIONAMIENTO:';
  RAISE NOTICE '  1. Cliente cancela cita';
  RAISE NOTICE '  2. Trigger ejecuta on_appointment_cancelled_tetris()';
  RAISE NOTICE '  3. Tetris busca clientes en waitlist';
  RAISE NOTICE '  4. Genera notificación en notifications_queue';
  RAISE NOTICE '  5. n8n procesa y envía WhatsApp';
  RAISE NOTICE '';
  RAISE NOTICE '🧪 PARA PROBAR:';
  RAISE NOTICE '  1. Cancela una cita: UPDATE appointments SET status = ''cancelled'' WHERE id = ''...''';
  RAISE NOTICE '  2. Verifica notificaciones: SELECT * FROM notifications_queue ORDER BY created_at DESC LIMIT 1';
  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
END $$;

COMMIT;
