explain (analyze, buffers, format text)
with cfg as materialized (
  select set_config('pg_trgm.word_similarity_threshold', '0.45', true) as limiar
), sinonimos_semente as (
  select v.termo, v.alvo, null::text as product_id, null::text as restaurant_id,
         array_to_string(public.assistant_tokens(btrim(v.termo)), ' ') as chave,
         array_to_string(public.assistant_tokens(btrim(v.alvo)), ' ') as alvo_chave,
         true as ativo
    from (values 
  ('gelado','mcflurry'),('gelado','sundae'),('gelado','cone'),('gelado','magnum'),('gelado','cornetto'),
  ('gelado','king sandy'),('gelado','king fusion'),('gelado','ben jerry'),('gelado','haagen dazs'),
  ('gelado','carte d or'),('gelado','solero'),('gelado','mochi'),('gelado','kream'),
  ('sorvete','gelado'),('sorvete','mcflurry'),('sorvete','sundae'),
  ('sobremesa','sundae'),('sobremesa','mcflurry'),('sobremesa','tarte'),('sobremesa','gelado'),('sobremesa','brownie'),
  ('sobremesa','cheesecake'),('sobremesa','mousse'),
  ('refrigerante','coca cola'),('refrigerante','fanta'),('refrigerante','sumol'),('refrigerante','7up'),
  ('refrigerante','sprite'),('refrigerante','pepsi'),('refrigerante','ice tea'),('refrigerante','fuze tea'),
  ('refrigerante','guarana'),('refrigerante','schweppes'),('refrigerante','gasosa'),('refrigerante','seven up'),
  ('refri','coca cola'),('refri','fanta'),('refri','sumol'),('refri','pepsi'),('refri','refrigerante'),
  ('cocacola','coca cola'),('coca','coca cola'),('coke','coca cola'),('cola','coca cola'),('cola','pepsi'),
  ('sumo','nectar'),('sumo','compal'),('sumo','bongo'),('suco','sumo'),('suco','nectar'),('suco','compal'),
  ('cerveja','sagres'),('cerveja','super bock'),('cerveja','heineken'),('cerveja','desperados'),
  ('cerveja','estrella'),('cerveja','imperial'),('birra','cerveja'),
  ('batata','fries'),('batata','batata frita'),('frita','batata'),('frita','fries'),
  ('batata frita','batata'),('batata frita','fries'),('batata frita','chips'),('batata frita','ruffles'),
  ('batata frita','pringles'),('batata frita','lays'),
  ('hamburguer','burger'),('hamburguer','hamburger'),('hamburguer','cheeseburger'),('hamburguer','big mac'),
  ('hamburguer','big tasty'),('hamburguer','mcroyal'),('hamburguer','whopper'),('hamburguer','big king'),
  ('hamburguer','mcchicken'),('hamburguer','cbo'),('hamburguer','big arch'),('hamburguer','boom'),
  ('burger','hamburguer'),('burger','hamburger'),('hamburger','hamburguer'),('hamburger','burger'),
  ('nugget','mcnugget'),('nugget','nuggets'),
  ('frango','chicken'),('frango','pedaco'),('frango','tender'),('frango','hotwing'),('frango','wing'),
  ('frango','asa'),('frango','nugget'),('frango','mcchicken'),('frango','crispy'),
  ('chicken','frango'),('asa','wing'),('asa','hotwing'),
  ('kebab','durum'),('kebab','doner'),('durum','kebab'),
  ('sushi','maki'),('sushi','nigiri'),('sushi','sashimi'),('sushi','uramaki'),('sushi','hossomaki'),
  ('sushi','temaki'),('sushi','roll'),('sushi','combinado'),
  ('salmao','salmon'),('salmao','sake'),
  ('sandes','sanduiche'),('sandes','sandwich'),('sandes','tosta'),('sandes','wrap'),
  ('sanduiche','sandes'),('sanduiche','sandwich'),('sanduiche','tosta'),
  ('molho','dip'),('molho','ketchup'),('molho','maionese'),
  ('pao','baguete'),('pao','broa'),('pao','carcaca'),('pao','papo seco'),('pao','regueifa'),('pao','bolo do caco'),
  ('papel higienico','rolo higienico'),('papel wc','papel higienico'),('papel casa banho','papel higienico'),
  ('rolo','papel higienico'),
  ('rolo cozinha','papel cozinha'),('rolo cozinha','rolo de cozinha'),('papel cozinha','rolo cozinha'),
  ('champo','shampoo'),('shampoo','champo'),('xampu','champo'),('xampu','shampoo'),
  ('gel banho','gel duche'),('gel duche','gel banho'),('gel banho','gel de banho'),
  ('desodorizante','desodorante'),('desodorante','desodorizante'),('desodorizante','antitranspirante'),
  ('pasta dente','dentifrico'),('pasta dente','pasta dentifrica'),('pasta dente','pasta de dentes'),
  ('creme dental','pasta de dentes'),('creme dental','dentifrico'),('dentifrico','pasta de dentes'),
  ('toalhete','toalhita'),('toalhita','toalhete'),('lenco humido','toalhita'),
  ('lixivia','javel'),('agua sanitaria','lixivia'),
  ('lava loica','detergente loica'),('detergente loica','lava loica'),
  ('iogurte','yogurt'),('iogurte','yoghurt'),('yogurt','iogurte'),('iogurte','yogurte'),
  ('macarrao','massa'),('macarrao','esparguete'),('massa','esparguete'),
  ('linguica','chourico'),('toucinho','bacon'),('carne moida','carne picada'),
  ('abacaxi','ananas'),('ananas','abacaxi'),
  ('geleia','compota'),('geleia','doce'),
  ('biscoito','bolacha'),('bolacha','biscoito'),('bolacha','cookie'),
  ('paracetamol','ben u ron'),('paracetamol','panadol'),('paracetamol','supofen'),
  ('benuron','ben u ron'),('ben u ron','paracetamol'),
  ('ibuprofeno','nurofen'),('ibuprofeno','brufen'),('ibuprofeno','trifene'),('ibuprofeno','spidifen'),
  ('brufen','ibuprofeno'),('brufen','nurofen'),('nurofen','ibuprofeno'),
  ('aspirina','acido acetilsalicilico'),
  ('dor cabeca','paracetamol'),('dor cabeca','ben u ron'),('dor cabeca','ibuprofeno'),('dor cabeca','aspirina'),
  ('dor cabeca','nurofen'),
  ('febre','paracetamol'),('febre','ben u ron'),('febre','ibuprofeno'),('febre','termometro'),
  ('dor garganta','garganta'),('dor garganta','strepsils'),('dor garganta','strepfen'),('dor garganta','tantum'),
  ('garganta','strepsils'),('garganta','strepfen'),('garganta','tantum verde'),
  ('tosse','xarope'),('tosse','bisoltussin'),('tosse','stodal'),
  ('gripe','cegripe'),('gripe','antigrippine'),('constipacao','cegripe'),('constipacao','antigrippine'),
  ('azia','rennie'),('azia','gaviscon'),
  ('protetor solar','solar'),('protetor solar','spf'),('protector','protetor'),('filtro solar','protetor solar'),
  ('filtro solar','solar'),('creme solar','solar'),('bronzeador','solar'),
  ('rimel','mascara de pestanas'),('rimel','mascara pestanas'),('rimel','pestanas'),
  ('batom','baton'),('batom','labial'),('baton','batom'),
  ('esmalte','verniz'),('verniz','esmalte'),
  ('elixir','colutorio'),('colutorio','elixir'),('elixir bucal','colutorio'),('elixir bucal','elixir'),
  ('fio dental','fio dentario'),('fio dentario','fio dental'),
  ('curativo','penso'),('band aid','penso'),('penso','curativo'),
  ('absorvente','penso higienico'),('penso higienico','absorvente'),
  ('camisinha','preservativo'),('durex','preservativo'),
  ('chucha','chupeta'),('mamadeira','biberao'),
  ('gilete','lamina'),('gilete','barbear'),('lamina','barbear'),
  ('cotonete','bastonete'),('cotonete','cotonetes')
  ) as v(termo, alvo)
)
select z.* from cfg,  (
with
q as (
  select btrim(regexp_replace(public.bora_normalize('papel higenico'::text), '\s+', ' ', 'g')) as qn,
         greatest(1, least(coalesce(50, 50), 200)) as lim
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
    join sinonimos_semente s
      on s.ativo
     and (s.restaurant_id is null or 'continente-guarda'::text is null or s.restaurant_id = 'continente-guarda'::text)
     and strpos(s.chave, ' ') = 0
     and (s.chave = pl.t or s.chave = pl.w
          or (length(pl.t) >= 5 and length(s.chave) >= 5 and extensions.similarity(s.chave, pl.t) >= 0.6))
  union all
  select s.alvo_chave, s.product_id, null::bigint, true
    from nq
    join sinonimos_semente s
      on s.ativo
     and (s.restaurant_id is null or 'continente-guarda'::text is null or s.restaurant_id = 'continente-guarda'::text)
     and strpos(s.chave, ' ') > 0
     and s.chave = nq.qs
),
alt as (
  select pal.i, pal.t as a, 0 as tipo from pal
  union select pal.i, pal.w, 0 from pal
  union select pal.i, replace(pal.t, 'ct', 't'), 0 from pal where strpos(pal.t, 'ct') > 0
  union select sin.i, sin.alvo_chave, 1 from sin where not sin.frase and sin.alvo_chave is not null
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
-- candidatos pelo índice de trigramas (GIN em search_normalized), depois a loja
cand_ids as materialized (
  select p0.id from public.products p0
   where p0.search_normalized ~ (select rx.v from rx)
  union
  select fixo.product_id from fixo
),
cand as (
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id,
         coalesce(p.is_popular, false) as popular
    from public.products p
   where p.id in (select cand_ids.id from cand_ids)
     and p.is_available
     and ('continente-guarda'::text is null or p.restaurant_id = 'continente-guarda'::text)
     and ('continente-guarda'::text is not null or exists (
           select 1 from public.restaurants r
            where r.id = p.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
),
-- ns = o nome como a pesquisa o compara. É, palavra a palavra, igual a
-- ' ' || array_to_string(assistant_tokens(nome), ' ') || ' ' (provado nos 59 475
-- produtos de produção a 09/11/2026: 0 diferenças), mas ~10x mais rápido: só
-- funções C, sem chamar uma função SQL por produto.
catn as (
  select k.category, (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(k.category, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as cs
    from (select distinct cand.category from cand) k
),
cn as (
  select c.*,
         (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(c.name, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as ns,
         coalesce(kn.cs, '  ') as cs,
         (' ' || regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(c.name, ''))), '[^a-z0-9]+', ' ', 'g') || ' ') as nr
    from cand c
    left join catn kn on kn.category is not distinct from c.category
),
forca as (
  select c.id, pl.i,
         coalesce(max(case when a.tipo = 0 then
           case when c.ns like '% ' || a.a || ' %' then 1.0
                when length(a.a) >= 3 and c.ns like '% ' || a.a || '%' then 0.75
                when length(a.a) >= 4 and strpos(c.ns, a.a) > 0 then 0.6
                else 0 end end), 0) as fo,
         greatest(
           coalesce(max(case when a.tipo = 1 then
             case when c.ns like '% ' || a.a || ' %' then 0.85
                  when length(a.a) >= 3 and c.ns like '% ' || a.a || '%' then 0.7
                  when length(a.a) >= 4 and strpos(c.ns, a.a) > 0 then 0.55
                  else 0 end end), 0),
           case when exists (select 1 from fixo f where f.i = pl.i and f.product_id = c.id) then 0.9 else 0 end
         ) as fs,
         coalesce(max(case when length(a.a) >= 3 and c.cs like '% ' || a.a || '%' then 0.4 else 0 end), 0) as fc,
         coalesce(bool_or(pl.i = 1 and length(a.a) >= 3 and c.ns like ' ' || a.a || '%'), false) as abre
    from cn c
    cross join pal pl
    join alt a on a.i = pl.i
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
  select p.id, p.name, p.category, p.category_root, p.price, p.photo_url, p.restaurant_id,
         coalesce(p.is_popular, false) as popular,
         (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p.name, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as ns
    from public.products p
   where p.id in (select fz_ids.id from fz_ids)
     and p.is_available
     and ('continente-guarda'::text is null or p.restaurant_id = 'continente-guarda'::text)
     and ('continente-guarda'::text is not null or exists (
           select 1 from public.restaurants r
            where r.id = p.restaurant_id and r.approval_status = 'approved'
              and coalesce(r.is_active_admin, true)))
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
           null::extensions.vector,
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
  select 'continente-guarda'::text is not null
         and (select count(*) from public.products p3
               where p3.restaurant_id = 'continente-guarda'::text and p3.is_available) <= 3000 as sim
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
      and p4.restaurant_id = 'continente-guarda'::text and p4.is_available)
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
     and ('continente-guarda'::text is null or p.restaurant_id = 'continente-guarda'::text)
),
semr as (
  select s.id, s.name, s.category, s.category_root, s.price, s.photo_url, s.restaurant_id,
         'significado'::text as kind, (1.5 + s.sim)::float8 as score, false as cheio
    from sem s
   where s.sim >= 0.93
     and s.sim >= (select max(s2.sim) from sem s2) - 0.015
     and ('continente-guarda'::text is not null or exists (
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
) z(id, name, category, category_root, price, photo_url, restaurant_id, kind, score);
