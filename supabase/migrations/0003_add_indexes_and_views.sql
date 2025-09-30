-- 0003_indexes_constraints_views.sql
-- Índices, constraints y vistas de métricas

-- APPOINTMENTS - Índices de rendimiento
create index if not exists idx_appts_profile_id on public.appointments(profile_id);
create index if not exists idx_appts_service_id on public.appointments(service_id);
create index if not exists idx_appts_start_time on public.appointments(start_time);
create index if not exists idx_appts_status on public.appointments(status);
create index if not exists idx_appts_status_start on public.appointments(status, start_time);

-- Índice GiST para solapes de citas confirmadas (requiere btree_gist en 0001)
drop index if exists idx_appts_service_status_range; -- Eliminación del índice obsoleto
create index if not exists idx_appts_confirmed_range_gist
on public.appointments
using gist (
    service_id,
    tstzrange(start_time, end_time, '[)')
)
where status = 'confirmed';

-- WAITLISTS - Índices y Constraint Único
create index if not exists idx_waitlist_status on public.waitlists(status);
create index if not exists idx_waitlist_desired_date on public.waitlists(desired_date);
create index if not exists idx_waitlist_service_date on public.waitlists(service_id, desired_date);

do $$
begin
if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.waitlists'::regclass
    and conname = 'waitlist_unique_profile_service_date'
) then
    alter table public.waitlists
    add constraint waitlist_unique_profile_service_date
    unique (profile_id, service_id, desired_date);
end if;
end $$;

-- CROSS SELL RULES - Constraint Único
do $$
begin
if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.cross_sell_rules'::regclass
    and conname = 'cross_sell_unique_pair'
) then
    alter table public.cross_sell_rules
    add constraint cross_sell_unique_pair
    unique (trigger_service_id, recommended_service_id);
end if;
end $$;
create index if not exists idx_cross_sell_trigger on public.cross_sell_rules(trigger_service_id);

-- NOTIFICATIONS QUEUE & AUDIT LOGS
create index if not exists idx_nq_pending on public.notifications_queue(created_at) where processed_at is null;
create index if not exists idx_audit_profile on public.audit_logs(profile_id);
create index if not exists idx_audit_timestamp on public.audit_logs(timestamp desc);

-- CONSTRAINTS DE VALIDACIÓN GENERALES (Idempotentes)
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.services'::regclass and conname = 'services_price_non_negative') then alter table public.services add constraint services_price_non_negative check (base_price >= 0); end if; end $$;
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.services'::regclass and conname = 'services_duration_positive') then alter table public.services add constraint services_duration_positive check (duration_minutes > 0); end if; end $$;
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.inventory'::regclass and conname = 'inventory_price_non_negative') then alter table public.inventory add constraint inventory_price_non_negative check (price >= 0); end if; end $$;
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.inventory'::regclass and conname = 'inventory_reorder_non_negative') then alter table public.inventory add constraint inventory_reorder_non_negative check (reorder_threshold >= 0); end if; end $$;
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.profiles'::regclass and conname = 'profiles_phone_not_empty') then alter table public.profiles add constraint profiles_phone_not_empty check (trim(phone_number) <> ''); end if; end $$;

-- VISTAS DE MÉTRICAS BÁSICAS
create or replace view public.owner_dashboard_metrics as
select
    date_trunc('day', a.start_time) as day,
    count(*) filter (where a.status = 'confirmed') as confirmed_appointments,
    sum(s.base_price) filter (where a.status = 'confirmed') as estimated_revenue,
    (
        select s2.name
        from public.services s2
        join public.appointments a2 on a2.service_id = s2.id and a2.status = 'confirmed'
        group by s2.id, s2.name
        order by count(*) desc
        limit 1
    ) as top_service
from public.appointments a
join public.services s on s.id = a.service_id
group by 1
order by 1 desc;

-- Vistas de Agregación (Materializadas y Normales)
create materialized view if not exists public.metrics_historical as
select
    date_trunc('day', a.start_time) as period_day,
    date_trunc('week', a.start_time) as period_week,
    date_trunc('month', a.start_time) as period_month,
    a.service_id,
    s.name as service_name,
    count(*) filter (where a.status = 'confirmed') as confirmed_count,
    count(*) filter (where a.status = 'cancelled') as cancelled_count,
    count(*) filter (where a.status = 'pending') as pending_count,
    sum(s.base_price) filter (where a.status = 'confirmed') as confirmed_revenue,
    avg(s.base_price) filter (where a.status = 'confirmed') as avg_revenue
