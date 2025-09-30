-- ===============================================
-- Migration: 0215_tetris_optimizer.sql
-- Purpose: Sistema inteligente de optimización de agenda tipo "Tetris"
-- Dependencies: 0004_functions_triggers.sql
-- ===============================================

begin;

-- Tipo de acción de optimización
do $$ begin
  create type public.tetris_action_type as enum ('adelantar_cita','rellenar_hueco','notificar_lista_espera');
exception when duplicate_object then null; end $$;

-- Tabla para tracking de optimizaciones
create table if not exists public.agenda_optimizations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  
  -- Evento que desencadenó la optimización
  trigger_appointment_id uuid references public.appointments(id) on delete set null,
  trigger_event text not null, -- 'cancellation', 'reschedule', 'manual'
  
  -- Hueco disponible
  available_slot_start timestamptz not null,
  available_slot_end timestamptz not null,
  service_id uuid not null references public.services(id) on delete cascade,
  
  -- Acciones tomadas
  actions_taken jsonb not null default '[]'::jsonb,
  
  -- Resultados
  candidates_found int not null default 0,
  notifications_sent int not null default 0,
  appointments_moved int not null default 0,
  
  -- Metadata
  processed boolean not null default false,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.agenda_optimizations is
  'Registro de optimizaciones automáticas de agenda (sistema Tetris). Tracking de huecos detectados y acciones tomadas.';

create index idx_optimizations_business on public.agenda_optimizations(business_id);
create index idx_optimizations_pending on public.agenda_optimizations(processed, created_at) 
  where processed = false;
create index idx_optimizations_slot on public.agenda_optimizations(available_slot_start, service_id);

-- RLS
alter table public.agenda_optimizations enable row level security;

drop policy if exists optimizations_owner_all on public.agenda_optimizations;
create policy optimizations_owner_all on public.agenda_optimizations
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = auth.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = auth.get_user_business_id()
  );

