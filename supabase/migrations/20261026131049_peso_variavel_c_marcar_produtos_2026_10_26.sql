-- Peso variável — parte C (Danilo 26/10/2026): marcar os produtos de peso variável dos mercados
-- (Continente, Auchan, Intermarché, Pingo Doce). Regras, por ordem: nome com "aprox";
-- vendido "Kg" sem número nas secções de frescos; fruta e legumes avulsos (sem tamanho de embalagem);
-- talho e peixaria frescos sem embalagem; Pingo Doce "- unidade NNN g". Coluna nova (antes tudo false),
-- por isso reverter = pôr false. O painel admin troca produto a produto (admin_set_variable_weight).
DO $marca$
DECLARE n integer;
BEGIN
  WITH alvo AS (
    SELECT p.id, p.name, p.taxonomy_section AS sec,
      (p.name ~* '(embalad|emb\.|\yemb\y|embalagem|garrafa|\ylata\y|frasco|\ypack\y|cx\.|\ycaixa\y|\ysaco\y|cuvete|couvete|\yrede\y|\d+([.,]\d+)?\s?(gr|g|kg|ml|cl|lt|l)\y|\d+\s?x\s?\d)'
        AND p.name !~* '(unidade\s+\d|aprox)') AS tem_tamanho
    FROM public.products p
    WHERE p.restaurant_id IN ('continente-guarda','auchan-guarda','intermarche-guarda','pingodoce-guarda')
  ), marca AS (
    SELECT a.id FROM alvo a WHERE
      (a.name ~* 'aprox')
      OR (a.sec IN ('Frutas & Legumes','Talho','Peixaria','Charcutaria & Queijos') AND a.name ~* '\ykg\y' AND a.name !~* '\d\s*kg')
      OR (a.sec = 'Frutas & Legumes' AND NOT a.tem_tamanho
          AND a.name ~* '^(metade\s+)?(banana|ma[cç][aã]|p[eê]ra|laranja|tangerina|clementina|lim[aã]o|lima|kiwi|manga|mam[aã]o|papaia|anan[aá]s|abacaxi|mel[aã]o|melancia|meloa|uva|p[eê]s+ego|nectarina|ameixa|alperce|damasco|figo|di[oó]spiro|rom[aã]|abacate|maracuj[aá]|toranja|tomate|batata|cebola|alho|cenoura|courgette|curgete|beringela|pimento|pepino|ab[oó]bora|couve|br[oó]colo|nabo|beterraba|gengibre|chuchu|inhame|mandioca|rabanete|aipo|funcho|feij[aã]o verde|alface)'
          AND a.name !~* '(semente|desidrat|\ysumo|n[eé]ctar|pur[eé]|compota|salada|cortad|ralad|ripad|fatiad|chips|frit|congelad|conserva|calda|xarope|iogurte|leite|bolacha|biol[oó]gic|\ybio\y|rodelas|palitos|cubos|peda[cç]os|cherry|cereja|\ymini\y|molho|cozid|assad[oa]\y|grelhad|(ameixa|figo|uva|alperce|damasco|banana)\s+sec|passa|triturad|polpa\y)')
      OR (a.sec IN ('Talho','Peixaria') AND NOT a.tem_tamanho
          AND a.name !~* '(congelad|ultracongelad|\yun\y|hamb[uú]rguer|salsich|nuggets|panad|alm[oô]ndega|cozinha continente|arroz de|preparad|tempero|caldo|fiambre|chouri[cç]o|\ypaio|presunto|enchid|lasanha|pizza|empad|rissol|croquete|pescanova|iglo|filetes de|del[ií]cias|surimi|conserva|fumad|cozid|assad|grelhad|marinad|panado|douradinh|tinta)')
      OR (a.sec IN ('Frutas & Legumes','Talho','Peixaria','Charcutaria & Queijos') AND a.name ~* 'unidade\s+\d' AND a.name !~* '(p[aã]o|brioche|preparado)')
  )
  UPDATE public.products p SET variable_weight = true
    FROM marca m WHERE p.id = m.id AND p.variable_weight = false;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'produtos marcados como peso variável: %', n;
END
$marca$;