from public.appointments a
join public.services s on s.id = a.service_id
group by 1, 2, 3, 4, 5;

-- Índices para la vista materializada
create index if not exists idx_metrics_hist_day on public.metrics_historical(period_day);
create index if not exists idx_metrics_hist_week on public.metrics_historical(period_week);
create index if not exists idx_metrics_hist_month on public.metrics_historical(period_month);
create index if not exists idx_metrics_hist_service on public.metrics_historical(service_id);

-- Índice UNIQUE requerido para refresco CONCURRENTLY (si se usara externamente)
create unique index if not exists uq_metrics_historical
on public.metrics_historical (
    period_day, period_week, period_month, service_id, service_name
);

-- Vista Diaria
create or replace view public.metrics_daily as
with daily_stats as (
    select
        date_trunc('day', a.start_time)::date as day,
        count(*) filter (where a.status = 'confirmed') as confirmed_today,
        count(*) filter (where a.status = 'pending') as pending_today,
        count(*) filter (where a.status = 'cancelled') as cancelled_today,
        sum(s.base_price) filter (where a.status = 'confirmed') as revenue_today
    from public.appointments a
    join public.services s on s.id = a.service_id
    group by date_trunc('day', a.start_time)::date
),
top_service_per_day as (
    select distinct on (date_trunc('day', a.start_time)::date)
        date_trunc('day', a.start_time)::date as day,
        s.name as top_service_today,
        count(*) as top_service_count
    from public.appointments a
    join public.services s on s.id = a.service_id
    where a.status = 'confirmed'
    group by date_trunc('day', a.start_time)::date, s.id, s.name
    order by date_trunc('day', a.start_time)::date, count(*) desc
)
select
    ds.day, ds.confirmed_today, ds.pending_today, ds.cancelled_today, ds.revenue_today,
    coalesce(ts.top_service_today, '') as top_service_today,
    coalesce(ts.top_service_count, 0) as top_service_count
from daily_stats ds
left join top_service_per_day ts on ts.day = ds.day
order by ds.day desc;

-- Vista de Top Servicios Global
create or replace view public.metrics_top_services_global as
select
    s.id as service_id,
    s.name as service_name,
    count(*) as total_appointments,
    count(*) filter (where a.status = 'confirmed') as confirmed_appointments,
    sum(s.base_price) filter (where a.status = 'confirmed') as total_revenue,
    avg(s.base_price) filter (where a.status = 'confirmed') as avg_revenue,
    min(a.start_time) as first_appointment,
    max(a.start_time) as last_appointment
from public.services s
left join public.appointments a on a.service_id = s.id
group by s.id, s.name
order by confirmed_appointments desc;

-- Vista de inventario bajo stock
create or replace view public.inventory_low_stock as
select
    id, sku, name, quantity, reorder_threshold, price,
    (reorder_threshold - quantity) as units_needed
from public.inventory
where quantity <= reorder_threshold
order by (reorder_threshold - quantity) desc;

-- Índices del módulo de recursos
create index if not exists idx_resources_type on public.resources(type);
create index if not exists idx_resources_status on public.resources(status);
create index if not exists idx_resources_type_status on public.resources(type, status);
create index if not exists idx_srr_service on public.service_resource_requirements(service_id);
create index if not exists idx_srr_resource on public.service_resource_requirements(resource_id);
create index if not exists idx_ar_appointment on public.appointment_resources(appointment_id);
create index if not exists idx_ar_resource on public.appointment_resources(resource_id);
create index if not exists idx_rb_resource on public.resource_blocks(resource_id);
create index if not exists idx_rb_start on public.resource_blocks(start_time);
create index if not exists idx_rb_end on public.resource_blocks(end_time);
create index if not exists idx_rb_resource_range on public.resource_blocks(resource_id, start_time, end_time);

-- Constraints de unicidad para recursos
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.service_resource_requirements'::regclass and conname = 'srr_unique_service_resource') then alter table public.service_resource_requirements add constraint srr_unique_service_resource unique (service_id, resource_id); end if; end $$;
do $$ begin if not exists (select 1 from pg_constraint where conrelid = 'public.appointment_resources'::regclass and conname = 'ar_unique_appointment_resource') then alter table public.appointment_resources add constraint ar_unique_appointment_resource unique (appointment_id, resource_id); end if; end $$;

-- Fin 0003
