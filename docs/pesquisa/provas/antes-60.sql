with casos(id, grupo, loja, termo, esperado) as (values
('M01','mercado','continente-guarda','pao','(^| )pa(o|es)( |$)'),
('M02','mercado','continente-guarda','cocacola','coca cola'),
('M03','mercado','continente-guarda','champo','champo'),
('M04','mercado','continente-guarda','shampoo','champo|shampoo'),
('M05','mercado','continente-guarda','papel higenico','papel higienico'),
('M06','mercado','continente-guarda','rolos de cozinha','rolo.*cozinha|cozinha.*rolo|papel.*cozinha|toalh.*cozinha'),
('M07','mercado','continente-guarda','refrigerante','coca cola|fanta|sumol|7 ?up|pepsi|sprite|gasosa|seven up|schweppes|guarana'),
('M08','mercado','continente-guarda','iogurtes','iogurte'),
('M09','mercado','continente-guarda','gelado','^gelados?( |$)|magnum|cornetto|haagen'),
('M10','mercado','continente-guarda','leite meio gordo','leite.*meio gordo'),
('M11','mercado','continente-guarda','batatas fritas','batatas? fritas?|chips|ruffles|pringles|lays'),
('M12','mercado','continente-guarda','fiambre','^fiambre'),
('M13','mercado','pingodoce-guarda','pao','(^| )pa(o|es)( |$)'),
('M14','mercado','pingodoce-guarda','bolaxas','bolacha'),
('M15','mercado','pingodoce-guarda','detergente loica','detergente.*loica|loica.*detergente'),
('M16','mercado','pingodoce-guarda','ovos','^ovos?( |$)'),
('M17','mercado','lidl-guarda','iogurtes','iogurte'),
('M18','mercado','auchan-guarda','fraldas','fralda'),
('M19','mercado','intermarche-guarda','chourico','chourico'),
('M20','mercado','intermarche-guarda','azeite','(^| )azeite'),
('R01','restaurante','mcdonalds-guarda','gelado','mcflurry|sundae'),
('R02','restaurante','mcdonalds-guarda','batatas','batata'),
('R03','restaurante','mcdonalds-guarda','batatas fritas','batata'),
('R04','restaurante','mcdonalds-guarda','cocacola','coca cola'),
('R05','restaurante','mcdonalds-guarda','refrigerante','coca cola|fanta|sumol'),
('R06','restaurante','mcdonalds-guarda','hamburguer','hamburguer|cheeseburger|big mac|big tasty|mcroyal|mcchicken|cbo|big arch'),
('R07','restaurante','mcdonalds-guarda','nugets','nuggets'),
('R08','restaurante','mcdonalds-guarda','sobremesa','sundae|mcflurry|tarte|fatias maca|polpa fruta|abacaxi'),
('R09','restaurante','mcdonalds-guarda','bigmac','big mac'),
('R10','restaurante','mcdonalds-guarda','gelado oreo','mcflurry.*oreo'),
('R11','restaurante','kfc-guarda','frango','pedaco|tender|hotwing|bucket|wing|frango'),
('R12','restaurante','kfc-guarda','batatas','batata|fries'),
('R13','restaurante','kfc-guarda','gelado','sundae|kream|shake'),
('R14','restaurante','kfc-guarda','refrigerante','pepsi|7up|sumol|ice tea'),
('R15','restaurante','burgerking-guarda','hamburguer','whopper|burger|big king|cheeseburger|hamburguer|steakhouse'),
('R16','restaurante','burgerking-guarda','batata frita','batata|fries'),
('R17','restaurante','burgerking-guarda','gelado','ben jerry|king sandy|king fusion|sundae|gelado'),
('R18','restaurante','boom-burger-guarda','hamburguer','^boom'),
('R19','restaurante','pordosol-guarda','kebab','kebab|durum|doner'),
('R20','restaurante','jyosmi-sushi-guarda','salmao','salmao|sake'),
('F01','farmacia','wells-guarda','paracetamol','ben u ron'),
('F02','farmacia','wells-guarda','benuron','ben u ron'),
('F03','farmacia','wells-guarda','brufen','ibuprofeno|nurofen'),
('F04','farmacia','wells-guarda','ibuprofeno','ibuprofeno|nurofen'),
('F05','farmacia','wells-guarda','champo','champo'),
('F06','farmacia','wells-guarda','shampo','champo|shampoo'),
('F07','farmacia','wells-guarda','protetor solar','solar|spf'),
('F08','farmacia','wells-guarda','protector solar','solar|spf'),
('F09','farmacia','wells-guarda','pasta dentes','pasta (de )?dentes|dentifric'),
('F10','farmacia','wells-guarda','escova de dentes','escova.*dent|dent.*escova|oral b'),
('F11','farmacia','wells-guarda','fraldas','fralda'),
('F12','farmacia','wells-guarda','preservativos','preservativ'),
('F13','farmacia','wells-guarda','termometro','termometro'),
('F14','farmacia','wells-guarda','desodorizante','desodoriz'),
('F15','farmacia','wells-guarda','rimel','mascara (de )?pestanas|pestana'),
('F16','farmacia','wells-guarda','elixir bucal','elixir|colutorio'),
('F17','farmacia','wells-guarda','xarope para a tosse','xarope|tosse'),
('F18','farmacia','wells-guarda','dor de garganta','garganta|strepsils|strepfen'),
('F19','farmacia','wells-guarda','vitamina c','vitamina c'),
('F20','farmacia','wells-guarda','toalhetes','toalhit')),
corrida as (
  select caso.id, caso.esperado, d.ms, b.linhas
    from casos caso
    cross join lateral (select clock_timestamp() as t0, caso.id as cid) a
    cross join lateral (
      select coalesce(jsonb_agg(jsonb_build_object('name', s.name) order by s.o), '[]'::jsonb) as linhas
        from public.search_products(caso.termo, caso.loja, 50)
               with ordinality s(result_type, id, name, category, category_root, price, photo_url, match_rank, o)
       where s.result_type = 'product' and a.cid is not null
    ) b
    cross join lateral (
      select round(extract(epoch from clock_timestamp() - a.t0)::numeric * 1000, 1) as ms, b.linhas as l
    ) d
),
res as (
  select r.id, x.pos::int as pos, x.e->>'name' as name,
         public.bora_normalize(x.e->>'name') ~ r.esperado as ok
    from corrida r
    cross join lateral jsonb_array_elements(r.linhas) with ordinality as x(e, pos)
)
select c.id, c.grupo, c.loja, c.termo,
       (select r.ms from corrida r where r.id = c.id) as ms,
       (select count(*) from res where res.id = c.id) as n,
       (select min(pos) from res where res.id = c.id and ok) as pos_certo,
       (select left(string_agg(res.name, ' | ' order by pos), 200) from res where res.id = c.id and pos <= 5) as top5
  from casos c
 order by c.id;
