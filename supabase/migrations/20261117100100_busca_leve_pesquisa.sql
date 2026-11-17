-- Missão servidor-busca-leve-2026-11-17, bloco B1 (1.3, 1.4 e 1.6). APLICA A CLAUDE.AI, depois da
-- 20261117100000 e do enchimento de produtos_busca_ns (APLICAR.md, passos 1 a 4).
--
-- pesquisa_produtos: os MESMOS passos e as MESMAS contas de pontuação; muda só ONDE se vai buscar o
-- que já se calculava:
--   a) ns, nr e cs vêm de produtos_busca_ns quando o nome e a categoria guardados são iguais aos do
--      produto; senão calcula-se na hora com bora_ns/bora_nr (o mesmo texto de antes). Resultado
--      igual mesmo com a tabela atrasada. (antes: ~12 regex por candidato, ~215 ms em "frango")
--   b) a linha guardada lê-se pela chave numa subconsulta escalar, uma vez por candidato, e o cand
--      fica "materialized" como já ficava antes: ensaiei juntar a tabela com JOIN/LATERAL e o
--      planeador trocava de plano (umas pesquisas ficavam 3-10x mais lentas); assim o plano dos
--      candidatos é o mesmo de hoje.
--   c) os padrões '% palavra %', '% palavra%' e ' palavra%' calculam-se uma vez por palavra (alt2)
--      e não uma vez por candidato e palavra (41 100 vezes em "frango").
--   d) LANGUAGE plpgsql com RETURN QUERY: o plano fica guardado na ligação. Em LANGUAGE sql o
--      Postgres 17 voltava a planear as ~35 CTE em cada chamada (23 ms no "frango").
--   #variable_conflict use_column: nomes de colunas iguais às colunas de saída resolvem-se para a
--   coluna, como numa função sql (onde as colunas de saída nem são variáveis).
-- search_products: as secções vêm de seccoes_disponiveis (mesmas regras de leitura de products) em
-- vez do DISTINCT nos ~51 mil produtos disponíveis. O resto igual (mínimo de 3 letras de 17/11).

-- carrega o pg_trgm nesta sessão: sem isto o SET pg_trgm.word_similarity_threshold da função dá
-- "permission denied to set parameter" (erro aprendido a 16/11).
select extensions.similarity('a', 'b');

create or replace function public.pesquisa_produtos(p_q text, p_restaurant_id text default null::text, p_limit integer default 50, p_embedding vector default null::vector)
 returns table(id text, name text, category text, category_root text, price numeric, photo_url text, restaurant_id text, match_kind text, score real)
 language plpgsql
 stable
 set search_path to 'public', 'extensions', 'pg_temp'
 set "pg_trgm.word_similarity_threshold" to '0.45'
