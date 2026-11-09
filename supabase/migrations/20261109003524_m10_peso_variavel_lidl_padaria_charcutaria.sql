-- M10 b2-limpeza (09/11/2026), item 2.2 — peso variável: Lidl, padaria ao quilo e charcutaria ao balcão.
-- Parte das regras no ar (20261031221858, produto_sugere_peso_variavel + gatilho trg_products_zzz_peso_variavel_novo).
--
-- O que muda (só a coluna products.variable_weight; NENHUM preço, preco_kg, peso_medio_kg ou taxa):
--   (1) produto_sugere_peso_variavel(nome, secção) ganha dois ramos:
--       * Padaria & Pastelaria vendida AO QUILO: "... Kg" sem tamanho fixo ("Pão Rústico Produção Própria Kg"
--         sim; "Pão Trigo Museu do Pão Fatiado 1 KG" não), ou "a granel"/"a peso"/"ao quilo". A padaria avulsa
--         vendida À UNIDADE ("Pão de Deus Un", "Bolo do Caco") tem preço fixo e fica de fora de propósito.
--       * Charcutaria & Queijos AO BALCÃO (cortado/fatiado na hora): "Fatiado no Balcão", "Queijo ... Balcão
--         <marca>", "(pedido ao balcão)", sem tamanho fixo ("... Fatiado ao Balcão Limiano 1KG" não).
--   (2) produto_sugere_peso_variavel_na_loja(loja, nome, secção, unidade) — a regra POR LOJA, usada pelo gatilho e
--       pela marcação abaixo (uma só fonte):
--       * Continente, Auchan, Intermarché, Pingo Doce → a regra (1), como até aqui;
--       * Lidl (NOVO) → só sinais fortes, porque as secções do catálogo Lidl estão erradas (chocolates e comida
--         de gato em "Peixaria"): unidade "Vendido ao kg", ou charcutaria/queijo "ao balcão" sem tamanho fixo;
--       * Mercadona continua de fora (loja parada até "vamos reabrir a loja").
--   (3) fn_products_peso_variavel_novo (BEFORE INSERT) passa a usar (2). Continua só no INSERT.
--   (4) Marcação dos produtos que já existem: variable_weight = true SÓ nos que as regras NOVAS apanham. Os que a
--       regra de 31/10 já apanhava e estão desligados (ex.: 5 congelados "aprox." do Continente desligados a 01/11)
--       foram decisão de alguém e NÃO se tocam.
--   Provado por SELECT a pg_trigger: trg_products_zzz_peca_ao_quilo (o que recalcula price) só dispara em UPDATE OF
--   price, name, peso_medio_kg, preco_kg; trg_products_price_history_upd só em UPDATE OF price/discount_*. Mudar só
--   variable_weight dispara apenas trg_products_set_updated_at (moddatetime). Prova em rollback: price igual em
--   todas as linhas marcadas e 0 linhas novas em product_price_history (relatório M10 b2-limpeza).
--   Ensaio em rollback a 09/11/2026: 72 produtos marcados — Lidl 14 (unidade "Vendido ao kg" e 4 ao balcão),
--   Auchan Padaria & Pastelaria 40 ("... Produção Própria Kg"), Continente Charcutaria & Queijos 18 ("... Balcão");
--   Intermarché e Pingo Doce 0. Os bolos "Cake Design Nº<n> Kg" (por encomenda) ficam de fora pelo "\d\s*kg".
-- Reverter: repor os corpos de 20261031221858, DROP FUNCTION public.produto_sugere_peso_variavel_na_loja(text,text,
--   text,text) e variable_weight=false nos marcados: guardar ANTES de aplicar os ids que a marcação vai apanhar
--   (mesmo WHERE do passo 4b, com a função nova) — ou, depois, os ids com variable_weight e updated_at desse minuto.

-- (4a) Antes de mudar a regra: o que a regra de 31/10 já apanhava (o estado desses fica como está).
create temp table _m10_peso_regra_antiga on commit drop as
  select id from public.products
   where restaurant_id in ('continente-guarda','auchan-guarda','intermarche-guarda','pingodoce-guarda')
     and public.produto_sugere_peso_variavel(name, taxonomy_section);

