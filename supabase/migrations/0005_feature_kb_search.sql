-- 1. FUNCIÓN HELPER DE NORMALIZACIÓN
create or replace function public.norm_txt(p text)
returns text
language sql
immutable
as $$
select lower(regexp_replace(unaccent(coalesce(p,'')), '\s+', ' ', 'g'))
$$;
comment on function public.norm_txt is 'Normaliza texto: minúsculas, sin acentos, espacios colapsados';

-- 2. COLUMNAS GENERADAS Y TRACKING DE VISTAS
-- Se asume que la tabla knowledge_base ya existe desde 0002.
-- Se eliminan las definiciones obsoletas de question_normalized si existen.
alter table public.knowledge_base drop column if exists question_normalized;
alter table public.knowledge_base
add column if not exists question_normalized text;

alter table public.knowledge_base
add column if not exists answer_normalized text
generated always as (public.norm_txt(answer)) stored;

alter table public.knowledge_base
add column if not exists view_count int not null default 0;

-- 3. TRIGGER DE NORMALIZACIÓN y BACKFILL
create or replace function public.kb_set_question_normalized()
returns trigger language plpgsql as $$
begin
new.question_normalized := public.norm_txt(new.question);
return new;
end $$;

drop trigger if exists trg_kb_norm on public.knowledge_base;
create trigger trg_kb_norm
before insert or update of question on public.knowledge_base
for each row execute function public.kb_set_question_normalized();

-- Backfill de question_normalized para registros existentes
update public.knowledge_base
set question_normalized = public.norm_txt(question)
where question_normalized is distinct from public.norm_txt(question);

-- Asegurar que question_normalized es NOT NULL y UNIQUE
alter table public.knowledge_base
alter column question_normalized set not null;

do $$
begin
if not exists (
select 1 from pg_constraint
where conrelid = 'public.knowledge_base'::regclass
and conname = 'knowledge_base_question_key'
) then
alter table public.knowledge_base
add constraint knowledge_base_question_key unique (question_normalized);
end if;
end $$;


-- 4. ÍNDICES AVANZADOS (TRGM y view_count)
create index if not exists idx_kb_qnorm_trgm
on public.knowledge_base using gin (question_normalized gin_trgm_ops);

create index if not exists idx_kb_answer_trgm
on public.knowledge_base using gin (answer_normalized gin_trgm_ops);

create index if not exists idx_kb_view_count
on public.knowledge_base(view_count desc);

-- Se eliminan los índices TRGM sobre la columna original 'question' si existen.
drop index if exists idx_kb_question_trgm;

-- 5. FUNCIONES DE BÚSQUEDA

-- Búsqueda por Similitud
create or replace function public.search_knowledge_base(
    p_query text,
    p_similarity_threshold double precision default 0.20,
    p_limit int default 5
)
returns table(id uuid, category text, question text, answer text, similarity double precision)
language sql
stable
as $$
select
    kb.id, kb.category, kb.question, kb.answer,
    similarity(kb.question_normalized, public.norm_txt(p_query)) as sim
from public.knowledge_base kb
where similarity(kb.question_normalized, public.norm_txt(p_query)) > p_similarity_threshold
order by sim desc
limit p_limit
$$;
comment on function public.search_knowledge_base is 'Búsqueda por similitud usando pg_trgm';

-- Búsqueda por Keywords
create or replace function public.search_knowledge_by_keywords(
    p_keywords text[],
    p_limit int default 5
)
returns table(id uuid, category text, question text, answer text, keyword_matches int)
language sql
stable
as $$
select
    kb.id, kb.category, kb.question, kb.answer,
    (
        select count(*)
        from unnest(p_keywords) as kw
        where kb.question_normalized ilike ('%' || public.norm_txt(kw) || '%')
        or kb.answer_normalized ilike ('%' || public.norm_txt(kw) || '%')
    )::int as keyword_matches
from public.knowledge_base kb
where exists (
    select 1
    from unnest(p_keywords) as kw
    where kb.question_normalized ilike ('%' || public.norm_txt(kw) || '%')
    or kb.answer_normalized ilike ('%' || public.norm_txt(kw) || '%')
)
order by keyword_matches desc, kb.id
limit p_limit
$$;
comment on function public.search_knowledge_by_keywords is 'Búsqueda por palabras clave';

-- Búsqueda Híbrida (Versión CORREGIDA con pesos y p_category)
drop function if exists public.search_knowledge_hybrid(text, double precision, int);
drop function if exists public.search_knowledge_hybrid(text, double precision, int, text); -- Eliminar versiones antiguas/duplicadas
create or replace function public.search_knowledge_hybrid(
    p_query text,
    p_similarity_threshold double precision default 0.15,
    p_limit int default 5,
    p_category text default null
)
returns table(id uuid, category text, question text, answer text, relevance_score double precision, match_type text)
language plpgsql
stable
as $$
declare
    vq text;
    v_keywords text[];