-- ===================================================
-- FUNCIÓN PRINCIPAL: Buscar oportunidades de Tetris
-- ===================================================
create or replace function public.find_tetris_opportunities(
  p_business_id uuid,
  p_available_start timestamptz,
  p_available_end timestamptz,
  p_service_id uuid,
  p_max_candidates int default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb := '[]'::jsonb;
  v_candidate record;
  v_service_duration interval;
begin
  -- Obtener duración del servicio
  select (duration_minutes || ' minutes')::interval into v_service_duration
  from public.services
  where id = p_service_id and business_id = p_business_id;
  
  if v_service_duration is null then
    raise exception 'Servicio no encontrado';
  end if;
  
  -- ESTRATEGIA 1: Buscar citas FUTURAS del mismo servicio que podrían adelantarse
  for v_candidate in
    select 
      a.id as appointment_id,
      a.profile_id,
      a.start_time as current_start,
      a.end_time as current_end,
      p.phone_number,
      p.name,
      extract(epoch from (a.start_time - p_available_start)) / 3600 as hours_can_advance,
      'adelantar_cita' as action_type,
      100 as priority -- Prioridad alta: ya tienen cita confirmada
    from public.appointments a
    join public.profiles p on p.id = a.profile_id
    where a.business_id = p_business_id
      and a.service_id = p_service_id
      and a.status = 'confirmed'
      and a.start_time > p_available_end -- Solo citas futuras DESPUÉS del hueco
      and a.start_time <= p_available_start + interval '7 days' -- Ventana de 7 días
      -- Verificar que la cita completa cabe en el hueco
      and (a.end_time - a.start_time) <= (p_available_end - p_available_start)
    order by a.start_time asc -- Más cercanas primero
    limit p_max_candidates / 2
  loop
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'type', v_candidate.action_type,
      'priority', v_candidate.priority,
      'appointment_id', v_candidate.appointment_id,
      'profile_id', v_candidate.profile_id,
      'profile_name', v_candidate.name,
      'profile_phone', v_candidate.phone_number,
      'current_slot', jsonb_build_object(
        'start', v_candidate.current_start,
        'end', v_candidate.current_end
      ),
      'proposed_slot', jsonb_build_object(
        'start', p_available_start,
        'end', p_available_start + v_service_duration
      ),
      'hours_can_advance', round(v_candidate.hours_can_advance::numeric, 1),
      'message_template', format(
        'Hola %s! Se liberó un hueco para tu servicio. ¿Te gustaría adelantar tu cita del %s a %s? Podrías tenerlo %s horas antes 🎉',
        v_candidate.name,
        to_char(v_candidate.current_start, 'DD/MM a las HH24:MI'),
        to_char(p_available_start, 'DD/MM a las HH24:MI'),
        round(v_candidate.hours_can_advance::numeric, 1)
      )
    ));
  end loop;
  
  -- ESTRATEGIA 2: Buscar en LISTA DE ESPERA para esta fecha/servicio
  for v_candidate in
    select 
      w.id as waitlist_id,
      w.profile_id,
      w.desired_date,
      p.phone_number,
      p.name,
      w.created_at,
      'notificar_lista_espera' as action_type,
      80 as priority -- Prioridad media-alta: están esperando
    from public.waitlists w
    join public.profiles p on p.id = w.profile_id
    where w.business_id = p_business_id
      and w.service_id = p_service_id
      and w.status = 'active'
      and w.desired_date = p_available_start::date -- Mismo día
    order by w.created_at asc -- Primero en entrar, primero en salir
    limit p_max_candidates / 2
  loop
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'type', v_candidate.action_type,
      'priority', v_candidate.priority,
      'waitlist_id', v_candidate.waitlist_id,
      'profile_id', v_candidate.profile_id,
      'profile_name', v_candidate.name,
      'profile_phone', v_candidate.phone_number,
      'proposed_slot', jsonb_build_object(
        'start', p_available_start,
        'end', p_available_start + v_service_duration
      ),
      'wait_time_days', extract(days from (now() - v_candidate.created_at)),
      'message_template', format(
        'Hola %s! Tenemos disponibilidad para el servicio que estabas esperando: %s. ¿Te interesa? 🎯',
        v_candidate.name,
        to_char(p_available_start, 'DD/MM a las HH24:MI')
      )
    ));
  end loop;
  
  return v_result;
end;
$$;

comment on function public.find_tetris_opportunities is
  'Encuentra oportunidades de optimización cuando se libera un hueco: citas que pueden adelantarse y personas en lista de espera.';

grant execute on function public.find_tetris_opportunities(uuid, timestamptz, timestamptz, uuid, int) to authenticated;

-- ===================================================
-- TRIGGER: Detectar cancelaciones y crear optimization job
-- ===================================================
create or replace function public.on_appointment_cancelled_tetris()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_opportunities jsonb;
  v_optimization_id uuid;
begin
  -- Solo procesar si es una cancelación nueva
  if new.status = 'cancelled' and old.status != 'cancelled' then
    
    -- Buscar oportunidades de optimización
    v_opportunities := public.find_tetris_opportunities(
      new.business_id,
      new.start_time,
      new.end_time,
      new.service_id,
      10 -- Máximo 10 candidatos
    );
    
    -- Crear registro de optimización
    insert into public.agenda_optimizations (
      business_id,
      trigger_appointment_id,
      trigger_event,
      available_slot_start,
      available_slot_end,
      service_id,
      actions_taken,
      candidates_found,
      processed
    ) values (
      new.business_id,
      new.id,
      'cancellation',
      new.start_time,
      new.end_time,
      new.service_id,
      v_opportunities,
      jsonb_array_length(v_opportunities),
      false -- Pendiente de procesar
    )
    returning id into v_optimization_id;
    
    -- Si hay candidatos, insertar en la cola de notificaciones
    if jsonb_array_length(v_opportunities) > 0 then
      insert into public.notifications_queue (
        business_id,
        event_type,
        payload
      ) values (
        new.business_id,
        'tetris_optimization_available',
        jsonb_build_object(
          'optimization_id', v_optimization_id,
          'cancelled_appointment_id', new.id,
          'slot_start', new.start_time,
          'slot_end', new.end_time,
          'service_id', new.service_id,
          'candidates_count', jsonb_array_length(v_opportunities),
          'opportunities', v_opportunities
        )
      );
      
      raise notice 'Optimización Tetris creada: % candidatos encontrados para hueco %-%', 
        jsonb_array_length(v_opportunities), new.start_time, new.end_time;
    else
      raise notice 'No se encontraron candidatos para optimización Tetris del hueco %-%',
        new.start_time, new.end_time;
    end if;
    
  end if;
  
  return new;
