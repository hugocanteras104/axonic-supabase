-- ===============================================
-- Migration: 0219_soft_deletes.sql
-- Purpose: Implementar borrado lógico (soft delete)
-- Dependencies: 0200-0213
-- ===============================================

begin;

-- Agregar columna deleted_at
alter table public.appointments add column if not exists deleted_at timestamptz;
alter table public.profiles add column if not exists deleted_at timestamptz;
alter table public.services add column if not exists deleted_at timestamptz;
alter table public.resources add column if not exists deleted_at timestamptz;
alter table public.inventory add column if not exists deleted_at timestamptz;

comment on column public.appointments.deleted_at is 
  'Borrado lógico: si tiene valor, el registro está eliminado pero recuperable';
comment on column public.profiles.deleted_at is 
  'Borrado lógico: permite desactivar clientes sin perder historial';
comment on column public.services.deleted_at is 
  'Borrado lógico: servicios descontinuados pero con historial';
comment on column public.resources.deleted_at is 
  'Borrado lógico: recursos dados de baja pero con historial';
comment on column public.inventory.deleted_at is 
  'Borrado lógico: productos descontinuados pero con historial';

-- Índices
create index if not exists idx_appointments_not_deleted 
  on public.appointments(business_id, start_time) 
  where deleted_at is null;
create index if not exists idx_profiles_not_deleted 
  on public.profiles(business_id, phone_number) 
  where deleted_at is null;
create index if not exists idx_services_not_deleted 
  on public.services(business_id) 
  where deleted_at is null;
create index if not exists idx_resources_not_deleted 
  on public.resources(business_id, type) 
  where deleted_at is null;
create index if not exists idx_inventory_not_deleted 
  on public.inventory(business_id, sku) 
  where deleted_at is null;

-- Función soft delete
create or replace function public.soft_delete(
  p_table_name text,
  p_record_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_user_id uuid;
  v_sql text;
begin
  v_business_id := public.get_user_business_id();
  
  begin
    v_user_id := (auth.jwt()->>'sub')::uuid;
  exception when others then
    v_user_id := null;
  end;
  
  if p_table_name not in ('appointments', 'profiles', 'services', 'resources', 'inventory') then
    raise exception 'Tabla % no soporta soft delete', p_table_name;
  end if;
  
  v_sql := format(
    'update public.%I set deleted_at = now() where id = $1 and business_id = $2 and deleted_at is null returning id',
    p_table_name
  );
  
  execute v_sql using p_record_id, v_business_id;
  
  if not found then
    raise exception 'Registro no encontrado o ya eliminado en tabla %', p_table_name;
  end if;
  
  insert into public.audit_logs (business_id, profile_id, action, payload)
  values (
    v_business_id,
    v_user_id,
    'soft_delete',
    jsonb_build_object(
      'table', p_table_name,
      'record_id', p_record_id,
      'reason', p_reason,
      'deleted_at', now()
    )
  );
  
  return jsonb_build_object(
    'success', true,
    'table', p_table_name,
    'record_id', p_record_id,
    'deleted_at', now()
  );
end;
$$;

grant execute on function public.soft_delete(text, uuid, text) to authenticated;

-- Función restore
create or replace function public.restore_deleted(
  p_table_name text,
  p_record_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_user_id uuid;
  v_sql text;
begin
  v_business_id := public.get_user_business_id();
  
  begin
    v_user_id := (auth.jwt()->>'sub')::uuid;
  exception when others then
    v_user_id := null;
  end;
  
  if p_table_name not in ('appointments', 'profiles', 'services', 'resources', 'inventory') then
    raise exception 'Tabla % no soporta restauración', p_table_name;
  end if;
  
  v_sql := format(
    'update public.%I set deleted_at = null where id = $1 and business_id = $2 and deleted_at is not null returning id',
    p_table_name
  );
  
  execute v_sql using p_record_id, v_business_id;
  
  if not found then
    raise exception 'Registro no encontrado o no estaba eliminado en tabla %', p_table_name;
  end if;
  
  insert into public.audit_logs (business_id, profile_id, action, payload)
  values (
    v_business_id,
    v_user_id,
    'restore_deleted',
    jsonb_build_object(
      'table', p_table_name,
      'record_id', p_record_id,
      'restored_at', now()
    )
  );
  
  return jsonb_build_object(
    'success', true,
    'table', p_table_name,
    'record_id', p_record_id,
    'restored_at', now()
  );
end;
$$;

grant execute on function public.restore_deleted(text, uuid) to authenticated;

-- Actualizar vista (versión corregida con CTEs)
drop view if exists public.owner_dashboard_metrics;

create view public.owner_dashboard_metrics as
with daily_appointments as (
    select
        a.business_id,
        date_trunc('day', a.start_time) as day,
        count(*) filter (where a.status = 'confirmed') as confirmed_appointments,
        sum(s.base_price) filter (where a.status = 'confirmed') as estimated_revenue
    from public.appointments a
    join public.services s on s.id = a.service_id and s.business_id = a.business_id
    where a.business_id is not null
      and a.deleted_at is null
      and s.deleted_at is null
    group by a.business_id, day
),
top_services as (
    select distinct on (a.business_id, date_trunc('day', a.start_time))
        a.business_id,
        date_trunc('day', a.start_time) as day,
        s.name as top_service
    from public.appointments a
    join public.services s on s.id = a.service_id and s.business_id = a.business_id
    where a.status = 'confirmed'
      and a.business_id is not null
      and a.deleted_at is null
      and s.deleted_at is null
    group by a.business_id, day, s.id, s.name
    order by a.business_id, day, count(*) desc
)
select
    da.business_id,
    da.day,
    da.confirmed_appointments,
    da.estimated_revenue,
    coalesce(ts.top_service, '') as top_service
from daily_appointments da
left join top_services ts 
  on ts.business_id = da.business_id 
  and ts.day = da.day
order by da.business_id, da.day desc;

commit;