begin
    vq := public.norm_txt(p_query);
    select array_agg(w) into v_keywords
    from (
        select word as w
        from regexp_split_to_table(vq, '\s+') as word
        where length(word) >= 3
    ) q;

    return query
    with base as (
        select
            kb.id as kb_id,
            kb.category as kb_category,
            kb.question as kb_question,
            kb.answer as kb_answer,
            kb.question_normalized as kb_question_normalized,
            kb.answer_normalized as kb_answer_normalized
        from public.knowledge_base kb
        where (p_category is null or kb.category = p_category)
    ),
    similarity_results as (
        select
            b.kb_id, b.kb_category, b.kb_question, b.kb_answer,
            similarity(b.kb_question_normalized, vq) * 100.0 as score,
            'similarity'::text as match_type
        from base b
        where similarity(b.kb_question_normalized, vq) > p_similarity_threshold
    ),
    keyword_results as (
        select
            b.kb_id, b.kb_category, b.kb_question, b.kb_answer,
            (
                -- Pesos diferenciados: pregunta (24 pts) > respuesta (16 pts)
                select (sum(case when b.kb_question_normalized ilike ('%' || kw || '%') then 1 else 0 end) * 24.0)
                + (sum(case when b.kb_answer_normalized ilike ('%' || kw || '%') then 1 else 0 end) * 16.0)
                from unnest(coalesce(v_keywords, array[]::text[])) as kw
            ) as score,
            'keywords'::text as match_type
        from base b
        where exists (
            select 1
            from unnest(coalesce(v_keywords, array[]::text[])) as kw
            where b.kb_question_normalized ilike ('%' || kw || '%')
            or b.kb_answer_normalized ilike ('%' || kw || '%')
        )
    ),
    combined as (
        select * from similarity_results
        union all
        select * from keyword_results
    )
    select
        c.kb_id, c.kb_category, c.kb_question, c.kb_answer,
        max(c.score) as relevance_score,
        string_agg(distinct c.match_type, '+' order by c.match_type) as match_type
    from combined c
    group by c.kb_id, c.kb_category, c.kb_question, c.kb_answer
    order by relevance_score desc
    limit p_limit;
end
$$;
comment on function public.search_knowledge_hybrid is 'Búsqueda híbrida con scoring. Pregunta 24pts, Respuesta 16pts. Soporta filtro por categoría. CORREGIDA: sin ambigüedad de columnas.';


-- Preguntas Relacionadas
create or replace function public.get_related_questions(
    p_question_id uuid,
    p_limit int default 3
)
returns table(id uuid, category text, question text, similarity double precision)
language sql
stable
as $$
select
    kb2.id, kb2.category, kb2.question,
    similarity(kb1.question_normalized, kb2.question_normalized) as sim
from public.knowledge_base kb1
cross join public.knowledge_base kb2
where kb1.id = p_question_id
and kb2.id != p_question_id
and similarity(kb1.question_normalized, kb2.question_normalized) > 0.15
order by sim desc
limit p_limit
$$;
comment on function public.get_related_questions is 'Obtiene preguntas similares';


-- 6. TRACKING DE POPULARIDAD
create table if not exists public.kb_views_footprint (
    kb_id uuid not null,
    phone_hash text not null,
    last_view timestamptz not null,
    primary key (kb_id, phone_hash)
);
comment on table public.kb_views_footprint is 'Registro de huella de usuario/pregunta para rate-limiting de vistas KB.';

-- Vista de Preguntas Populares
create or replace view public.knowledge_popular_questions as
select
    id, category, question, view_count, created_at
from public.knowledge_base
where view_count > 0
order by view_count desc, created_at desc
limit 10;

-- Función de incremento con rate-limit y LOCKS (Versión CORREGIDA/ROBUSTA)
create or replace function public.increment_kb_view_count_guarded(
    p_question_id uuid,
    p_phone_hash text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_should_increment boolean := false;
    v_last_view timestamptz;
    v_lock_id bigint;
begin
    -- Generar un ID de lock único basado en kb_id + phone_hash
    v_lock_id := hashtext(p_question_id::text || p_phone_hash);
    -- Adquirir lock advisory (bloquea otras sesiones con el mismo lock_id)
    perform pg_advisory_xact_lock(v_lock_id);

    -- Consultar el último registro de visualización
    select last_view into v_last_view
    from public.kb_views_footprint
    where kb_id = p_question_id and phone_hash = p_phone_hash;

    -- Determinar si incrementar ANTES de modificar last_view
    if v_last_view is null then
        v_should_increment := true;
    elsif now() - v_last_view > interval '60 seconds' then
        v_should_increment := true;
    end if;

    -- Actualizamos o insertamos el registro de visualización
    insert into public.kb_views_footprint(kb_id, phone_hash, last_view)
    values (p_question_id, p_phone_hash, now())
    on conflict (kb_id, phone_hash)
    do update set last_view = now();

    -- Si determinamos que debemos incrementar, lo hacemos
    if v_should_increment then
        update public.knowledge_base
        set view_count = view_count + 1
        where id = p_question_id;
    end if;
end $$;
comment on function public.increment_kb_view_count_guarded is 'Incrementa view_count con rate-limiting (60s). Usa advisory locks para prevenir race conditions. CORREGIDA: evalúa condición ANTES de actualizar last_view.';

-- Función simple (sin rate-limit, para desarrollo/debug)
create or replace function public.increment_kb_view_count(p_question_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
update public.knowledge_base
set view_count = view_count + 1
where id = p_question_id
$$;
comment on function public.increment_kb_view_count is 'Incrementa view_count (sin rate-limit)';


-- 7. TABLA DE SUGERENCIAS
create table if not exists public.knowledge_suggestions (
    id uuid primary key default gen_random_uuid(),
    profile_id uuid references public.profiles(id) on delete set null,
    suggested_question text not null,
    context text,
    status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
    created_at timestamptz not null default now(),
    reviewed_at timestamptz,
    reviewed_by uuid references public.profiles(id)
);
comment on table public.knowledge_suggestions is 'Sugerencias de usuarios para ampliar KB';

create index if not exists idx_ks_status on public.knowledge_suggestions(status);
create index if not exists idx_ks_created on public.knowledge_suggestions(created_at desc);