as $function$
#variable_conflict use_column
begin
return query
-- CORPO-INICIO
with
q as (
  select btrim(regexp_replace(public.bora_normalize(p_q), '\s+', ' ', 'g')) as qn,
         greatest(1, least(coalesce(p_limit, 50), 200)) as lim
),
pal as (
  select row_number() over (order by x.o) as i, x.w, public.assistant_singular(x.w) as t
    from q cross join lateral regexp_split_to_table(q.qn, ' ') with ordinality as x(w, o)
   where length(q.qn) >= 2
     and x.w <> ''
     and x.w not in ('de','da','do','das','dos','em','e','a','o','os','as','para','p','ao','aos',
                     'na','no','nas','nos','c','um','uma','ou','pra',
                     'kg','g','gr','grs','ml','cl','lt','un','und','unid','unidade','unidades',
                     'emb','embalagem','pack','litro','litros','quilo','quilos','kilo')
),
nq as (
  select count(*)::int as n, coalesce(string_agg(t, ' ' order by i), '') as qs from pal
),
sin as (
  select s.alvo_chave, s.product_id, pl.i, false as frase
    from pal pl
    join public.pesquisa_sinonimos s
      on s.ativo
     and (s.restaurant_id is null or p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
     and strpos(s.chave, ' ') = 0
     and (s.chave = pl.t or s.chave = pl.w
          or (length(pl.t) >= 5 and length(s.chave) >= 5 and extensions.similarity(s.chave, pl.t) >= 0.6))
  union all
  select s.alvo_chave, s.product_id, null::bigint, true
    from nq
    join public.pesquisa_sinonimos s
      on s.ativo
     and (s.restaurant_id is null or p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
     and strpos(s.chave, ' ') > 0
     and s.chave = nq.qs
),
alt as (
  select pal.i, pal.t as a, 0 as tipo from pal
  union select pal.i, pal.w, 0 from pal
  union select pal.i, replace(pal.t, 'ct', 't'), 0 from pal where strpos(pal.t, 'ct') > 0
  union select sin.i, sin.alvo_chave, 1 from sin where not sin.frase and sin.alvo_chave is not null
),
-- (c) os três padrões de cada alternativa, uma vez só
alt2 as (
  select alt.i, alt.a, alt.tipo,
         '% ' || alt.a || ' %' as p_inteira,
         '% ' || alt.a || '%' as p_comeco,
         ' ' || alt.a || '%' as p_abre
    from alt
),
falt as (
  select distinct sin.alvo_chave as a from sin where sin.frase and sin.alvo_chave is not null
),
fixo as (
  select distinct sin.i, sin.product_id from sin where sin.product_id is not null
),
rx as (
  select string_agg(distinct z.v, '|') as v from (
    select alt.a as v from alt where length(alt.a) >= 2
    union select falt.a from falt where length(falt.a) >= 2
    union select regexp_replace(pal.t, 'ao$', 'aes') from pal where pal.t ~ 'ao$'
    union select regexp_replace(pal.t, 'ao$', 'oes') from pal where pal.t ~ 'ao$'
    union select regexp_replace(pal.t, 'al$', 'ais') from pal where pal.t ~ 'al$'
    union select regexp_replace(pal.t, 'el$', 'eis') from pal where pal.t ~ 'el$'
    union select regexp_replace(pal.t, 'm$', 'ns') from pal where pal.t ~ 'm$'
  ) z
),
-- candidatos pelo índice de trigramas (GIN em search_normalized), depois a loja (igual a antes)
cand_ids as materialized (
  select p0.id from public.products p0
   where p0.search_normalized ~ (select rx.v from rx)
  union
  select fixo.product_id from fixo
),
-- materialized: antes o cand era lido por duas CTE (catn e cn) e por isso ficava materializado; agora
-- só o cn o lê e o Postgres iria fundi-lo no cn e trocar de plano (medido: pior). Fica como era.
cand as materialized (
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id,
         coalesce(p.is_popular, false) as popular
    from public.products p
   where p.id in (select cand_ids.id from cand_ids)
     and p.is_available
     and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
     and (p_restaurant_id is not null or exists (
           select 1 from public.restaurants r
            where r.id = p.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
),
-- (a) ns = o nome como a pesquisa o compara; cs = o mesmo para a categoria; nr = o nome tal como
-- foi escrito, sem acentos. Guardados em produtos_busca_ns; se a linha guardada não for do nome e
-- da categoria de agora, calcula-se na hora (o mesmo texto de antes, em bora_ns/bora_nr).
-- A linha guardada lê-se pela chave, uma vez por candidato, numa subconsulta escalar (o planeador
-- não a transforma numa junção à tabela inteira; "offset 0" faz com que corra uma vez só por linha).
cn as (
  select z.id, z.name, z.category, z.category_root, z.price, z.photo_url, z.restaurant_id, z.popular,
         case when (z.b).product_id is not null and (z.b).nome is not distinct from z.name
              then (z.b).ns else public.bora_ns(z.name) end as ns,
         case when (z.b).product_id is not null and (z.b).categoria is not distinct from z.category
              then (z.b).cs else public.bora_ns(z.category) end as cs,
         case when (z.b).product_id is not null and (z.b).nome is not distinct from z.name
              then (z.b).nr else public.bora_nr(z.name) end as nr
    from (select c.*,
                 (select b0 from public.produtos_busca_ns b0 where b0.product_id = c.id) as b
            from cand c
          offset 0) z
),
forca as (
  select c.id, pl.i,
         coalesce(max(case when a.tipo = 0 then
           case when c.ns like a.p_inteira then 1.0
                when length(a.a) >= 3 and c.ns like a.p_comeco then 0.75
                when length(a.a) >= 4 and strpos(c.ns, a.a) > 0 then 0.6
                else 0 end end), 0) as fo,
         greatest(
           coalesce(max(case when a.tipo = 1 then
             case when c.ns like a.p_inteira then 0.85
                  when length(a.a) >= 3 and c.ns like a.p_comeco then 0.7
                  when length(a.a) >= 4 and strpos(c.ns, a.a) > 0 then 0.55
                  else 0 end end), 0),
           case when exists (select 1 from fixo f where f.i = pl.i and f.product_id = c.id) then 0.9 else 0 end
         ) as fs,
         coalesce(max(case when length(a.a) >= 3 and c.cs like a.p_comeco then 0.4 else 0 end), 0) as fc,
         coalesce(bool_or(pl.i = 1 and length(a.a) >= 3 and c.ns like a.p_abre), false) as abre
    from cn c
    cross join pal pl
    join alt2 a on a.i = pl.i
   group by c.id, pl.i
),
agg as (
  select f.id,
         count(*) filter (where f.fo > 0) as ok_o,
         count(*) filter (where greatest(f.fo, f.fs) > 0) as ok_n,
         count(*) filter (where greatest(f.fo, f.fs, f.fc) > 0) as ok_c,
         coalesce(bool_or(f.i = 1 and f.fo > 0), false) as ok1,
         avg(greatest(f.fo, f.fs, f.fc)) as media,
         coalesce(bool_or(f.abre), false) as abre
    from forca f
   group by f.id
),
fr as (
  select distinct c.id from cn c join falt on c.ns like '% ' || falt.a || '%'
),
princ as (
  select c.id, c.name, c.category, c.category_root, c.price, c.photo_url, c.restaurant_id,
         k.kind,
         (case k.kind when 'exato' then 6.0 when 'comeca' then 5.0 when 'texto' then 4.0
                      when 'sinonimo' then 3.5 when 'categoria' then 3.0 else 1.0 end
          + 0.5 * coalesce(g.media, 0.5)
          + case when c.ns like ' ' || nq.qs || '%' then 0.3
                 when coalesce(g.abre, false) then 0.15 else 0 end
          -- a frase inteira, tal como foi escrita ("vitamina c"), aparece no nome
          + case when c.nr like '% ' || q.qn || ' %' then 0.15 else 0 end
          + case when c.popular then 0.05 else 0 end
          - least(length(c.name), 120) / 1000.0) as score,
         k.kind <> 'parcial' as cheio
    from cn c
    cross join nq
    cross join q
    left join agg g on g.id = c.id
    cross join lateral (
      select case
        when nq.n = 0 then null
        when c.ns = ' ' || nq.qs || ' ' then 'exato'
        when g.ok_o = nq.n and c.ns like ' ' || nq.qs || '%' then 'comeca'
        when g.ok_o = nq.n and c.ns like ' ' || (select pal.t from pal where pal.i = 1) || '%' then 'comeca'
        when g.ok_o = nq.n then 'texto'
        when nq.n >= 3 and g.ok_o >= nq.n - 1 and g.ok1 then 'texto'
        when g.ok_n = nq.n or c.id in (select fr.id from fr) then 'sinonimo'
        when g.ok_c = nq.n then 'categoria'
        when coalesce(g.ok_c, 0) >= 1 then 'parcial'
        else null end as kind
    ) k
   where k.kind is not null
),
-- erros de escrita: só se o texto deu menos de 5 produtos certos, e começando
-- pelas palavras que menos acharam (ex.: "papel higenico" → "higenico" primeiro)
gate1 as (
  select count(*) < 5 and (select nq.n from nq) > 0 as abrir
    from (select 1 from princ where princ.cheio limit 5) z
),
falha as (
  select pal.i, pal.t, row_number() over (order by coalesce(m.n, 0), pal.i) as k
    from pal
    left join (select f.i, count(*) filter (where greatest(f.fo, f.fs) > 0) as n
                 from forca f group by f.i) m
      on m.i = pal.i
   where (select gate1.abrir from gate1)
     and length(pal.t) >= 4
     and coalesce(m.n, 0) < 3
),
fz_ids as materialized (
  select p0.id from public.products p0
   where (select falha.t from falha where falha.k = 1) operator(extensions.<%) p0.search_normalized
  union
  select p0.id from public.products p0
   where (select falha.t from falha where falha.k = 2) operator(extensions.<%) p0.search_normalized
  union
  select p0.id from public.products p0
   where p0.search_normalized ~ (select regexp_replace(regexp_replace(falha.t, '(.)\1+', '\1', 'g'), '(.)', '\1+', 'g')
                                   from falha where falha.k = 1)
),
fzc as (
  select z.id, z.name, z.category, z.category_root, z.price, z.photo_url, z.restaurant_id, z.popular,
         case when (z.b).product_id is not null and (z.b).nome is not distinct from z.name
              then (z.b).ns else public.bora_ns(z.name) end as ns
    from (select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id,
                 coalesce(p.is_popular, false) as popular,
                 (select b0 from public.produtos_busca_ns b0 where b0.product_id = p.id) as b
            from public.products p
           where p.id in (select fz_ids.id from fz_ids)
             and p.is_available
             and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
             and (p_restaurant_id is not null or exists (
                   select 1 from public.restaurants r
                    where r.id = p.restaurant_id and r.approval_status = 'approved'
                      and coalesce(r.is_active_admin, true)))
          offset 0) z
),
fzf as (
  select c.id, pl.i,
         greatest(
           case when c.ns like '% ' || pl.t || '%' then 0.75
                when length(pl.t) >= 4 and strpos(c.ns, pl.t) > 0 then 0.6 else 0 end,
           case when length(pl.t) >= 4
                 and strpos(regexp_replace(replace(replace(replace(replace(c.ns, 'ch', 'x'), 'sh', 'x'), 'ph', 'f'), 'y', 'i'), '(.)\1+', '\1', 'g'),
                            regexp_replace(replace(replace(replace(replace(pl.t, 'ch', 'x'), 'sh', 'x'), 'ph', 'f'), 'y', 'i'), '(.)\1+', '\1', 'g')) > 0
                then 0.7 else 0 end,
           case when length(pl.t) >= 4 and extensions.word_similarity(pl.t, c.ns) >= 0.45
                then 0.3 + 0.5 * extensions.word_similarity(pl.t, c.ns) else 0 end,
           coalesce((select max(case when c.ns like '% ' || a.a || '%' then 0.7 else 0 end)
                       from alt a where a.i = pl.i and a.tipo = 1), 0)
         ) as f
    from fzc c cross join pal pl
),
fzr as (
  select c.id, c.name, c.category, c.category_root, c.price, c.photo_url, c.restaurant_id,
         'parecido'::text as kind,
         (2.5 + 0.5 * case when length(replace(nq.qs, ' ', '')) >= 5
                            and strpos(replace(c.ns, ' ', ''), replace(nq.qs, ' ', '')) > 0 then 0.95
                           else g.media end
          + case when c.popular then 0.05 else 0 end
          - least(length(c.name), 120) / 1000.0) as score,
         true as cheio
    from fzc c
    cross join nq
    join (select fzf.id, count(*) filter (where fzf.f > 0) as ok, avg(fzf.f) as media
            from fzf group by fzf.id) g on g.id = c.id
   where g.ok = nq.n
      or (length(replace(nq.qs, ' ', '')) >= 5
          and strpos(replace(c.ns, ' ', ''), replace(nq.qs, ' ', '')) > 0)
),
-- significado (vetores): só quando ainda há menos de 3 produtos certos
gate2 as (
  select count(*) < 3 and (select nq.n from nq) > 0 as abrir from (
    select 1 from princ where princ.cheio
    union all select 1 from fzr
    limit 3) z
),
vq as (
  select coalesce(
           p_embedding,
           (select extensions.avg(e.embedding) from (
              select g.embedding
                from public.products p2
                join public.product_embeddings_gte g on g.product_id = p2.id
               where p2.is_available
                 and p2.search_normalized ~ ('(^| )(' || (select rx.v from rx) || ')')
               limit 30) e)
         ) as v
   where (select gate2.abrir from gate2)
),
-- loja pequena (até 3000 produtos): distância a todos os produtos dela;
-- loja grande ou lupa: os 300 mais perto pelo índice HNSW, depois filtra.
pequena as (
  select p_restaurant_id is not null
         and (select count(*) from public.products p3
               where p3.restaurant_id = p_restaurant_id and p3.is_available) <= 3000 as sim
),
sem_ids as (
  (select g.product_id, 1 - (g.embedding operator(extensions.<=>) (select vq.v from vq)) as sim
     from public.product_embeddings_gte g
    where (select extensions.vector_dims(vq.v) = 384 from vq) and not (select pequena.sim from pequena)
    order by g.embedding operator(extensions.<=>) (select vq.v from vq)
    limit 300)
  union all
  (select g.product_id, 1 - (g.embedding operator(extensions.<=>) (select vq.v from vq)) as sim
     from public.products p4
     join public.product_embeddings_gte g on g.product_id = p4.id
    where (select extensions.vector_dims(vq.v) = 384 from vq) and (select pequena.sim from pequena)
      and p4.restaurant_id = p_restaurant_id and p4.is_available)
  union all
  (select g.product_id, 1 - (g.embedding operator(extensions.<=>) (select vq.v from vq)) as sim
     from public.product_embeddings g
    where (select extensions.vector_dims(vq.v) = 768 from vq)
    order by g.embedding operator(extensions.<=>) (select vq.v from vq)
    limit 300)
),
sem as (
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id, si.sim
    from sem_ids si
    join public.products p on p.id = si.product_id
   where p.is_available
     and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
),
semr as (
  select s.id, s.name, s.category, s.category_root, s.price, s.photo_url, s.restaurant_id,
         'significado'::text as kind, (1.5 + s.sim)::float8 as score, false as cheio
    from sem s
   where s.sim >= 0.93
     and s.sim >= (select max(s2.sim) from sem s2) - 0.015
     and (p_restaurant_id is not null or exists (
           select 1 from public.restaurants r
            where r.id = s.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
   order by s.sim desc
   limit 8
),
todos as (
  select princ.id, princ.name, princ.category, princ.category_root, princ.price, princ.photo_url,
         princ.restaurant_id, princ.kind, princ.score::float8 as score from princ
  union all
  select fzr.id, fzr.name, fzr.category, fzr.category_root, fzr.price, fzr.photo_url,
         fzr.restaurant_id, fzr.kind, fzr.score::float8 from fzr
  union all
  select semr.id, semr.name, semr.category, semr.category_root, semr.price, semr.photo_url,
         semr.restaurant_id, semr.kind, semr.score from semr
),
melhor as (
  select distinct on (todos.id) todos.* from todos order by todos.id, todos.score desc
)
select m.id, m.name, m.category, m.category_root, m.price, m.photo_url, m.restaurant_id,
       m.kind, m.score::real
  from melhor m
 order by m.score desc, m.name
 limit (select q.lim from q)
-- CORPO-FIM
;
end
$function$;

-- os mesmos privilégios de antes (create or replace mantém-nos; isto só os confirma)
grant execute on function public.pesquisa_produtos(text, text, integer, vector) to anon, authenticated, service_role;

create or replace function public.search_products(query_text text, p_restaurant_id text default null::text, max_results integer default 50)
 returns table(result_type text, id text, name text, category text, category_root text, price numeric, photo_url text, match_rank real)
 language sql
 stable
 set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  -- 17/11 (servidor-busca-leve, 1.4): as secções vêm de seccoes_disponiveis (390 linhas, mantida por
  -- gatilho, mesmas regras de leitura de products) em vez de DISTINCT nos ~51 mil produtos.
  with cats as materialized (
    select distinct s.category_root as cr
      from public.seccoes_disponiveis s
     where (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
  ),
  q as (
    select btrim(regexp_replace(public.bora_normalize(query_text), '\s+', ' ', 'g')) as qn
  ),
  sec as (
    select z.cr, (10 + extensions.similarity(public.bora_normalize(z.cr), q.qn))::real as rank
      from q, cats z
     where length(q.qn) >= 2
       and (' ' || public.bora_normalize(z.cr)) like '% ' || q.qn || '%'
     order by 2 desc
     limit 3
  )
  select 'section'::text, null::text, sec.cr, null::text, sec.cr, null::numeric, null::text, sec.rank
    from sec
  union all
  select 'product'::text, r.id, r.name, r.category, r.category_root, r.price, r.photo_url, r.score
    from q
    cross join lateral public.pesquisa_produtos(query_text, p_restaurant_id,
                                  greatest(1, least(coalesce(max_results, 50), 200))) r
   where length(replace(q.qn, ' ', '')) >= 3
  order by 8 desc
$function$;
