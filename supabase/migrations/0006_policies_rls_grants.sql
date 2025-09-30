-- 1. HABILITAR RLS en todas las tablas
alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.appointments enable row level security;
alter table public.inventory enable row level security;
alter table public.knowledge_base enable row level security;
alter table public.cross_sell_rules enable row level security;
alter table public.waitlists enable row level security;
alter table public.audit_logs enable row level security;
alter table public.notifications_queue enable row level security;
alter table public.resources enable row level security;
alter table public.service_resource_requirements enable row level security;
alter table public.appointment_resources enable row level security;
alter table public.resource_blocks enable row level security;
alter table public.knowledge_suggestions enable row level security;

-- RLS desactivado para tablas internas del bot, como kb_views_footprint
alter table public.kb_views_footprint disable row level security;
comment on table public.kb_views_footprint is 'Registro de huella de usuario/pregunta para rate-limiting de vistas KB. RLS está desactivado ya que solo el bot/funciones de seguridad interactúan con esta tabla.';

-- 2. POLÍTICAS RLS (DROP IF EXISTS + CREATE POLICY)

-- PROFILES
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (auth.jwt()->>'user_role' = 'owner' or phone_number = (auth.jwt()->>'phone_number'));
drop policy if exists profiles_owner_insert on public.profiles;
create policy profiles_owner_insert on public.profiles for insert to authenticated with check (auth.jwt()->>'user_role' = 'owner');
drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles for update to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');
drop policy if exists profiles_lead_update_self on public.profiles;
create policy profiles_lead_update_self on public.profiles for update to authenticated using (phone_number = (auth.jwt()->>'phone_number')) with check (phone_number = (auth.jwt()->>'phone_number'));
drop policy if exists profiles_owner_delete on public.profiles;
create policy profiles_owner_delete on public.profiles for delete to authenticated using (auth.jwt()->>'user_role' = 'owner');

-- SERVICES
drop policy if exists services_read_all on public.services;
create policy services_read_all on public.services for select to authenticated using (true);
drop policy if exists services_owner_write on public.services;
create policy services_owner_write on public.services for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

-- APPOINTMENTS
drop policy if exists appts_owner_all on public.appointments;
create policy appts_owner_all on public.appointments for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');
drop policy if exists appts_lead_read on public.appointments;
create policy appts_lead_read on public.appointments for select to authenticated using (exists (select 1 from public.profiles p where p.id = appointments.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));
drop policy if exists appts_lead_insert on public.appointments;
create policy appts_lead_insert on public.appointments for insert to authenticated with check (exists (select 1 from public.profiles p where p.id = appointments.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));
drop policy if exists appts_lead_update on public.appointments;
create policy appts_lead_update on public.appointments for update to authenticated using (exists (select 1 from public.profiles p where p.id = appointments.profile_id and p.phone_number = (auth.jwt()->>'phone_number'))) with check (exists (select 1 from public.profiles p where p.id = appointments.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));

-- INVENTORY
drop policy if exists inventory_read_all on public.inventory;
create policy inventory_read_all on public.inventory for select to authenticated using (true);
drop policy if exists inventory_owner_write on public.inventory;
create policy inventory_owner_write on public.inventory for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

-- KNOWLEDGE BASE
drop policy if exists kb_read_all on public.knowledge_base;
create policy kb_read_all on public.knowledge_base for select to authenticated using (true);
drop policy if exists kb_owner_write on public.knowledge_base;
create policy kb_owner_write on public.knowledge_base for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

-- CROSS SELL
drop policy if exists crosssell_read_all on public.cross_sell_rules;
create policy crosssell_read_all on public.cross_sell_rules for select to authenticated using (true);
drop policy if exists crosssell_owner_write on public.cross_sell_rules;
create policy crosssell_owner_write on public.cross_sell_rules for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

-- WAITLISTS
drop policy if exists waitlists_owner_all on public.waitlists;
create policy waitlists_owner_all on public.waitlists for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');
drop policy if exists waitlists_lead_read on public.waitlists;
create policy waitlists_lead_read on public.waitlists for select to authenticated using (exists (select 1 from public.profiles p where p.id = waitlists.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));
drop policy if exists waitlists_lead_insert on public.waitlists;
create policy waitlists_lead_insert on public.waitlists for insert to authenticated with check (exists (select 1 from public.profiles p where p.id = waitlists.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));
drop policy if exists waitlists_lead_update on public.waitlists;
create policy waitlists_lead_update on public.waitlists for update to authenticated using (exists (select 1 from public.profiles p where p.id = waitlists.profile_id and p.phone_number = (auth.jwt()->>'phone_number'))) with check (exists (select 1 from public.profiles p where p.id = waitlists.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));

