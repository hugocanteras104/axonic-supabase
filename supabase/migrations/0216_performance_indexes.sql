-- ===============================================
-- Migration: 0216_performance_indexes.sql
-- Purpose: Índices adicionales para mejorar rendimiento
-- Dependencies: 0200-0213
-- ===============================================

begin;

-- PROFILES: Búsqueda por email
create index if not exists idx_profiles_email_lower 
  on public.profiles(lower(email)) 
  where email is not null;

-- PROFILES: Búsqueda por nombre
create index if not exists idx_profiles_name_trgm 
  on public.profiles using gin (name gin_trgm_ops)
  where name is not null;

-- APPOINTMENTS: Índice compuesto para disponibilidad
create index if not exists idx_appointments_availability 
  on public.appointments(business_id, service_id, status, start_time, end_time)
  where status = 'confirmed';

-- INVENTORY: Productos con stock bajo
create index if not exists idx_inventory_low_stock 
  on public.inventory(business_id, reorder_threshold)
  where quantity <= reorder_threshold;

-- WAITLISTS: Lista de espera activa
create index if not exists idx_waitlists_active_lookup 
  on public.waitlists(business_id, service_id, desired_date, created_at)
  where status = 'active';

-- KNOWLEDGE_BASE: Búsqueda por categoría + popularidad
create index if not exists idx_kb_category_popular 
  on public.knowledge_base(business_id, category, view_count desc)
  where view_count > 0;

-- AUDIT_LOGS: Búsqueda de acciones por tipo
create index if not exists idx_audit_action_time 
  on public.audit_logs(business_id, action, timestamp desc);

commit;
