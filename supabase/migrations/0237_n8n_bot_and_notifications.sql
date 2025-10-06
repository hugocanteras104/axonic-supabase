-- 0237_n8n_bot_and_notifications.sql

BEGIN;

-- ============================================
-- HELPERS PARA N8N BOT
-- ============================================

CREATE OR REPLACE FUNCTION public.get_or_create_client_whatsapp(
  p_phone text,
  p_business_id uuid
)
RETURNS TABLE (
  id uuid,
  name text,
  email text,
  phone_number text,
  total_appointments bigint,
  no_show_count bigint,
  reliability_score int,
  has_active_packages boolean
) AS $$
BEGIN
  INSERT INTO profiles (business_id, phone_number, role, name)
  VALUES (p_business_id, p_phone, 'lead', 'Cliente Nuevo')
  ON CONFLICT (business_id, phone_number) DO NOTHING;
  
  RETURN QUERY
  SELECT 
    p.id, p.name, p.email, p.phone_number,
    COUNT(DISTINCT a.id) as total_appointments,
    COUNT(a.id) FILTER (WHERE a.no_show = true) as no_show_count,
    COALESCE(crs.reliability_score, 100) as reliability_score,
    EXISTS(SELECT 1 FROM client_packages cp WHERE cp.profile_id = p.id AND cp.status = 'active') as has_active_packages
  FROM profiles p
  LEFT JOIN appointments a ON a.profile_id = p.id
  LEFT JOIN client_reliability_score crs ON crs.profile_id = p.id
  WHERE p.phone_number = p_phone AND p.business_id = p_business_id
  GROUP BY p.id, crs.reliability_score;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.create_appointment_bot(
  p_profile_id uuid,
  p_service_id uuid,
  p_datetime timestamptz
)
RETURNS json AS $$
DECLARE
  v_business_id uuid;
  v_service record;
  v_needs_deposit boolean;
  v_appt_id uuid;
  v_end_time timestamptz;
