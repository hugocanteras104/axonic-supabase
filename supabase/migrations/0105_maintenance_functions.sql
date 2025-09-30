-- Funciones de mantenimiento para datos operativos

-- Limpieza de notificaciones procesadas antiguas
create or replace function public.cleanup_old_notifications(
    days_to_keep int default 90
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_deleted integer;
begin
    delete from public.notifications_queue
    where processed_at is not null
        and processed_at < now() - make_interval(days => days_to_keep);

    get diagnostics v_deleted = row_count;

    return v_deleted;
end $$;

comment on function public.cleanup_old_notifications is
    'Elimina notificaciones procesadas con más de X días de antigüedad. Por defecto 90 días.';

grant execute on function public.cleanup_old_notifications(int) to authenticated;

-- Función para detectar recursos poco utilizados
create or replace function public.find_unused_resources(
    min_days_unused int default 90
)
returns table(
    resource_id uuid,
    resource_name text,
    resource_type text,
    days_since_last_use int,
    total_uses bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    return query
    select
        r.id as resource_id,
        r.name as resource_name,
        r.type::text as resource_type,
        coalesce(
            extract(day from now() - max(a.start_time))::int,
            9999
        ) as days_since_last_use,
        count(ar.id) as total_uses
    from public.resources r
    left join public.appointment_resources ar on ar.resource_id = r.id
    left join public.appointments a on a.id = ar.appointment_id
    group by r.id, r.name, r.type
    having coalesce(
        extract(day from now() - max(a.start_time))::int,
        9999
    ) >= min_days_unused
    order by days_since_last_use desc;
end $$;

comment on function public.find_unused_resources is
    'Detecta recursos que no se han usado en X días. Útil para optimizar inventario de recursos.';

grant execute on function public.find_unused_resources(int) to authenticated;
