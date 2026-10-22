-- B2 (fechar-pendencias-2026-10-20) — pesquisa de produtos com pontuação real.
-- Ajudantes puros (sem efeitos): normalização igual para a pesquisa e para o
-- nome do produto — acentos fora, hífen = espaço, plural → singular.

create or replace function public.assistant_singular(p_w text)
returns text
language sql
immutable parallel safe strict
set search_path to 'public'
as $function$
  select case
    when length(p_w) <= 3 or p_w ~ '^[0-9]' then p_w
    when p_w ~ 'oes$' then regexp_replace(p_w, 'oes$', 'ao')
    when p_w ~ 'aes$' then regexp_replace(p_w, 'aes$', 'ao')
    when p_w ~ 'ais$' then regexp_replace(p_w, 'ais$', 'al')
    when p_w ~ 'eis$' then regexp_replace(p_w, 'eis$', 'el')
    when p_w ~ 'ois$' then regexp_replace(p_w, 'ois$', 'ol')
    when p_w ~ 'ns$'  then regexp_replace(p_w, 'ns$', 'm')
    when length(p_w) > 4 and p_w ~ '[rz]es$' then left(p_w, -2)
    when p_w ~ '[^s]s$' then left(p_w, -1)
    else p_w
  end;
$function$;

create or replace function public.assistant_tokens(p_texto text)
returns text[]
language sql
immutable parallel safe
set search_path to 'public'
as $function$
  select coalesce(array_agg(public.assistant_singular(t.w) order by t.o), '{}'::text[])
    from regexp_split_to_table(
           btrim(regexp_replace(public.f_unaccent(coalesce(p_texto, '')), '[^a-z0-9]+', ' ', 'g')),
           ' ') with ordinality as t(w, o)
   where t.w <> ''
     and t.w not in ('de','da','do','das','dos','em','e','a','o','os','as','para','p',
                     'ao','aos','na','no','nas','nos','c','um','uma','ou','pra');
$function$;

-- Cabeça do nome: a 1.ª palavra a sério. Nos nomes "Marca - Produto"
-- (Intermarché) é a 1.ª palavra depois do traço; números, unidades e
-- "metade/meia" não contam.
create or replace function public.assistant_cabeca(p_nome text)
returns text
language plpgsql
immutable parallel safe
set search_path to 'public'
as $function$
declare
  v_n      text := public.f_unaccent(coalesce(p_nome, ''));
  v_depois text;
  v_t      text[];
  -- unidades e prefixos de quantidade não são a cabeça ("Metade Abóbora")
  c_unid   constant text[] := array['un','und','unid','unidade','kg','g','gr','grs',
                                    'ml','cl','l','lt','emb','embalagem','pack','v',
                                    'metade','meia','box'];
begin
  v_depois := substring(v_n from '^[^-]{1,30}?\s+-\s+(.*)$');
  if v_depois is not null then
    v_t := array(select x from unnest(public.assistant_tokens(v_depois)) with ordinality as u(x, o)
                  where x !~ '[0-9]' and length(x) > 1 and not (x = any (c_unid))
                  order by o);
    if cardinality(v_t) > 0 then return v_t[1]; end if;
  end if;
  v_t := array(select x from unnest(public.assistant_tokens(v_n)) with ordinality as u(x, o)
                where x !~ '[0-9]' and length(x) > 1 and not (x = any (c_unid))
                order by o);
  return v_t[1];
end;
$function$;

-- Que parte das palavras da pesquisa (p_q) aparece nas palavras do nome (p_n,
-- já normalizadas por assistant_tokens), 0..1. Palavra igual depois de
-- normalizada, ou quase igual (erro de escrita, >= 5 letras).
create or replace function public.assistant_cobertura(p_q text[], p_n text[])
returns numeric
language sql
immutable parallel safe
set search_path to 'public', 'extensions'
as $function$
  select case when count(*) = 0 then 0::numeric
         else round((count(*) filter (where exists (
                       select 1 from unnest(coalesce(p_n, '{}'::text[])) w
                        where w = q.x
                           or (length(q.x) >= 5 and length(w) >= 5
                               and extensions.similarity(q.x, w) > 0.52))))::numeric
                    / count(*), 3)
         end
    from (select distinct x from unnest(p_q) x where x !~ '[0-9]') q;
$function$;

