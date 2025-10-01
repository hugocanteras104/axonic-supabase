-- ===============================================
-- Migration: 0211_update_views_multitenancy.sql
-- Purpose: Actualizar vistas materializadas y normales con business_id
-- Dependencies: 0207_update_functions_multitenancy.sql
-- ===============================================

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'appointments' and column_name = 'business_id'
  ) then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: columna business_id\nAplicar primero: 0200-0207';
  end if;
  
  raise notice '✅ Dependencias verificadas';
end $$;

begin;

-- Eliminar vistas existentes
drop view if exists public.owner_dashboard_metrics cascade;
drop view if exists public.metrics_daily cascade;
drop view if exists public.metrics_top_services_global cascade;
drop view if exists public.inventory_low_stock cascade;
drop view if exists public.knowledge_popular_questions cascade;
drop materialized view if exists public.metrics_historical cascade;

-- Crear vista materializada
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

-- Vista dashboard
create view public.owner_dashboard_metrics as
with daily_appointments as (
    select
        a.business_id,
        date_trunc('day', a.start_time) as day,
        count(*) filter (where a.status = 'confirmed') as confirmed_appointments,
        sum(s.base_price) filter (where a.status = 'confirmed') as estimated_revenue
    from public.appointments a
    join public.services s on s.id = a.service_id and s.business_id = a.business_id
    where a.business_id is not null
    group by a.business_id, day
),
top_services as (
    select distinct on (a.business_id, date_trunc('day', a.start_time))
        a.business_id,
        date_trunc('day', a.start_time) as day,
        s.name as top_service
    from public.appointments a
    join public.services s on s.id = a.service_id and s.business_id = a.business_id
    where a.status = 'confirmed'
      and a.business_id is not null
    group by a.business_id, day, s.id, s.name
    order by a.business_id, day, count(*) desc
)
select
    da.business_id,
    da.day,
    da.confirmed_appointments,
    da.estimated_revenue,
    coalesce(ts.top_service, '') as top_service
from daily_appointments da
left join top_services ts 
  on ts.business_id = da.business_id 
  and ts.day = da.day
order by da.business_id, da.day desc;

-- Vista diaria
create view public.metrics_daily as
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

-- Vista top servicios
create view public.metrics_top_services_global as
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

-- Vista inventario bajo
create view public.inventory_low_stock as
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

-- Vista preguntas populares
create view public.knowledge_popular_questions as
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

-- Refrescar vista materializada
refresh materialized view public.metrics_historical;

commit;
