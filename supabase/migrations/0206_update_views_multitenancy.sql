-- ===============================================
-- Migration: 0206_update_views_multitenancy.sql
-- Purpose: Actualizar vistas materializadas y normales con business_id
-- Dependencies: 0200_add_multitenancy.sql
-- ===============================================

begin;

drop materialized view if exists public.metrics_historical cascade;

create materialized view public.metrics_historical as
select
    a.business_id,
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
where a.business_id = s.business_id
  and a.business_id is not null
group by a.business_id, period_day, period_week, period_month, a.service_id, s.name;

create index if not exists idx_metrics_hist_business 
  on public.metrics_historical(business_id);
create index if not exists idx_metrics_hist_day 
  on public.metrics_historical(business_id, period_day);
create index if not exists idx_metrics_hist_week 
  on public.metrics_historical(business_id, period_week);
create index if not exists idx_metrics_hist_month 
  on public.metrics_historical(business_id, period_month);
create index if not exists idx_metrics_hist_service 
  on public.metrics_historical(business_id, service_id);

create unique index if not exists uq_metrics_historical
on public.metrics_historical (
    business_id,
    period_day, 
    period_week, 
    period_month, 
    service_id, 
    service_name
);

raise notice 'Vista materializada metrics_historical actualizada';

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
          and date_trunc('day', a2.start_time) = date_trunc('day', a.start_time)
        group by s2.id, s2.name
        order by count(*) desc
        limit 1
    ) as top_service
from public.appointments a
join public.services s on s.id = a.service_id and s.business_id = a.business_id
where a.business_id is not null
group by a.business_id, day
order by day desc;

raise notice 'Vista owner_dashboard_metrics actualizada';

create or replace view public.metrics_daily as
with daily_stats as (
    select
        a.business_id,
        date_trunc('day', a.start_time)::date as day,
        count(*) filter (where a.status = 'confirmed') as confirmed_today,
        count(*) filter (where a.status = 'pending') as pending_today,
        count(*) filter (where a.status = 'cancelled') as cancelled_today,
        sum(s.base_price) filter (where a.status = 'confirmed') as revenue_today
    from public.appointments a
    join public.services s on s.id = a.service_id and s.business_id = a.business_id
    where a.business_id is not null
    group by a.business_id, date_trunc('day', a.start_time)::date
),
top_service_per_day as (
    select distinct on (a.business_id, date_trunc('day', a.start_time)::date)
        a.business_id,
        date_trunc('day', a.start_time)::date as day,
        s.name as top_service_today,
        count(*) as top_service_count
    from public.appointments a
    join public.services s on s.id = a.service_id and s.business_id = a.business_id
    where a.status = 'confirmed'
      and a.business_id is not null
    group by a.business_id, date_trunc('day', a.start_time)::date, s.id, s.name
    order by a.business_id, date_trunc('day', a.start_time)::date, count(*) desc
)
select
    ds.business_id,
    ds.day, 
    ds.confirmed_today, 
    ds.pending_today, 
    ds.cancelled_today, 
    ds.revenue_today,
    coalesce(ts.top_service_today, '') as top_service_today,
    coalesce(ts.top_service_count, 0) as top_service_count
from daily_stats ds
left join top_service_per_day ts 
  on ts.business_id = ds.business_id 
  and ts.day = ds.day
order by ds.business_id, ds.day desc;

raise notice 'Vista metrics_daily actualizada';

create or replace view public.metrics_top_services_global as
select
    s.business_id,
    s.id as service_id,
    s.name as service_name,
    count(a.id) as total_appointments,
    count(a.id) filter (where a.status = 'confirmed') as confirmed_appointments,
    sum(s.base_price) filter (where a.status = 'confirmed') as total_revenue,
    avg(s.base_price) filter (where a.status = 'confirmed') as avg_revenue,
    min(a.start_time) as first_appointment,
    max(a.start_time) as last_appointment
from public.services s
left join public.appointments a on a.service_id = s.id and a.business_id = s.business_id
where s.business_id is not null
group by s.business_id, s.id, s.name
order by s.business_id, confirmed_appointments desc;

raise notice 'Vista metrics_top_services_global actualizada';

create or replace view public.inventory_low_stock as
select
    business_id,
    id, 
    sku, 
    name, 
    quantity, 
    reorder_threshold, 
    price,
    (reorder_threshold - quantity) as units_needed
from public.inventory
where quantity <= reorder_threshold
order by business_id, (reorder_threshold - quantity) desc;

raise notice 'Vista inventory_low_stock actualizada';

create or replace view public.knowledge_popular_questions as
select
    business_id,
    id, 
    category, 
    question, 
    view_count, 
    created_at
from public.knowledge_base
where view_count > 0
order by business_id, view_count desc, created_at desc;

raise notice 'Vista knowledge_popular_questions actualizada';

refresh materialized view public.metrics_historical;

raise notice 'Vista materializada metrics_historical refrescada';

commit;

raise notice '========================================';
raise notice 'Migración 0206_update_views_multitenancy completada';
raise notice 'Todas las vistas actualizadas con business_id';
raise notice '========================================';
