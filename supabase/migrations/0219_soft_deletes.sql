-- ===============================================
-- Migration: 0219_soft_deletes.sql
-- Purpose: Implementar borrado lógico (soft delete) en tablas críticas
-- Dependencies: 0200-0213
-- ===============================================

begin;

-- Agregar columna deleted_at a tablas críticas
alter table public.appointments add column if not exists deleted_at timestamptz;
alter table public.profiles add column if not exists deleted_at timestamptz;
alter table public.services add column if not exists deleted_at timestamptz;
alter table public.resources add column if not exists deleted_at timestamptz;
alter table public.inventory add column if not exists deleted_at timestamptz;

comment on column public.appointments.deleted_at is 
  'Borrado lógico: si tiene valor, el registro está "eliminado" pero recuperable';
comment on column public.profiles.deleted_at is 
  'Borrado lógico: permite desactivar clientes sin perder historial';
comment on column public.services.deleted_at is 
  'Borrado lógico: servicios descontinuados pero con historial';
comment on column public.resources.deleted_at is 
  'Borrado lógico: recursos dados de baja pero con historial';
comment on column public.inventory.deleted_at is 
  'Borrado lógico: productos descontinuados pero con historial';

-- Índices para excluir registros eliminados
create index idx_appointments_not_deleted on public.appointments(business_id, start_time) 
  where deleted_at is null;
create index idx_profiles_not_deleted on public.profiles(business_id, phone_number) 
  where deleted_at is null;
create index idx_services_not_deleted on public.services(business_id) 
  where deleted_at is null;
create index idx_resources_not_deleted on public.resources(business_id, type) 
  where deleted_at is null;
create index idx_inventory_not_deleted on public.inventory(business_id, sku) 
  where deleted_at is null;

-- Función helper para soft delete
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
  
  -- Validar tabla permitida
  if p_table_name not in ('appointments', 'profiles', 'services', 'resources', 'inventory') then
    raise exception 'Tabla % no soporta soft delete', p_table_name;
  end if;
  
  -- Construir y ejecutar UPDATE
  v_sql := format(
    'update public.%I set deleted_at = now() where id = $1 and business_id = $2 and deleted_at is null returning id',
    p_table_name
  );
  
  execute v_sql using p_record_id, v_business_id;
  
  if not found then
    raise exception 'Registro no encontrado o ya eliminado en tabla %', p_table_name;
  end if;
  
  -- Auditar
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

comment on function public.soft_delete is
  'Marca un registro como eliminado (soft delete) sin borrarlo físicamente. Uso: select public.soft_delete(''appointments'', uuid, ''motivo'');';

grant execute on function public.soft_delete(text, uuid, text) to authenticated;

-- Función para restaurar registros eliminados
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
  
  -- Validar tabla
  if p_table_name not in ('appointments', 'profiles', 'services', 'resources', 'inventory') then
    raise exception 'Tabla % no soporta restauración', p_table_name;
  end if;
  
  -- Restaurar
  v_sql := format(
    'update public.%I set deleted_at = null where id = $1 and business_id = $2 and deleted_at is not null returning id',
    p_table_name
  );
  
  execute v_sql using p_record_id, v_business_id;
  
  if not found then
    raise exception 'Registro no encontrado o no estaba eliminado en tabla %', p_table_name;
  end if;
  
  -- Auditar
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

comment on function public.restore_deleted is
  'Restaura un registro eliminado con soft delete. Uso: select public.restore_deleted(''appointments'', uuid);';

grant execute on function public.restore_deleted(text, uuid) to authenticated;

-- Actualizar vistas para excluir registros eliminados
create or replace view public.owner_dashboard_metrics as
select
    a.business_id,
    date_trunc('day', a.start_time) as day,
    count(*) filter (where a.status = 'confirmed') as confirmed_appointments,
    sum(s.base_price) filter (where a.status = 'confirmed') as estimated_revenue,
    (
        select s2.name
        from public.services s2
        join public.appointments a2 on a2.service_id = s2.id 
        where a2.business_id = a.business_id
          and s2.business_id = a.business_id
          and a2.status = 'confirmed'
          and a2.deleted_at is null
          and s2.deleted_at is null
          and date_trunc('day', a2.start_time) = date_trunc('day', a.start_time)
        group by s2.id, s2.name
        order by count(*) desc
        limit 1
    ) as top_service
from public.appointments a
join public.services s on s.id = a.service_id and s.business_id = a.business_id
where a.business_id is not null
  and a.deleted_at is null
  and s.deleted_at is null
group by a.business_id, day
order by day desc;

commit;

raise notice '========================================';
raise notice 'Soft Deletes implementado';
raise notice '';
raise notice 'Uso:';
raise notice '  Eliminar: select public.soft_delete(''appointments'', uuid, ''razón'');';
raise notice '  Restaurar: select public.restore_deleted(''appointments'', uuid);';
raise notice '========================================';
