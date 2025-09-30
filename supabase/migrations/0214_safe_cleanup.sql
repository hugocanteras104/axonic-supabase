-- ===============================================
-- Migration: 0214_safe_cleanup.sql
-- Purpose: Limpieza segura con respaldo de datos antiguos
-- Dependencies: 0205_cleanup_footprints.sql
-- ===============================================

begin;

-- Tabla de archivo para datos eliminados
create table if not exists public.kb_views_footprint_archive (
  id uuid primary key default gen_random_uuid(),
  archived_at timestamptz not null default now(),
  original_count bigint not null,
  data jsonb not null
);

comment on table public.kb_views_footprint_archive is
  'Respaldo de registros de kb_views_footprint antes de ser eliminados. Permite recuperación si es necesario.';

create index if not exists idx_footprint_archive_date 
  on public.kb_views_footprint_archive(archived_at desc);

-- Función mejorada de limpieza con respaldo
create or replace function public.cleanup_old_footprints()
returns table(deleted_count bigint, archived_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_count bigint;
  v_archived_count bigint;
  v_archive_data jsonb;
begin
  -- Paso 1: Recopilar datos a eliminar
  select 
    count(*),
    jsonb_agg(
      jsonb_build_object(
        'kb_id', kb_id,
        'phone_hash', phone_hash,
        'last_view', last_view
      )
    )
  into v_archived_count, v_archive_data
  from public.kb_views_footprint
  where last_view < now() - interval '2 years';
  
  -- Paso 2: Guardar respaldo si hay datos
  if v_archived_count > 0 then
    insert into public.kb_views_footprint_archive (original_count, data)
    values (v_archived_count, v_archive_data);
    
    raise notice 'Respaldo creado: % registros archivados', v_archived_count;
  end if;
  
  -- Paso 3: Eliminar datos antiguos
  delete from public.kb_views_footprint 
  where last_view < now() - interval '2 years';
  
  get diagnostics v_deleted_count = row_count;
  
  raise notice 'Limpieza completada: % registros eliminados, % archivados', 
    v_deleted_count, v_archived_count;
  
  -- Retornar estadísticas
  return query select v_deleted_count, v_archived_count;
end;
$$;

comment on function public.cleanup_old_footprints is
  'Limpia registros antiguos de kb_views_footprint (>2 años) creando respaldo antes de borrar. Retorna (deleted_count, archived_count).';

-- Función para recuperar datos archivados (si se necesita)
create or replace function public.restore_footprint_archive(p_archive_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_archive record;
  v_restored_count bigint := 0;
  v_record jsonb;
begin
  -- Obtener archivo
  select * into v_archive
  from public.kb_views_footprint_archive
  where id = p_archive_id;
  
  if not found then
    raise exception 'Archivo % no encontrado', p_archive_id;
  end if;
  
  -- Restaurar cada registro
  for v_record in select * from jsonb_array_elements(v_archive.data)
  loop
    insert into public.kb_views_footprint (kb_id, phone_hash, last_view)
    values (
      (v_record->>'kb_id')::uuid,
      v_record->>'phone_hash',
      (v_record->>'last_view')::timestamptz
    )
    on conflict (kb_id, phone_hash) do nothing; -- Evitar duplicados
    
    v_restored_count := v_restored_count + 1;
  end loop;
  
  raise notice 'Restaurados % registros desde archivo %', v_restored_count, p_archive_id;
  
  return v_restored_count;
end;
$$;

comment on function public.restore_footprint_archive is
  'Restaura registros desde un archivo específico. Útil si se necesita recuperar datos eliminados.';

grant execute on function public.restore_footprint_archive(uuid) to authenticated;

commit;

raise notice '========================================';
raise notice 'Sistema de limpieza segura implementado';
raise notice 'Los datos se respaldan antes de eliminarse';
raise notice 'Para restaurar: select public.restore_footprint_archive(archive_id);';
raise notice '========================================';