end;
$$;

comment on function public.on_appointment_cancelled_tetris is
  'Detecta cancelaciones y busca automáticamente oportunidades de optimización tipo Tetris (adelantar citas o notificar lista de espera).';

-- Reemplazar trigger anterior de cancelación
drop trigger if exists trg_on_appointment_cancelled on public.appointments;
create trigger trg_on_appointment_cancelled 
  after update on public.appointments
  for each row 
  execute function public.on_appointment_cancelled_tetris();

-- ===================================================
-- FUNCIÓN: Adelantar una cita automáticamente
-- ===================================================
create or replace function public.advance_appointment(
  p_appointment_id uuid,
  p_new_start timestamptz,
  p_reason text default 'Optimización automática de agenda'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment record;
  v_new_end timestamptz;
  v_duration interval;
  v_business_id uuid;
begin
  v_business_id := auth.get_user_business_id();
  
  -- Obtener cita actual
  select * into v_appointment
  from public.appointments
  where id = p_appointment_id
    and business_id = v_business_id
  for update;
  
  if not found then
    raise exception 'Cita no encontrada o sin acceso';
  end if;
  
  if v_appointment.status != 'confirmed' then
    raise exception 'Solo se pueden adelantar citas confirmadas';
  end if;
  
  -- Calcular nueva hora de fin
  v_duration := v_appointment.end_time - v_appointment.start_time;
  v_new_end := p_new_start + v_duration;
  
  -- Verificar que el nuevo slot está disponible
  if exists (
    select 1
    from public.appointments
    where business_id = v_business_id
      and service_id = v_appointment.service_id
      and id != p_appointment_id
      and status = 'confirmed'
      and tstzrange(start_time, end_time, '[)') && tstzrange(p_new_start, v_new_end, '[)')
  ) then
    raise exception 'El nuevo horario no está disponible';
  end if;
  
  -- Actualizar cita
  update public.appointments
  set 
    start_time = p_new_start,
    end_time = v_new_end,
    notes = coalesce(notes || E'\n\n', '') || format(
      '[%s] Cita adelantada desde %s por: %s',
      to_char(now(), 'YYYY-MM-DD HH24:MI'),
      to_char(v_appointment.start_time, 'YYYY-MM-DD HH24:MI'),
      p_reason
    ),
    updated_at = now()
  where id = p_appointment_id;
  
  -- Registrar en auditoría
  insert into public.audit_logs (
    business_id,
    profile_id,
    action,
    payload
  ) values (
    v_business_id,
    v_appointment.profile_id,
    'appointment_advanced',
    jsonb_build_object(
      'appointment_id', p_appointment_id,
      'old_start', v_appointment.start_time,
      'new_start', p_new_start,
      'reason', p_reason
    )
  );
  
  return jsonb_build_object(
    'success', true,
    'appointment_id', p_appointment_id,
    'old_start', v_appointment.start_time,
    'new_start', p_new_start,
    'hours_advanced', extract(epoch from (v_appointment.start_time - p_new_start)) / 3600
  );
end;
$$;

comment on function public.advance_appointment is
  'Adelanta una cita confirmada a un nuevo horario, verificando disponibilidad. Registra el cambio en auditoría.';

grant execute on function public.advance_appointment(uuid, timestamptz, text) to authenticated;

-- ===================================================
-- FUNCIÓN: Procesar optimization job y enviar notificaciones
-- ===================================================
create or replace function public.process_tetris_optimization(
  p_optimization_id uuid,
  p_send_notifications boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_optimization record;
  v_candidate jsonb;
  v_notifications_sent int := 0;
  v_result jsonb := '{"notifications": []}'::jsonb;
begin
  -- Obtener optimization job
  select * into v_optimization
  from public.agenda_optimizations
  where id = p_optimization_id
  for update;
  
  if not found then
    raise exception 'Optimization job no encontrado';
  end if;
  
  if v_optimization.processed then
    raise exception 'Optimization job ya procesado';
  end if;
  
  -- Procesar cada candidato
  for v_candidate in
    select value
    from jsonb_array_elements(v_optimization.actions_taken)
    order by (value->>'priority')::int desc
  loop
    if p_send_notifications then
      -- Insertar notificación individual
      insert into public.notifications_queue (
        business_id,
        event_type,
        payload
      ) values (
        v_optimization.business_id,
        case 
          when v_candidate->>'type' = 'adelantar_cita' then 'suggest_advance_appointment'
          when v_candidate->>'type' = 'notificar_lista_espera' then 'waitlist_slot_available'
          else 'tetris_notification'
        end,
        jsonb_build_object(
          'optimization_id', p_optimization_id,
          'profile_id', v_candidate->>'profile_id',
          'phone_number', v_candidate->>'profile_phone',
          'message', v_candidate->>'message_template',
          'candidate_data', v_candidate
        )
      );
      
      v_notifications_sent := v_notifications_sent + 1;
    end if;
    
    -- Agregar a resultado
    v_result := jsonb_set(
      v_result,
      '{notifications}',
      (v_result->'notifications') || jsonb_build_array(v_candidate)
    );
  end loop;
  
  -- Marcar como procesado
  update public.agenda_optimizations
  set 
    processed = true,
    processed_at = now(),
    notifications_sent = v_notifications_sent
  where id = p_optimization_id;
  
  return jsonb_set(v_result, '{notifications_sent}', to_jsonb(v_notifications_sent));
end;
$$;

comment on function public.process_tetris_optimization is
  'Procesa un job de optimización y envía notificaciones a los candidatos. Retorna resumen de acciones.';

grant execute on function public.process_tetris_optimization(uuid, boolean) to authenticated;

-- ===================================================
-- VISTA: Dashboard de optimizaciones
-- ===================================================
create or replace view public.tetris_optimization_stats as
select
  business_id,
  date_trunc('day', created_at)::date as day,
  count(*) as total_optimizations,
  sum(candidates_found) as total_candidates_found,
  sum(notifications_sent) as total_notifications_sent,
  sum(appointments_moved) as total_appointments_moved,
  count(*) filter (where processed) as processed_count,
  count(*) filter (where not processed) as pending_count,
  avg(candidates_found) as avg_candidates_per_optimization
from public.agenda_optimizations
group by business_id, day
order by day desc;

comment on view public.tetris_optimization_stats is
  'Estadísticas diarias del sistema de optimización Tetris: oportunidades encontradas, notificaciones enviadas, citas movidas.';

-- RLS para vista
alter table public.agenda_optimizations enable row level security;

grant select on public.tetris_optimization_stats to authenticated;

commit;

raise notice '========================================';
raise notice 'Sistema Tetris Optimizer implementado con éxito!';
raise notice '';
raise notice 'Funcionalidades:';
raise notice '1. Detecta cancelaciones automáticamente';
raise notice '2. Busca citas futuras que pueden adelantarse';
raise notice '3. Notifica a lista de espera';
raise notice '4. Prioriza candidatos inteligentemente';
raise notice '';
raise notice 'Para procesar optimizaciones manualmente:';
raise notice '  select public.process_tetris_optimization(optimization_id);';
raise notice '';
raise notice 'Para ver estadísticas:';
raise notice '  select * from public.tetris_optimization_stats;';
raise notice '========================================';
