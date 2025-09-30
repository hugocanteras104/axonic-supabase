-- Redefine availability RPCs with role checks and tighter security
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
begin
    v_role := auth.jwt()->>'user_role';
    if v_role not in ('owner', 'lead') then
        raise exception 'insufficient privileges for role %', coalesce(v_role, 'unknown');
    end if;

    select duration_minutes into v_dur from public.services where id = p_service_id;
    if v_dur is null then
        raise exception 'Service not found';
    end if;
    if p_start >= p_end then
        raise exception 'Invalid window';
    end if;

    v_cursor := p_start;
    while v_cursor + (v_dur || ' minutes')::interval <= p_end loop
        if not exists (
            select 1
            from public.appointments a
            where a.service_id = p_service_id
              and a.status = 'confirmed'
              and tstzrange(a.start_time, a.end_time, '[)') && tstzrange(v_cursor, v_cursor + (v_dur || ' minutes')::interval, '[)')
        ) then
            slot_start := v_cursor;
            slot_end := v_cursor + (v_dur || ' minutes')::interval;
            return next;
        end if;
        v_cursor := v_cursor + make_interval(mins => p_step_minutes);
    end loop;
end;
$$;

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
    v_all_available boolean;
    v_role text;
begin
    v_role := auth.jwt()->>'user_role';
    if v_role not in ('owner', 'lead') then
        raise exception 'insufficient privileges for role %', coalesce(v_role, 'unknown');
    end if;

    select duration_minutes into v_dur from public.services where id = p_service_id;
    if v_dur is null then
        raise exception 'Service not found';
    end if;
    if p_start >= p_end then
        raise exception 'Invalid time window';
    end if;

    select array_agg(resource_id)
    into v_required_resources
    from public.service_resource_requirements
    where service_id = p_service_id
      and is_optional = false;

    if v_required_resources is null or array_length(v_required_resources, 1) = 0 then
        return query select * from public.get_available_slots(p_service_id, p_start, p_end, p_step_minutes);
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
                  and tstzrange(rb.start_time, rb.end_time, '[)') && tstzrange(v_cursor, v_slot_end, '[)')
            ) or exists (
                select 1
                from public.appointment_resources ar
                join public.appointments a on a.id = ar.appointment_id
                where ar.resource_id = v_required_resources[i]
                  and a.status = 'confirmed'
                  and tstzrange(a.start_time, a.end_time, '[)') && tstzrange(v_cursor, v_slot_end, '[)')
            ) then
                v_all_available := false;
                exit;
            else
                select v_available_resources || jsonb_build_object('resource_id', r.id, 'name', r.name, 'type', r.type)
                into v_available_resources
                from public.resources r
                where r.id = v_required_resources[i];
            end if;
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

revoke all on function public.get_available_slots(uuid, timestamptz, timestamptz, int) from public;
grant execute on function public.get_available_slots(uuid, timestamptz, timestamptz, int) to authenticated;

revoke all on function public.get_available_slots_with_resources(uuid, timestamptz, timestamptz, int) from public;
grant execute on function public.get_available_slots_with_resources(uuid, timestamptz, timestamptz, int) to authenticated;
