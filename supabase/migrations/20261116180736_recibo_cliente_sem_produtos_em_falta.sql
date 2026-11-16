-- 16/11/2026 (Danilo 18:05): o resumo do pedido por email (recibo-pedido-cliente) listava produtos
-- que o estafeta marcou como em falta (caso morango, pedido 96db899f da Leticia). O total cobrado
-- estava certo (final_total), mas os itens vinham de orders.items (lista original).
-- Agora, quando ha compra registada em order_purchase_items_v2, os itens saem dai, com as mesmas
-- regras do finalizar_talao_nao_parceiro: em falta nao entra; substituido com nome/qtd/preco reais;
-- acrescentado com o preco real + non_partner_markup_pct. Sem compra registada: como antes.
-- Aplicada em producao por MCP (apply_migration) a 16/11/2026 18:07 UTC.
CREATE OR REPLACE FUNCTION public._recibo_pedido(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o        record;
  v_itens  jsonb := '[]'::jsonb;
  v_linhas jsonb := '[]'::jsonb;
  v_desc   jsonb := '[]'::jsonb;
  v_ck_cents integer := 0;  -- 11/11/2026 R7
  v_total  integer;
  v_gorj   integer;
  v_d      integer;
  v_nif    text;
  v_nome   text;
  v_fav    boolean;
  v_markup numeric;          -- 16/11/2026
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR o.status IS DISTINCT FROM 'delivered' THEN RETURN NULL; END IF;
  v_fav := o.service_type = 'errand';

  IF v_fav THEN
    IF COALESCE(o.final_purchase_value, 0) > 0 THEN
      v_itens := jsonb_build_array(jsonb_build_object('nome', 'Compra: ' || COALESCE(NULLIF(btrim(o.errand_description), ''), 'Favor'),
                                                      'qtd', 1, 'valor_cents', ROUND(o.final_purchase_value * 100)::int));
    END IF;
    v_linhas := v_linhas || jsonb_build_object('nome', 'Serviço do Favor (deslocação e entrega)',
                                               'valor_cents', ROUND(COALESCE(o.delivery_fee, 0) * 100)::int);
  ELSE
    IF EXISTS (SELECT 1 FROM public.order_purchase_items_v2 p WHERE p.order_id = o.id) THEN
      -- 16/11/2026: itens da compra real (o que o estafeta marcou), nao da lista original.
      SELECT COALESCE((SELECT (value #>> '{}')::numeric FROM public.platform_settings WHERE key = 'non_partner_markup_pct'), 0.15)
        INTO v_markup;
      IF v_markup IS NULL OR v_markup < 0 OR v_markup > 1 THEN v_markup := 0.15; END IF;
      SELECT COALESCE(jsonb_agg(x.j ORDER BY x.ordem, x.criado), '[]'::jsonb)
        INTO v_itens
        FROM (
          SELECT CASE WHEN p.status = 'added' THEN 2 ELSE 1 END AS ordem,
                 p.created_at AS criado,
                 CASE
                   WHEN p.status = 'replaced' THEN jsonb_build_object(
                     'nome', COALESCE(NULLIF(btrim(p.actual_name), ''), p.original_name, 'Artigo')
                             || CASE WHEN NULLIF(btrim(p.actual_name), '') IS NOT NULL
                                      AND p.actual_name IS DISTINCT FROM p.original_name
                                     THEN ' (em vez de ' || COALESCE(p.original_name, 'artigo pedido') || ')' ELSE '' END,
                     'qtd', COALESCE(p.actual_qty, p.original_qty, 1),
                     'valor_cents', COALESCE(p.actual_price_cents, p.original_price_cents, 0))
                   WHEN p.status = 'added' THEN jsonb_build_object(
                     'nome', COALESCE(NULLIF(btrim(p.actual_name), ''), 'Artigo') || ' (acrescentado)',
                     'qtd', COALESCE(p.actual_qty, 1),
                     'valor_cents', ROUND(COALESCE(p.actual_price_cents, 0) * (1 + v_markup))::int)
                   ELSE jsonb_build_object(
                     'nome', COALESCE(p.original_name, 'Artigo'),
                     'qtd', COALESCE(p.original_qty, 1),
                     'valor_cents', COALESCE(p.original_price_cents, 0))
                 END AS j
            FROM public.order_purchase_items_v2 p
           WHERE p.order_id = o.id
             AND p.status IS DISTINCT FROM 'unavailable'
        ) x;
    ELSE
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'nome', COALESCE(i->>'name', 'Artigo'),
               'qtd', COALESCE(NULLIF(i->>'quantity', '')::numeric, 1),
               'valor_cents', ROUND(COALESCE(NULLIF(i->>'price', '')::numeric, 0) * 100)::int)), '[]'::jsonb)
        INTO v_itens
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.items) = 'array' THEN o.items ELSE '[]'::jsonb END) i;
    END IF;
    IF COALESCE(o.delivery_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Entrega', 'valor_cents', ROUND(o.delivery_fee * 100)::int);
    END IF;
    IF COALESCE(o.service_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Taxa de serviço', 'valor_cents', ROUND(o.service_fee * 100)::int);
    END IF;
    IF COALESCE(o.bag_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Saco', 'valor_cents', ROUND(o.bag_fee * 100)::int);
    END IF;
    IF COALESCE(o.small_order_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Pedido pequeno', 'valor_cents', ROUND(o.small_order_fee * 100)::int);
    END IF;
    IF COALESCE(o.helper_fee_eur, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Ajudante', 'valor_cents', ROUND(o.helper_fee_eur * 100)::int);
    END IF;
    -- 09/11/2026: depósito Volta em linha própria (obrigação legal), com os acertos do talão.
    IF COALESCE(o.deposit_cents, 0) + COALESCE(o.deposit_ajuste_cents, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object(
        'nome', 'Depósito Volta (' || GREATEST(1, ROUND((COALESCE(o.deposit_cents, 0) + COALESCE(o.deposit_ajuste_cents, 0))
                                                     / NULLIF(public.volta_deposito_cents_unidade(), 0)::numeric))::int
                || ' emb.)',
        'valor_cents', COALESCE(o.deposit_cents, 0) + COALESCE(o.deposit_ajuste_cents, 0));
    END IF;
  END IF;

  -- 11/11/2026 R7: desconto do check-in, pago pela Bora, em linha própria.
  SELECT COALESCE(sum(c.valor_cents), 0)::int INTO v_ck_cents FROM public.checkin_premios_vales c
   WHERE c.pedido_id = o.id AND c.tipo = 'desconto' AND c.estado = 'usado';
  IF v_ck_cents > 0 THEN
    v_linhas := v_linhas || jsonb_build_object('nome', 'Desconto do check-in (pago pela Bora)', 'valor_cents', -v_ck_cents);
  END IF;
  v_total := ROUND(COALESCE(CASE WHEN COALESCE(o.is_purchase_finalized, false) THEN o.final_total END,
                            o.customer_total, o.price, o.total, 0) * 100)::int;
  v_gorj := COALESCE(o.tip_amount_cents, 0);
  IF COALESCE(o.wallet_applied_cents, 0) > 0 THEN
    v_desc := v_desc || jsonb_build_object('nome', 'Saldo da carteira', 'valor_cents', o.wallet_applied_cents);
  END IF;
  IF COALESCE(o.tokens_applied_value_cents, 0) > 0 THEN
    v_desc := v_desc || jsonb_build_object('nome', 'Tokens Bora', 'valor_cents', o.tokens_applied_value_cents);
  END IF;
  IF COALESCE(o.menu_credit_applied_cents, 0) > 0 THEN
    v_desc := v_desc || jsonb_build_object('nome', 'Crédito', 'valor_cents', o.menu_credit_applied_cents);
  END IF;
  v_d := COALESCE(o.wallet_applied_cents, 0) + COALESCE(o.tokens_applied_value_cents, 0) + COALESCE(o.menu_credit_applied_cents, 0);

  SELECT NULLIF(btrim(COALESCE(i.nif, '')), ''), NULLIF(btrim(COALESCE(i.nome, '')), '') INTO v_nif, v_nome
    FROM public.order_invoice_requests i WHERE i.order_id = o.id;

  RETURN jsonb_build_object(
    'pedido_id', o.id,
    'numero', upper(left(replace(o.id, '-', ''), 8)),
    'data', COALESCE(o.delivered_at, o.created_at),
    'loja', COALESCE(o.vendor_name, CASE WHEN v_fav THEN 'Favor Bora' ELSE 'Bora' END),
    'tipo', o.service_type,
    'itens', v_itens,
    'linhas', v_linhas,
    'total_pedido_cents', v_total,
    'gorjeta_cents', v_gorj,
    'descontos', v_desc,
    'total_pago_cents', GREATEST(0, v_total + v_gorj - v_d),
    'metodo', o.payment_method,
    'nif', v_nif,
    'nome_fatura', v_nome,
    'user_id', o.user_id,
    'teste', COALESCE(o.is_test_order, false));
END $function$;
