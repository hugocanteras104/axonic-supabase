-- 0002_core_tables.sql
-- Tablas principales y de recursos

-- Perfiles
create table if not exists public.profiles (
    id uuid primary key default gen_random_uuid(),
    phone_number text unique not null,
    role public.user_role not null default 'lead',
    name text,
    email text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Servicios
create table if not exists public.services (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    description text,
    base_price numeric(10, 2) not null default 0,
    duration_minutes int not null default 60,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Citas
create table if not exists public.appointments (
    id uuid primary key default gen_random_uuid(),
    profile_id uuid not null references public.profiles (id) on delete cascade,
    service_id uuid not null references public.services (id) on delete restrict,
    calendar_event_id text,
    status public.appointment_status not null default 'pending',
    start_time timestamptz not null,
    end_time timestamptz not null,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint appt_time_window check (start_time < end_time)
);

-- Inventario
create table if not exists public.inventory (
    id uuid primary key default gen_random_uuid(),
    sku text unique not null,
    name text not null,
    quantity int not null default 0,
    reorder_threshold int not null default 0,
    price numeric(10, 2) not null default 0,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint inv_non_negative check (quantity >= 0)
);

-- Reglas de cross-sell
create table if not exists public.cross_sell_rules (
    id uuid primary key default gen_random_uuid(),
    trigger_service_id uuid not null references public.services (id) on delete cascade,
    recommended_service_id uuid not null references public.services (id) on delete cascade,
    message_template text not null,
    priority int not null default 1,
    created_at timestamptz not null default now()
);

-- Listas de espera
create table if not exists public.waitlists (
    id uuid primary key default gen_random_uuid(),
    service_id uuid not null references public.services (id) on delete cascade,
    desired_date date not null,
    profile_id uuid not null references public.profiles (id) on delete cascade,
    status public.waitlist_status not null default 'active',
    created_at timestamptz not null default now()
);

-- Auditoría
create table if not exists public.audit_logs (
    id uuid primary key default gen_random_uuid(),
    profile_id uuid references public.profiles (id),
    action text not null,
    payload jsonb not null default '{}'::jsonb,
    timestamp timestamptz not null default now()
);

-- Cola de notificaciones
create table if not exists public.notifications_queue (
    id bigserial primary key,
    event_type text not null,
    payload jsonb not null,
    created_at timestamptz not null default now(),
    processed_at timestamptz
);

-- Recursos
create table if not exists public.resources (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    type public.resource_type not null,
    status public.resource_status not null default 'available',
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Requisitos de recursos por servicio
create table if not exists public.service_resource_requirements (
    id uuid primary key default gen_random_uuid(),
    service_id uuid not null references public.services (id) on delete cascade,
    resource_id uuid not null references public.resources (id) on delete cascade,
    quantity int not null default 1,
    is_optional boolean not null default false,
    created_at timestamptz not null default now(),
    constraint srr_quantity_positive check (quantity > 0)
);

-- Recursos asignados a una cita
create table if not exists public.appointment_resources (
    id uuid primary key default gen_random_uuid(),
    appointment_id uuid not null references public.appointments (id) on delete cascade,
    resource_id uuid not null references public.resources (id) on delete restrict,
    created_at timestamptz not null default now()
);

-- Bloqueos de recursos (mantenimiento/ausencia)
create table if not exists public.resource_blocks (
    id uuid primary key default gen_random_uuid(),
    resource_id uuid not null references public.resources (id) on delete cascade,
    start_time timestamptz not null,
    end_time timestamptz not null,
    reason text not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint rb_time_window check (start_time < end_time)
);

-- Base de conocimiento (definición básica; normalización avanzada en 0005)
create table if not exists public.knowledge_base (
    id uuid primary key default gen_random_uuid(),
    category text,
    question text not null,
    answer text not null,
    metadata jsonb not null default '{}'::jsonb,
    last_modified_by uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Fin 0002
