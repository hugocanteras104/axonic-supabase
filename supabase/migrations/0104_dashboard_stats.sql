-- Funciones de estadísticas para el dashboard

-- Estadísticas del día actual
create or replace function public.get_today_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_stats jsonb;
begin
    select jsonb_build_object(
        'date', current_date,
        'appointments', jsonb_build_object(
            'total', count(*),
            'confirmed', count(*) filter (where a.status = 'confirmed'),
            'pending', count(*) filter (where a.status = 'pending'),
            'cancelled', count(*) filter (where a.status = 'cancelled')
        ),
        'revenue', jsonb_build_object(
            'estimated', coalesce(sum(s.base_price) filter (where a.status = 'confirmed'), 0),
            'potential', coalesce(sum(s.base_price) filter (where a.status in ('confirmed', 'pending')), 0)
        ),
        'top_service', (
            select jsonb_build_object(
                'name', s2.name,
                'appointments', count(*)
            )
            from public.appointments a2
            join public.services s2 on s2.id = a2.service_id
            where date(a2.start_time) = current_date
                and a2.status = 'confirmed'
            group by s2.id, s2.name
            order by count(*) desc
            limit 1
        )
    ) into v_stats
    from public.appointments a
    left join public.services s on s.id = a.service_id
    where date(a.start_time) = current_date;

    return coalesce(v_stats, '{}'::jsonb);
end $$;

comment on function public.get_today_dashboard is
    'Devuelve estadísticas del día actual para el dashboard en formato JSON';

grant execute on function public.get_today_dashboard() to authenticated;

-- Estadísticas de la semana actual
create or replace function public.get_week_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    return (
        select jsonb_build_object(
            'week_start', date_trunc('week', current_date),
            'total_appointments', count(*),
            'confirmed', count(*) filter (where status = 'confirmed'),
            'total_revenue', coalesce(sum(s.base_price) filter (where a.status = 'confirmed'), 0),
            'avg_daily_appointments', round(count(*)::numeric / 7, 1)
        )
        from public.appointments a
        join public.services s on s.id = a.service_id
        where a.start_time >= date_trunc('week', current_date)
            and a.start_time < date_trunc('week', current_date) + interval '1 week'
    );
end $$;

comment on function public.get_week_summary is
    'Devuelve estadísticas agregadas de la semana actual';

grant execute on function public.get_week_summary() to authenticated;
