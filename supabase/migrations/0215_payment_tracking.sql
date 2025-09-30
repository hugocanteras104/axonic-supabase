-- ===============================================
-- Migration: 0215_payment_tracking.sql
-- Purpose: Sistema de tracking de pagos para depósitos y servicios
-- Dependencies: 0209_add_validations_audit.sql
-- ===============================================

-- Verificar dependencias
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'appointments' and column_name = 'deposit_required'
  ) then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: columnas de depósito\nAplicar primero: 0209_add_validations_audit.sql';
  end if;
  
  raise notice '✅ Dependencias verificadas';
end $$;

begin;

-- Tipos de pago
do $$ begin
  create type public.payment_method as enum ('efectivo','tarjeta','transferencia','bizum','stripe','otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_status as enum ('pendiente','procesando','completado','fallido','reembolsado');
exception when duplicate_object then null; end $$;

-- Tabla de transacciones de pago
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  
  -- Detalles del pago
  amount numeric(10,2) not null check (amount > 0),
  payment_method public.payment_method not null,
  payment_status public.payment_status not null default 'pendiente',
  
  -- Referencia externa (para integraciones)
  external_reference text, -- ID de Stripe, número de transferencia, etc.
  
  -- Metadata
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  
  -- Auditoría
  processed_by uuid references public.profiles(id) on delete set null,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.payment_transactions is
  'Registro de todas las transacciones de pago (depósitos, pagos completos, reembolsos)';
comment on column public.payment_transactions.external_reference is
  'ID externo del sistema de pagos (Stripe payment_intent, número de transferencia, etc.)';
comment on column public.payment_transactions.metadata is
  'Datos adicionales: respuesta de API de pago, comprobantes, etc.';

-- Índices
create index idx_payments_business on public.payment_transactions(business_id);
create index idx_payments_appointment on public.payment_transactions(appointment_id);
create index idx_payments_status on public.payment_transactions(payment_status);
create index idx_payments_created on public.payment_transactions(created_at desc);
create index idx_payments_external_ref on public.payment_transactions(external_reference) 
  where external_reference is not null;

-- Trigger para updated_at
drop trigger if exists trg_upd_payments on public.payment_transactions;
create trigger trg_upd_payments 
  before update on public.payment_transactions
  for each row 
  execute function public.set_updated_at();

-- RLS
alter table public.payment_transactions enable row level security;

drop policy if exists payments_owner_all on public.payment_transactions;
create policy payments_owner_all on public.payment_transactions
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = auth.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = auth.get_user_business_id()
  );

drop policy if exists payments_lead_read_own on public.payment_transactions;
create policy payments_lead_read_own on public.payment_transactions
  for select to authenticated
  using (
    business_id = auth.get_user_business_id()
    and exists (
      select 1 
      from public.appointments a
      join public.profiles p on p.id = a.profile_id
      where a.id = payment_transactions.appointment_id
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

-- Función para registrar pago y actualizar appointment.deposit_paid
create or replace function public.register_payment(
  p_appointment_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_external_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_transaction_id uuid;
  v_user_id uuid;
begin
  -- Obtener contexto
  v_business_id := auth.get_user_business_id();
  
  begin
    v_user_id := (auth.jwt()->>'sub')::uuid;
  exception when others then
    v_user_id := null;
  end;
  
  -- Validar appointment existe y pertenece al business
  if not exists (
    select 1 
    from public.appointments 
    where id = p_appointment_id 
      and business_id = v_business_id
  ) then
    raise exception 'Cita no encontrada o sin acceso';
  end if;
  
  -- Crear transacción
  insert into public.payment_transactions (
    business_id,
    appointment_id,
    amount,
    payment_method,
    payment_status,
    external_reference,
    notes,
    processed_by,
    processed_at
  ) values (
    v_business_id,
    p_appointment_id,
    p_amount,
    p_payment_method::public.payment_method,
    'completado',
    p_external_reference,
    p_notes,
    v_user_id,
    now()
  )
  returning id into v_transaction_id;
  
  -- Actualizar deposit_paid en appointment
  update public.appointments
  set deposit_paid = deposit_paid + p_amount
  where id = p_appointment_id;
  
  return v_transaction_id;
end;
$$;

comment on function public.register_payment is
  'Registra un pago y actualiza automáticamente el deposit_paid de la cita. Retorna el ID de la transacción.';

grant execute on function public.register_payment(uuid, numeric, text, text, text) to authenticated;

commit;

raise notice '========================================';
raise notice 'Sistema de tracking de pagos implementado';
raise notice 'Usar: select public.register_payment(appointment_id, 30.00, ''tarjeta'');';
raise notice '========================================';
