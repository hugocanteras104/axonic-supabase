-- ===============================================
-- Migration: 0200_add_multitenancy.sql
-- Date: 2025-01-XX
-- Purpose: Agregar soporte para múltiples negocios
-- Breaking changes: Requiere asignar business_id a datos existentes
-- Dependencies: Todas las migraciones previas
-- ===============================================

begin;

-- ===============================================
-- PASO 1: CREAR TABLA BUSINESSES
-- ===============================================
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null check (slug ~ '^[a-z0-9-]+$'),
  phone text,
  email text,
  address text,
  metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.businesses is 
  'Negocios/clínicas que usan el sistema. Cada negocio tiene datos completamente aislados.';
comment on column public.businesses.slug is 
  'Identificador único para URLs amigables (ej: clinica-madrid-centro)';
comment on column public.businesses.metadata is 
  'Datos adicionales: logo, colores, configuración personalizada, etc.';

create index if not exists idx_businesses_slug on public.businesses(slug);
create index if not exists idx_businesses_active on public.businesses(is_active) where is_active = true;

raise notice '[1/8] Tabla businesses creada';

-- ===============================================
-- PASO 2: CREAR NEGOCIO POR DEFECTO
-- ===============================================
insert into public.businesses (id, name, slug, metadata)
values (
  '00000000-0000-0000-0000-000000000000',
  'Negocio Principal',
  'negocio-principal',
  '{"is_default": true}'::jsonb
)
on conflict (id) do nothing;

raise notice '[2/8] Negocio por defecto creado';

-- ===============================================
-- PASO 3: AGREGAR COLUMNA business_id
-- ===============================================
alter table public.profiles 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.services 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.appointments 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.resources 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.inventory 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.knowledge_base 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.waitlists 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.audit_logs 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.cross_sell_rules 
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.notifications_queue
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.service_resource_requirements
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.resource_blocks
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.knowledge_suggestions
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

alter table public.appointment_resources
  add column if not exists business_id uuid references public.businesses(id) on delete cascade;

raise notice '[3/8] Columnas business_id agregadas';

-- ===============================================
-- PASO 4: MIGRAR DATOS EXISTENTES
-- ===============================================
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

raise notice '[4/8] Datos existentes migrados al negocio por defecto';

-- ===============================================
-- PASO 5: HACER business_id OBLIGATORIO
-- ===============================================
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

raise notice '[5/8] Columnas business_id marcadas como NOT NULL';

-- ===============================================
-- PASO 6: CREAR ÍNDICES DE RENDIMIENTO
-- ===============================================
create index if not exists idx_profiles_business on public.profiles(business_id);
create index if not exists idx_services_business on public.services(business_id);
create index if not exists idx_appointments_business on public.appointments(business_id);
create index if not exists idx_resources_business on public.resources(business_id);
create index if not exists idx_inventory_business on public.inventory(business_id);
create index if not exists idx_kb_business on public.knowledge_base(business_id);
create index if not exists idx_waitlists_business on public.waitlists(business_id);
create index if not exists idx_audit_business on public.audit_logs(business_id);
create index if not exists idx_cross_sell_business on public.cross_sell_rules(business_id);
create index if not exists idx_nq_business on public.notifications_queue(business_id);
create index if not exists idx_srr_business on public.service_resource_requirements(business_id);
create index if not exists idx_rb_business on public.resource_blocks(business_id);
create index if not exists idx_ks_business on public.knowledge_suggestions(business_id);
create index if not exists idx_ar_business on public.appointment_resources(business_id);

alter table public.profiles drop constraint if exists profiles_phone_number_key;
create unique index if not exists idx_profiles_business_phone on public.profiles(business_id, phone_number);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'services_id_business_key'
      and conrelid = 'public.services'::regclass
  ) then
    alter table public.services
      add constraint services_id_business_key unique (id, business_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_id_business_key'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_id_business_key unique (id, business_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'resources_id_business_key'
      and conrelid = 'public.resources'::regclass
  ) then
    alter table public.resources
      add constraint resources_id_business_key unique (id, business_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'appointments_id_business_key'
      and conrelid = 'public.appointments'::regclass
  ) then
    alter table public.appointments
      add constraint appointments_id_business_key unique (id, business_id);
  end if;
end $$;

raise notice '[6/8] Índices creados';

-- ===============================================
-- PASO 7: CONSTRAINTS DE INTEGRIDAD
-- ===============================================
alter table public.appointments
  drop constraint if exists appt_same_business_service;

alter table public.appointments
  drop constraint if exists appt_same_business_profile;

alter table public.service_resource_requirements
  drop constraint if exists srr_same_business;

alter table public.cross_sell_rules
  drop constraint if exists csr_same_business;

alter table public.appointments
  drop constraint if exists appointments_profile_id_fkey;