-- (1)
create or replace function public.produto_sugere_peso_variavel(p_name text, p_section text)
returns boolean language sql immutable parallel safe set search_path to 'public'
as $function$
  WITH x AS (
    SELECT COALESCE(p_name, '') AS n,
           COALESCE(p_section, '') AS sec,
           (COALESCE(p_name, '') ~* '(embalad|emb\.|\yemb\y|embalagem|garrafa|\ylata\y|frasco|\ypack\y|cx\.|\ycaixa\y|\ysaco\y|cuvete|couvete|\yrede\y|\d+([.,]\d+)?\s?(gr|g|kg|ml|cl|lt|l)\y|\d+\s?x\s?\d)'
            AND COALESCE(p_name, '') !~* '(unidade\s+\d|aprox)') AS tem_tamanho
  )
  SELECT
    (x.n ~* 'aprox')
    OR (x.sec IN ('Frutas & Legumes','Talho','Peixaria','Charcutaria & Queijos') AND x.n ~* '\ykg\y' AND x.n !~* '\d\s*kg')
    OR (x.sec IN ('Frutas & Legumes','Outros') AND NOT x.tem_tamanho
        AND x.n ~* '^(metade\s+)?(mini\s+melancia|banana|ma[cç][aã]|p[eê]ra|laranja|tangerina|clementina|lim[aã]o|lima|kiwi|manga|mam[aã]o|papaia|anan[aá]s|abacaxi|mel[aã]o|melancia|meloa|uva|p[eê]s+ego|nectarina|ameixa|alperce|damasco|figo|di[oó]spiro|rom[aã]|abacate|maracuj[aá]|toranja|tomate|batata|cebola|alho|cenoura|courgette|curgete|beringela|pimento|pepino|ab[oó]bora|couve|br[oó]colo|nabo|beterraba|gengibre|chuchu|inhame|mandioca|rabanete|aipo|funcho|feij[aã]o verde|alface)'
        AND x.n !~* '(sementes?\s+(de|para)\y|desidrat|\ysumo|n[eé]ctar|pur[eé]|compota|salada|cortad|ralad|ripad|fatiad|chips|frit|congelad|conserva|calda|xarope|iogurte|leite|bolacha|biol[oó]gic|\ybio\y|rodelas|palitos|cubos|peda[cç]os|cherry|cereja|\ymini\y(?!\s+melancia)|molho|cozid|assad[oa]\y|grelhad|(ameixa|figo|uva|alperce|damasco|banana)\s+sec|passa|triturad|polpa\y|bread|\ybolo|\yp[aã]o\y|tarte|gelad|chocolate|\ybarra|snack|creme|aroma|champ[oô]|\ygel\y|perfume|\yvela|brinquedo|peluche|gelatina|pastilha|rebu[cç]ado|gomas|licor|vinho|cocktail|refresco|bebida|\ych[aá]\y|infus|l[ií]quido|mo[ií]d[oa]|saqueta|decorativ|refrigerador|pl[aá]stic|\ykasa\y|desperd)')
    OR (x.sec IN ('Talho','Peixaria') AND NOT x.tem_tamanho
        AND x.n !~* '(congelad|ultracongelad|\yun\y|hamb[uú]rguer|salsich|nuggets|panad|alm[oô]ndega|cozinha continente|arroz de|preparad|tempero|caldo|fiambre|chouri[cç]o|\ypaio|presunto|enchid|lasanha|pizza|empad|rissol|croquete|pescanova|iglo|filetes de|del[ií]cias|surimi|conserva|fumad|cozid|assad|grelhad|marinad|panado|douradinh|tinta)')
    OR (x.sec IN ('Frutas & Legumes','Talho','Peixaria','Charcutaria & Queijos') AND x.n ~* 'unidade\s+\d' AND x.n !~* '(p[aã]o|brioche|preparado)')
    OR (x.sec = 'Charcutaria & Queijos' AND x.n ~* '(ao corte|corte na hora|fatiad[oa] na hora|\ya granel|\ya peso\y)')
    -- M10 (09/11/2026): charcutaria e queijo ao balcão, sem tamanho fixo.
    OR (x.sec = 'Charcutaria & Queijos' AND x.n ~* 'balc[aã]o' AND NOT x.tem_tamanho)
    -- M10 (09/11/2026): padaria e pastelaria vendida ao quilo (a avulsa à unidade tem preço fixo).
    OR (x.sec = 'Padaria & Pastelaria'
        AND ((x.n ~* '\ykg\y' AND x.n !~* '\d\s*kg') OR x.n ~* '(\ya granel|\ya peso\y|ao quilo)'))
  FROM x;
$function$;

-- (2)
create or replace function public.produto_sugere_peso_variavel_na_loja(
  p_loja text, p_name text, p_section text, p_unit text)
returns boolean language sql immutable parallel safe set search_path to 'public'
as $function$
  SELECT CASE
    WHEN p_loja IN ('continente-guarda','auchan-guarda','intermarche-guarda','pingodoce-guarda')
      THEN public.produto_sugere_peso_variavel(p_name, p_section)
    -- Lidl: as secções do catálogo estão erradas; só a unidade "Vendido ao kg" ou o balcão contam.
    WHEN p_loja = 'lidl-guarda'
      THEN COALESCE(p_unit, '') ~* 'vendido ao (kg|quilo)'
        OR (COALESCE(p_section, '') = 'Charcutaria & Queijos'
            AND COALESCE(p_name, '') ~* 'balc[aã]o'
            AND COALESCE(p_name, '') !~* '\d+([.,]\d+)?\s?(gr|g|kg)\y'
            AND COALESCE(p_unit, '') !~* '\d')
    ELSE false
  END;
$function$;

revoke all on function public.produto_sugere_peso_variavel_na_loja(text, text, text, text) from public, anon, authenticated;

-- (3)
create or replace function public.fn_products_peso_variavel_novo()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
BEGIN
  IF COALESCE(NEW.variable_weight, false) = false
     AND public.produto_sugere_peso_variavel_na_loja(NEW.restaurant_id, NEW.name, NEW.taxonomy_section, NEW.unit) THEN
    NEW.variable_weight := true;
  END IF;
  RETURN NEW;
END;
$function$;

-- (4b) Marcação: só variable_weight, só o que as regras NOVAS apanham.
update public.products p
   set variable_weight = true
 where p.variable_weight is distinct from true
   and public.produto_sugere_peso_variavel_na_loja(p.restaurant_id, p.name, p.taxonomy_section, p.unit)
   and not exists (select 1 from _m10_peso_regra_antiga a where a.id = p.id);