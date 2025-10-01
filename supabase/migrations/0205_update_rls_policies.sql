-- ===============================================
-- Migration: 0205_update_rls_policies.sql
-- Purpose: Crear función helper y actualizar RLS básico
-- Dependencies: 0204_add_foreign_key_constraints.sql
-- ===============================================

begin;

-- Crear función helper en schema PUBLIC (no auth)
create or replace function public.get_user_business_id()
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

comment on function public.get_user_business_id is 
  'Retorna el business_id del usuario autenticado actualmente';

-- Habilitar RLS en businesses
alter table public.businesses enable row level security;

drop policy if exists businesses_owner_read on public.businesses;
create policy businesses_owner_read on public.businesses
  for select to authenticated
  using (id = public.get_user_business_id());

drop policy if exists businesses_admin_write on public.businesses;
create policy businesses_admin_write on public.businesses
  for all to authenticated
  using (false)
  with check (false);

do $$
begin
  raise notice '✅ [6/6] Función helper y RLS básico creados';
  raise notice '🎉 Fase 1 de multitenancy completada';
  raise notice 'Aplicar siguiente: 0206_update_rls_deep.sql';
end $$;

commit;
