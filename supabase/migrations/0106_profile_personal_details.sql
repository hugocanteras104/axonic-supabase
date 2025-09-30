-- 0106_profile_personal_details.sql
-- Almacena información adicional de clientes como cumpleaños, condiciones de piel o detalles familiares

create table if not exists public.profile_personal_details (
    profile_id uuid primary key references public.profiles (id) on delete cascade,
    birth_date date,
    skin_concerns text[] not null default '{}',
    notes text,
    children_count int check (children_count >= 0),
    personal_preferences jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.profile_personal_details is 'Detalles personales opcionales vinculados a cada perfil (cumpleaños, condiciones de piel, familia).';
comment on column public.profile_personal_details.birth_date is 'Fecha de nacimiento para felicitaciones o recordatorios.';
comment on column public.profile_personal_details.skin_concerns is 'Lista de preocupaciones de piel (ej. {"acne","rosácea"}).';
comment on column public.profile_personal_details.notes is 'Notas adicionales relevantes para la atención personalizada.';
comment on column public.profile_personal_details.children_count is 'Número de hijos reportado por el cliente.';
comment on column public.profile_personal_details.personal_preferences is 'Preferencias opcionales almacenadas en JSON (ej. alergias, tratamientos favoritos).';

-- RLS y políticas
alter table public.profile_personal_details enable row level security;

drop policy if exists profile_details_owner_all on public.profile_personal_details;
create policy profile_details_owner_all
    on public.profile_personal_details
    for all
    to authenticated
    using (auth.jwt()->>'user_role' = 'owner')
    with check (auth.jwt()->>'user_role' = 'owner');

drop policy if exists profile_details_lead_access on public.profile_personal_details;
create policy profile_details_lead_access
    on public.profile_personal_details
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.profiles p
            where p.id = profile_personal_details.profile_id
              and p.phone_number = (auth.jwt()->>'phone_number')
        )
    );

drop policy if exists profile_details_lead_update on public.profile_personal_details;
create policy profile_details_lead_update
    on public.profile_personal_details
    for insert
    to authenticated
    with check (
        exists (
            select 1
            from public.profiles p
            where p.id = profile_personal_details.profile_id
              and p.phone_number = (auth.jwt()->>'phone_number')
        )
    );

drop policy if exists profile_details_lead_modify on public.profile_personal_details;
create policy profile_details_lead_modify
    on public.profile_personal_details
    for update
    to authenticated
    using (
        exists (
            select 1
            from public.profiles p
            where p.id = profile_personal_details.profile_id
              and p.phone_number = (auth.jwt()->>'phone_number')
        )
    )
    with check (
        exists (
            select 1
            from public.profiles p
            where p.id = profile_personal_details.profile_id
              and p.phone_number = (auth.jwt()->>'phone_number')
        )
    );

drop trigger if exists trg_upd_profile_personal_details on public.profile_personal_details;

create trigger trg_upd_profile_personal_details
    before update on public.profile_personal_details
    for each row
    execute function public.set_updated_at();
