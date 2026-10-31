-- Peso variável — parte D (missão fecho-pendentes-2026-10-31, Bloco 1; regra do Danilo 26/10, "Autorizo" 10:16).
-- (1) Apaga a cópia de teste _talao_peso_teste (fechada a todos desde 26/10; o gate da Claude.ai não a deixou apagar).
-- (2) Função pura produto_sugere_peso_variavel(nome, secção) com as regras da parte C (26/10) e as correções de 31/10:
--     "sem/poucas/com sementes" já não tira a melancia (só "sementes de/para ..."); fruta e legumes avulsos também na
--     secção "Outros"; "mini melancia" entra; charcutaria "ao corte"/"a peso"/"a granel" entra; exclusões novas para
--     não-comida que cai em Outros (alho líquido/moído, abóbora decorativa, manga refrigeradora...).
-- (3) Gatilho BEFORE INSERT: produto NOVO dos 4 mercados revistos (Continente, Auchan, Intermarché, Pingo Doce) que a
--     regra reconhece nasce com variable_weight = true. Só no INSERT: o que o admin desligar à mão fica desligado.
--     Lidl e Mercadona ficam de fora de propósito: as secções desses catálogos estão erradas (detergente em Peixaria).
-- (4) Aplica a regra aos produtos que já existem e ainda não estavam marcados (7 em 31/10, revistos um a um).
-- Reverter: DROP TRIGGER trg_products_zzz_peso_variavel_novo ON public.products; DROP FUNCTION
--   public.fn_products_peso_variavel_novo(); DROP FUNCTION public.produto_sugere_peso_variavel(text,text);
--   e pôr variable_weight=false nos 7 ids do passo 4 (lista no relatório).

DROP FUNCTION IF EXISTS public._talao_peso_teste(text, text, integer, jsonb, integer);

CREATE OR REPLACE FUNCTION public.produto_sugere_peso_variavel(p_name text, p_section text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public'
AS $f$
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
  FROM x;
$f$;

COMMENT ON FUNCTION public.produto_sugere_peso_variavel(text, text) IS
  'Peso variável (26/10 + 31/10): true quando o nome/secção é de um produto que se vende ao quilo (fruta e legumes avulsos, talho e peixaria frescos, charcutaria ao corte, "aprox", "unidade N kg"). Usada pelo gatilho trg_products_zzz_peso_variavel_novo.';

REVOKE ALL ON FUNCTION public.produto_sugere_peso_variavel(text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_products_peso_variavel_novo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $f$
BEGIN
  IF COALESCE(NEW.variable_weight, false) = false
     AND NEW.restaurant_id IN ('continente-guarda','auchan-guarda','intermarche-guarda','pingodoce-guarda')
     AND public.produto_sugere_peso_variavel(NEW.name, NEW.taxonomy_section) THEN
    NEW.variable_weight := true;
  END IF;
  RETURN NEW;
END;
$f$;

REVOKE ALL ON FUNCTION public.fn_products_peso_variavel_novo() FROM PUBLIC, anon, authenticated;

-- "zzz" no nome: corre depois de trg_products_zz_auto_taxonomy (mesma fase, ordem alfabética), já com a secção posta.
DROP TRIGGER IF EXISTS trg_products_zzz_peso_variavel_novo ON public.products;
CREATE TRIGGER trg_products_zzz_peso_variavel_novo
  BEFORE INSERT ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.fn_products_peso_variavel_novo();

DO $marca$
DECLARE n integer;
BEGIN
  UPDATE public.products p SET variable_weight = true
   WHERE p.restaurant_id IN ('continente-guarda','auchan-guarda','intermarche-guarda','pingodoce-guarda')
     AND p.variable_weight = false
     AND public.produto_sugere_peso_variavel(p.name, p.taxonomy_section);
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'produtos marcados agora: %', n;
END
$marca$;
