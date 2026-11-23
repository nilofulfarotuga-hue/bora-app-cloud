-- 23/11/2026 11:00 — regra que o Emanuel (Boom) deu: "a cada 30 € é 1 € a mais" (até 30 € = 1 €; acima de 30 € = 2 €;
-- acima de 60 € = 3 €; acima de 90 € = 4 €...). Troca o modelo de 2 escalões pelo de escalão fixo (colunas novas sem dados).
-- E separa a embalagem (que é da loja) das contas da Bora: relatórios, fecho, extrato do parceiro e cotação (bag_label).

ALTER TABLE public.restaurants
  DROP COLUMN IF EXISTS embalagem_grande_cents,
  DROP COLUMN IF EXISTS embalagem_grande_a_partir_cents,
  ADD COLUMN IF NOT EXISTS embalagem_escalao_cents integer CHECK (embalagem_escalao_cents IS NULL OR embalagem_escalao_cents > 0);
COMMENT ON COLUMN public.restaurants.embalagem_cents IS 'Embalagem cobrada ao cliente (cêntimos) em vez do saco, por cada escalão de subtotal; vai 100% para a loja. NULL = usa o saco normal.';
COMMENT ON COLUMN public.restaurants.embalagem_escalao_cents IS 'Tamanho do escalão de subtotal (cêntimos). Ex.: 3000 = +embalagem_cents a cada 30 € (até 30 € = 1x, acima de 30 € = 2x...). NULL = valor fixo.';

CREATE OR REPLACE FUNCTION public.embalagem_loja_valor(p_restaurant_id text, p_subtotal numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $f$
  SELECT ROUND(CASE
           WHEN r.embalagem_cents IS NULL THEN NULL
           WHEN r.embalagem_escalao_cents IS NULL THEN r.embalagem_cents / 100.0
           ELSE r.embalagem_cents
                * GREATEST(1, CEIL(ROUND(COALESCE(p_subtotal, 0) * 100) / r.embalagem_escalao_cents::numeric))
                / 100.0
         END, 2)
    FROM public.restaurants r
   WHERE r.id = p_restaurant_id;
$f$;

CREATE OR REPLACE FUNCTION public.e_embalagem_da_loja(p_restaurant_id text, p_bag_fee numeric)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $f$
  SELECT COALESCE(p_bag_fee, 0) > 0 AND EXISTS (
    SELECT 1 FROM public.restaurants x
     WHERE x.id = p_restaurant_id
       AND COALESCE(x.embalagem_cents, 0) > 0
       AND ROUND(p_bag_fee * 100)::int % x.embalagem_cents = 0);
$f$;

DO $mig$
DECLARE d text; d0 text;
BEGIN
  -- quote_order_pricing: diz à app o nome da linha ("Embalagem" ou "Saco")
  d := pg_get_functiondef('public.quote_order_pricing'::regproc); d0 := d;
  d := replace(d, $q$    'bag_fee', v_bag_fee,
    'apartment_surcharge'$q$, $q$    'bag_fee', v_bag_fee,
    'bag_label', CASE WHEN public.e_embalagem_da_loja(v_restaurant_id, v_bag_fee) THEN 'Embalagem' ELSE 'Saco' END,
    'embalagem_da_loja', public.e_embalagem_da_loja(v_restaurant_id, v_bag_fee),
    'apartment_surcharge'$q$);
  IF d = d0 THEN RAISE EXCEPTION 'quote_order_pricing: texto nao encontrado'; END IF;
  EXECUTE d;

  -- admin_weekly_bora_totals: a embalagem da loja não é receita da Bora
  d := pg_get_functiondef('public.admin_weekly_bora_totals'::regproc); d0 := d;
  d := replace(d, $q$         COALESCE(SUM(COALESCE(bag_fee, 0)), 0)
  INTO v_orders_count$q$, $q$         COALESCE(SUM(CASE WHEN public.e_embalagem_da_loja(restaurant_id::text, bag_fee) THEN 0 ELSE COALESCE(bag_fee, 0) END), 0)
  INTO v_orders_count$q$);
  IF d = d0 THEN RAISE EXCEPTION 'admin_weekly_bora_totals: texto nao encontrado'; END IF;
  EXECUTE d;

  -- _fecho_pedidos (usado pelo fecho mensal): embalagem conta como custo (vai para a loja), não como taxa da Bora
  d := pg_get_functiondef('public._fecho_pedidos'::regproc); d0 := d;
  d := replace(d, $q$                 + coalesce(o.bag_fee,0) + coalesce(o.small_order_fee,0), 2) AS v_taxas,$q$,
$q$                 + coalesce(o.bag_fee,0) + coalesce(o.small_order_fee,0)
                 - CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN coalesce(o.bag_fee,0) ELSE 0 END, 2) AS v_taxas,
           CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN round(coalesce(o.bag_fee,0),2) ELSE 0 END AS v_emb,$q$);
  d := replace(d, $q$             WHEN o.parte_loja IS NOT NULL THEN round(o.parte_loja, 2)
$q$, $q$             WHEN o.parte_loja IS NOT NULL THEN round(o.parte_loja, 2)
               + CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN round(coalesce(o.bag_fee,0),2) ELSE 0 END
$q$);
  d := replace(d, $q$         round(coalesce(c.bag_fee,0),2), round(coalesce(c.small_order_fee,0),2),$q$,
$q$         round(coalesce(c.bag_fee,0),2) - c.v_emb, round(coalesce(c.small_order_fee,0),2),$q$);
  d := replace(d, $q$ELSE round(coalesce(c.subtotal,0),2) - c.v_custo END$q$,
$q$ELSE round(coalesce(c.subtotal,0),2) - c.v_custo + c.v_emb END$q$);
  IF position('AS v_emb,' in d) = 0 OR position('round(coalesce(c.bag_fee,0),2) - c.v_emb' in d) = 0
     OR position('- c.v_custo + c.v_emb END' in d) = 0
     OR position($q$round(o.parte_loja, 2)
               + CASE WHEN public.e_embalagem_da_loja$q$ in d) = 0 THEN
    RAISE EXCEPTION '_fecho_pedidos: texto nao encontrado';
  END IF;
  EXECUTE d;

  -- extrato_parceiro: embalagem sai das taxas da Bora e entra no que é da loja
  d := pg_get_functiondef('public.extrato_parceiro'::regproc); d0 := d;
  d := replace(d, $q$                  + COALESCE(o.bag_fee, 0) + COALESCE(o.small_order_fee, 0)) * 100)::int AS taxas_cents,$q$,
$q$                  + COALESCE(o.bag_fee, 0) + COALESCE(o.small_order_fee, 0)
                  - CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN COALESCE(o.bag_fee, 0) ELSE 0 END) * 100)::int AS taxas_cents,$q$);
  d := replace(d, $q$o.restaurant_id::text)) * 100)::int AS parceiro_cents,$q$,
$q$o.restaurant_id::text)) * 100)::int
           + CASE WHEN public.e_embalagem_da_loja(o.restaurant_id::text, o.bag_fee) THEN ROUND(COALESCE(o.bag_fee, 0) * 100)::int ELSE 0 END AS parceiro_cents,$q$);
  IF position('THEN COALESCE(o.bag_fee, 0) ELSE 0 END) * 100)::int AS taxas_cents' in d) = 0
     OR position('ELSE 0 END AS parceiro_cents' in d) = 0 THEN
    RAISE EXCEPTION 'extrato_parceiro: texto nao encontrado';
  END IF;
  EXECUTE d;
END
$mig$;