BEGIN
  SELECT business_id INTO v_business_id FROM profiles WHERE id = p_profile_id;
  SELECT * INTO v_service FROM services WHERE id = p_service_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Service not found');
  END IF;
  
  SELECT COUNT(*) > 2 INTO v_needs_deposit FROM appointments 
  WHERE profile_id = p_profile_id AND no_show = true;
  
  v_end_time := p_datetime + (v_service.duration_minutes + COALESCE(v_service.buffer_minutes, 15))::text || ' minutes'::interval;
  
  INSERT INTO appointments (
    business_id, profile_id, service_id, start_time, end_time, status,
    requires_deposit, deposit_amount
  ) VALUES (
    v_business_id, p_profile_id, p_service_id, p_datetime, v_end_time, 'confirmed',
    v_needs_deposit, CASE WHEN v_needs_deposit THEN v_service.base_price * 0.5 END
  ) RETURNING id INTO v_appt_id;
  
  -- Trigger multi-channel notifications
  PERFORM send_appointment_confirmation_multicanal(v_appt_id);
  
  RETURN json_build_object(
    'appointment_id', v_appt_id,
    'requires_deposit', v_needs_deposit,
    'start_time', p_datetime
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- SISTEMA NOTIFICACIONES MULTI-CANAL
-- ============================================

CREATE OR REPLACE FUNCTION public.send_appointment_confirmation_multicanal(
  p_appointment_id uuid
)
RETURNS void AS $$
DECLARE
  v_appt record;
  v_profile record;
BEGIN
  SELECT a.*, s.name as service_name, s.base_price, b.name as business_name
  INTO v_appt
  FROM appointments a
  JOIN services s ON s.id = a.service_id
  JOIN businesses b ON b.id = a.business_id
  WHERE a.id = p_appointment_id;
  
  SELECT * INTO v_profile FROM profiles WHERE id = v_appt.profile_id;
  
  -- WhatsApp
  IF v_profile.phone_number IS NOT NULL THEN
    INSERT INTO notifications_queue (business_id, event_type, payload)
    VALUES (v_appt.business_id, 'send_whatsapp', json_build_object(
      'to', v_profile.phone_number,
      'template_key', 'appointment_confirmation',
      'appointment_id', p_appointment_id
    ));
  END IF;
  
  -- Email
  IF v_profile.email IS NOT NULL THEN
    INSERT INTO notifications_queue (business_id, event_type, payload)
    VALUES (v_appt.business_id, 'send_email', json_build_object(
      'to', v_profile.email,
      'template_key', 'appointment_confirmation',
      'appointment_id', p_appointment_id
    ));
  END IF;
  
  -- Google Calendar (cliente)
  IF v_profile.email IS NOT NULL THEN
    INSERT INTO notifications_queue (business_id, event_type, payload)
    VALUES (v_appt.business_id, 'google_calendar_invite', json_build_object(
      'appointment_id', p_appointment_id,
      'attendee_email', v_profile.email
    ));
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reminders multi-canal con Google Calendar
CREATE OR REPLACE FUNCTION public.process_pending_reminders(
  p_business_id uuid
)
RETURNS json AS $$
DECLARE
  v_count int := 0;
BEGIN
  WITH reminders AS (
    SELECT a.id, a.profile_id, a.start_time, 
           s.name as service_name, 
           p.phone_number, p.email
    FROM appointments a
    JOIN services s ON s.id = a.service_id
    JOIN profiles p ON p.id = a.profile_id
    WHERE a.business_id = p_business_id
    AND a.status = 'confirmed'
    AND a.reminder_sent_at IS NULL
    AND a.start_time BETWEEN now() + interval '23 hours' AND now() + interval '25 hours'
  )
  INSERT INTO notifications_queue (business_id, event_type, payload)
  SELECT p_business_id, channel, json_build_object(
    'to', CASE 
      WHEN channel = 'send_whatsapp' THEN r.phone_number
      WHEN channel = 'send_email' THEN r.email
    END,
    'template_key', 'appointment_reminder_24h',
    'appointment_id', r.id
  )
  FROM reminders r
  CROSS JOIN (VALUES ('send_whatsapp'), ('send_email')) AS channels(channel)
  WHERE (channel = 'send_whatsapp' AND r.phone_number IS NOT NULL)
     OR (channel = 'send_email' AND r.email IS NOT NULL);
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  
  UPDATE appointments SET reminder_sent_at = now()
  WHERE business_id = p_business_id
  AND status = 'confirmed'
  AND reminder_sent_at IS NULL
  AND start_time BETWEEN now() + interval '23 hours' AND now() + interval '25 hours';
  
  RETURN json_build_object('notifications_queued', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- TRIGGER: Sync automático a Google Calendar
-- ============================================

CREATE OR REPLACE FUNCTION public.sync_appointment_to_gcal_and_notify()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'confirmed' THEN
    -- Crear evento en Google Calendar (owner)
    INSERT INTO notifications_queue (business_id, event_type, payload)
    VALUES (NEW.business_id, 'google_calendar_sync_create', json_build_object(
      'appointment_id', NEW.id
    ));
  END IF;
  
  IF TG_OP = 'UPDATE' AND (
    OLD.start_time != NEW.start_time OR 
    OLD.status != NEW.status
  ) THEN
    INSERT INTO notifications_queue (business_id, event_type, payload)
    VALUES (NEW.business_id, 'google_calendar_sync_update', json_build_object(
      'appointment_id', NEW.id,
      'action', CASE WHEN NEW.status = 'cancelled' THEN 'delete' ELSE 'update' END
    ));
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_gcal_on_appointment_change ON appointments;
CREATE TRIGGER sync_gcal_on_appointment_change
AFTER INSERT OR UPDATE ON appointments
FOR EACH ROW
EXECUTE FUNCTION sync_appointment_to_gcal_and_notify();

GRANT EXECUTE ON FUNCTION public.get_or_create_client_whatsapp TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_appointment_bot TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_pending_reminders TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_appointment_confirmation_multicanal TO authenticated;

COMMIT;
