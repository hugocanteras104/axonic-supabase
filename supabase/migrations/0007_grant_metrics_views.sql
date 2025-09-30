-- Grant authenticated users read-only access to owner metrics views
revoke all on table public.owner_dashboard_metrics from public, anon;
grant select on table public.owner_dashboard_metrics to authenticated;

revoke all on table public.metrics_historical from public, anon;
grant select on table public.metrics_historical to authenticated;

revoke all on table public.metrics_daily from public, anon;
grant select on table public.metrics_daily to authenticated;

revoke all on table public.metrics_top_services_global from public, anon;
grant select on table public.metrics_top_services_global to authenticated;

revoke all on table public.inventory_low_stock from public, anon;
grant select on table public.inventory_low_stock to authenticated;
