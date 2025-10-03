-- ===============================================
-- Migration: 0206_update_rls_deep.sql
-- Purpose: Actualizar políticas RLS para multitenancy
-- Dependencies: 0205_update_rls_policies.sql
-- ===============================================

do $$
begin
  if not exists (select 1 from pg_proc where proname = 'get_user_business_id') then
    raise exception E'❌ DEPENDENCIA FALTANTE\n\nRequiere: función public.get_user_business_id()\nAplicar primero: 0205_update_rls_policies.sql';
  end if;
end $$;

begin;

-- PROFILES
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles 
  for select to authenticated
  using (
    business_id = public.get_user_business_id()
    or phone_number = (auth.jwt()->>'phone_number')
  );

drop policy if exists profiles_owner_insert on public.profiles;
create policy profiles_owner_insert on public.profiles 
  for insert to authenticated
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles 
  for update to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

drop policy if exists profiles_lead_update_self on public.profiles;
create policy profiles_lead_update_self on public.profiles 
  for update to authenticated
  using (
    phone_number = (auth.jwt()->>'phone_number')
    and business_id = public.get_user_business_id()
  )
  with check (
    phone_number = (auth.jwt()->>'phone_number')
    and business_id = public.get_user_business_id()
  );

drop policy if exists profiles_owner_delete on public.profiles;
create policy profiles_owner_delete on public.profiles 
  for delete to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- SERVICES
drop policy if exists services_read_all on public.services;
create policy services_read_all on public.services 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists services_owner_write on public.services;
create policy services_owner_write on public.services 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- APPOINTMENTS
drop policy if exists appts_owner_all on public.appointments;
create policy appts_owner_all on public.appointments 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

drop policy if exists appts_lead_read on public.appointments;
create policy appts_lead_read on public.appointments 
  for select to authenticated
  using (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = appointments.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

drop policy if exists appts_lead_insert on public.appointments;
create policy appts_lead_insert on public.appointments 
  for insert to authenticated
  with check (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = appointments.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

drop policy if exists appts_lead_update on public.appointments;
create policy appts_lead_update on public.appointments 
  for update to authenticated
  using (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = appointments.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  )
  with check (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = appointments.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

-- INVENTORY
drop policy if exists inventory_read_all on public.inventory;
create policy inventory_read_all on public.inventory 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists inventory_owner_write on public.inventory;
create policy inventory_owner_write on public.inventory 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- KNOWLEDGE_BASE
drop policy if exists kb_read_all on public.knowledge_base;
create policy kb_read_all on public.knowledge_base 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists kb_owner_write on public.knowledge_base;
create policy kb_owner_write on public.knowledge_base 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- CROSS_SELL_RULES
drop policy if exists crosssell_read_all on public.cross_sell_rules;
create policy crosssell_read_all on public.cross_sell_rules 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists crosssell_owner_write on public.cross_sell_rules;
create policy crosssell_owner_write on public.cross_sell_rules 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- WAITLISTS
drop policy if exists waitlists_owner_all on public.waitlists;
create policy waitlists_owner_all on public.waitlists 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

drop policy if exists waitlists_lead_read on public.waitlists;
create policy waitlists_lead_read on public.waitlists 
  for select to authenticated
  using (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = waitlists.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

drop policy if exists waitlists_lead_insert on public.waitlists;
create policy waitlists_lead_insert on public.waitlists 
  for insert to authenticated
  with check (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = waitlists.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

drop policy if exists waitlists_lead_update on public.waitlists;
create policy waitlists_lead_update on public.waitlists 
  for update to authenticated
  using (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = waitlists.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  )
  with check (
    business_id = public.get_user_business_id()
    and exists (
      select 1 from public.profiles p 
      where p.id = waitlists.profile_id 
        and p.phone_number = (auth.jwt()->>'phone_number')
    )
  );

-- AUDIT_LOGS
drop policy if exists audit_owner_read on public.audit_logs;
create policy audit_owner_read on public.audit_logs 
  for select to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

drop policy if exists audit_insert_all on public.audit_logs;
create policy audit_insert_all on public.audit_logs 
  for insert to authenticated
  with check (business_id = public.get_user_business_id());

-- NOTIFICATIONS_QUEUE
drop policy if exists nq_owner_read on public.notifications_queue;
create policy nq_owner_read on public.notifications_queue 
  for select to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

drop policy if exists nq_insert_all on public.notifications_queue;
create policy nq_insert_all on public.notifications_queue 
  for insert to authenticated
  with check (business_id = public.get_user_business_id());

-- RESOURCES
drop policy if exists resources_read_all on public.resources;
create policy resources_read_all on public.resources 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists resources_owner_write on public.resources;
create policy resources_owner_write on public.resources 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- APPOINTMENT_RESOURCES
drop policy if exists ar_read_owner on public.appointment_resources;
drop policy if exists ar_insert_all on public.appointment_resources;

create policy ar_read_scoped on public.appointment_resources
  for select to authenticated
  using (
    business_id = public.get_user_business_id()
    and (
      auth.jwt()->>'user_role' = 'owner'
      or exists (
        select 1
        from public.appointments a
        join public.profiles p on p.id = a.profile_id
        where a.id = appointment_resources.appointment_id
          and a.business_id = public.get_user_business_id()
          and p.phone_number = (auth.jwt()->>'phone_number')
      )
    )
  );

create policy ar_owner_manage on public.appointment_resources
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- SERVICE_RESOURCE_REQUIREMENTS
drop policy if exists srr_read_all on public.service_resource_requirements;
create policy srr_read_all on public.service_resource_requirements 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists srr_owner_write on public.service_resource_requirements;
create policy srr_owner_write on public.service_resource_requirements 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- RESOURCE_BLOCKS
drop policy if exists rb_read_all on public.resource_blocks;
create policy rb_read_all on public.resource_blocks 
  for select to authenticated
  using (business_id = public.get_user_business_id());

drop policy if exists rb_owner_write on public.resource_blocks;
create policy rb_owner_write on public.resource_blocks 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

-- KNOWLEDGE_SUGGESTIONS
drop policy if exists ks_insert_authenticated on public.knowledge_suggestions;
create policy ks_insert_authenticated on public.knowledge_suggestions 
  for insert to authenticated
  with check (business_id = public.get_user_business_id());

drop policy if exists ks_read_own on public.knowledge_suggestions;
create policy ks_read_own on public.knowledge_suggestions 
  for select to authenticated
  using (
    business_id = public.get_user_business_id()
    and (
      auth.jwt()->>'user_role' = 'owner'
      or exists (
        select 1 from public.profiles p 
        where p.id = knowledge_suggestions.profile_id 
          and p.phone_number = (auth.jwt()->>'phone_number')
      )
    )
  );

drop policy if exists ks_owner_manage on public.knowledge_suggestions;
create policy ks_owner_manage on public.knowledge_suggestions 
  for all to authenticated
  using (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  )
  with check (
    auth.jwt()->>'user_role' = 'owner'
    and business_id = public.get_user_business_id()
  );

commit;
