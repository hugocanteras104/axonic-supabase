-- 0005_feature_kb_search.sql
-- Funciones y estructuras para la Knowledge Base (KB)

-- ==========================================
-- 1) Normalización de texto
-- ==========================================
create or replace function public.norm_txt(p text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(unaccent(coalesce(p,'')), '\s+', ' ', 'g'))
$$;

-- ==========================================
-- 2) Columnas derivadas y métricas de KB
-- ==========================================
alter table public.knowledge_base
  add column if not exists question_normalized text;

alter table public.knowledge_base
  add column if not exists answer_normalized text
  generated always as (public.norm_txt(answer)) stored;

alter table public.knowledge_base
  add column if not exists view_count int not null default 0;

-- Trigger para mantener question_normalized
create or replace function public.kb_set_question_normalized()
returns trigger
language plpgsql
as $$
begin
  new.question_normalized := public.norm_txt(new.question);
  return new;
end;
$$;

drop trigger if exists trg_kb_question_normalized on public.knowledge_base;
create trigger trg_kb_question_normalized
before insert or update of question on public.knowledge_base
for each row execute function public.kb_set_question_normalized();

-- Backfill inicial
update public.knowledge_base
set question_normalized = public.norm_txt(question)
where question_normalized is null;

-- ==========================================
-- 3) Índices de búsqueda
-- ==========================================
create index if not exists idx_kb_qnorm_trgm
  on public.knowledge_base using gin (question_normalized gin_trgm_ops);

create index if not exists idx_kb_anorm_trgm
  on public.knowledge_base using gin (answer_normalized gin_trgm_ops);

create index if not exists idx_kb_view_count
  on public.knowledge_base(view_count);

-- ==========================================
-- 4) Funciones de búsqueda
-- ==========================================

-- Búsqueda por similitud en question_normalized
create or replace function public.search_knowledge_base(p_query text, p_limit int default 5)
returns table (id uuid, question text, answer text, similarity real)
language sql
stable
as $$
  select k.id, k.question, k.answer,
         similarity(public.norm_txt(p_query), k.question_normalized) as sim
  from public.knowledge_base k
  where k.question_normalized % public.norm_txt(p_query)
  order by sim desc
  limit p_limit;
$$;

-- Búsqueda por keywords en answer_normalized
create or replace function public.search_knowledge_by_keywords(p_keywords text[], p_limit int default 5)
returns table (id uuid, question text, answer text, matched_keywords int)
language sql
stable
as $$
  select k.id, k.question, k.answer,
         cardinality(array(
           select unnest(p_keywords)
           intersect
           select unnest(string_to_array(k.answer_normalized,' '))
         )) as matched_keywords
  from public.knowledge_base k
  order by matched_keywords desc
  limit p_limit;
$$;

-- Búsqueda híbrida (CORREGIDA)
create or replace function public.search_knowledge_hybrid(
  p_query text,
  p_keywords text[] default '{}',
  p_category text default null,
  p_limit int default 5
)
returns table (id uuid, question text, answer text, score real)
language sql
stable
as $$
  with base as (
    select k.id, k.question, k.answer,
           similarity(public.norm_txt(p_query), k.question_normalized) as sim,
           cardinality(array(
             select unnest(p_keywords)
             intersect
             select unnest(string_to_array(k.answer_normalized,' '))
           )) as kw_count
    from public.knowledge_base k
    where (p_category is null or k.category = p_category)
  )
  select id, question, answer, (sim + (kw_count * 0.2)) as score
  from base
  order by score desc
  limit p_limit;
$$;

-- Relacionar preguntas similares
create or replace function public.get_related_questions(p_question_id uuid, p_limit int default 5)
returns table (id uuid, question text, similarity real)
language sql
stable
as $$
  select k2.id, k2.question,
         similarity(k1.question_normalized, k2.question_normalized) as sim
  from public.knowledge_base k1
  join public.knowledge_base k2 on k1.id <> k2.id
  where k1.id = p_question_id
  order by sim desc
  limit p_limit;
$$;

-- ==========================================
-- 5) Tracking de popularidad
-- ==========================================

-- Huella de vistas por usuario (hash del teléfono, etc.)
create table if not exists public.kb_views_footprint (
  kb_id uuid references public.knowledge_base(id) on delete cascade,
  phone_hash text not null,
  last_view timestamptz not null default now(),
  primary key (kb_id, phone_hash)
);

-- Función de incremento con rate-limit (CORREGIDA)
create or replace function public.increment_kb_view_count_guarded(
  p_kb_id uuid,
  p_phone_hash text,
  p_cooldown_secs int default 60
)
returns void
language plpgsql
as $$
declare
  v_last timestamptz;
begin
  select last_view into v_last
  from public.kb_views_footprint
  where kb_id = p_kb_id and phone_hash = p_phone_hash;

  if v_last is null or v_last < now() - make_interval(secs => p_cooldown_secs) then
    insert into public.kb_views_footprint(kb_id, phone_hash, last_view)
    values (p_kb_id, p_phone_hash, now())
    on conflict (kb_id, phone_hash) do update
      set last_view = excluded.last_view;

    update public.knowledge_base
    set view_count = view_count + 1
    where id = p_kb_id;
  end if;
end;
$$;

-- Vista de preguntas más vistas
create or replace view public.knowledge_popular_questions as
select id, question, answer, view_count
from public.knowledge_base
order by view_count desc
limit 20;

-- ==========================================
-- 6) Tabla de sugerencias de usuarios
-- ==========================================
create table if not exists public.knowledge_suggestions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade,
  question text not null,
  suggested_answer text,
  status text check (status in ('pending','approved','rejected')) default 'pending',
  created_at timestamptz default now(),
  reviewed_at timestamptz
);

create index if not exists idx_ksuggestions_status on public.knowledge_suggestions(status);
create index if not exists idx_ksuggestions_created_at on public.knowledge_suggestions(created_at);

-- ==========================================
-- 7) Permisos de funciones
-- ==========================================
revoke all on function public.search_knowledge_base(text, int) from public;
revoke all on function public.search_knowledge_by_keywords(text[], int) from public;
revoke all on function public.search_knowledge_hybrid(text, text[], text, int) from public;
revoke all on function public.get_related_questions(uuid, int) from public;
revoke all on function public.increment_kb_view_count_guarded(uuid, text, int) from public;

grant execute on function public.search_knowledge_base(text, int) to authenticated;
grant execute on function public.search_knowledge_by_keywords(text[], int) to authenticated;
grant execute on function public.search_knowledge_hybrid(text, text[], text, int) to authenticated;
grant execute on function public.get_related_questions(uuid, int) to authenticated;
grant execute on function public.increment_kb_view_count_guarded(uuid, text, int) to authenticated;

-- Fin 0005
