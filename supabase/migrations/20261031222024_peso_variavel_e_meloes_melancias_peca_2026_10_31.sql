-- Peso variável — parte E (missão fecho-pendentes-2026-10-31, Bloco 1; ordem do Danilo na missão 31/10).
-- Melancias, melões e meloas da Auchan e do Intermarché tinham o PREÇO DO QUILO guardado como se fosse a PEÇA
-- (ex.: "Melão Amarelo Auchan Kg" a 1,99 €; "Melancia" do Intermarché a 1,65 €). O cliente pedia 1 e o estafeta
-- pagava 4-8 € na caixa; o ajuste de peso (±30%) não chegava para corrigir.
-- Agora: products.preco_kg (preço do quilo da loja) e products.peso_medio_kg (peso médio de uma peça). Com peso
-- médio posto, o gatilho trg_products_zzz_peca_ao_quilo guarda price = preco_kg × peso_medio_kg e o nome acaba em
-- "(~N kg)". Quem escrever o preço destes produtos (o robô semanal da Auchan, update-products, terça 03:00) escreve
-- o preço do QUILO, como no site: o gatilho converte sozinho e a correção não se perde. Para escrever um preço já por
-- peça: SET LOCAL app.preco_por_peca = 'on' na mesma transação. O estafeta continua a acertar o peso real na balança.
-- Pesos médios: melancia inteira 4 kg (balança do Continente 31/10: 4,136 kg), mini melancia e metade 2 kg, melão
-- inteiro 2 kg, metade 1 kg, meloa 1 kg, metade de meloa 0,5 kg. Ficam de fora os tabuleiros "pedaços/cortado".
-- Reverter: UPDATE products SET peso_medio_kg = NULL, price = preco_kg WHERE peso_medio_kg IS NOT NULL (com
--   app.preco_por_peca='on') e tirar o "(~N kg)" do nome; o histórico fica em product_price_history e
--   catalog_price_updates (decided_by = 'claude_code_fecho_31_10').

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS preco_kg numeric(10,4);
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS peso_medio_kg numeric(6,3);
COMMENT ON COLUMN public.products.preco_kg IS 'Preço do quilo na loja (mercados não-parceiros, peças ao quilo). Só com peso_medio_kg.';
COMMENT ON COLUMN public.products.peso_medio_kg IS 'Peso médio de uma peça (kg). Com valor, price = preco_kg × peso_medio_kg (gatilho trg_products_zzz_peca_ao_quilo).';

CREATE OR REPLACE FUNCTION public.fn_products_peca_ao_quilo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $f$
DECLARE
  v_peso text;
BEGIN
  IF COALESCE(NEW.peso_medio_kg, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' OR NEW.price IS DISTINCT FROM OLD.price THEN
    IF COALESCE(current_setting('app.preco_por_peca', true), '') = 'on' THEN
      -- Quem escreveu já deu o preço da peça: guarda o quilo correspondente.
      NEW.preco_kg := ROUND(NEW.price / NEW.peso_medio_kg, 4);
    ELSE
      -- Preço vindo da loja/robô = preço do quilo.
      NEW.preco_kg := NEW.price;
      NEW.price := ROUND(NEW.price * NEW.peso_medio_kg, 2);
    END IF;
  ELSIF NEW.peso_medio_kg IS DISTINCT FROM OLD.peso_medio_kg OR NEW.preco_kg IS DISTINCT FROM OLD.preco_kg THEN
    NEW.price := ROUND(COALESCE(NEW.preco_kg, OLD.price) * NEW.peso_medio_kg, 2);
  END IF;

  v_peso := NEW.peso_medio_kg::text;
  IF position('.' IN v_peso) > 0 THEN
    v_peso := rtrim(rtrim(v_peso, '0'), '.');
  END IF;
  v_peso := replace(v_peso, '.', ',');
  NEW.name := regexp_replace(COALESCE(NEW.name, ''), '\s*\(~[0-9.,]+ kg\)\s*$', '');
  NEW.name := regexp_replace(NEW.name, '\s+kg\s*$', '', 'i') || ' (~' || v_peso || ' kg)';
  RETURN NEW;
END;
$f$;

REVOKE ALL ON FUNCTION public.fn_products_peca_ao_quilo() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_zzz_peca_ao_quilo ON public.products;
CREATE TRIGGER trg_products_zzz_peca_ao_quilo
  BEFORE INSERT OR UPDATE OF price, name, peso_medio_kg, preco_kg ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.fn_products_peca_ao_quilo();

DO $meloes$
DECLARE n integer;
BEGIN
  CREATE TEMP TABLE _pecas (id text PRIMARY KEY, peso numeric) ON COMMIT DROP;
  INSERT INTO _pecas VALUES
    ('auc-3438596', 4), ('auc-214450', 2), ('auc-3438590', 2), ('auc-3440742', 2),
    ('auc-3438605', 2), ('auc-3439509', 1), ('auc-3440649', 1), ('auc-233249', 2),
    ('auc-3305151', 1), ('auc-3440646', 1), ('auc-245413', 2), ('auc-395099', 1),
    ('auc-3438719', 1), ('auc-3440650', 0.5), ('auc-3438717', 1), ('auc-3440651', 0.5),
    ('int-98c5e3c0-c04e-5629-9e74-564dec17dc19', 4), ('int-d8309a67-4d80-4c14-817e-d0dfdb463624', 4),
    ('int-3f973767-82a7-4c90-9b0b-a07b1c6f70e0', 2), ('int-e7db99ae-a4a7-5927-b2bd-d82c60c5dcfe', 4),
    ('int-f0a76e91-e41c-411d-ba65-660d95faec74', 2), ('int-2022e8e6-176a-56fe-904c-f5bb7dc4ad1c', 2),
    ('int-7e7cd367-e6f5-5843-adfd-937816c3b9d7', 2), ('int-b73f4ee1-a3a7-40cb-9d5d-6cf8703fb865', 2),
    ('int-2e076894-2ef8-510b-ae7f-cd30881f7df2', 2), ('int-cecfe937-8f50-5d5f-a905-4b50d2387792', 2),
    ('int-af29e274-08de-4580-84f8-dea8056d06f0', 2), ('int-c7a38f97-b221-4653-a477-ebc04af8039b', 2),
    ('int-12bf2cda-7794-4705-b313-6fdaaf8b13c4', 1), ('int-e69bc8d1-25e0-43ce-a0bc-c687a8c37268', 1),
    ('int-f76535fd-7391-4761-b174-8b99fda041aa', 1), ('int-c1f19f3b-9d10-45b4-8ad4-47524b99a1fd', 1);

  INSERT INTO public.catalog_price_updates
    (product_id, restaurant_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
  SELECT p.id, p.restaurant_id, p.price, ROUND(p.price * c.peso, 2), 0.800,
         format('Peça ao quilo (missão fecho-pendentes 31/10): %s €/kg × %s kg de peso médio. Estava o preço do quilo como se fosse a peça.', p.price, c.peso),
         'applied', now(), 'claude_code_fecho_31_10'
    FROM public.products p JOIN _pecas c ON c.id = p.id
   WHERE p.peso_medio_kg IS NULL;

  UPDATE public.products p
     SET preco_kg = p.price, peso_medio_kg = c.peso, variable_weight = true
    FROM _pecas c
   WHERE p.id = c.id AND p.peso_medio_kg IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  RAISE NOTICE 'peças corrigidas: %', n;
END
$meloes$;
