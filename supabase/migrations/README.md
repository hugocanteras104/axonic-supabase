# 📘 Guía de Migraciones - Axonic Assistant

## 🎯 Reglas de Oro

1. **SIEMPRE** aplicar en orden numérico
2. **NUNCA** saltar una migración
3. **SIEMPRE** hacer backup antes de aplicar en producción
4. Ejecutar `validate.sql` antes de aplicar cualquier migración nueva

## 📋 Orden de Aplicación

### Fase 1: Fundamentos (0001-0007)
Base del sistema. Sin estas migraciones NADA funciona.
0001_setup_extensions_and_enums.sql
↓ Instala herramientas PostgreSQL
0002_create_core_tables.sql
↓ Crea tablas principales
↓ Requiere: 0001
0003_add_indexes_and_views.sql
↓ Índices para velocidad
↓ Requiere: 0002
0004_functions_triggers.sql
↓ Funciones automáticas
↓ Requiere: 0002
0005_feature_kb_search.sql
↓ Búsqueda inteligente
↓ Requiere: 0001, 0002
0006_policies_rls_grants.sql
↓ Seguridad
↓ Requiere: 0002, 0004, 0005
0007_grant_metrics_views.sql
↓ Permisos métricas
↓ Requiere: 0003

### Fase 2: Multi-Negocio (0200-0205)
⚠️ CRÍTICO: Aplicar TODAS en orden. No saltar ninguna.
0200_create_businesses_table.sql
↓ Crea tabla businesses
↓ Requiere: 0001-0007
0201_add_business_id_columns.sql
↓ Agrega columnas business_id
↓ Requiere: 0200
0202_migrate_data_to_default_business.sql
↓ Migra datos existentes
↓ Requiere: 0201
0203_make_business_id_required.sql
↓ Hace business_id obligatorio
↓ Requiere: 0202
0204_add_foreign_key_constraints.sql
↓ Foreign keys compuestas
↓ Requiere: 0203
0205_update_rls_policies.sql
↓ RLS básico + función helper
↓ Requiere: 0204

### Fase 3: Multi-Negocio Avanzado (0206-0213)
0206_update_rls_deep.sql
↓ RLS completo para todas las tablas
↓ Requiere: 0205 (get_user_business_id)
0207_update_functions_multitenancy.sql
↓ Actualiza funciones (slots, KB, etc.)
↓ Requiere: 0205, 0206
0208_business_settings.sql
↓ Configuración por negocio (IMPORTANTE)
↓ Requiere: 0205
↓ Crea función: is_within_business_hours()
0209_add_validations_audit.sql
↓ Depósitos y auditoría
↓ Requiere: 0208
0210_cleanup_footprints.sql
↓ Limpieza automática
↓ Requiere: 0005
0211_update_views_multitenancy.sql
↓ Vistas materializadas
↓ Requiere: 0207
0212_update_seed_multitenancy.sql
↓ Datos de prueba (dev only)
↓ Requiere: 0211
0213_validate_business_hours.sql
↓ Validar horarios
↓ Requiere: 0208 (is_within_business_hours)

### Fase 4: Funcionalidades Avanzadas (0214-0219)
0214_flexible_business_hours.sql
↓ Horarios flexibles
↓ Requiere: 0208
0215_payment_tracking.sql
↓ Sistema de pagos
↓ Requiere: 0209
0216_performance_indexes.sql
↓ Optimización de velocidad
↓ Requiere: 0200-0213
0217_safe_cleanup.sql
↓ Limpieza con respaldo
↓ Requiere: 0210
0218_tetris_optimizer.sql
↓ Optimización inteligente de agenda
↓ Requiere: 0004, 0200-0213
0219_soft_deletes.sql
↓ Borrado lógico
↓ Requiere: 0200-0213

