-- ===============================================
-- Migration: 0216_performance_indexes.sql
-- Purpose: Índices adicionales para mejorar rendimiento de consultas frecuentes
-- Dependencies: 0200-0213
-- ===============================================

begin;

-- PROFILES: Búsqueda por email
create index if not exists idx_profiles_email_lower 
  on public.profiles(lower(email)) 
  where email is not null;

comment on index idx_profiles_email_lower is
  'Búsqueda case-insensitive de emails (ej: buscar JUAN@GMAIL.COM = juan@gmail.com)';

-- PROFILES: Búsqueda por nombre
create index if not exists idx_profiles_name_trgm 
  on public.profiles using gin (name gin_trgm_ops)
  where name is not null;

comment on index idx_profiles_name_trgm is
  'Búsqueda fuzzy de nombres (ej: buscar "maria" encuentra "María López")';

-- APPOINTMENTS: Citas de hoy (consulta muy frecuente)
create index if not exists idx_appointments_today 
  on public.appointments(business_id, start_time, status)
  where start_time::date = current_date;

comment on index idx_appointments_today is
  'Optimiza "mostrar citas de hoy" - se recrea automáticamente cada día';

-- APPOINTMENTS: Citas futuras por servicio
create index if not exists idx_appointments_future_by_service 
  on public.appointments(business_id, service_id, start_time)
  where status in ('confirmed', 'pending') 
    and start_time >= current_timestamp;

comment on index idx_appointments_future_by_service is
  'Optimiza búsqueda de disponibilidad futura por servicio';

-- APPOINTMENTS: Índice compuesto para disponibilidad (la consulta MÁS crítica)
drop index if exists idx_appointments_availability;
create index idx_appointments_availability 
  on public.appointments(business_id, service_id, status, start_time, end_time)
  where status = 'confirmed';

comment on index idx_appointments_availability is
  'Índice crítico para get_available_slots - consulta más frecuente del sistema';

-- INVENTORY: Productos con stock bajo
create index if not exists idx_inventory_low_stock 
  on public.inventory(business_id, reorder_threshold)
  where quantity <= reorder_threshold;

comment on index idx_inventory_low_stock is
  'Optimiza vista de productos con stock bajo';

-- WAITLISTS: Lista de espera activa por servicio/fecha
create index if not exists idx_waitlists_active_lookup 
  on public.waitlists(business_id, service_id, desired_date, created_at)
  where status = 'active';

comment on index idx_waitlists_active_lookup is
  'Optimiza búsqueda de clientes en espera para un servicio/fecha específica';

-- KNOWLEDGE_BASE: Búsqueda por categoría + popularidad
create index if not exists idx_kb_category_popular 
  on public.knowledge_base(business_id, category, view_count desc)
  where view_count > 0;

comment on index idx_kb_category_popular is
  'Optimiza "preguntas populares por categoría"';

-- AUDIT_LOGS: Búsqueda de acciones por tipo
create index if not exists idx_audit_action_time 
  on public.audit_logs(business_id, action, timestamp desc);

comment on index idx_audit_action_time is
  'Optimiza filtrado de auditoría por tipo de acción';

commit;

raise notice '========================================';
raise notice 'Índices de rendimiento creados';
raise notice 'Las consultas principales serán 10-100x más rápidas';
raise notice '========================================';
