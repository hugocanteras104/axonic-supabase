-- Validaciones adicionales para datos clave

-- Validación de formato de email en profiles
alter table public.profiles
    drop constraint if exists profiles_email_format;

alter table public.profiles
    add constraint profiles_email_format
        check (email is null or email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Validación de formato de teléfono internacional en profiles
alter table public.profiles
    drop constraint if exists profiles_phone_format;

alter table public.profiles
    add constraint profiles_phone_format
        check (phone_number ~ '^\+[0-9]{10,15}$');

-- Validación de duración razonable para servicios
alter table public.services
    drop constraint if exists services_duration_reasonable;

alter table public.services
    add constraint services_duration_reasonable
        check (duration_minutes between 15 and 480);

-- Validación de duración mínima de citas
alter table public.appointments
    drop constraint if exists appointments_min_duration;

alter table public.appointments
    add constraint appointments_min_duration
        check (end_time - start_time >= interval '10 minutes');

-- Comentarios sobre las restricciones
comment on constraint profiles_email_format on public.profiles is
    'Email debe tener formato válido (ej: usuario@dominio.com)';

comment on constraint profiles_phone_format on public.profiles is
    'Teléfono debe estar en formato internacional con + y 10-15 dígitos';

comment on constraint services_duration_reasonable on public.services is
    'Duración debe estar entre 15 minutos y 8 horas';

comment on constraint appointments_min_duration on public.appointments is
    'La cita debe durar al menos 10 minutos';