revoke all on function public.assistant_singular(text) from public, anon, authenticated;
revoke all on function public.assistant_tokens(text) from public, anon, authenticated;
revoke all on function public.assistant_cabeca(text) from public, anon, authenticated;
revoke all on function public.assistant_cobertura(text[], text[]) from public, anon, authenticated;
grant execute on function public.assistant_singular(text) to service_role;
grant execute on function public.assistant_tokens(text) to service_role;
grant execute on function public.assistant_cabeca(text) to service_role;
grant execute on function public.assistant_cobertura(text[], text[]) to service_role;
-- Pesquisa do Bora Assistente com pontuação real (B2, 20/10/2026).
-- Antes: "alta" bastava o nome ter a 1.ª palavra da pesquisa (papo-seco →
-- comida de gato; azeite → atum em azeite). Agora cada linha tem uma
-- qualidade 0..1 = 0,6 × cobertura (palavras da pesquisa no nome, já sem
-- acentos/plural/hífen/unidades) + 0,4 × cabeça (o nome COMEÇA pelo que se
-- pediu). "alta" = cabeça + pelo menos metade das palavras (qualidade >= 0,7).
-- Tudo no nome mas a começar por outra coisa ("Atum em azeite") = "parecido".
-- O resto sai. Sem nenhuma "alta", a resposta vem vazia ("não encontrei").
-- Mesma assinatura e mesmas colunas: as versões da app já instaladas e o
-- cesto do Assistente continuam a chamar igual.
create or replace function public.assistant_search_products(p_query text, p_restaurant_id text default null::text, p_limit integer default 12, p_embedding vector default null::vector, p_per_store boolean default false)
 returns table(product_id text, name text, restaurant_id text, restaurant_name text, is_partner boolean, service_type text, price numeric, display_price numeric, unit text, category text, photo_url text, maior_18 boolean, score numeric, match_kind text, confidence text)
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
#variable_conflict use_column
declare
  v_q      text := public.f_unaccent(coalesce(p_query, ''));
  v_ts     tsquery;
  v_ts_or  tsquery;   -- afinação 08/10: qualquer palavra (ordena quem tem todas primeiro)
  v_ts_1   tsquery;   -- a primeira palavra (o substantivo) é obrigatória
  v_markup numeric;
  v_qt     text[];    -- B2 20/10: palavras da pesquisa, normalizadas
  v_q1     text;      -- a 1.ª palavra a sério (o que se pediu)
  v_nq     int;
