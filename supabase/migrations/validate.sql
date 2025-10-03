create or replace function validate_migration_state()
returns table(
  status text,
  object_name text,
  required_by text,
  severity text,
  suggestion text
) language plpgsql as $$
begin
  -- Extensiones
  return query
  select case when exists(select 1 from pg_extension where extname = 'pgcrypto') then '✅' else '❌' end,
    'Extensión pgcrypto', '0002', 'CRITICAL', 'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'pgcrypto');
  
  return query
  select case when exists(select 1 from pg_extension where extname = 'pg_trgm') then '✅' else '❌' end,
    'Extensión pg_trgm', '0005', 'CRITICAL', 'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'pg_trgm');
  
  return query
  select case when exists(select 1 from pg_extension where extname = 'unaccent') then '✅' else '❌' end,
    'Extensión unaccent', '0005', 'CRITICAL', 'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'unaccent');
  
  return query
  select case when exists(select 1 from pg_extension where extname = 'btree_gist') then '✅' else '❌' end,
    'Extensión btree_gist', '0003', 'CRITICAL', 'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'btree_gist');
  
  -- Tablas
  return query
  select case when exists(select 1 from pg_tables where tablename = 'profiles') then '✅' else '❌' end,
    'Tabla profiles', 'FASE 1', 'CRITICAL', 'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'profiles');
  
  return query
  select case when exists(select 1 from pg_tables where tablename = 'services') then '✅' else '❌' end,
    'Tabla services', 'FASE 1', 'CRITICAL', 'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'services');
  
  return query
  select case when exists(select 1 from pg_tables where tablename = 'appointments') then '✅' else '❌' end,
    'Tabla appointments', 'FASE 1', 'CRITICAL', 'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'appointments');
  
  return query
  select case when exists(select 1 from pg_tables where tablename = 'knowledge_base') then '✅' else '❌' end,
    'Tabla knowledge_base', 'FASE 1', 'CRITICAL', 'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'knowledge_base');
  
  -- Multitenancy
  return query
  select case when exists(select 1 from pg_tables where tablename = 'businesses') then '✅' else '⚠️' end,
    'Tabla businesses', 'FASE 2', 
    case when exists(select 1 from pg_tables where tablename = 'businesses') then 'INFO' else 'HIGH' end,
    case when exists(select 1 from pg_tables where tablename = 'businesses') 
      then 'Multitenancy habilitado' 
      else 'Aplicar: 0200_create_businesses_table.sql' 
    end;
  
  if exists(select 1 from pg_tables where tablename = 'businesses') then
    return query
    select case when exists(select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'business_id') then '✅' else '❌' end,
      'Columna business_id en profiles', 'FASE 2', 'CRITICAL', 'Aplicar: 0201_add_business_id_columns.sql'
    where not exists(select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'business_id');
    
    return query
    select case when exists(select 1 from information_schema.columns where table_name = 'appointments' and column_name = 'business_id') then '✅' else '❌' end,
      'Columna business_id en appointments', 'FASE 2', 'CRITICAL', 'Aplicar: 0201_add_business_id_columns.sql'
    where not exists(select 1 from information_schema.columns where table_name = 'appointments' and column_name = 'business_id');
  end if;
  
  -- Funciones
  return query
  select case when exists(select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'set_updated_at') then '✅' else '❌' end,
    'Función set_updated_at()', 'FASE 1', 'CRITICAL', 'Aplicar: 0004_functions_triggers.sql'
  where not exists(select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'set_updated_at');
  
  return query
  select case when exists(select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'norm_txt') then '✅' else '❌' end,
    'Función norm_txt()', 'FASE 1', 'CRITICAL', 'Aplicar: 0005_feature_kb_search.sql'
  where not exists(select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'norm_txt');
  
  if exists(select 1 from pg_tables where tablename = 'businesses') then
    return query
    select case when exists(select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'get_user_business_id') then '✅' else '❌' end,
      'Función get_user_business_id()', 'FASE 2', 'CRITICAL', 'Aplicar: 0205_update_rls_policies.sql'
    where not exists(select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'get_user_business_id');
  end if;
  
  -- Integridad
  if exists(select 1 from pg_tables where tablename = 'businesses') 
     and exists(select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'business_id') then
    
    return query
    select case when count(*) = 0 then '✅' else '❌' end, 'Perfiles sin business_id', 'FASE 2', 
      case when count(*) = 0 then 'INFO' else 'CRITICAL' end,
      case when count(*) = 0 then 'OK' else format('Hay %s perfiles sin negocio. Aplicar: 0202', count(*)) end
    from profiles where business_id is null having count(*) > 0;
    
    return query
    select case when count(*) = 0 then '✅' else '❌' end, 'Servicios sin business_id', 'FASE 2',
      case when count(*) = 0 then 'INFO' else 'CRITICAL' end,
      case when count(*) = 0 then 'OK' else format('Hay %s servicios sin negocio. Aplicar: 0202', count(*)) end
    from services where business_id is null having count(*) > 0;
    
    return query
    select case when count(*) = 0 then '✅' else '❌' end, 'Citas sin business_id', 'FASE 2',
      case when count(*) = 0 then 'INFO' else 'CRITICAL' end,
      case when count(*) = 0 then 'OK' else format('Hay %s citas sin negocio. Aplicar: 0202', count(*)) end
    from appointments where business_id is null having count(*) > 0;
  end if;
end $$;

select * from validate_migration_state()
order by case severity when 'CRITICAL' then 1 when 'HIGH' then 2 when 'MEDIUM' then 3 else 4 end, object_name;

drop function validate_migration_state();
