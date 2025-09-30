-- ===============================================
-- Migration: 0200_create_businesses_table.sql
-- Purpose: Crear tabla businesses (solo la tabla)
-- Dependencies: 0001-0007
-- ===============================================

begin;

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

-- Crear negocio por defecto
insert into public.businesses (id, name, slug, metadata)
values (
  '00000000-0000-0000-0000-000000000000',
  'Negocio Principal',
  'negocio-principal',
  '{"is_default": true}'::jsonb
)
on conflict (id) do nothing;

-- Verificar
do $$
begin
  assert (select count(*) from public.businesses) >= 1, 
    'ERROR: No se creó el negocio por defecto';
  
  raise notice '✅ [1/6] Tabla businesses creada correctamente';
end $$;

commit;
