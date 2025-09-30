-- ===============================================
-- Migration: 0204_add_foreign_key_constraints.sql
-- Purpose: Crear foreign keys compuestas
-- Dependencies: 0203_make_business_id_required.sql
-- ===============================================

begin;

-- Verificar dependencias
do $$
begin
  if not exists (
    select 1 from pg_constraint 
    where conname = 'profiles_id_business_key' 
      and conrelid = 'public.profiles'::regclass
  ) then
    raise exception '❌ Faltan constraints únicos. Aplicar primero: 0203';
  end if;
  raise notice '✅ Dependencias OK';
end $$;

-- Eliminar foreign keys viejas
alter table public.appointments drop constraint if exists appointments_profile_id_fkey;
alter table public.appointments drop constraint if exists appointments_service_id_fkey;
alter table public.service_resource_requirements drop constraint if exists service_resource_requirements_service_id_fkey;
alter table public.service_resource_requirements drop constraint if exists service_resource_requirements_resource_id_fkey;
alter table public.cross_sell_rules drop constraint if exists cross_sell_rules_trigger_service_id_fkey;
alter table public.cross_sell_rules drop constraint if exists cross_sell_rules_recommended_service_id_fkey;
alter table public.waitlists drop constraint if exists waitlists_service_id_fkey;
alter table public.waitlists drop constraint if exists waitlists_profile_id_fkey;
alter table public.resource_blocks drop constraint if exists resource_blocks_resource_id_fkey;
alter table public.appointment_resources drop constraint if exists appointment_resources_appointment_id_fkey;
alter table public.appointment_resources drop constraint if exists appointment_resources_resource_id_fkey;
alter table public.audit_logs drop constraint if exists audit_logs_profile_id_fkey;

-- Crear foreign keys compuestas
alter table public.appointments
  add constraint fk_appointments_profile_business
  foreign key (profile_id, business_id)
  references public.profiles(id, business_id)
  on delete cascade;

alter table public.appointments
  add constraint fk_appointments_service_business
  foreign key (service_id, business_id)
  references public.services(id, business_id)
  on delete restrict;

alter table public.service_resource_requirements
  add constraint fk_srr_service_business
  foreign key (service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.service_resource_requirements
  add constraint fk_srr_resource_business
  foreign key (resource_id, business_id)
  references public.resources(id, business_id)
  on delete cascade;

alter table public.cross_sell_rules
  add constraint fk_csr_trigger_service_business
  foreign key (trigger_service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.cross_sell_rules
  add constraint fk_csr_recommended_service_business
  foreign key (recommended_service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.waitlists
  add constraint fk_waitlists_service_business
  foreign key (service_id, business_id)
  references public.services(id, business_id)
  on delete cascade;

alter table public.waitlists
  add constraint fk_waitlists_profile_business
  foreign key (profile_id, business_id)
  references public.profiles(id, business_id)
  on delete cascade;

alter table public.resource_blocks
  add constraint fk_resource_blocks_resource_business
  foreign key (resource_id, business_id)
  references public.resources(id, business_id)
  on delete cascade;

alter table public.appointment_resources
  add constraint fk_ar_appointment_business
  foreign key (appointment_id, business_id)
  references public.appointments(id, business_id)
  on delete cascade;

alter table public.appointment_resources
  add constraint fk_ar_resource_business
  foreign key (resource_id, business_id)
  references public.resources(id, business_id)
  on delete restrict;

alter table public.audit_logs
  add constraint fk_audit_logs_profile_business
  foreign key (profile_id, business_id)
  references public.profiles(id, business_id);

raise notice '✅ [5/6] Foreign keys compuestas creadas';

commit;