alter table public.appointments
  drop constraint if exists appointments_service_id_fkey;

alter table public.service_resource_requirements
  drop constraint if exists service_resource_requirements_service_id_fkey;

alter table public.service_resource_requirements
  drop constraint if exists service_resource_requirements_resource_id_fkey;

alter table public.cross_sell_rules
  drop constraint if exists cross_sell_rules_trigger_service_id_fkey;

alter table public.cross_sell_rules
  drop constraint if exists cross_sell_rules_recommended_service_id_fkey;

alter table public.waitlists
  drop constraint if exists waitlists_service_id_fkey;

alter table public.waitlists
  drop constraint if exists waitlists_profile_id_fkey;

alter table public.resource_blocks
  drop constraint if exists resource_blocks_resource_id_fkey;

alter table public.appointment_resources
  drop constraint if exists appointment_resources_appointment_id_fkey;

alter table public.appointment_resources
  drop constraint if exists appointment_resources_resource_id_fkey;

alter table public.audit_logs
  drop constraint if exists audit_logs_profile_id_fkey;

alter table public.appointments
  add constraint fk_appointments_profile_business
  foreign key (profile_id, business_id)
  references public.profiles(id, business_id)
  on delete cascade;

alter table public.appointments
  add constraint fk_appointments_service_business
  foreign key (service_id, business_id)
  references public.services(id, business_id)
  on delete restrict;

alter table public.service_resource_requirements
  add constraint fk_srr_service_business
  foreign key (service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.service_resource_requirements
  add constraint fk_srr_resource_business
  foreign key (resource_id, business_id)
  references public.resources(id, business_id)
  on delete cascade;

alter table public.cross_sell_rules
  add constraint fk_csr_trigger_service_business
  foreign key (trigger_service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.cross_sell_rules
  add constraint fk_csr_recommended_service_business
  foreign key (recommended_service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.waitlists
  add constraint fk_waitlists_service_business
  foreign key (service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.waitlists
  add constraint fk_waitlists_profile_business
  foreign key (profile_id, business_id)
  references public.profiles(id, business_id)
  on delete cascade;

alter table public.resource_blocks
  add constraint fk_resource_blocks_resource_business
  foreign key (resource_id, business_id)
  references public.resources(id, business_id)
  on delete cascade;

alter table public.appointment_resources
  add constraint fk_ar_appointment_business
  foreign key (appointment_id, business_id)
  references public.appointments(id, business_id)
  on delete cascade;

alter table public.appointment_resources
  add constraint fk_ar_resource_business
  foreign key (resource_id, business_id)
  references public.resources(id, business_id)
  on delete restrict;

alter table public.audit_logs
  add constraint fk_audit_logs_profile_business
  foreign key (profile_id, business_id)
  references public.profiles(id, business_id);

raise notice '[7/8] Constraints de integridad creados';

-- ===============================================
-- PASO 8: FUNCIÓN HELPER
-- ===============================================
create or replace function auth.get_user_business_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select business_id 
  from public.profiles 
  where id = (auth.jwt()->>'sub')::uuid
  limit 1
$$;

comment on function auth.get_user_business_id is 
  'Retorna el business_id del usuario autenticado actualmente';

raise notice '[8/8] Función helper creada';

-- ===============================================
-- RLS: Habilitar en businesses
-- ===============================================
alter table public.businesses enable row level security;

drop policy if exists businesses_owner_read on public.businesses;
create policy businesses_owner_read on public.businesses
  for select to authenticated
  using (id = auth.get_user_business_id());

drop policy if exists businesses_admin_write on public.businesses;
create policy businesses_admin_write on public.businesses
  for all to authenticated
  using (false)
  with check (false);

raise notice 'RLS configurado para businesses';

commit;

raise notice '========================================';
raise notice 'Migración 0200_add_multitenancy completada exitosamente';
raise notice '========================================';

-- ===============================================
-- ROLLBACK (en caso de emergencia)
-- ===============================================
-- begin;
--   alter table profiles drop column if exists business_id;
--   alter table services drop column if exists business_id;
--   alter table appointments drop column if exists business_id;
--   alter table resources drop column if exists business_id;
--   alter table inventory drop column if exists business_id;
--   alter table knowledge_base drop column if exists business_id;
--   alter table waitlists drop column if exists business_id;
--   alter table audit_logs drop column if exists business_id;
--   alter table cross_sell_rules drop column if exists business_id;
--   alter table notifications_queue drop column if exists business_id;
--   alter table service_resource_requirements drop column if exists business_id;
--   alter table resource_blocks drop column if exists business_id;
--   alter table knowledge_suggestions drop column if exists business_id;
--   alter table appointment_resources drop column if exists business_id;
--   drop function if exists auth.get_user_business_id();
--   drop table if exists businesses cascade;
-- commit;