begin
  -- B2 20/10: hífen = espaço ("papo-seco" = "papo seco"; no websearch o "-"
  -- ainda podia ser lido como "sem").
  v_q := replace(v_q, '-', ' ');
  v_q := regexp_replace(v_q, '[^a-z0-9%/,\. ]', ' ', 'g');
  v_q := btrim(regexp_replace(v_q, '\s+', ' ', 'g'));
  if length(v_q) < 2 then return; end if;
  -- palavras da pesquisa sem unidades ("cenoura kg" = "cenoura": o nome
  -- pode dizer "2KG" colado ao número)
  v_qt := array(select x from unnest(public.assistant_tokens(v_q)) with ordinality as u(x, o)
                 where not (x = any (array['kg','g','gr','grs','ml','cl','lt','un','und','unid',
                                           'unidade','emb','embalagem','pack','litro','quilo','kilo']))
                 order by o);
  if cardinality(v_qt) = 0 then v_qt := public.assistant_tokens(v_q); end if;
  v_q1 := (select x from unnest(v_qt) with ordinality as u(x, o)
            where x !~ '[0-9]' and length(x) > 1 order by o limit 1);
  v_nq := (select count(distinct x) from unnest(v_qt) x where x !~ '[0-9]');
  v_ts := websearch_to_tsquery('portuguese', v_q);
  v_ts_or := websearch_to_tsquery('portuguese', regexp_replace(v_q, '\s+', ' or ', 'g'));
  v_ts_1 := websearch_to_tsquery('portuguese', split_part(v_q, ' ', 1));
  if v_ts_1 is null or numnode(v_ts_1) = 0 then v_ts_1 := v_ts_or; end if;
  select coalesce((ps.value::text)::numeric, 0.15) into v_markup
    from public.platform_settings ps where ps.key = 'non_partner_markup_pct';
  v_markup := coalesce(v_markup, 0.15);

  return query
  with lojas as (
    select l.* from public.assistant_lojas l
     where p_restaurant_id is null or l.id = p_restaurant_id
  ),
  base as not materialized (
    select p.id, p.name, p.restaurant_id, p.price, p.unit, p.category, p.photo_url,
           p.taxonomy_section, p.category_root, p.search_normalized,
           l.name as loja, l.is_partner, l.service_type
      from public.products p
      join lojas l on l.id = p.restaurant_id
     where coalesce(p.is_available, true) and p.price > 0
  ),
  fts as (
    select b.id, b.restaurant_id,
           row_number() over (partition by b.restaurant_id
             -- B2 20/10: primeiro os nomes que começam pelo que se pediu
             -- (também "Marca - Produto" e "12 Ovos"); expressão barata, sem
             -- função por linha, porque aqui passam todos os candidatos
             order by coalesce(public.f_unaccent(b.name) ~ ('^([^-]{1,30}?\s+-\s+)?([0-9]+\s+)?' || v_q1), false) desc,
                      (to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts) desc,
                      ts_rank_cd(to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))), v_ts_or) desc,
                      length(b.name) asc, b.price asc) as rn
      from base b
     where to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts_1
       and to_tsvector('portuguese', public.f_unaccent(coalesce(b.name,'') || ' ' || coalesce(b.category,''))) @@ v_ts_or
  ),
  trg as (
    select b.id, b.restaurant_id,
           row_number() over (partition by b.restaurant_id
             order by word_similarity(v_q, coalesce(b.search_normalized, public.f_unaccent(b.name))) desc,
                      length(b.name) asc, b.price asc) as rn,
           word_similarity(v_q, coalesce(b.search_normalized, public.f_unaccent(b.name))) as sim
      from base b
     where v_q <% b.search_normalized
  ),
  vec as (
    select e.product_id as id, row_number() over (order by e.embedding <=> p_embedding) as rn,
           (1 - (e.embedding <=> p_embedding))::numeric as sim
      from public.product_embeddings e
     where p_embedding is not null
     order by e.embedding <=> p_embedding
     limit 100
  ),
  fused as (
    select x.id,
           sum(x.s)::numeric as score,
           string_agg(x.kind, '+' order by x.kind) as match_kind,
           max(x.sim) as best_sim,
           max(case when x.kind = 'vec' then x.sim end) as vec_sim
      from (
        select f.id, 1.0 / (60 + f.rn) as s, 'fts' as kind, null::numeric as sim from fts f where f.rn <= 8
        union all
        select t.id, 1.0 / (60 + t.rn) as s, 'trgm' as kind, t.sim::numeric from trg t where t.rn <= 8
        union all
        select v.id, 1.0 / (60 + v.rn) as s, 'vec' as kind, v.sim from vec v
      ) x
     group by x.id
  ),
  cand as (
    -- palavras e cabeça de cada candidato calculadas uma só vez
    select b.*, f.match_kind, f.best_sim, f.vec_sim, f.score as rrf_base,
           public.assistant_tokens(b.name) as nt,
           -- num restaurante a secção do menu também diz o que é ("Copo Mega"
           -- na secção "Açaí"); nos mercados a categoria é larga ("Mercearia")
           -- e não conta
           case when b.service_type = 'restaurant'
                then public.assistant_tokens(coalesce(b.category, '')) end as ct,
           public.assistant_cabeca(b.name) as cab
      from fused f join base b on b.id = f.id
  ),
  medido as (
    select c.*,
           c.rrf_base
             + case when public.f_unaccent(c.name) like v_q || '%' then 0.02 else 0 end
             + case when c.match_kind like '%fts%' and c.match_kind like '%trgm%' then 0.01 else 0 end as rrf,
           public.assistant_cobertura(v_qt, c.nt || coalesce(c.ct, '{}'::text[])) as cov,
           public.assistant_cobertura(array[v_q1], c.nt || coalesce(c.ct, '{}'::text[])) as cov1,
           (c.cab = v_q1
             or (length(v_q1) >= 5 and extensions.similarity(coalesce(c.cab, ''), v_q1) > 0.52)
             or v_q1 = any (coalesce(c.ct, '{}'::text[]))) as cabeca_ok
      from cand c
  ),
  bons as (
    select m.*,
           case when v_q1 is null then 0
                else round(0.6 * m.cov + 0.4 * (case when m.cabeca_ok then 1 else 0 end), 3)
           end as qualidade
      from medido m
     where v_q1 is null                                     -- só números ("7up"): como antes
        or (m.cabeca_ok and m.cov1 >= 1 and m.cov >= 0.5)   -- boa: começa pelo pedido
        or m.cov >= 1                                       -- tem tudo, mas é outra coisa
        or coalesce(m.vec_sim, 0) >= 0.80                   -- semântica muito perto (só vetores)
  ),
  scored as (
    select s.*,
           s.qualidade + s.rrf as score_final,
           ((s.cabeca_ok and s.cov1 >= 1 and s.cov >= 0.5) or coalesce(s.vec_sim, 0) >= 0.85) as boa,
           row_number() over (partition by s.restaurant_id
                              order by s.qualidade desc, s.rrf desc, s.price asc) as rn_loja
      from bons s
  ),
  final as (
    select s.*, count(*) filter (where s.boa) over () as n_boas
      from scored s
  )
  select s.id, s.name, s.restaurant_id, s.loja, s.is_partner, s.service_type,
         s.price,
         case when s.is_partner then s.price else round(s.price * (1 + v_markup), 2) end as display_price,
         s.unit, s.category, s.photo_url,
         public.produto_e_maior_18(s.name, s.category, s.taxonomy_section, s.category_root) as maior_18,
         round(s.score_final, 5) as score, s.match_kind,
         case when v_q1 is null then
                case when (s.match_kind like '%fts%' and to_tsvector('portuguese', public.f_unaccent(coalesce(s.name,'') || ' ' || coalesce(s.category,''))) @@ v_ts)
                          or coalesce(s.best_sim, 0) >= 0.7
                     then 'alta' else 'parecido' end
              when s.boa then 'alta'
              else 'parecido' end as confidence
    from final s
   where ((not p_per_store) or s.rn_loja = 1)
     -- sem nenhuma correspondência boa não se devolve o "parecido" sozinho:
     -- a resposta vem vazia e o Assistente diz que não encontrou
     and (v_q1 is null or s.n_boas > 0)
   order by s.score_final desc, s.price asc
   limit greatest(1, least(coalesce(p_limit, 12), 200));
