+📘 Guía de Migraciones - Axonic Assistant
+🎯 Reglas de Oro
+
+SIEMPRE aplicar en orden numérico
+NUNCA saltar una migración
+SIEMPRE hacer backup antes de aplicar en producción
+Ejecutar validate.sql después de cada fase
+
+📋 Orden de Aplicación Completo
+Fase 1: Fundamentos (0001-0007)
+Base del sistema. Sin estas migraciones NADA funciona.
+0001_setup_extensions_and_enums.sql
+↓ Extensiones PostgreSQL (pgcrypto, pg_trgm, unaccent, btree_gist)
+0002_create_core_tables.sql
+↓ Tablas: profiles, services, appointments, inventory, knowledge_base, etc.
+0003_add_indexes_and_views.sql
+↓ Índices de rendimiento y vistas de métricas
+0004_functions_triggers.sql
+↓ set_updated_at(), triggers automáticos
+0005_feature_kb_search.sql
+↓ Búsqueda inteligente en knowledge base
+0006_policies_rls_grants.sql
+↓ Row Level Security (RLS)
+0007_grant_metrics_views.sql
+↓ Permisos para vistas de métricas
+Verificación Fase 1:
+sql-- Ejecutar validate.sql
+-- Debe mostrar ✅ en extensiones, tablas core y funciones básicas
+
+Fase 1.5: Mejoras y Complementos (0099-0107)
+0099_seed_dev.sql
+↓ Datos de prueba (SOLO desarrollo) - OPCIONAL
+
+0100_fix_availability_rpcs.sql
+↓ Corrige funciones get_available_slots() con security definer
+
+0101_waitlist_index_and_comments.sql
+↓ Índice para waitlists activas
+
+0102_more_comments.sql
+↓ Documentación de tablas
+
+0103_add_validations.sql
+↓ Validaciones: formato email, teléfono, duración citas
+
+0104_dashboard_stats.sql
+↓ Funciones: get_today_dashboard(), get_week_summary()
+
+0105_maintenance_functions.sql
+↓ cleanup_old_notifications(), find_unused_resources()
+
+0106_profile_personal_details.sql
+↓ Tabla: cumpleaños, condiciones de piel, hijos
+
+0107_profile_staff_notes.sql
+↓ Tabla: notas internas del staff sobre clientes
+Verificación Fase 1.5:
+sqlSELECT 
+  'Funciones dashboard' as check_type,
+  exists(select 1 from pg_proc where proname = 'get_today_dashboard') as ok
+UNION ALL
+SELECT 
+  'Tabla profile_personal_details',
+  exists(select 1 from pg_tables where tablename = 'profile_personal_details')
+UNION ALL
+SELECT 
+  'Tabla profile_staff_notes',
+  exists(select 1 from pg_tables where tablename = 'profile_staff_notes');
+
+Fase 2: Multitenancy (0200-0218) ⚠️ CRÍTICA
+Esta fase modifica TODAS las tablas existentes. No se puede revertir fácilmente.
+0200_create_businesses_table.sql
+↓ Crea tabla businesses + negocio por defecto
+
+0201_add_business_id_columns.sql
+↓ Añade business_id (nullable) a TODAS las tablas
+
+0202_migrate_data_to_default_business.sql
+↓ Migra datos existentes al negocio por defecto (CRÍTICA)
+
+0203_make_business_id_required.sql
+↓ business_id pasa a NOT NULL
+
+0204_add_foreign_key_constraints.sql
+↓ Foreign keys compuestas (business_id, id)
+
+0205_update_rls_policies.sql
+↓ Crea get_user_business_id() y RLS básico
+
+0206_update_rls_deep.sql
+↓ RLS completo para todas las tablas
+
+0207_update_functions_multitenancy.sql
+↓ Actualiza funciones: get_available_slots(), search_knowledge_base(), etc.
+
+0208_business_settings.sql
+↓ Tabla business_settings + función is_within_business_hours()
+
+0209_add_validations_audit.sql
+↓ Validaciones de negocio + auditoría de cancelaciones
+
+0210_cleanup_footprints.sql
+↓ Limpieza automática con pg_cron
+
+0211_update_views_multitenancy.sql
+↓ Actualiza vistas materializadas con business_id
+
+0213_validate_business_hours.sql
+↓ Trigger de validación de horarios
+
+0214_flexible_business_hours.sql
+↓ Validación flexible (solo citas nuevas)
+
+0215_payment_tracking.sql
+↓ Sistema de pagos y depósitos
+
+0216_performance_indexes.sql
+↓ Índices adicionales de optimización
+
+0217_safe_cleanup.sql
+↓ Limpieza con respaldo automático
+
+0218_tetris_optimizer.sql
+↓ Optimización inteligente de agenda
+Verificación Fase 2:
+sql-- Ejecutar validate.sql
+-- Debe mostrar:
+-- ✅ Tabla businesses
+-- ✅ Columna business_id en todas las tablas
+-- ✅ Función get_user_business_id()
+-- ✅ 0 registros sin business_id
+
+SELECT 
+  (SELECT count(*) FROM businesses) as negocios,
+  (SELECT count(*) FROM profiles WHERE business_id IS NULL) as perfiles_sin_negocio,
+  (SELECT count(*) FROM appointments WHERE business_id IS NULL) as citas_sin_negocio;
+-- Resultado esperado: 1 negocio, 0 sin business_id
+
+Fase 3: Funcionalidades Avanzadas (0219-0226)
+0219_soft_deletes.sql
+↓ Columna deleted_at + funciones soft_delete() y restore_deleted()
+
+0220_google_calendar_sync.sql
+↓ Tabla calendar_events para sincronización con Google Calendar
+
+0221_notification_templates.sql
+↓ Plantillas personalizables de notificaciones
+
+0222_fix_rls_security_and_no_shows.sql
+↓ Fix vulnerabilidad RLS + sistema de no-shows
+
+0223_update_notification_templates.sql
+↓ Plantillas con política de cancelación variable
+
+0224_security_hardening.sql
+↓ Auditoría de seguridad completa
+
+0225_add_table_comments.sql
+↓ Documentación de tablas faltantes
+
+0226_auto_notification_templates.sql
+↓ Trigger para crear plantillas automáticamente
+Verificación Fase 3:
+sql-- Ejecutar validate.sql (debe estar todo ✅)
+
+SELECT 
+  'Soft deletes' as feature,
+  exists(select 1 from information_schema.columns 
+         where table_name = 'appointments' and column_name = 'deleted_at') as habilitado
+UNION ALL
+SELECT 'No-shows',
+  exists(select 1 from information_schema.columns 
+         where table_name = 'appointments' and column_name = 'no_show')
+UNION ALL
+SELECT 'Plantillas notificaciones',
+  exists(select 1 from pg_tables where tablename = 'notification_templates')
+UNION ALL
+SELECT 'Google Calendar sync',
+  exists(select 1 from pg_tables where tablename = 'calendar_events');
+
+🔗 Mapa de Dependencias Críticas
+0208 (business_settings)
+│   Crea: is_within_business_hours()
+├─→ 0209 (validations)
+├─→ 0213 (validate hours)
+└─→ 0214 (flexible hours)
+
+0004 (functions_triggers)
+│   Crea: set_updated_at()
+└─→ 0218 (tetris optimizer)
+
+0200-0205 (multitenancy base)
+├─→ 0206 (RLS deep)
+├─→ 0207 (functions)
+├─→ 0211 (views)
+└─→ 0216-0226 (funcionalidades)
+
+⚠️ Migraciones que NO Existen
+Estas numeraciones están ausentes intencionalmente:
+
+0008-0098: Reservadas para futuro
+0212: Eliminada o fusionada
+
+
+🧪 Testing Antes de Aplicar
+bash# 1. Hacer backup
+pg_dump -h localhost -U postgres -d mi_base > backup_$(date +%Y%m%d_%H%M%S).sql
+
+# 2. Verificar dependencias
+# Ejecutar validate.sql en SQL Editor
+
+# 3. Aplicar migración
+# Copiar/pegar en SQL Editor → Run
+
+# 4. Verificar que funcionó
+# Ejecutar validate.sql de nuevo
+
+📊 Checklist de Producción
+
+ Backup completo realizado
+ validate.sql ejecutado sin errores CRITICAL
+ Migraciones probadas en desarrollo
+ Ventana de mantenimiento programada (30-60 min)
+ Plan de rollback documentado
+ Equipo notificado
+
+
+🚨 Plan de Rollback (Solo emergencias)
+sql-- SOLO SI ALGO SALE MAL en Fase 2
+-- Restaurar desde backup:
+psql -h localhost -U postgres -d mi_base < backup_YYYYMMDD_HHMMSS.sql
+
+📞 Warnings Conocidos del Linter
+Security Definer Views (7 warnings) - Ignorables
+Las siguientes vistas generan falsos positivos:
+
+owner_dashboard_metrics
+inventory_low_stock
+client_reliability_score
+metrics_daily
+knowledge_popular_questions
+tetris_optimization_stats
+metrics_top_services_global
+
+Estado: Las vistas NO usan SECURITY DEFINER, solo security_barrier=true
+Riesgo: Ninguno
+Acción: Ignorar o silenciar con migración 0227 (opcional)
+RLS Disabled en kb_views_footprint - Intencionado
+Tabla: kb_views_footprint
+Razón: Tabla interna de tracking, solo accesible por funciones del sistema
+Acción: Ignorar
+
+🎯 Resumen por Fase
+FaseMigracionesTiempoRiesgoReversible10001-000715 minBajoSí1.50100-010710 minBajoSí20200-021845 minAltoNo30219-022620 minMedioParcial
+Total: ~90 minutos
 
EOF
)
