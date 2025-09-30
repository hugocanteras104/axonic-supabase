-- Complemento a 0106: Notas del staff sobre clientes

create table if not exists public.profile_staff_notes (
    id uuid primary key default gen_random_uuid(),
    profile_id uuid not null references public.profiles(id) on delete cascade,
    note text not null,
    note_type text default 'general' check (note_type in ('general', 'medical', 'comportamiento', 'servicio', 'alerta')),
    is_alert boolean default false,
    created_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now()
);

comment on table public.profile_staff_notes is 
    'Notas internas del staff sobre clientes. Complementa profile_personal_details con observaciones operativas.';

comment on column public.profile_staff_notes.note_type is 
    'Tipo de nota: general, medical (condiciones médicas), comportamiento (actitud del cliente), servicio (preferencias de tratamiento), alerta (avisos importantes)';

comment on column public.profile_staff_notes.is_alert is 
    'Marcar como alerta para mostrar prominentemente (ej: alergia severa, cliente conflictivo)';

-- Índices
create index if not exists idx_staff_notes_profile on public.profile_staff_notes(profile_id);
create index if not exists idx_staff_notes_created_at on public.profile_staff_notes(created_at desc);
create index if not exists idx_staff_notes_alerts on public.profile_staff_notes(profile_id) where is_alert = true;

alter table public.profile_staff_notes enable row level security;

-- Solo owners pueden ver/crear notas del staff
drop policy if exists staff_notes_owner_all on public.profile_staff_notes;
create policy staff_notes_owner_all on public.profile_staff_notes
    for all to authenticated
    using (auth.jwt()->>'user_role' = 'owner')
    with check (auth.jwt()->>'user_role' = 'owner');

-- Trigger para updated_at si lo necesitas en el futuro
-- (Por ahora solo created_at porque las notas no se editan, se crean nuevas)
