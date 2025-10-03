-- ===============================================
-- Migration: 0210_cleanup_footprints.sql
-- Purpose: Limpieza automática de datos antiguos
-- Dependencies: 0005_feature_kb_search.sql, 0200_add_multitenancy.sql
-- ===============================================

begin;

create or replace function public.cleanup_old_footprints()
returns table(deleted_count bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count bigint;
begin
  delete from public.kb_views_footprint 
  where last_view < now() - interval '2 years';
  
  get diagnostics v_count = row_count;
  
  
  return query select v_count;
end $$;

comment on function public.cleanup_old_footprints is
  'Borra registros de visualizaciones de KB más antiguos de 2 años. Retorna cantidad de registros eliminados.';


create extension if not exists pg_cron;


do $$
begin
  perform cron.unschedule('cleanup-footprints');
exception
  when others then
    raise notice 'No había job previo, continuando...';
end $$;

select cron.schedule(
  'cleanup-footprints',
  '0 2 1 * *',
  'select public.cleanup_old_footprints()'
);


create or replace function public.check_scheduled_jobs()
returns table(
  jobid bigint,
  schedule text,
  command text,
  nodename text,
  nodeport int,
  database text,
  username text,
  active boolean
)
language sql
stable
as $$
  select 
    jobid,
    schedule,
    command,
    nodename,
    nodeport,
    database,
    username,
    active
  from cron.job
  order by jobid;
$$;

comment on function public.check_scheduled_jobs is
  'Lista todos los jobs programados con pg_cron';


create or replace function public.check_job_history(p_limit int default 20)
returns table(
  runid bigint,
  jobid bigint,
  job_name text,
  start_time timestamptz,
  end_time timestamptz,
  status text,
  return_message text
)
language sql
stable
as $$
  select 
    jrd.runid,
    jrd.jobid,
    j.jobname as job_name,
    jrd.start_time,
    jrd.end_time,
    jrd.status,
    jrd.return_message
  from cron.job_run_details jrd
  join cron.job j on j.jobid = jrd.jobid
  order by jrd.start_time desc
  limit p_limit;
$$;

comment on function public.check_job_history is
  'Muestra el historial de ejecuciones de jobs programados';


commit;