## 🔗 Mapa de Dependencias Críticas
┌─────────────────────────────────────┐
│  0208 (business_settings)           │
│  • Crea is_within_business_hours()  │
└──────────────┬──────────────────────┘
│
┌───────┴───────┬──────────────┐
↓               ↓              ↓
0209            0213           0211
(validations)   (validate hrs)  (flexible hrs)
│
↓
0212
(payments)

┌─────────────────────────────────────┐
│  0004 (functions_triggers)          │
│  • Crea set_updated_at()            │
└──────────────┬──────────────────────┘
│
↓
0215
(tetris optimizer)

┌─────────────────────────────────────┐
│  0200-0205 (multitenancy base)      │
└──────────────┬──────────────────────┘
│
┌───────┴───────┬──────────────┐
↓               ↓              ↓
0206            0207           0211
(RLS deep)    (functions)      (views)
│               │              │
└───────┬───────┴──────────────┘
↓
0212-0216
(funcionalidades)

## ⚠️ Errores Comunes y Soluciones

### Error 1: `function is_within_business_hours does not exist`
**Causa:** Aplicaste 0213 sin aplicar 0208  
**Solución:** 
```bash
psql -f supabase/migrations/0208_business_settings.sql
psql -f supabase/migrations/0213_validate_business_hours.sql
```

### Error 2: `function auth.get_user_business_id does not exist`
**Causa:** Saltaste 0205  
**Solución:** Aplica 0200-0205 en orden

### Error 3: `column business_id does not exist`
**Causa:** Saltaste fase 2 completa  
**Solución:** Aplica 0200-0205 en orden

### Error 4: `relation businesses does not exist`
**Causa:** No aplicaste 0200  
**Solución:** Aplica 0200 primero

### Error 5: `ERROR: Hay X perfiles sin business_id`
**Causa:** Saltaste 0202 (migración de datos)  
**Solución:** Aplica 0202

## 🧪 Testing Antes de Aplicar
```bash
# 1. Hacer backup
pg_dump -h localhost -U postgres -d mi_base > backup_$(date +%Y%m%d_%H%M%S).sql

# 2. Verificar dependencias
psql -h localhost -U postgres -d mi_base -f supabase/migrations/validate.sql

# 3. Si todo OK, aplicar migración
psql -h localhost -U postgres -d mi_base -f supabase/migrations/0XXX_nombre.sql

# 4. Verificar que funcionó
psql -h localhost -U postgres -d mi_base -c "SELECT version, applied_at FROM schema_version ORDER BY version DESC LIMIT 5;"
```

## 📊 Checklist de Producción
Antes de aplicar en producción:

- [ ] Backup completo realizado
- [ ] `validate.sql` ejecutado sin errores
- [ ] Migraciones probadas en ambiente de desarrollo
- [ ] Migraciones probadas en ambiente de staging
- [ ] Ventana de mantenimiento programada (30-60 min)
- [ ] Plan de rollback documentado
- [ ] Equipo notificado

## 🚨 Plan de Rollback
Si algo sale mal durante la fase 2 (multitenancy):
```sql
-- SOLO en caso de EMERGENCIA
begin;
  -- Eliminar constraints
  alter table profiles drop constraint if exists fk_appointments_profile_business;
  -- ... (eliminar todos los constraints nuevos)
  
  -- Eliminar columnas
  alter table profiles drop column if exists business_id;
  -- ... (eliminar de todas las tablas)
  
  -- Eliminar tabla
  drop table if exists businesses cascade;
  
  -- Eliminar función
  drop function if exists auth.get_user_business_id();
commit;

-- Luego restaurar desde backup
psql -h localhost -U postgres -d mi_base < backup_YYYYMMDD_HHMMSS.sql
```

## 📞 Soporte
Si encuentras problemas:

1. Revisa este README
2. Ejecuta `validate.sql`
3. Revisa los logs de PostgreSQL
4. Busca el error específico en la sección "Errores Comunes"

## 📚 Referencias

- Documentación PostgreSQL
- Supabase Migrations
- RLS en PostgreSQL
