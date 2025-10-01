-- ===============================================
-- Migration: 0207_update_seed_multitenancy.sql
-- Purpose: Actualizar datos de prueba con business_id (solo entornos de desarrollo)
-- Dependencies: 0099_seed_dev.sql, 0200_add_multitenancy.sql
-- ===============================================

-- Verificación de seguridad
-- Solo permitir ejecución en bases dev/test/local/staging

do $$
declare
    v_db_name text := current_database();
    v_is_safe boolean;
begin
    v_is_safe := v_db_name ilike '%dev%'
        or v_db_name ilike '%develop%'
        or v_db_name ilike '%test%'
        or v_db_name ilike '%local%'
        or v_db_name ilike '%staging%';

    if not v_is_safe then
        raise exception 'Esta migración solo puede ejecutarse en bases de datos de desarrollo. Base de datos actual: %', v_db_name;
    end if;
end $$;

begin;

insert into public.businesses (id, name, slug, phone, email, address, metadata)
values 
(
  '11111111-1111-1111-1111-111111111111',
  'Clínica Belleza Madrid Centro',
  'belleza-madrid-centro',
  '+34911222333',
  'info@bellezamadrid.com',
  'Calle Gran Vía 123, Madrid',
  '{"is_test": true, "city": "Madrid"}'::jsonb
),
(
  '22222222-2222-2222-2222-222222222222',
  'Spa Relax Barcelona',
  'spa-relax-barcelona',
  '+34933444555',
  'hola@sparelax.com',
  'Passeig de Gràcia 45, Barcelona',
  '{"is_test": true, "city": "Barcelona"}'::jsonb
)
on conflict (id) do update set
  name = excluded.name,
  slug = excluded.slug,
  phone = excluded.phone,
  email = excluded.email,
  address = excluded.address,
  metadata = excluded.metadata;


insert into public.business_settings (business_id, setting_key, setting_value, description)
values 
(
  '11111111-1111-1111-1111-111111111111',
  'business_hours',
  '{
    "timezone": "Europe/Madrid",
    "schedule": {
      "monday": {"open": "09:00", "close": "20:00"},
      "tuesday": {"open": "09:00", "close": "20:00"},
      "wednesday": {"open": "09:00", "close": "20:00"},
      "thursday": {"open": "09:00", "close": "20:00"},
      "friday": {"open": "09:00", "close": "20:00"},
      "saturday": {"open": "09:00", "close": "18:00"},
      "sunday": {"closed": true}
    },
    "holidays": ["2025-01-01", "2025-01-06", "2025-05-01", "2025-12-25"]
  }'::jsonb,
  'Horario de atención - Madrid'
),
(
  '11111111-1111-1111-1111-111111111111',
  'cancellation_policy',
  '{
    "hours_notice": 24,
    "penalty_percentage": 50,
    "allow_same_day": false,
    "free_cancellation_window_hours": 48
  }'::jsonb,
  'Política de cancelaciones'
),
(
  '11111111-1111-1111-1111-111111111111',
  'pricing_rules',
  '{
    "min_price": 10.00,
    "max_price": 500.00,
    "deposit_required_above": 100.00,
    "deposit_percentage": 30,
    "currency": "EUR"
  }'::jsonb,
  'Reglas de precios'
)
on conflict (business_id, setting_key) do update set
  setting_value = excluded.setting_value,
  description = excluded.description;


insert into public.business_settings (business_id, setting_key, setting_value, description)
values 
(
  '22222222-2222-2222-2222-222222222222',
  'business_hours',
  '{
    "timezone": "Europe/Madrid",
    "schedule": {
      "monday": {"open": "10:00", "close": "22:00"},
      "tuesday": {"open": "10:00", "close": "22:00"},
      "wednesday": {"open": "10:00", "close": "22:00"},
      "thursday": {"open": "10:00", "close": "22:00"},
      "friday": {"open": "10:00", "close": "22:00"},
      "saturday": {"open": "10:00", "close": "22:00"},
      "sunday": {"open": "10:00", "close": "20:00"}
    },
    "holidays": []
  }'::jsonb,
  'Horario de atención - Barcelona (7 días)'
),
(
  '22222222-2222-2222-2222-222222222222',
  'pricing_rules',
  '{
    "min_price": 15.00,
    "max_price": 800.00,
    "deposit_required_above": 150.00,
    "deposit_percentage": 40,
    "currency": "EUR"
  }'::jsonb,
  'Reglas de precios - Barcelona'
)
on conflict (business_id, setting_key) do update set
  setting_value = excluded.setting_value,
  description = excluded.description;


update public.profiles 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.services 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.appointments 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.resources 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.inventory 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.knowledge_base 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.cross_sell_rules 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.service_resource_requirements 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';

update public.resource_blocks 
set business_id = '11111111-1111-1111-1111-111111111111'
where business_id = '00000000-0000-0000-0000-000000000000';


select public.generate_test_appointments(90, 30, 8);


commit;