-- AUDIT LOGS
drop policy if exists audit_owner_read on public.audit_logs;
create policy audit_owner_read on public.audit_logs for select to authenticated using (auth.jwt()->>'user_role' = 'owner');
drop policy if exists audit_insert_all on public.audit_logs;
create policy audit_insert_all on public.audit_logs for insert to authenticated with check (true);

-- NOTIFICATIONS QUEUE
drop policy if exists nq_owner_read on public.notifications_queue;
create policy nq_owner_read on public.notifications_queue for select to authenticated using (auth.jwt()->>'user_role' = 'owner');
drop policy if exists nq_insert_all on public.notifications_queue;
create policy nq_insert_all on public.notifications_queue for insert to authenticated with check (true);

-- KB SUGGESTIONS
drop policy if exists ks_insert_authenticated on public.knowledge_suggestions;
create policy ks_insert_authenticated on public.knowledge_suggestions for insert to authenticated with check (true);
drop policy if exists ks_read_own on public.knowledge_suggestions;
create policy ks_read_own on public.knowledge_suggestions for select to authenticated using (auth.jwt()->>'user_role' = 'owner' or exists (select 1 from public.profiles p where p.id = knowledge_suggestions.profile_id and p.phone_number = (auth.jwt()->>'phone_number')));
drop policy if exists ks_owner_manage on public.knowledge_suggestions;
create policy ks_owner_manage on public.knowledge_suggestions for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');
revoke all on table public.knowledge_suggestions from public, anon;

-- POLÍTICAS DE RECURSOS
drop policy if exists resources_read_all on public.resources;
create policy resources_read_all on public.resources for select to authenticated using (true);
drop policy if exists resources_owner_write on public.resources;
create policy resources_owner_write on public.resources for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

drop policy if exists srr_read_all on public.service_resource_requirements;
create policy srr_read_all on public.service_resource_requirements for select to authenticated using (true);
drop policy if exists srr_owner_write on public.service_resource_requirements;
create policy srr_owner_write on public.service_resource_requirements for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

drop policy if exists ar_read_owner on public.appointment_resources;
create policy ar_read_owner on public.appointment_resources for select to authenticated using (auth.jwt()->>'user_role' = 'owner' or exists (select 1 from public.appointments a join public.profiles p on p.id = a.profile_id where a.id = appointment_resources.appointment_id and p.phone_number = (auth.jwt()->>'phone_number')));
drop policy if exists ar_insert_all on public.appointment_resources;
create policy ar_insert_all on public.appointment_resources for insert to authenticated with check (true);

drop policy if exists rb_read_all on public.resource_blocks;
create policy rb_read_all on public.resource_blocks for select to authenticated using (true);
drop policy if exists rb_owner_write on public.resource_blocks;
create policy rb_owner_write on public.resource_blocks for all to authenticated using (auth.jwt()->>'user_role' = 'owner') with check (auth.jwt()->>'user_role' = 'owner');

-- 3. GRANTS DE FUNCIONES (RPCs y KB)

-- RPCs Generales
revoke execute on function public.decrement_inventory(text,int) from anon, authenticated;
grant execute on function public.decrement_inventory(text,int) to authenticated;
grant execute on function public.refresh_metrics_historical() to authenticated;

-- KB Search Functions
revoke all on function public.search_knowledge_base(text, double precision, int) from public, anon;
grant execute on function public.search_knowledge_base(text, double precision, int) to authenticated;

revoke all on function public.search_knowledge_by_keywords(text[], int) from public, anon;
grant execute on function public.search_knowledge_by_keywords(text[], int) to authenticated;

revoke all on function public.search_knowledge_hybrid(text, double precision, int, text) from public, anon;
grant execute on function public.search_knowledge_hybrid(text, double precision, int, text) to authenticated;

revoke all on function public.get_related_questions(uuid, int) from public, anon;
grant execute on function public.get_related_questions(uuid, int) to authenticated;

-- KB Tracking Functions
revoke all on function public.increment_kb_view_count(uuid) from public, anon;
grant execute on function public.increment_kb_view_count(uuid) to authenticated;

revoke all on function public.increment_kb_view_count_guarded(uuid, text) from public, anon;
grant execute on function public.increment_kb_view_count_guarded(uuid, text) to authenticated;

-- Grants para la tabla de tracking interna del KB (kb_views_footprint)
revoke all on public.kb_views_footprint from public, anon;
grant select, insert, update on public.kb_views_footprint to authenticated;

-- Grants para la vista de popularidad
revoke all on table public.knowledge_popular_questions from public, anon;
grant select on table public.knowledge_popular_questions to authenticated;

-- Resource RPCs
grant execute on function public.get_available_slots_with_resources(uuid,timestamptz,timestamptz,int) to authenticated;
grant execute on function public.confirm_appointment_with_resources(uuid,text) to authenticated;
