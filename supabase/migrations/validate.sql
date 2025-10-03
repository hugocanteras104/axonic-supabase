-- ==================================================
-- validate.sql - Verificador de Estado de Migraciones
-- ==================================================

create or replace function validate_migration_state()
returns table(
  status text,
  object_name text,
  required_by text,
  severity text,
  suggestion text
) language plpgsql as $$
begin
  -- 1. Verificar Extensiones (Fase 1)
  
  return query
  select 
    case when exists(select 1 from pg_extension where extname = 'pgcrypto') 
         then '✅' else '❌' end as status,
    'Extensión pgcrypto' as object_name,
    '0002 (core tables)' as required_by,
    'CRITICAL' as severity,
    'Aplicar: 0001_setup_extensions_and_enums.sql' as suggestion
  where not exists(select 1 from pg_extension where extname = 'pgcrypto');
  
  return query
  select 
    case when exists(select 1 from pg_extension where extname = 'pg_trgm') 
         then '✅' else '❌' end,
    'Extensión pg_trgm',
    '0005 (KB search)',
    'CRITICAL',
    'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'pg_trgm');
  
  return query
  select 
    case when exists(select 1 from pg_extension where extname = 'unaccent') 
         then '✅' else '❌' end,
    'Extensión unaccent',
    '0005 (KB search)',
    'CRITICAL',
    'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'unaccent');
  
  return query
  select 
    case when exists(select 1 from pg_extension where extname = 'btree_gist') 
         then '✅' else '❌' end,
    'Extensión btree_gist',
    '0003 (indexes)',
    'CRITICAL',
    'Aplicar: 0001_setup_extensions_and_enums.sql'
  where not exists(select 1 from pg_extension where extname = 'btree_gist');
  
  -- 2. Verificar Tablas Principales
  
  return query
  select 
    case when exists(select 1 from pg_tables where tablename = 'profiles') 
         then '✅' else '❌' end,
    'Tabla profiles',
    'Todas las migraciones',
    'CRITICAL',
    'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'profiles');
  
  return query
  select 
    case when exists(select 1 from pg_tables where tablename = 'services') 
         then '✅' else '❌' end,
    'Tabla services',
    'Todas las migraciones',
    'CRITICAL',
    'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'services');
  
  return query
  select 
    case when exists(select 1 from pg_tables where tablename = 'appointments') 
         then '✅' else '❌' end,
    'Tabla appointments',
    'Todas las migraciones',
    'CRITICAL',
    'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'appointments');
  
  return query
  select 
    case when exists(select 1 from pg_tables where tablename = 'knowledge_base') 
         then '✅' else '❌' end,
    'Tabla knowledge_base',
    '0005, 0006, 0007',
    'CRITICAL',
    'Aplicar: 0002_create_core_tables.sql'
  where not exists(select 1 from pg_tables where tablename = 'knowledge_base');
  
  -- 3. Verificar Multitenancy (Fase 2)
  
  return query
  select 
    case when exists(select 1 from pg_tables where tablename = 'businesses') 
         then '✅' else '⚠️' end,
    'Tabla businesses',
    '0201-0216 (Todo multitenancy)',
    case when exists(select 1 from pg_tables where tablename = 'businesses') 
         then 'INFO' else 'HIGH' end,
    case when exists(select 1 from pg_tables where tablename = 'businesses')
         then 'Multitenancy habilitado'
         else 'Aplicar: 0200_create_businesses_table.sql si necesitas multitenancy'
    end;
  
  if exists(select 1 from pg_tables where tablename = 'businesses') then
    
    return query
    select 
      case when exists(
        select 1 from information_schema.columns
        where table_name = 'profiles' and column_name = 'business_id'
      ) then '✅' else '❌' end,
      'Columna business_id en profiles',
      '0206+ (RLS, funciones)',
      'CRITICAL',
      'Aplicar: 0201_add_business_id_columns.sql'
    where not exists(
      select 1 from information_schema.columns
      where table_name = 'profiles' and column_name = 'business_id'
    );
    
    return query
    select 
      case when exists(
        select 1 from information_schema.columns
        where table_name = 'appointments' and column_name = 'business_id'
      ) then '✅' else '❌' end,
      'Columna business_id en appointments',
      '0206+ (RLS, funciones)',
      'CRITICAL',
      'Aplicar: 0201_add_business_id_columns.sql'
    where not exists(
      select 1 from information_schema.columns
      where table_name = 'appointments' and column_name = 'business_id'
    );
    
  end if;
  
  -- 4. Verificar Funciones Críticas
  
  return query
  select 
    case when exists(
      select 1 from pg_proc p
      join pg_namespace n on p.pronamespace = n.oid
      where n.nspname = 'public' and p.proname = 'set_updated_at'
    ) then '✅' else '❌' end,
    'Función set_updated_at()',
    '0215 (tetris)',
    'CRITICAL',
    'Aplicar: 0004_functions_triggers.sql'
  where not exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'set_updated_at'
  );
  
  return query
  select 
    case when exists(
      select 1 from pg_proc p
      join pg_namespace n on p.pronamespace = n.oid
      where n.nspname = 'public' and p.proname = 'norm_txt'
    ) then '✅' else '❌' end,
    'Función norm_txt()',
    '0005 (KB search)',
    'CRITICAL',
    'Aplicar: 0005_feature_kb_search.sql'
  where not exists(
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'norm_txt'
  );
  
  if exists(select 1 from pg_tables where tablename = 'businesses') then
    
    return query
    select 
      case when exists(
        select 1 from pg_proc p
        join pg_namespace n on p.pronamespace = n.oid
        where n.nspname = 'public' and p.proname = 'get_user_business_id'
      ) then '✅' else '❌' end,
      'Función get_user_business_id()',
      '0206+ (RLS)',
      'CRITICAL',
      'Aplicar: 0205_update_rls_policies.sql'
    where not exists(
      select 1 from pg_proc p
      join pg_namespace n on p.pronamespace = n.oid
      where n.nspname = 'public' and p.proname = 'get_user_business_id'
    );
    
    return query
    select 
      case when exists(
        select 1 from pg_proc p
        join pg_namespace n on p.pronamespace = n.oid
        where n.nspname = 'public' and p.proname = 'is_within_business_hours'
      ) then '✅' else '⚠️' end,
      'Función is_within_business_hours()',
      '0213 (validate hours), 0211 (flexible hours)',
      case when exists(
        select 1 from pg_proc p
        join pg_namespace n on p.pronamespace = n.oid
        where n.nspname = 'public' and p.proname = 'is_within_business_hours'
      ) then 'INFO' else 'HIGH' end,
      case when exists(
        select 1 from pg_proc p
        join pg_namespace n on p.pronamespace = n.oid
        where n.nspname = 'public' and p.proname = 'is_within_business_hours'
      ) then 'OK'
      else 'Aplicar: 0208_business_settings.sql'
      end
    where not exists(
      select 1 from pg_proc p
      join pg_namespace n on p.pronamespace = n.oid
      where n.nspname = 'public' and p.proname = 'is_within_business_hours'
    );
    
  end if;
  
  -- 5. Verificar Consistencia de Datos
  
  if exists(select 1 from pg_tables where tablename = 'businesses') 
     and exists(
       select 1 from information_schema.columns
       where table_name = 'profiles' and column_name = 'business_id'
     ) then
    
    return query
    select 
      case when count(*) = 0 then '✅' else '❌' end,
      'Perfiles sin business_id',
      'Integridad de datos',
      case when count(*) = 0 then 'INFO' else 'CRITICAL' end,
      case when count(*) = 0 
           then 'OK'
           else format('Hay %s perfiles sin negocio. Aplicar: 0202_migrate_data_to_default_business.sql', count(*))
      end
    from profiles
    where business_id is null
    having count(*) > 0;
    
    return query
    select 
      case when count(*) = 0 then '✅' else '❌' end,
      'Servicios sin business_id',
      'Integridad de datos',
      case when count(*) = 0 then 'INFO' else 'CRITICAL' end,
      case when count(*) = 0 
           then 'OK'
           else format('Hay %s servicios sin negocio. Aplicar: 0202_migrate_data_to_default_business.sql', count(*))
      end
    from services
    where business_id is null
    having count(*) > 0;
    
    return query
    select 
      case when count(*) = 0 then '✅' else '❌' end,
      'Citas sin business_id',
      'Integridad de datos',
      case when count(*) = 0 then 'INFO' else 'CRITICAL' end,
      case when count(*) = 0 
           then 'OK'
           else format('Hay %s citas sin negocio. Aplicar: 0202_migrate_data_to_default_business.sql', count(*))
      end
    from appointments
    where business_id is null
    having count(*) > 0;
    
  end if;
  
  -- 6. Verificar Tablas Opcionales
  
  return query
  select 
    case when exists(select 1 from pg_tables where tablename = 'business_settings') 
         then '✅' else '⚠️' end,
    'Tabla business_settings',
    '0209 (validations), 0213 (validate hours)',
    case when exists(select 1 from pg_tables where tablename = 'business_settings')
         then 'INFO' else 'MEDIUM' end,
    case when exists(select 1 from pg_tables where tablename = 'business_settings')
         then 'Configuración de negocio habilitada'
         else 'Aplicar: 0208_business_settings.sql si necesitas validación de horarios'
    end;
  
  return query
  select 
    case when exists(
      select 1 from information_schema.columns
      where table_name = 'appointments' and column_name = 'deposit_required'
    ) then '✅' else '⚠️' end,
    'Columnas de depósito',
    '0212 (payment tracking)',
    case when exists(
      select 1 from information_schema.columns
      where table_name = 'appointments' and column_name = 'deposit_required'
    ) then 'INFO' else 'MEDIUM' end,
    case when exists(
      select 1 from information_schema.columns
      where table_name = 'appointments' and column_name = 'deposit_required'
    ) then 'Sistema de depósitos habilitado'
    else 'Aplicar: 0209_add_validations_audit.sql si necesitas tracking de pagos'
    end;
  
  -- 7. Mensaje Final
  
  return query
  select 
    '🎉' as status,
    'Estado del sistema' as object_name,
    'N/A' as required_by,
    'INFO' as severity,
    'Sin errores críticos. Sistema operativo.' as suggestion
  where not exists(
    select 1 from validate_migration_state() v 
    where v.severity = 'CRITICAL' and v.status = '❌'
  );
  
  return query
  select 
    '⚠️' as status,
    'Estado del sistema' as object_name,
    'N/A' as required_by,
    'WARNING' as severity,
    format('Hay %s errores críticos. Revisar arriba.', 
      (select count(*) from validate_migration_state() v 
       where v.severity = 'CRITICAL' and v.status = '❌')
    ) as suggestion
  where exists(
    select 1 from validate_migration_state() v 
    where v.severity = 'CRITICAL' and v.status = '❌'
  );
  
end $$;

select * from validate_migration_state()
order by 
  case severity
    when 'CRITICAL' then 1
    when 'HIGH' then 2
    when 'MEDIUM' then 3
    else 4
  end,
  object_name;

drop function if exists validate_migration_state();