end;
$function$;
-- Lupa única (B2, 20/10/2026): mesma normalização do Assistente (sem acentos,
-- singular, hífen = espaço, sem unidades). A 1.ª palavra tem de estar no
-- produto e as outras quase todas — "azei" já mostra azeite. A semelhança solta
-- da frase inteira (que punha comida de gato em "papo-seco") passa a ser só
-- recurso para erros de escrita, palavra a palavra, quando não há nada exato.
-- Sem nada bom, a lista vem vazia e o ecrã diz que não encontrou.
-- Mesma assinatura e mesmo formato (lojas/produtos): versões instaladas iguais.
create or replace function public.cliente_pesquisar(p_q text, p_limit integer default 30)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'extensions'
as $function$
declare qn text; lojas jsonb; prods jsonb; v_qt text[]; v_qo text[]; v_q1 text;
begin
  qn := trim(unaccent(lower(coalesce(p_q,''))));
  -- B2 20/10: hífen e pontuação = espaço
  qn := btrim(regexp_replace(regexp_replace(qn, '[^a-z0-9 ]+', ' ', 'g'), '\s+', ' ', 'g'));
  if length(qn) < 2 then return jsonb_build_object('lojas','[]'::jsonb,'produtos','[]'::jsonb); end if;
  -- cada palavra no singular (v_qt) e como foi escrita (v_qo), alinhadas;
  -- sem palavras vazias nem unidades ("cenoura kg" = "cenoura")
  select array_agg(public.assistant_singular(w) order by o), array_agg(w order by o)
    into v_qt, v_qo
    from regexp_split_to_table(qn, ' ') with ordinality as t(w, o)
   where w <> ''
     and w not in ('de','da','do','das','dos','em','e','a','o','os','as','para','p','ao','aos',
                   'na','no','nas','nos','c','um','uma','ou','pra',
                   'kg','g','gr','grs','ml','cl','lt','un','und','unid','unidade','unidades',
                   'emb','embalagem','pack','litro','litros','quilo','quilos','kilo');
  if coalesce(cardinality(v_qt), 0) = 0 then v_qt := string_to_array(qn, ' '); v_qo := v_qt; end if;
  v_q1 := v_qt[1];

  select coalesce(jsonb_agg(x), '[]'::jsonb) into lojas from (
    select r.id, r.name, r.category, r.cuisine_type, r.photo_url, r.cover_url, r.is_partner,
           coalesce(r.coming_soon,false) as coming_soon, coalesce(r.is_online,true) as is_online
    from restaurants r
    where r.approval_status='approved' and coalesce(r.is_active_admin,true)
      and (unaccent(lower(r.name || ' ' || coalesce(r.cuisine_type,'') || ' ' || coalesce(r.category,''))) ilike '%'||qn||'%'
           or word_similarity(qn, unaccent(lower(r.name || ' ' || coalesce(r.cuisine_type,'')))) > 0.5)
    order by (unaccent(lower(r.name)) ilike qn||'%') desc, r.name
    limit greatest(1, least(p_limit,50))
  ) x;

  -- 1) a 1.ª palavra tem de estar (início de palavra; com 4+ letras também a
  --    meio, "burger" acha "cheeseburger"; com 6+ letras quase igual,
  --    "chouriço" acha "chouriça"); com 1-2 palavras, todas; com 3+, 60 % —
  --    ou o produto começa pela 1.ª palavra.
  --    Da 2.ª em diante aceita-se a forma parecida ("fatiado" ~ "fatias").
  select coalesce(jsonb_agg(y), '[]'::jsonb) into prods from (
    select p.id, p.name, p.price, p.photo_url, p.restaurant_id, r.name as restaurant_name, r.category as restaurant_category,
           coalesce(r.coming_soon,false) as coming_soon
    from products p join restaurants r on r.id=p.restaurant_id
    cross join lateral (
      select count(*) filter (where z.ok) as n_ok, coalesce(bool_or(z.ok) filter (where z.i = 1), false) as ok1
        from (select i, (
                p.search_normalized ~ ('(^| )' || v_qt[i])
                or (length(v_qt[i]) >= 4 and position(v_qt[i] in p.search_normalized) > 0)
                or (v_qo[i] is not null and p.search_normalized ~ ('(^| )' || v_qo[i]))
                or (v_qo[i] is not null and length(v_qo[i]) >= 4 and position(v_qo[i] in p.search_normalized) > 0)
                or (length(v_qt[i]) >= (case when i = 1 then 6 else 4 end)
                    and exists (select 1 from regexp_split_to_table(p.search_normalized, ' ') w
                                 where length(w) >= 4
                                   and extensions.similarity(v_qt[i], w) > (case when i = 1 then 0.6 else 0.45 end)))
              ) as ok
              from generate_subscripts(v_qt, 1) i) z
    ) m
    where coalesce(p.is_available,true) and r.approval_status='approved' and coalesce(r.is_active_admin,true)
      and (p.search_normalized ilike '%'||v_q1||'%'
           or p.search_normalized ilike '%'||coalesce(v_qo[1], v_q1)||'%'
           or v_q1 <% p.search_normalized)
      and m.ok1
      and (m.n_ok >= (case when cardinality(v_qt) <= 2 then cardinality(v_qt)
                           else ceil(0.6 * cardinality(v_qt)) end)
           -- o produto COMEÇA pela 1.ª palavra ("Abóbora Butternut" em
           -- "abóbora manteiga"): entra, depois dos que têm tudo
           or p.search_normalized ~ ('^' || v_q1)
           or p.search_normalized ~ ('^' || coalesce(v_qo[1], v_q1)))
    order by (p.search_normalized ilike qn||'%') desc, m.n_ok desc, word_similarity(qn, p.search_normalized) desc, p.name
    limit greatest(1, least(p_limit*2,100))
  ) y;

  -- 2) erro de escrita: só se o exato não deu nada, e palavra a palavra
  if jsonb_array_length(prods) = 0 then
    select coalesce(jsonb_agg(y), '[]'::jsonb) into prods from (
      select p.id, p.name, p.price, p.photo_url, p.restaurant_id, r.name as restaurant_name, r.category as restaurant_category,
             coalesce(r.coming_soon,false) as coming_soon
      from products p join restaurants r on r.id=p.restaurant_id
      where coalesce(p.is_available,true) and r.approval_status='approved' and coalesce(r.is_active_admin,true)
        and qn <% p.search_normalized
        and not exists (
          select 1 from unnest(v_qt) q
           where not exists (
             select 1 from regexp_split_to_table(p.search_normalized, ' ') w
              where w like q || '%'
                 or (length(q) >= 4 and length(w) >= 4 and extensions.similarity(q, w) > 0.45)))
      order by word_similarity(qn, p.search_normalized) desc, p.name
      limit greatest(1, least(p_limit*2,100))
    ) y;
  end if;

  return jsonb_build_object('lojas', lojas, 'produtos', prods);
end $function$;
