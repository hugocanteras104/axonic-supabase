-- ===============================================
-- Migration: 0202_migrate_data_to_default_business.sql
-- Purpose: Llenar business_id con valor por defecto
-- Dependencies: 0201_add_business_id_columns.sql
-- ===============================================

begin;

-- Verificar dependencias
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'profiles' and column_name = 'business_id'
  ) then
    raise exception '❌ Falta columna business_id. Aplicar primero: 0201_add_business_id_columns.sql';
  end if;
  raise notice '✅ Dependencias OK';
end $$;

-- Contar registros a migrar
do $$
declare
  v_profiles int;
  v_services int;
  v_appointments int;
begin
  select count(*) into v_profiles from profiles where business_id is null;
  select count(*) into v_services from services where business_id is null;
  select count(*) into v_appointments from appointments where business_id is null;
  
  raise notice 'Por migrar: % perfiles, % servicios, % citas', 
    v_profiles, v_services, v_appointments;
end $$;

-- Migrar datos
update public.profiles set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.services set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.appointments set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.resources set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.inventory set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.knowledge_base set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.waitlists set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.audit_logs set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.cross_sell_rules set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.notifications_queue set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.service_resource_requirements set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.resource_blocks set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.knowledge_suggestions set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;
update public.appointment_resources set business_id = '00000000-0000-0000-0000-000000000000' where business_id is null;

-- Verificar que no quedó nada sin migrar
do $$
begin
  assert (select count(*) from profiles where business_id is null) = 0, 'ERROR: Hay perfiles sin business_id';
  assert (select count(*) from services where business_id is null) = 0, 'ERROR: Hay servicios sin business_id';
  assert (select count(*) from appointments where business_id is null) = 0, 'ERROR: Hay citas sin business_id';
  assert (select count(*) from resources where business_id is null) = 0, 'ERROR: Hay recursos sin business_id';
  assert (select count(*) from inventory where business_id is null) = 0, 'ERROR: Hay inventario sin business_id';
  assert (select count(*) from knowledge_base where business_id is null) = 0, 'ERROR: Hay KB sin business_id';
  assert (select count(*) from waitlists where business_id is null) = 0, 'ERROR: Hay waitlists sin business_id';
  assert (select count(*) from audit_logs where business_id is null) = 0, 'ERROR: Hay audit_logs sin business_id';
  assert (select count(*) from cross_sell_rules where business_id is null) = 0, 'ERROR: Hay cross_sell_rules sin business_id';
  assert (select count(*) from notifications_queue where business_id is null) = 0, 'ERROR: Hay notifications_queue sin business_id';
  assert (select count(*) from service_resource_requirements where business_id is null) = 0, 'ERROR: Hay SRR sin business_id';
  assert (select count(*) from resource_blocks where business_id is null) = 0, 'ERROR: Hay resource_blocks sin business_id';
  assert (select count(*) from knowledge_suggestions where business_id is null) = 0, 'ERROR: Hay knowledge_suggestions sin business_id';
  assert (select count(*) from appointment_resources where business_id is null) = 0, 'ERROR: Hay appointment_resources sin business_id';
  
  raise notice '✅ [3/6] Todos los datos migrados correctamente';
end $$;

commit;
