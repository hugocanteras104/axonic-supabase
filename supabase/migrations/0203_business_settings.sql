-- ===============================================
-- Migration: 0203_business_settings.sql
-- Purpose: Tabla de configuración personalizable por negocio
-- Dependencies: 0200_add_multitenancy.sql
-- ===============================================

begin;

create table if not exists public.business_settings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  setting_key text not null,
  setting_value jsonb not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_settings_unique_key unique (business_id, setting_key)
);

comment on table public.business_settings is 
  'Configuración personalizable por negocio: horarios, políticas, precios, etc.';
comment on column public.business_settings.setting_key is 
  'Clave de configuración: business_hours, cancellation_policy, pricing_rules, etc.';
comment on column public.business_settings.setting_value is 
  'Valor en formato JSON con la configuración específica';

create index if not exists idx_business_settings_business 
  on public.business_settings(business_id);
create index if not exists idx_business_settings_key 
  on public.business_settings(business_id, setting_key);

raise notice 'Tabla business_settings creada';

drop trigger if exists trg_upd_business_settings on public.business_settings;
create trigger trg_upd_business_settings 
  before update on public.business_settings 
  for each row 
  execute function public.set_updated_at();

raise notice 'Trigger para business_settings creado';

alter table public.business_settings enable row level security;

drop policy if exists bs_read on public.business_settings;
create policy bs_read on public.business_settings
  for select to authenticated
  using (business_id = auth.get_user_business_id());

drop policy if exists bs_owner_write on public.business_settings;
create policy bs_owner_write on public.business_settings
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = auth.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = auth.get_user_business_id()
  );

raise notice 'RLS configurado para business_settings';

create or replace function public.is_within_business_hours(
  p_business_id uuid,
  p_timestamp timestamptz
)
returns boolean
language plpgsql
stable
as $$
declare
  v_settings jsonb;
  v_day_index int;
  v_day_key text;
  v_day_config jsonb;
  v_hour time;
  v_timezone text;
  v_date date;
  v_holidays jsonb;
  v_days text[] := array['sunday','monday','tuesday','wednesday','thursday','friday','saturday'];
begin
  select setting_value into v_settings
  from public.business_settings
  where business_id = p_business_id
    and setting_key = 'business_hours';
  
  if v_settings is null then
    return extract(hour from p_timestamp) between 9 and 20
       and extract(dow from p_timestamp) between 1 and 6;
  end if;
  
  v_timezone := coalesce(v_settings->>'timezone', 'Europe/Madrid');
  v_holidays := v_settings->'holidays';
  v_date := (p_timestamp at time zone v_timezone)::date;
  
  if v_holidays is not null and v_holidays ? v_date::text then
    return false;
  end if;
  
  v_day_index := extract(dow from p_timestamp at time zone v_timezone)::int;
  if v_day_index < 0 or v_day_index >= array_length(v_days, 1) then
    return false;
  end if;

  v_day_key := v_days[v_day_index + 1];
  v_day_config := v_settings->'schedule'->v_day_key;
  
  if v_day_config is null then
    return false;
  end if;
  
  if coalesce((v_day_config->>'closed')::boolean, false) then
    return false;
  end if;
  
  v_hour := (p_timestamp at time zone v_timezone)::time;
  
  return v_hour >= (v_day_config->>'open')::time
     and v_hour < (v_day_config->>'close')::time;
end;
$$;

comment on function public.is_within_business_hours is
  'Valida si un timestamp está dentro del horario de negocio configurado. Si no hay configuración, usa horario por defecto (Lun-Sáb 9-20h).';

raise notice 'Función is_within_business_hours creada';

create or replace function public.get_business_setting(
  p_setting_key text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select setting_value
  from public.business_settings
  where business_id = auth.get_user_business_id()
    and setting_key = p_setting_key
  limit 1
$$;

comment on function public.get_business_setting is
  'Obtiene una configuración específica del negocio del usuario actual';

raise notice 'Función get_business_setting creada';

commit;

raise notice '========================================';
raise notice 'Migración 0203_business_settings completada';
raise notice '========================================';
