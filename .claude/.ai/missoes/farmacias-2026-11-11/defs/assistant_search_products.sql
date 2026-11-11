CREATE OR REPLACE FUNCTION public.assistant_search_products(p_query text, p_restaurant_id text DEFAULT NULL::text, p_limit integer DEFAULT 12, p_embedding extensions.vector DEFAULT NULL::extensions.vector, p_per_store boolean DEFAULT false)
 RETURNS TABLE(product_id text, name text, restaurant_id text, restaurant_name text, is_partner boolean, service_type text, price numeric, display_price numeric, unit text, category text, photo_url text, maior_18 boolean, score numeric, match_kind text, confidence text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
  -- 03/11: o tamanho do vetor diz o motor (384 = gte-small, 768 = Gemini)
  v_gte    boolean := p_embedding is not null and extensions.vector_dims(p_embedding) = 384;
  v_vbons  numeric := 0.80;  -- semântica muito perto (só vetores) — limiares do Gemini, como antes
  v_vboa   numeric := 0.85;
begin
  if v_gte then
    select coalesce((select (ps.value #>> '{}')::numeric from public.platform_settings ps where ps.key = 'assistant_gte_vec_bons_min'), 0.92),
           coalesce((select (ps.value #>> '{}')::numeric from public.platform_settings ps where ps.key = 'assistant_gte_vec_boa_min'), 0.94)
      into v_vbons, v_vboa;
    perform set_config('hnsw.ef_search', '100', true);
  end if;
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
  -- 03/11: os 100 vizinhos no motor do vetor que veio (só um dos dois ramos corre)
  vec_raw as (
    (select g.product_id as id, (g.embedding <=> p_embedding) as d
       from public.product_embeddings_gte g
      where v_gte
      order by g.embedding <=> p_embedding
      limit 100)
    union all
    (select e.product_id as id, (e.embedding <=> p_embedding) as d
       from public.product_embeddings e
      where p_embedding is not null and not v_gte
      order by e.embedding <=> p_embedding
      limit 100)
  ),
  vec as (
    select r.id, row_number() over (order by r.d) as rn, (1 - r.d)::numeric as sim
      from vec_raw r
  ),
  fused as (
    select x.id,
           sum(x.s)::numeric as score,
           string_agg(x.kind, '+' order by x.kind) as match_kind,
           max(x.sim) as best_sim,
           max(case when x.kind = 'vec' then x.sim end) as vec_sim
      from (
        select f.id, 1.0 / (60 + f.rn) as s, 'fts' as kind, null::numeric as sim from fts f where f.rn <= 8
           or (p_restaurant_id is not null
               and to_tsvector('portuguese', public.f_unaccent(coalesce((select bb.name from base bb where bb.id = f.id),''))) @@ websearch_to_tsquery('portuguese', replace(v_q,' ',' '))
               and public.assistant_cobertura(v_qt, public.assistant_tokens((select bb.name from base bb where bb.id = f.id))) >= 1)
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
        or coalesce(m.vec_sim, 0) >= v_vbons                -- semântica muito perto (só vetores)
  ),
  scored as (
    select s.*,
           ((s.cabeca_ok and s.cov1 >= 1 and s.cov >= 0.5) or coalesce(s.vec_sim, 0) >= v_vboa) as boa,
           -- só em pesquisas de 1 palavra: "Leite de Coco", "Ovos de Codorniz",
           -- "Arroz de Pato" — a palavra pedida seguida de "de/com/em…" é
           -- outro produto
           (v_nq = 1 and coalesce(public.f_unaccent(s.name) ~ ('^([^-]{1,30}?\s+-\s+)?([0-9]+\s+)?'
                    || v_q1 || '\S*\s+(de|do|da|dos|das|com|em)\s'), false)) as composto
      from bons s
  ),
  -- Só em pesquisas de 1 palavra ("leite", "ovos", "arroz"): a secção do
  -- catálogo onde mais se vende o que se pediu, contada em TODOS os produtos
  -- das lojas cujo nome começa pela palavra ("leite" → Laticínios & Ovos 227,
  -- Bebé 73, Mercearia 63). Só vale se ganhar com folga (>= 1,3 × a 2.ª):
  -- "alho" empata Frutas & Legumes com Mercearia e fica sem desempate.
  -- "Bio & Saudável" e "Outros" não contam (são atributos/resto).
  seccoes as (
    select b.taxonomy_section as sec, count(*) as n
      from base b
     where v_nq = 1 and v_q1 is not null
       and b.search_normalized ~ ('^' || v_q1)
       and coalesce(b.taxonomy_section, 'Outros') not in ('Outros', 'Bio & Saudável')
     group by b.taxonomy_section
  ),
  seccao as (
    select s1.sec
      from seccoes s1
     where s1.n >= 1.3 * coalesce((select max(s2.n) from seccoes s2 where s2.sec <> s1.sec), 0)
     order by s1.n desc
     limit 1
  ),
  final as (
    select s.*,
           coalesce(s.taxonomy_section = (select sec from seccao)
                    or (s.taxonomy_section = 'Bio & Saudável' and exists (select 1 from seccao)),
                    false) as na_seccao,
           count(*) filter (where s.boa) over () as n_boas
      from scored s
  ),
  ordenado as (
    select f.*,
           f.qualidade + f.rrf as score_final,
           row_number() over (partition by f.restaurant_id
                              order by f.qualidade desc, f.na_seccao desc, f.composto asc,
                                       f.rrf desc, f.price asc) as rn_loja
      from final f
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
    from ordenado s
   where ((not p_per_store) or s.rn_loja = 1)
     -- sem nenhuma correspondência boa não se devolve o "parecido" sozinho:
     -- a resposta vem vazia e o Assistente diz que não encontrou
     and (v_q1 is null or s.n_boas > 0)
   order by s.qualidade desc, s.na_seccao desc, s.composto asc, s.rrf desc, s.price asc
   limit greatest(1, least(coalesce(p_limit, 12), 200));
end;
$function$
;
