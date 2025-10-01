-- ===============================================
-- Migration: 0207_update_functions_multitenancy.sql
-- Purpose: Actualizar funciones RPC para multitenancy
-- Dependencies: 0205_update_rls_policies.sql, 0206_update_rls_deep.sql
-- ===============================================

-- Verificar dependencias
do $$
begin
  if not exists (select 1 from pg_proc where proname = 'get_user_business_id') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función public.get_user_business_id()\nAplicar primero: 0205_update_rls_policies.sql';
  end if;
  
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'appointments' and column_name = 'business_id'
  ) then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: columna business_id\nAplicar primero: 0200-0205 (fase multitenancy completa)';
  end if;
  
  raise notice '✅ Dependencias verificadas';
end $$;

begin;

-- ===============================================
-- get_available_slots
-- ===============================================
create or replace function public.get_available_slots(
    p_service_id uuid,
    p_start timestamptz,
    p_end timestamptz,
    p_step_minutes int default 15
)
returns table(slot_start timestamptz, slot_end timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_dur int;
    v_cursor timestamptz;
    v_role text;
    v_business_id uuid;
begin
    v_business_id := public.get_user_business_id();
    v_role := auth.jwt()->>'user_role';

    if v_business_id is null then
        raise exception 'Business context not found for current user';
    end if;

    if v_role not in ('owner', 'lead') then
        raise exception 'Insufficient privileges for role %', coalesce(v_role, 'unknown');
    end if;

    select duration_minutes into v_dur 
    from public.services 
    where id = p_service_id
      and business_id = v_business_id;
    
    if v_dur is null then
        raise exception 'Service not found or access denied';
    end if;
    
    if p_start >= p_end then
        raise exception 'Invalid time window';
    end if;

    v_cursor := p_start;
    while v_cursor + (v_dur || ' minutes')::interval <= p_end loop
        if not exists (
            select 1
            from public.appointments a
            where a.service_id = p_service_id
              and a.business_id = v_business_id
              and a.status = 'confirmed'
              and tstzrange(a.start_time, a.end_time, '[)') && 
                  tstzrange(v_cursor, v_cursor + (v_dur || ' minutes')::interval, '[)')
        ) then
            slot_start := v_cursor;
            slot_end := v_cursor + (v_dur || ' minutes')::interval;
            return next;
        end if;
        v_cursor := v_cursor + make_interval(mins => p_step_minutes);
    end loop;
end;
$$;


-- ===============================================
-- get_available_slots_with_resources (CORREGIDA)
-- ===============================================
create or replace function public.get_available_slots_with_resources(
    p_service_id uuid,
    p_start timestamptz,
    p_end timestamptz,
    p_step_minutes int default 15
)
returns table(slot_start timestamptz, slot_end timestamptz, available_resources jsonb)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_dur int;
    v_cursor timestamptz;
    v_slot_end timestamptz;
    v_required_resources uuid[];
    v_available_resources jsonb;
    v_resource_json jsonb;
    v_all_available boolean;
    v_role text;
    v_business_id uuid;
    i int;
begin
    v_business_id := public.get_user_business_id();
    v_role := auth.jwt()->>'user_role';
    
    if v_business_id is null then
        raise exception 'Business context not found for current user';
    end if;
    
    if v_role not in ('owner', 'lead') then
        raise exception 'Insufficient privileges for role %', coalesce(v_role, 'unknown');
    end if;

    select duration_minutes into v_dur 
    from public.services 
    where id = p_service_id
      and business_id = v_business_id;
    
    if v_dur is null then
        raise exception 'Service not found or access denied';
    end if;
    
    if p_start >= p_end then
        raise exception 'Invalid time window';
    end if;

    select array_agg(resource_id)
    into v_required_resources
    from public.service_resource_requirements
    where service_id = p_service_id
      and business_id = v_business_id
      and is_optional = false;

    if v_required_resources is null or array_length(v_required_resources, 1) = 0 then
        return query 
        select * from public.get_available_slots(p_service_id, p_start, p_end, p_step_minutes);
        return;
    end if;

    v_cursor := p_start;
    while v_cursor + (v_dur || ' minutes')::interval <= p_end loop
        v_slot_end := v_cursor + (v_dur || ' minutes')::interval;
        v_all_available := true;
        v_available_resources := '[]'::jsonb;

        for i in 1..array_length(v_required_resources, 1) loop
            if exists (
                select 1
                from public.resource_blocks rb
                where rb.resource_id = v_required_resources[i]
                  and rb.business_id = v_business_id
                  and tstzrange(rb.start_time, rb.end_time, '[)') && 
                      tstzrange(v_cursor, v_slot_end, '[)')
            ) then
                v_all_available := false;
                exit;
            end if;
            
            if exists (
                select 1
                from public.appointment_resources ar
                join public.appointments a on a.id = ar.appointment_id
                where ar.resource_id = v_required_resources[i]
                  and ar.business_id = v_business_id
                  and a.business_id = v_business_id
                  and a.status = 'confirmed'
                  and tstzrange(a.start_time, a.end_time, '[)') &&
                      tstzrange(v_cursor, v_slot_end, '[)')
            ) then
                v_all_available := false;
                exit;
            end if;
            
            select jsonb_build_object(
                'resource_id', r.id,
                'name', r.name,
                'type', r.type
            )
            into v_resource_json
            from public.resources r
            where r.id = v_required_resources[i]
              and r.business_id = v_business_id;
            
            if v_resource_json is null then
                v_all_available := false;
                exit;
            end if;
            
            v_available_resources := v_available_resources || jsonb_build_array(v_resource_json);
        end loop;

        if v_all_available then
            slot_start := v_cursor;
            slot_end := v_slot_end;
            available_resources := v_available_resources;
            return next;
        end if;

        v_cursor := v_cursor + make_interval(mins => p_step_minutes);
    end loop;
end;
$$;


-- ===============================================
-- confirm_appointment_with_resources
-- ===============================================
create or replace function public.confirm_appointment_with_resources(
    p_appointment_id uuid,
    p_strategy text default 'first_available'
)
returns jsonb 
language plpgsql 
security definer 
set search_path = public 
as $$
declare 
    v_appointment record;
    v_required record;
    v_assigned_resources jsonb := '[]'::jsonb;
    v_business_id uuid;
begin
    v_business_id := public.get_user_business_id();
    
    if v_business_id is null then
        raise exception 'Business context not found for current user';
    end if;
    
    select * into v_appointment 
    from public.appointments 
    where id = p_appointment_id 
      and business_id = v_business_id
    for update;
    
    if not found then 
        raise exception 'Appointment not found or access denied';
    end if;
    
    if v_appointment.status = 'confirmed' then 
        raise exception 'Appointment already confirmed';
    end if;

    for v_required in 
        select 
            srr.resource_id, 
            srr.quantity, 
            r.name, 
            r.type 
        from public.service_resource_requirements srr
        join public.resources r on r.id = srr.resource_id
        where srr.service_id = v_appointment.service_id
          and srr.business_id = v_business_id
          and r.business_id = v_business_id
          and srr.is_optional = false
    loop
        if exists (
            select 1
            from public.resource_blocks rb
            where rb.resource_id = v_required.resource_id
              and rb.business_id = v_business_id
              and tstzrange(rb.start_time, rb.end_time, '[)') && 
                  tstzrange(v_appointment.start_time, v_appointment.end_time, '[)')
        ) then
            raise exception 'Resource % (%) is blocked for the requested time slot', 
                v_required.name, v_required.type;
        end if;
        
        if exists (
            select 1
            from public.appointment_resources ar
            join public.appointments a on a.id = ar.appointment_id
            where ar.resource_id = v_required.resource_id
              and ar.business_id = v_business_id
              and a.business_id = v_business_id
              and a.status = 'confirmed'
              and a.id != p_appointment_id
              and tstzrange(a.start_time, a.end_time, '[)') &&
                  tstzrange(v_appointment.start_time, v_appointment.end_time, '[)')
        ) then
            raise exception 'Resource % (%) is not available for the requested time slot',
                v_required.name, v_required.type;
        end if;

        insert into public.appointment_resources (appointment_id, resource_id, business_id)
        values (p_appointment_id, v_required.resource_id, v_business_id)
        on conflict do nothing;
        
        v_assigned_resources := v_assigned_resources || jsonb_build_array(jsonb_build_object(
            'resource_id', v_required.resource_id,
            'name', v_required.name,
            'type', v_required.type
        ));
    end loop;

    update public.appointments 
    set status = 'confirmed', updated_at = now() 
    where id = p_appointment_id;
    
    return jsonb_build_object(
        'appointment_id', p_appointment_id,
        'status', 'confirmed',
        'assigned_resources', v_assigned_resources
    );
end $$;


-- ===============================================
-- decrement_inventory
-- ===============================================
create or replace function public.decrement_inventory(
    p_sku text,
    p_qty int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare 
    v_item record;
    v_business_id uuid;
begin
    v_business_id := public.get_user_business_id();
    
    if v_business_id is null then
        raise exception 'Business context not found for current user';
    end if;
    
    if p_qty is null or p_qty <= 0 then 
        raise exception 'Quantity must be positive, got: %', p_qty;
    end if;
    
    select * into v_item 
    from public.inventory 
    where sku = p_sku 
      and business_id = v_business_id
    for update;
    
    if not found then 
        raise exception 'SKU % not found in your business', p_sku;
    end if;
    
    if v_item.quantity < p_qty then 
        raise exception 'Insufficient stock for % (have %, need %)', 
            p_sku, v_item.quantity, p_qty;
    end if;
    
    update public.inventory 
    set quantity = quantity - p_qty, updated_at = now() 
    where id = v_item.id;
end $$;


-- ===============================================
-- refresh_metrics_historical
-- ===============================================
create or replace function public.refresh_metrics_historical()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    refresh materialized view public.metrics_historical;
end $$;


-- ===============================================
-- Funciones de KB (Knowledge Base)
-- ===============================================

create or replace function public.search_knowledge_base(
    p_query text,
    p_similarity_threshold double precision default 0.20,
    p_limit int default 5
)
returns table(id uuid, category text, question text, answer text, similarity double precision)
language sql
stable
as $$
select
    kb.id, kb.category, kb.question, kb.answer,
    similarity(kb.question_normalized, public.norm_txt(p_query)) as sim
from public.knowledge_base kb
where kb.business_id = public.get_user_business_id()
  and similarity(kb.question_normalized, public.norm_txt(p_query)) > p_similarity_threshold
order by sim desc
limit p_limit
$$;


create or replace function public.search_knowledge_by_keywords(
    p_keywords text[],
    p_limit int default 5
)
returns table(id uuid, category text, question text, answer text, keyword_matches int)
language sql
stable
as $$
select
    kb.id, kb.category, kb.question, kb.answer,
    (
        select count(*)
        from unnest(p_keywords) as kw
        where kb.question_normalized ilike ('%' || public.norm_txt(kw) || '%')
           or kb.answer_normalized ilike ('%' || public.norm_txt(kw) || '%')
    )::int as keyword_matches
from public.knowledge_base kb
where kb.business_id = public.get_user_business_id()
  and exists (
    select 1
    from unnest(p_keywords) as kw
    where kb.question_normalized ilike ('%' || public.norm_txt(kw) || '%')
       or kb.answer_normalized ilike ('%' || public.norm_txt(kw) || '%')
)
order by keyword_matches desc, kb.id
limit p_limit
$$;


create or replace function public.search_knowledge_hybrid(
    p_query text,
    p_similarity_threshold double precision default 0.15,
    p_limit int default 5,
    p_category text default null
)
returns table(id uuid, category text, question text, answer text, relevance_score double precision, match_type text)
language plpgsql
stable
as $$
declare
    vq text;
    v_keywords text[];
    v_business_id uuid;
begin
    v_business_id := public.get_user_business_id();
    vq := public.norm_txt(p_query);
    
    select array_agg(w) into v_keywords
    from (
        select word as w
        from regexp_split_to_table(vq, '\\s+') as word
        where length(word) >= 3
    ) q;

    return query
    with base as (
        select
            kb.id as kb_id,
            kb.category as kb_category,
            kb.question as kb_question,
            kb.answer as kb_answer,
            kb.question_normalized as kb_question_normalized,
            kb.answer_normalized as kb_answer_normalized
        from public.knowledge_base kb
        where kb.business_id = v_business_id
          and (p_category is null or kb.category = p_category)
    ),
    similarity_results as (
        select
            b.kb_id, b.kb_category, b.kb_question, b.kb_answer,
            similarity(b.kb_question_normalized, vq) * 100.0 as score,
            'similarity'::text as match_type
        from base b
        where similarity(b.kb_question_normalized, vq) > p_similarity_threshold
    ),
    keyword_results as (
        select
            b.kb_id, b.kb_category, b.kb_question, b.kb_answer,
            (
                select (sum(case when b.kb_question_normalized ilike ('%' || kw || '%') then 1 else 0 end) * 24.0)
                     + (sum(case when b.kb_answer_normalized ilike ('%' || kw || '%') then 1 else 0 end) * 16.0)
                from unnest(coalesce(v_keywords, array[]::text[])) as kw
            ) as score,
            'keywords'::text as match_type
        from base b
        where exists (
            select 1
            from unnest(coalesce(v_keywords, array[]::text[])) as kw
            where b.kb_question_normalized ilike ('%' || kw || '%')
               or b.kb_answer_normalized ilike ('%' || kw || '%')
        )
    ),
    combined as (
        select * from similarity_results
        union all
        select * from keyword_results
    )
    select
        c.kb_id, c.kb_category, c.kb_question, c.kb_answer,
        max(c.score) as relevance_score,
        string_agg(distinct c.match_type, '+' order by c.match_type) as match_type
    from combined c
    group by c.kb_id, c.kb_category, c.kb_question, c.kb_answer
    order by relevance_score desc
    limit p_limit;
end
$$;


create or replace function public.get_related_questions(
    p_question_id uuid,
    p_limit int default 3
)
returns table(id uuid, category text, question text, similarity double precision)
language sql
stable
as $$
select
    kb2.id, kb2.category, kb2.question,
    similarity(kb1.question_normalized, kb2.question_normalized) as sim
from public.knowledge_base kb1
cross join public.knowledge_base kb2
where kb1.id = p_question_id
  and kb2.id != p_question_id
  and kb1.business_id = public.get_user_business_id()
  and kb2.business_id = public.get_user_business_id()
  and similarity(kb1.question_normalized, kb2.question_normalized) > 0.15
order by sim desc
limit p_limit
$$;


create or replace function public.increment_kb_view_count_guarded(
    p_question_id uuid,
    p_phone_hash text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_should_increment boolean := false;
    v_last_view timestamptz;
    v_lock_id bigint;
    v_business_id uuid;
begin
    v_business_id := public.get_user_business_id();
    
    if v_business_id is null then
        raise exception 'Business context not found for current user';
    end if;
    
    if not exists (
        select 1 from public.knowledge_base 
        where id = p_question_id 
          and business_id = v_business_id
    ) then
        raise exception 'Question not found or access denied';
    end if;
    
    v_lock_id := hashtext(p_question_id::text || coalesce(p_phone_hash, ''));
    perform pg_advisory_xact_lock(v_lock_id);

    select last_view into v_last_view
    from public.kb_views_footprint
    where kb_id = p_question_id and phone_hash = p_phone_hash;

    if v_last_view is null then
        v_should_increment := true;
    elsif now() - v_last_view > interval '60 seconds' then
        v_should_increment := true;
    end if;

    insert into public.kb_views_footprint(kb_id, phone_hash, last_view)
    values (p_question_id, p_phone_hash, now())
    on conflict (kb_id, phone_hash)
    do update set last_view = now();

    if v_should_increment then
        update public.knowledge_base
        set view_count = view_count + 1
        where id = p_question_id
          and business_id = v_business_id;
    end if;
end $$;


commit;

