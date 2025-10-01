-- ===============================================
-- Migration: 0203_make_business_id_required.sql
-- Purpose: Hacer business_id NOT NULL y crear constraints únicos
-- Dependencies: 0202_migrate_data_to_default_business.sql
-- ===============================================

begin;

-- Verificar que no hay datos sin business_id
do $$
declare
  v_null_count int;
begin
  select count(*) into v_null_count from profiles where business_id is null;
  if v_null_count > 0 then
    raise exception '❌ Hay % perfiles sin business_id. Aplicar primero: 0202', v_null_count;
  end if;
  raise notice '✅ Dependencias OK';
end $$;

-- Hacer columnas NOT NULL
alter table public.profiles alter column business_id set not null;
alter table public.services alter column business_id set not null;
alter table public.appointments alter column business_id set not null;
alter table public.resources alter column business_id set not null;
alter table public.inventory alter column business_id set not null;
alter table public.knowledge_base alter column business_id set not null;
alter table public.waitlists alter column business_id set not null;
alter table public.audit_logs alter column business_id set not null;
alter table public.cross_sell_rules alter column business_id set not null;
alter table public.notifications_queue alter column business_id set not null;
alter table public.service_resource_requirements alter column business_id set not null;
alter table public.resource_blocks alter column business_id set not null;
alter table public.knowledge_suggestions alter column business_id set not null;
alter table public.appointment_resources alter column business_id set not null;

-- Constraints únicos compuestos
alter table public.profiles drop constraint if exists profiles_phone_number_key;
create unique index if not exists idx_profiles_business_phone on public.profiles(business_id, phone_number);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'services_id_business_key' and conrelid = 'public.services'::regclass) then
    alter table public.services add constraint services_id_business_key unique (id, business_id);
  end if;
  
  if not exists (select 1 from pg_constraint where conname = 'profiles_id_business_key' and conrelid = 'public.profiles'::regclass) then
    alter table public.profiles add constraint profiles_id_business_key unique (id, business_id);
  end if;
  
  if not exists (select 1 from pg_constraint where conname = 'resources_id_business_key' and conrelid = 'public.resources'::regclass) then
    alter table public.resources add constraint resources_id_business_key unique (id, business_id);
  end if;
  
  if not exists (select 1 from pg_constraint where conname = 'appointments_id_business_key' and conrelid = 'public.appointments'::regclass) then
    alter table public.appointments add constraint appointments_id_business_key unique (id, business_id);
  end if;
end $$;

raise notice '✅ [4/6] Columnas marcadas como NOT NULL y constraints creados';

commit;
