-- ===============================================
-- Migration: 0201_add_business_id_columns.sql
-- Purpose: Agregar columna business_id a todas las tablas
-- Dependencies: 0200_create_businesses_table.sql
-- ===============================================

begin;

-- Verificar dependencias
do $$
begin
  if not exists (select 1 from pg_tables where tablename = 'businesses') then
    raise exception '❌ Falta tabla businesses. Aplicar primero: 0200_create_businesses_table.sql';
  end if;
  raise notice '✅ Dependencias OK';
end $$;

-- Agregar columnas (nullable por ahora)
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

-- Crear índices
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

raise notice '✅ [2/6] Columnas e índices creados correctamente';

commit;
