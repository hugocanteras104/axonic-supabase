-- Add descriptive metadata and performance improvements

comment on table public.appointments is 'Citas agendadas entre clientes y servicios disponibles.';
comment on column public.appointments.status is 'Estado de la cita: pending, confirmed o cancelled.';

create index if not exists idx_waitlists_active_service_date
    on public.waitlists (service_id, desired_date)
    where status = 'active';
