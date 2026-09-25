-- ============================================================================
-- MEXE EM PAGAMENTO/DINHEIRO — aplicada com o "vai" do Danilo (22/09/2026).
-- Parceiro edita pedido — parte do dinheiro        run: parceiro-edita-pedido-2026-09-22
-- ----------------------------------------------------------------------------
-- Depende de 20260922200000_parceiro_edita_pedido_base.sql (já aplicada).
-- Provada em transacção com ROLLBACK a 2026-09-22 (ver RELATORIO-parceiro-edita-pedido-2026-09-22.md).
--
-- REGRA (a que já está no ar — nada muda nela, só se usa):
--   • subtotal novo = subtotal antigo − (preço da linha × unidades tiradas)
--                                     + (preço do produto + extras) × unidades novas
--     (preço do produto = products.price, o preço do APP; extras =
--      order_line_options_extras — o mesmo que o orçamento do cliente usa).
--   • taxa de serviço, comissão visível, markup oculto e comissão da plataforma:
--     pricing_calculate(subtotal novo) + o MESMO acerto por loja do gatilho
--     zz_relabel_partner_split_por_loja (partner_store_share COM loja).
--   • taxa de pedido pequeno: small_order_fee_calc(..., loja) → 0 no parceiro.
--   • entrega, saco e ganho do estafeta ficam como estão.
--   • total novo = total antigo + Δsubtotal + Δtaxa de serviço (+ Δtaxa pequena,
--     só se ela estava mesmo dentro do total).
--   • o que a loja recebe no fim sai de post_order_to_ledger / apply_order_financial_split,
--     que já lêem orders.subtotal no momento da entrega → usam o subtotal EDITADO.
--
-- DINHEIRO QUE SE MOVE:
--   Tirar (em falta)  → aplica-se logo.
--       cartão   → reembolso parcial Stripe no mesmo pagamento (Edge Function
--                  order-edit-settle, chamada daqui por pg_net; resto que o
--                  cartão não cobriu → carteira pelo split)
--       MB Way / carteira → crédito na carteira pelo split de platform_settings
--                  (wallet_split_free_pct: 80 % saldo livre + 20 % tokens)
--       dinheiro → o total a cobrar na entrega desce.
--   Acrescentar → 'pendente_cliente' até o cliente aceitar.
--       dinheiro → soma ao total (recusa se passar max_cash_amount_cents)
--       cartão   → PaymentIntent off-session no cartão guardado; se falhar, o
--                  cliente paga no ecrã (Payment Sheet). Só se aplica depois de pago.
--       MB Way   → pedido MB Way só da diferença; aplica-se quando o PI confirma.
--       Recusado → o pedido fica como estava.
--
-- ALTERA uma função de dinheiro já existente:
--   wallet_credit_refund_split ganha p_idempotency_key (DEFAULT NULL → comportamento
--   de hoje, igual ao cêntimo). Sem isto a idempotência é POR PEDIDO e um segundo
--   crédito no mesmo pedido (2.ª edição, ou cancelamento depois de uma edição)
--   seria engolido em silêncio. Backup do corpo actual: bkp_fn_wallet_credit_refund_split_20260922.
-- ============================================================================

BEGIN;

-- ── 0. Backup das funções que se tocam ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bkp_fn_wallet_credit_refund_split_20260922 AS
SELECT now() AS guardado_em, pg_get_functiondef('public.wallet_credit_refund_split(text,uuid,integer,text)'::regprocedure) AS definicao;
ALTER TABLE public.bkp_fn_wallet_credit_refund_split_20260922 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_fn_wallet_credit_refund_split_20260922 FROM PUBLIC, anon, authenticated;

-- ── 1. wallet_credit_refund_split com chave de idempotência opcional ──────
DROP FUNCTION IF EXISTS public.wallet_credit_refund_split(text, uuid, integer, text);
CREATE FUNCTION public.wallet_credit_refund_split(
  p_order_id text, p_user_id uuid, p_total_cents integer, p_reason text,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_before INTEGER;
  v_debt_cleared   INTEGER := 0;
  v_remaining      INTEGER;
  v_split_pct      NUMERIC;
  v_free_amount    INTEGER;
  v_tokens_amount  INTEGER;
  v_tokens_count   INTEGER;
  v_balance_mid    INTEGER;
  v_token_id       UUID;
  v_existing       RECORD;
  -- NULL → chave de hoje (por pedido). Com chave → por operação (ex.: edit_<grupo>).
  v_k              TEXT := COALESCE(NULLIF(trim(p_idempotency_key), ''), p_order_id);
BEGIN
  IF p_total_cents <= 0 THEN RAISE EXCEPTION 'total_must_be_positive'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_required'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  IF p_order_id IS NULL OR length(trim(p_order_id)) = 0 THEN RAISE EXCEPTION 'order_required'; END IF;

  SELECT amount_cents, balance_after_cents INTO v_existing
    FROM public.wallet_transactions
   WHERE idempotency_key IN ('refund_split_free_' || v_k, 'refund_split_settle_' || v_k)
   ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'already_applied', true,
      'free_cents', v_existing.amount_cents,
      'balance_after_cents', v_existing.balance_after_cents);
  END IF;

  INSERT INTO public.client_wallets (user_id, free_balance_cents)
    VALUES (p_user_id, 0) ON CONFLICT (user_id) DO NOTHING;
  SELECT free_balance_cents INTO v_balance_before
    FROM public.client_wallets WHERE user_id = p_user_id FOR UPDATE;

  v_remaining := p_total_cents;

  IF v_balance_before < 0 THEN
    v_debt_cleared := LEAST(-v_balance_before, v_remaining);
    v_balance_mid  := v_balance_before + v_debt_cleared;
    UPDATE public.client_wallets
      SET free_balance_cents = v_balance_mid, updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
      VALUES (p_user_id, v_debt_cleared, 'settlement',
              p_reason || ' (refund->settle debt)', p_order_id, v_balance_mid,
              'refund_split_settle_' || v_k);
    v_remaining := v_remaining - v_debt_cleared;
  ELSE
    v_balance_mid := v_balance_before;
  END IF;

  IF v_remaining > 0 THEN
    SELECT COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80)
      INTO v_split_pct;

    v_free_amount   := ROUND(v_remaining * v_split_pct);
    v_tokens_amount := v_remaining - v_free_amount;
    v_tokens_count  := v_tokens_amount * 2;

    UPDATE public.client_wallets
      SET free_balance_cents = free_balance_cents + v_free_amount,
          updated_at = now()
      WHERE user_id = p_user_id;
    INSERT INTO public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
      VALUES (p_user_id, v_free_amount, 'refund_credit_free',
              p_reason, p_order_id, v_balance_mid + v_free_amount,
              'refund_split_free_' || v_k);

    IF v_tokens_count > 0 THEN
      v_token_id := public.add_tokens(p_user_id, 'client', v_tokens_count, p_order_id);

      INSERT INTO public.wallet_transactions
        (user_id, amount_cents, kind, reason, related_order_id, balance_after_cents, idempotency_key)
        VALUES (p_user_id, v_tokens_amount, 'refund_credit_tokens',
                p_reason || ' (' || v_tokens_count || ' tokens)', p_order_id,
                v_balance_mid + v_free_amount,
                'refund_split_tokens_' || v_k);
    END IF;
  ELSE
    v_free_amount   := 0;
    v_tokens_amount := 0;
    v_tokens_count  := 0;
    v_split_pct     := COALESCE((public.get_setting('wallet_split_free_pct'))::numeric, 0.80);
  END IF;

  BEGIN
    PERFORM public.log_admin_action('wallet_refund_split','order',NULL,
      jsonb_build_object('order_id',p_order_id,'user_id',p_user_id,
        'total_cents',p_total_cents,'debt_cleared_cents',v_debt_cleared,
        'free_cents',v_free_amount,'tokens_cents_value',v_tokens_amount,
        'tokens_count',v_tokens_count,'split_pct',v_split_pct,
        'balance_before_cents',v_balance_before,'idempotency_key',v_k));
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'wallet_credit_refund_split: log falhou (%): %', p_order_id, SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'debt_cleared_cents', v_debt_cleared,
    'free_cents', v_free_amount,
    'tokens_count', v_tokens_count,
    'tokens_value_cents', v_tokens_amount,
    'split_pct', v_split_pct,
    'balance_before_cents', v_balance_before
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.wallet_credit_refund_split(text, uuid, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_credit_refund_split(text, uuid, integer, text, text) TO service_role;

-- ── 2. Dinheiro de um pedido de loja parceira para um subtotal novo ───────
-- Mesma regra do INSERT: pricing_calculate + o acerto por loja do gatilho
-- zz_relabel_partner_split_por_loja. Devolve os campos a gravar + o Δ do total.
CREATE OR REPLACE FUNCTION public._order_edit_money(p_order_id text, p_new_subtotal numeric)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o        public.orders%ROWTYPE;
  pc       RECORD;
  v_sub    numeric := ROUND(p_new_subtotal, 2);
  v_pct    numeric;
  v_rate   numeric;
  v_share0 numeric; v_share1 numeric; v_markup numeric; v_comm numeric;
  v_small  numeric; v_small_in_total boolean; v_delta numeric;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF v_sub <= 0 THEN RAISE EXCEPTION 'SUBTOTAL_ZERO: usa cancelar o pedido'; END IF;

  SELECT * INTO pc FROM public.pricing_calculate(
    o.service_type, v_sub, o.distance_km, true,
    COALESCE(o.apartment_delivery, false), false, COALESCE(o.bag_count, 0));

  -- acerto por loja (igual a fn_relabel_partner_split_por_loja)
  SELECT app_markup_pct INTO v_pct FROM public.restaurants WHERE id = o.restaurant_id;
  v_markup := pc.partner_markup_hidden;
  v_comm   := pc.platform_commission;
  IF COALESCE(v_pct, 0) > 0 THEN
    v_rate   := COALESCE((SELECT (value::text)::numeric FROM public.platform_settings
                           WHERE key = 'partner_hidden_markup_pct'), 0.05);
    v_share0 := public.partner_store_share(v_sub);
    v_share1 := public.partner_store_share(v_sub, o.restaurant_id);
    v_markup := ROUND(v_share1 * v_rate, 2);
    v_comm   := pc.platform_commission + (v_share0 - v_share1) + (pc.partner_markup_hidden - v_markup);
  END IF;

  v_small := COALESCE(public.small_order_fee_calc(o.service_type, v_sub, o.restaurant_id), 0);
  -- A taxa pequena antiga só conta para o Δ se estava mesmo dentro do total
  -- (houve pedidos antigos com a taxa gravada e não cobrada).
  v_small_in_total := ABS(COALESCE(o.price, 0)
      - (COALESCE(o.subtotal,0) + COALESCE(o.service_fee,0) + COALESCE(o.delivery_fee,0)
         + COALESCE(o.bag_fee,0) + COALESCE(o.small_order_fee,0))) < 0.005;
  IF NOT v_small_in_total THEN v_small := COALESCE(o.small_order_fee, 0); END IF;

  v_delta := ROUND((v_sub - COALESCE(o.subtotal, 0))
                 + (pc.service_fee - COALESCE(o.service_fee, 0))
                 + (v_small - COALESCE(o.small_order_fee, 0)), 2);

  RETURN jsonb_build_object(
    'subtotal', v_sub,
    'service_fee', pc.service_fee,
    'partner_service_fee_client', pc.service_fee,
    'partner_markup_hidden', v_markup,
    'partner_commission_visible', ROUND(v_comm, 2),
    'platform_commission', ROUND(v_comm, 2),
    'small_order_fee', v_small,
    'delta_total', v_delta,
    'total_antes', ROUND(COALESCE(o.final_total, o.price, 0), 2),
    'total_depois', ROUND(COALESCE(o.final_total, o.price, 0) + v_delta, 2),
    'loja_recebe_depois', public.partner_store_share(v_sub, o.restaurant_id));
END $$;
REVOKE ALL ON FUNCTION public._order_edit_money(text, numeric) FROM PUBLIC, anon, authenticated;

-- ── 3. Construir a alteração (itens novos + linhas + números) ─────────────
-- p_alteracoes = [ {"tipo":"remove","linha_idx":0,"quantidade":1},
--                  {"tipo":"qty","linha_idx":1,"quantidade":2},
--                  {"tipo":"add","product_id":"x","quantidade":1,
--                   "opcoes":[{"group":"Extras","items":["Whey"]}]} ]
-- Uma chamada é SÓ de tirar ou SÓ de acrescentar (tirar aplica-se já; acrescentar espera o cliente).
CREATE OR REPLACE FUNCTION public._order_edit_build(p_order_id text, p_alteracoes jsonb, p_grupo_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o          public.orders%ROWTYPE;
  v_items    jsonb;
  v_alt      jsonb;
  v_tipo     text;
  v_idx      integer;
  v_qtd      integer;
  v_line     jsonb;
  v_prod     RECORD;
  v_extras   numeric; v_priced jsonb;
  v_unit     numeric;
  v_sub      numeric;
  v_linhas   jsonb := '[]'::jsonb;
  v_kind     text := NULL;
  v_kind_l   text;
  v_money    jsonb;
  j          integer;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF jsonb_typeof(p_alteracoes) <> 'array' OR jsonb_array_length(p_alteracoes) = 0 THEN
    RAISE EXCEPTION 'SEM_ALTERACOES';
  END IF;

  v_items := COALESCE(o.items, '[]'::jsonb);
  v_sub   := ROUND(COALESCE(o.subtotal, 0), 2);

  FOR v_alt IN SELECT * FROM jsonb_array_elements(p_alteracoes) LOOP
    v_tipo := v_alt->>'tipo';
    v_qtd  := COALESCE((v_alt->>'quantidade')::integer, 0);
    IF v_tipo NOT IN ('add','remove','qty') THEN RAISE EXCEPTION 'TIPO_INVALIDO: %', v_tipo; END IF;
    IF v_qtd <= 0 OR v_qtd > 99 THEN RAISE EXCEPTION 'QUANTIDADE_INVALIDA'; END IF;
    -- (plpgsql corta a condição de um IF no primeiro THEN: o CASE vai para uma variável)
    v_kind_l := CASE WHEN v_tipo = 'remove' THEN 'remove' ELSE 'add' END;
    IF v_kind IS NULL THEN v_kind := v_kind_l;
    ELSIF v_kind <> v_kind_l THEN
      RAISE EXCEPTION 'MISTURA: tirar e acrescentar vão em pedidos separados';
    END IF;

    IF v_tipo IN ('remove','qty') THEN
      v_idx := (v_alt->>'linha_idx')::integer;
      -- a linha é procurada pelo índice; se o índice já não bate com o produto
      -- (outra edição mexeu nas linhas), procura a 1.ª com o mesmo produto+opções.
      IF v_idx IS NULL OR v_idx < 0 OR v_idx >= jsonb_array_length(v_items)
         OR (v_alt ? 'product_id' AND (v_items->v_idx->>'productId') IS DISTINCT FROM (v_alt->>'product_id')) THEN
        v_idx := NULL;
        FOR j IN 0 .. jsonb_array_length(v_items) - 1 LOOP
          IF (v_items->j->>'productId') = (v_alt->>'product_id')
             AND COALESCE(v_items->j->'selected_options','[]'::jsonb) = COALESCE(v_alt->'opcoes', v_items->j->'selected_options', '[]'::jsonb) THEN
            v_idx := j; EXIT;
          END IF;
        END LOOP;
        IF v_idx IS NULL THEN RAISE EXCEPTION 'LINHA_NAO_EXISTE'; END IF;
      END IF;
      v_line := v_items->v_idx;
      v_unit := ROUND(COALESCE((v_line->>'price')::numeric, 0), 2);

      IF v_tipo = 'remove' THEN
        IF v_qtd > COALESCE((v_line->>'quantity')::integer, 1) THEN RAISE EXCEPTION 'TIRA_MAIS_DO_QUE_HA'; END IF;
        v_sub := v_sub - v_unit * v_qtd;
        IF v_qtd = COALESCE((v_line->>'quantity')::integer, 1) THEN
          v_items := v_items - v_idx;
        ELSE
          v_items := jsonb_set(v_items, ARRAY[v_idx::text, 'quantity'],
                               to_jsonb(COALESCE((v_line->>'quantity')::integer, 1) - v_qtd));
        END IF;
      ELSE -- qty (+ unidades do mesmo produto, mesmo preço da linha)
        v_sub := v_sub + v_unit * v_qtd;
        v_items := jsonb_set(v_items, ARRAY[v_idx::text, 'quantity'],
                             to_jsonb(COALESCE((v_line->>'quantity')::integer, 1) + v_qtd));
      END IF;

      v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
        'tipo', v_tipo, 'linha_idx', v_idx, 'product_id', v_line->>'productId',
        'nome', v_line->>'name', 'opcoes', COALESCE(v_line->'selected_options','[]'::jsonb),
        'quantidade', v_qtd, 'preco_unitario', v_unit));

    ELSE -- add
      SELECT p.id, p.name, p.price, p.is_available, p.restaurant_id INTO v_prod
        FROM public.products p WHERE p.id = v_alt->>'product_id';
      IF NOT FOUND OR v_prod.restaurant_id IS DISTINCT FROM o.restaurant_id THEN
        RAISE EXCEPTION 'PRODUTO_NAO_E_DA_LOJA';
      END IF;
      IF NOT COALESCE(v_prod.is_available, false) THEN RAISE EXCEPTION 'PRODUTO_INDISPONIVEL'; END IF;
      v_extras := 0; v_priced := '[]'::jsonb;
      IF jsonb_typeof(v_alt->'opcoes') = 'array' AND jsonb_array_length(v_alt->'opcoes') > 0 THEN
        SELECT t.extras_total, t.options_priced INTO v_extras, v_priced
          FROM public.order_line_options_extras(v_prod.id, v_alt->'opcoes') t;
      END IF;
      v_unit := ROUND(COALESCE(v_prod.price, 0) + COALESCE(v_extras, 0), 2);
      v_sub  := v_sub + v_unit * v_qtd;
      v_items := v_items || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'name', v_prod.name, 'price', v_unit, 'quantity', v_qtd,
        'basePrice', v_prod.price, 'productId', v_prod.id, 'purchaseStatus', 'pending',
        'selected_options', CASE WHEN v_extras IS NOT NULL AND jsonb_array_length(COALESCE(v_alt->'opcoes','[]'::jsonb)) > 0 THEN v_alt->'opcoes' END,
        'selected_options_priced', CASE WHEN jsonb_array_length(v_priced) > 0 THEN v_priced END,
        'added_by_partner', true,
        'order_edit_group', p_grupo_id)));
      v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
        'tipo', 'add', 'linha_idx', jsonb_array_length(v_items) - 1, 'product_id', v_prod.id,
        'nome', v_prod.name, 'opcoes', COALESCE(v_alt->'opcoes','[]'::jsonb),
        'quantidade', v_qtd, 'preco_unitario', v_unit));
    END IF;
  END LOOP;

  v_sub := ROUND(v_sub, 2);
  IF v_sub <= 0 OR jsonb_array_length(v_items) = 0 THEN
    RAISE EXCEPTION 'PEDIDO_FICA_VAZIO: para tirar tudo, cancela o pedido';
  END IF;

  v_money := public._order_edit_money(p_order_id, v_sub);
  RETURN jsonb_build_object(
    'kind', v_kind, 'linhas', v_linhas, 'itens_novos', v_items,
    'subtotal_antes', ROUND(COALESCE(o.subtotal,0),2), 'subtotal_depois', v_sub,
    'total_antes', v_money->'total_antes', 'total_depois', v_money->'total_depois',
    'diferenca', v_money->'delta_total', 'dinheiro', v_money);
END $$;
REVOKE ALL ON FUNCTION public._order_edit_build(text, jsonb, uuid) FROM PUBLIC, anon, authenticated;

-- ── 4. Guarda comum: quem pode e quando ────────────────────────────────────
CREATE OR REPLACE FUNCTION public._order_edit_guard(p_order_id text, p_para_escrever boolean)
RETURNS public.orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o public.orders%ROWTYPE;
BEGIN
  IF p_para_escrever THEN
    SELECT * INTO o FROM public.orders WHERE id = p_order_id FOR UPDATE;
  ELSE
    SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT COALESCE(o.is_partner_store, false) THEN RAISE EXCEPTION 'SO_LOJAS_PARCEIRAS'; END IF;
  IF NOT public.is_admin() AND NOT EXISTS (
       SELECT 1 FROM public.restaurants r WHERE r.id = o.restaurant_id AND r.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'NAO_E_A_TUA_LOJA' USING ERRCODE = '42501';
  END IF;
  IF o.status NOT IN ('created','preparing','callingDriver','driverAccepted','readyForPickup')
     OR o.takeaway_picked_up_at IS NOT NULL THEN
    RAISE EXCEPTION 'JA_RECOLHIDO: o pedido já saiu da loja';
  END IF;
  IF o.payment_method IN ('card','mbway') AND COALESCE(o.payment_status,'') <> 'paid' THEN
    RAISE EXCEPTION 'PAGAMENTO_POR_CONFIRMAR';
  END IF;
  RETURN o;
END $$;
REVOKE ALL ON FUNCTION public._order_edit_guard(text, boolean) FROM PUBLIC, anon, authenticated;

-- ── 5. Chamadas para fora (push e Edge Function), sem travar a transacção ──
CREATE OR REPLACE FUNCTION public._order_edit_http(p_fn text, p_body jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_url text; v_key text;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE WARNING '_order_edit_http: segredos em falta, % não chamado', p_fn; RETURN;
  END IF;
  PERFORM net.http_post(
    url := v_url || '/functions/v1/' || p_fn,
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := p_body);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_order_edit_http(%): %', p_fn, SQLERRM;
END $$;
REVOKE ALL ON FUNCTION public._order_edit_http(text, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._order_edit_avisa(p_order_id text, p_cliente_titulo text, p_cliente_texto text, p_estafeta boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF p_cliente_titulo IS NOT NULL AND o.user_id IS NOT NULL THEN
    PERFORM public._push_in_app_notification(o.user_id, 'order_edit', p_cliente_titulo, p_cliente_texto, p_order_id);
    PERFORM public._order_edit_http('notify-client', jsonb_build_object(
      'clientId', o.user_id::text, 'orderId', p_order_id,
      'title', p_cliente_titulo, 'body', p_cliente_texto));
  END IF;
  IF p_estafeta AND NULLIF(o.assigned_driver_id, '') IS NOT NULL THEN
    BEGIN
      PERFORM public._push_in_app_notification(o.assigned_driver_id::uuid, 'order_edit',
        'Pedido alterado pela loja',
        'A lista do pedido mudou.' || CASE WHEN o.payment_method = 'cash'
          THEN ' Cobra ' || to_char(COALESCE(o.final_total, o.price), 'FM999990.00') || ' € na entrega.' ELSE '' END,
        p_order_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING '_order_edit_avisa estafeta: %', SQLERRM; END;
    PERFORM public._order_edit_http('notify-driver-assigned', jsonb_build_object(
      'driverId', o.assigned_driver_id, 'orderId', p_order_id, 'type', 'order_updated',
      'title', 'Pedido alterado pela loja',
      'body', 'A lista do pedido mudou.' || CASE WHEN o.payment_method = 'cash'
          THEN ' Cobra ' || to_char(COALESCE(o.final_total, o.price), 'FM999990.00') || ' € na entrega.' ELSE '' END));
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._order_edit_avisa(text, text, text, boolean) FROM PUBLIC, anon, authenticated;

-- ── 6. Aplicar um grupo ao pedido (recalcula SEMPRE sobre o pedido actual) ─
CREATE OR REPLACE FUNCTION public._order_edit_apply(p_grupo_id uuid, p_liquidacao jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_order  text;
  v_estado text;
  o        public.orders%ROWTYPE;
  v_alts   jsonb;
  v_b      jsonb;
  v_m      jsonb;
  v_delta  numeric;
  v_cents  integer;
  v_liq    jsonb := COALESCE(p_liquidacao, '{}'::jsonb);
  v_cap    numeric;
  v_w      jsonb;
  v_nomes  text;
BEGIN
  SELECT order_id, estado INTO v_order, v_estado FROM public.order_edits WHERE grupo_id = p_grupo_id LIMIT 1;
  IF v_order IS NULL THEN RAISE EXCEPTION 'GRUPO_NAO_EXISTE'; END IF;
  IF v_estado = 'aplicado' THEN RETURN jsonb_build_object('ok', true, 'ja_aplicado', true); END IF;
  IF v_estado <> 'aceite' THEN RAISE EXCEPTION 'GRUPO_NAO_ACEITE: %', v_estado; END IF;

  SELECT * INTO o FROM public.orders WHERE id = v_order FOR UPDATE;

  SELECT jsonb_agg(jsonb_build_object('tipo', tipo, 'linha_idx', linha_idx, 'product_id', product_id,
                                      'opcoes', opcoes, 'quantidade', quantidade) ORDER BY id),
         string_agg(quantidade || '× ' || nome, ', ' ORDER BY id)
    INTO v_alts, v_nomes
    FROM public.order_edits WHERE grupo_id = p_grupo_id;

  v_b := public._order_edit_build(v_order, v_alts, p_grupo_id);
  v_m := v_b->'dinheiro';
  v_delta := (v_m->>'delta_total')::numeric;
  v_cents := ROUND(ABS(v_delta) * 100)::integer;

  IF o.payment_method = 'cash' AND v_delta > 0 THEN
    v_cap := COALESCE((public.get_setting('max_cash_amount_cents')::text)::numeric, 4000) / 100.0;
    IF (v_m->>'total_depois')::numeric > v_cap THEN
      RAISE EXCEPTION 'LIMITE_DINHEIRO: pagamento em dinheiro só até % €', to_char(v_cap, 'FM999990.00');
    END IF;
  END IF;

  PERFORM set_config('app.financial_bypass', 'true', true);
  UPDATE public.orders SET
    items                      = v_b->'itens_novos',
    subtotal                   = (v_m->>'subtotal')::numeric,
    service_fee                = (v_m->>'service_fee')::numeric,
    partner_service_fee_client = (v_m->>'partner_service_fee_client')::numeric,
    partner_markup_hidden      = (v_m->>'partner_markup_hidden')::numeric,
    partner_commission_visible = (v_m->>'partner_commission_visible')::numeric,
    platform_commission        = (v_m->>'platform_commission')::numeric,
    small_order_fee            = (v_m->>'small_order_fee')::numeric,
    price                      = ROUND(COALESCE(price, 0) + v_delta, 2),
    -- total e customer_total são colunas GERADAS (= price): seguem sozinhas.
    final_total                = CASE WHEN final_total IS NULL THEN NULL ELSE ROUND(final_total + v_delta, 2) END,
    payment_buffer_total       = CASE WHEN payment_buffer_total IS NULL THEN NULL ELSE ROUND((payment_buffer_total + v_delta)::numeric, 2) END,
    cash_total_due             = CASE WHEN cash_total_due IS NULL THEN NULL ELSE ROUND(cash_total_due + v_delta, 2) END
    -- items_added NÃO se toca: é o formato do storeShopping (price_final_cents…).
    -- O histórico das edições vive em order_edits.
  WHERE id = v_order;
  PERFORM set_config('app.financial_bypass', 'false', true);

  -- Dinheiro de volta quando se tira (o que é pago à cabeça volta; dinheiro vivo só desce)
  IF v_delta < 0 AND v_cents > 0 THEN
    IF o.payment_method = 'cash' THEN
      v_liq := v_liq || jsonb_build_object('metodo', 'dinheiro', 'estado', 'feito',
                                           'devolvido_cents', v_cents, 'nota', 'total a cobrar na entrega desceu');
    ELSIF o.payment_method = 'card' AND o.payment_intent_id IS NOT NULL THEN
      v_liq := v_liq || jsonb_build_object('metodo', 'cartao', 'estado', 'pendente',
                                           'devolver_cents', v_cents, 'payment_intent_id', o.payment_intent_id);
    ELSE
      v_w := public.wallet_credit_refund_split(v_order, o.user_id, v_cents,
               'Produto em falta no pedido ' || left(v_order, 8), 'edit_' || p_grupo_id::text);
      v_liq := v_liq || jsonb_build_object('metodo', 'carteira', 'estado', 'feito',
                                           'devolvido_cents', v_cents, 'carteira', v_w);
    END IF;
  ELSIF v_delta > 0 AND o.payment_method = 'cash' THEN
    v_liq := v_liq || jsonb_build_object('metodo', 'dinheiro', 'estado', 'feito',
                                         'cobrar_a_mais_cents', v_cents, 'nota', 'soma ao total a cobrar na entrega');
  END IF;

  UPDATE public.order_edits SET
    estado = 'aplicado', aplicado_em = now(), liquidacao = v_liq,
    subtotal_antes = (v_b->>'subtotal_antes')::numeric, subtotal_depois = (v_b->>'subtotal_depois')::numeric,
    total_antes = (v_b->>'total_antes')::numeric, total_depois = (v_b->>'total_depois')::numeric
  WHERE grupo_id = p_grupo_id;

  IF v_liq->>'metodo' = 'cartao' AND v_liq->>'estado' = 'pendente' THEN
    PERFORM public._order_edit_http('order-edit-settle',
      jsonb_build_object('action', 'refund', 'grupo_id', p_grupo_id));
  END IF;

  IF v_delta < 0 THEN
    PERFORM public._order_edit_avisa(v_order, 'Produto em falta',
      v_nomes || ' não havia na loja. ' ||
      CASE o.payment_method
        WHEN 'cash' THEN 'Pagas menos ' || to_char(v_cents / 100.0, 'FM999990.00') || ' € na entrega.'
        WHEN 'card' THEN 'Foram devolvidos ' || to_char(v_cents / 100.0, 'FM999990.00') || ' € ao teu cartão.'
        ELSE 'Foram devolvidos ' || to_char(v_cents / 100.0, 'FM999990.00') || ' € à tua carteira Bora.'
      END, true);
  ELSE
    PERFORM public._order_edit_avisa(v_order, NULL, NULL, true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'grupo_id', p_grupo_id, 'delta_total', v_delta,
                            'total_depois', v_b->'total_depois', 'liquidacao', v_liq);
END $$;
REVOKE ALL ON FUNCTION public._order_edit_apply(uuid, jsonb) FROM PUBLIC, anon, authenticated;

-- ── 7. RPC do parceiro: orçamento (só lê) ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.order_edit_quote(p_order_id text, p_alteracoes jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_b jsonb;
BEGIN
  PERFORM public._order_edit_guard(p_order_id, false);
  v_b := public._order_edit_build(p_order_id, p_alteracoes, NULL);
  -- a app nunca vê comissão nem markup: só os totais do cliente
  RETURN jsonb_build_object('ok', true, 'kind', v_b->'kind', 'linhas', v_b->'linhas',
    'subtotal_antes', v_b->'subtotal_antes', 'subtotal_depois', v_b->'subtotal_depois',
    'total_antes', v_b->'total_antes', 'total_depois', v_b->'total_depois',
    'diferenca', v_b->'diferenca',
    'loja_recebe_depois', v_b->'dinheiro'->'loja_recebe_depois');
END $$;
REVOKE ALL ON FUNCTION public.order_edit_quote(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.order_edit_quote(text, jsonb) TO authenticated;

-- ── 8. RPC do parceiro: propor ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_propose_order_edit(p_order_id text, p_alteracoes jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o       public.orders%ROWTYPE;
  v_b     jsonb;
  v_grupo uuid := gen_random_uuid();
  v_l     jsonb;
  v_estado text;
  v_cap   numeric;
  v_res   jsonb;
  v_nomes text;
BEGIN
  IF NOT COALESCE((public.get_setting('order_edit_enabled')::text)::boolean, false) THEN
    RAISE EXCEPTION 'EDICAO_DESLIGADA';
  END IF;
  o := public._order_edit_guard(p_order_id, true);

  v_b := public._order_edit_build(p_order_id, p_alteracoes, v_grupo);

  IF v_b->>'kind' = 'add' THEN
    IF EXISTS (SELECT 1 FROM public.order_edits WHERE order_id = p_order_id AND estado IN ('pendente_cliente','aceite')) THEN
      RAISE EXCEPTION 'JA_HA_PROPOSTA: espera a resposta do cliente';
    END IF;
    IF o.payment_method = 'cash' THEN
      v_cap := COALESCE((public.get_setting('max_cash_amount_cents')::text)::numeric, 4000) / 100.0;
      IF (v_b->>'total_depois')::numeric > v_cap THEN
        RAISE EXCEPTION 'LIMITE_DINHEIRO: pagamento em dinheiro só até % €', to_char(v_cap, 'FM999990.00');
      END IF;
    ELSIF (v_b->>'diferenca')::numeric < 0.50 THEN
      RAISE EXCEPTION 'VALOR_MINIMO: a diferença a cobrar tem de ser pelo menos 0,50 €';
    END IF;
    v_estado := 'pendente_cliente';
  ELSE
    v_estado := 'aceite'; -- tirar não precisa do cliente: aplica-se já
  END IF;

  FOR v_l IN SELECT * FROM jsonb_array_elements(v_b->'linhas') LOOP
    INSERT INTO public.order_edits (grupo_id, order_id, restaurant_id, editado_por, tipo, linha_idx,
      product_id, nome, opcoes, quantidade, preco_unitario,
      subtotal_antes, subtotal_depois, total_antes, total_depois, estado)
    VALUES (v_grupo, p_order_id, o.restaurant_id, auth.uid(), v_l->>'tipo', (v_l->>'linha_idx')::integer,
      v_l->>'product_id', COALESCE(v_l->>'nome','?'), COALESCE(v_l->'opcoes','[]'::jsonb),
      (v_l->>'quantidade')::integer, (v_l->>'preco_unitario')::numeric,
      (v_b->>'subtotal_antes')::numeric, (v_b->>'subtotal_depois')::numeric,
      (v_b->>'total_antes')::numeric, (v_b->>'total_depois')::numeric, v_estado);
  END LOOP;

  IF v_estado = 'aceite' THEN
    v_res := public._order_edit_apply(v_grupo, '{}'::jsonb);
  ELSE
    SELECT string_agg(quantidade || '× ' || nome, ', ') INTO v_nomes FROM public.order_edits WHERE grupo_id = v_grupo;
    PERFORM public._order_edit_avisa(p_order_id, 'A loja quer acrescentar ao teu pedido',
      v_nomes || ' (+' || to_char((v_b->>'diferenca')::numeric, 'FM999990.00') || ' €). Aceitar ou recusar?', false);
    v_res := jsonb_build_object('ok', true);
  END IF;

  RETURN v_res || jsonb_build_object('grupo_id', v_grupo, 'estado',
    (SELECT estado FROM public.order_edits WHERE grupo_id = v_grupo LIMIT 1),
    'total_antes', v_b->'total_antes', 'total_depois', v_b->'total_depois', 'diferenca', v_b->'diferenca');
END $$;
REVOKE ALL ON FUNCTION public.partner_propose_order_edit(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_propose_order_edit(text, jsonb) TO authenticated;

-- ── 9. RPC do cliente: aceitar / recusar ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_respond_order_edit(p_grupo_id uuid, p_aceitar boolean)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_order text; v_estado text; o public.orders%ROWTYPE; v_res jsonb; v_b jsonb; v_alts jsonb;
BEGIN
  SELECT order_id, estado INTO v_order, v_estado FROM public.order_edits WHERE grupo_id = p_grupo_id LIMIT 1;
  IF v_order IS NULL THEN RAISE EXCEPTION 'GRUPO_NAO_EXISTE'; END IF;
  SELECT * INTO o FROM public.orders WHERE id = v_order FOR UPDATE;
  IF o.user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'NAO_E_O_TEU_PEDIDO' USING ERRCODE = '42501';
  END IF;
  IF v_estado <> 'pendente_cliente' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'JA_RESPONDIDO', 'estado', v_estado);
  END IF;

  IF NOT p_aceitar THEN
    UPDATE public.order_edits SET estado = 'recusado', respondido_em = now(),
           motivo = COALESCE(motivo, 'cliente recusou') WHERE grupo_id = p_grupo_id;
    PERFORM public._push_in_app_notification(r.user_id, 'order_edit', 'O cliente recusou',
      'O pedido fica como estava.', v_order)
      FROM public.restaurants r WHERE r.id = o.restaurant_id;
    RETURN jsonb_build_object('ok', true, 'estado', 'recusado');
  END IF;

  IF o.status NOT IN ('created','preparing','callingDriver','driverAccepted','readyForPickup')
     OR o.takeaway_picked_up_at IS NOT NULL THEN
    UPDATE public.order_edits SET estado = 'recusado', respondido_em = now(),
           motivo = 'o pedido já tinha saído da loja' WHERE grupo_id = p_grupo_id;
    RETURN jsonb_build_object('ok', false, 'erro', 'JA_RECOLHIDO');
  END IF;

  UPDATE public.order_edits SET estado = 'aceite', respondido_em = now() WHERE grupo_id = p_grupo_id;

  IF o.payment_method = 'cash' THEN
    v_res := public._order_edit_apply(p_grupo_id, '{}'::jsonb);
    RETURN v_res || jsonb_build_object('estado', 'aplicado', 'precisa_pagamento', false);
  END IF;

  -- cartão / MB Way: fica 'aceite' até o pagamento confirmar (order-edit-settle)
  SELECT jsonb_agg(jsonb_build_object('tipo', tipo, 'linha_idx', linha_idx, 'product_id', product_id,
                                      'opcoes', opcoes, 'quantidade', quantidade) ORDER BY id)
    INTO v_alts FROM public.order_edits WHERE grupo_id = p_grupo_id;
  v_b := public._order_edit_build(v_order, v_alts, p_grupo_id);
  UPDATE public.order_edits SET liquidacao = jsonb_build_object(
      'metodo', CASE WHEN o.payment_method = 'card' THEN 'cartao' ELSE 'mbway' END,
      'estado', 'a_cobrar', 'cobrar_cents', ROUND(((v_b->>'diferenca')::numeric) * 100)::integer)
   WHERE grupo_id = p_grupo_id;
  RETURN jsonb_build_object('ok', true, 'estado', 'aceite', 'precisa_pagamento', true,
    'metodo', o.payment_method, 'cobrar_cents', ROUND(((v_b->>'diferenca')::numeric) * 100)::integer);
END $$;
REVOKE ALL ON FUNCTION public.client_respond_order_edit(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_respond_order_edit(uuid, boolean) TO authenticated;

-- ── 10. Só a Edge Function (service_role): pagamento da diferença confirmado ─
CREATE OR REPLACE FUNCTION public.order_edit_mark_paid(p_grupo_id uuid, p_payment_intent_id text, p_amount_cents integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_liq jsonb; v_estado text; v_res jsonb;
BEGIN
  SELECT estado, liquidacao INTO v_estado, v_liq FROM public.order_edits WHERE grupo_id = p_grupo_id LIMIT 1;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'GRUPO_NAO_EXISTE'; END IF;
  IF v_estado = 'aplicado' THEN RETURN jsonb_build_object('ok', true, 'ja_aplicado', true); END IF;
  IF v_estado <> 'aceite' THEN RAISE EXCEPTION 'GRUPO_NAO_ACEITE: %', v_estado; END IF;
  IF p_amount_cents IS DISTINCT FROM (v_liq->>'cobrar_cents')::integer THEN
    RAISE EXCEPTION 'VALOR_NAO_BATE: pago % vs a cobrar %', p_amount_cents, v_liq->>'cobrar_cents';
  END IF;
  v_res := public._order_edit_apply(p_grupo_id,
    v_liq || jsonb_build_object('estado', 'pago', 'payment_intent_id', p_payment_intent_id,
                                'cobrado_cents', p_amount_cents, 'pago_em', now()));
  RETURN v_res;
END $$;
REVOKE ALL ON FUNCTION public.order_edit_mark_paid(uuid, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.order_edit_mark_paid(uuid, text, integer) TO service_role;

-- ── 11. Só a Edge Function (service_role): reembolso Stripe feito ──────────
-- p_resto_cents = parte que o cartão já não cobria (carteira/tokens) → carteira pelo split.
CREATE OR REPLACE FUNCTION public.order_edit_refund_done(p_grupo_id uuid, p_refund_id text, p_refunded_cents integer, p_resto_cents integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_liq jsonb; v_order text; v_user uuid; v_w jsonb := NULL;
BEGIN
  SELECT e.liquidacao, e.order_id, o.user_id INTO v_liq, v_order, v_user
    FROM public.order_edits e JOIN public.orders o ON o.id = e.order_id
   WHERE e.grupo_id = p_grupo_id LIMIT 1;
  IF v_order IS NULL THEN RAISE EXCEPTION 'GRUPO_NAO_EXISTE'; END IF;
  IF v_liq->>'estado' = 'feito' THEN RETURN jsonb_build_object('ok', true, 'ja_feito', true); END IF;
  IF COALESCE(p_refunded_cents,0) + COALESCE(p_resto_cents,0) <> (v_liq->>'devolver_cents')::integer THEN
    RAISE EXCEPTION 'SOMA_NAO_BATE: % + % <> %', p_refunded_cents, p_resto_cents, v_liq->>'devolver_cents';
  END IF;
  IF COALESCE(p_resto_cents, 0) > 0 THEN
    v_w := public.wallet_credit_refund_split(v_order, v_user, p_resto_cents,
             'Produto em falta (parte da carteira) ' || left(v_order, 8), 'edit_' || p_grupo_id::text);
  END IF;
  UPDATE public.order_edits SET liquidacao = v_liq || jsonb_build_object(
      'estado', 'feito', 'refund_id', p_refund_id, 'devolvido_cartao_cents', p_refunded_cents,
      'devolvido_carteira_cents', COALESCE(p_resto_cents,0), 'carteira', v_w, 'feito_em', now())
   WHERE grupo_id = p_grupo_id;
  RETURN jsonb_build_object('ok', true);
END $$;
REVOKE ALL ON FUNCTION public.order_edit_refund_done(uuid, text, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.order_edit_refund_done(uuid, text, integer, integer) TO service_role;

-- Falha do Stripe fica registada (sem engolir) para o admin forçar outra vez.
CREATE OR REPLACE FUNCTION public.order_edit_settle_failed(p_grupo_id uuid, p_erro text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.order_edits SET liquidacao = liquidacao || jsonb_build_object(
      'ultimo_erro', left(p_erro, 500), 'ultimo_erro_em', now(),
      'tentativas', COALESCE((liquidacao->>'tentativas')::integer, 0) + 1)
   WHERE grupo_id = p_grupo_id;
END $$;
REVOKE ALL ON FUNCTION public.order_edit_settle_failed(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.order_edit_settle_failed(uuid, text) TO service_role;

-- ── 12. Admin (PT-BR): aprovar por conta do cliente e forçar o estorno ─────
CREATE OR REPLACE FUNCTION public.admin_approve_order_edit(p_grupo_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_res jsonb; v_order text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = '42501'; END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN RAISE EXCEPTION 'MOTIVO_OBRIGATORIO'; END IF;
  SELECT order_id INTO v_order FROM public.order_edits WHERE grupo_id = p_grupo_id LIMIT 1;
  v_res := public.client_respond_order_edit(p_grupo_id, true);
  UPDATE public.order_edits SET motivo = 'admin aprovou: ' || trim(p_motivo) WHERE grupo_id = p_grupo_id;
  IF COALESCE((v_res->>'precisa_pagamento')::boolean, false) THEN
    PERFORM public._order_edit_http('order-edit-settle', jsonb_build_object('action', 'charge', 'grupo_id', p_grupo_id));
  END IF;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt() ->> 'email', 'order_edit_approve', 'order', v_order,
          jsonb_build_object('grupo_id', p_grupo_id, 'motivo', p_motivo, 'resultado', v_res));
  RETURN v_res;
END $$;
REVOKE ALL ON FUNCTION public.admin_approve_order_edit(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_order_edit(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_force_refund_order_edit(p_grupo_id uuid, p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_liq jsonb; v_order text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_ONLY' USING ERRCODE = '42501'; END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN RAISE EXCEPTION 'MOTIVO_OBRIGATORIO'; END IF;
  SELECT liquidacao, order_id INTO v_liq, v_order FROM public.order_edits WHERE grupo_id = p_grupo_id LIMIT 1;
  IF v_liq->>'metodo' <> 'cartao' OR v_liq->>'estado' <> 'pendente' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'NADA_A_ESTORNAR', 'liquidacao', v_liq);
  END IF;
  PERFORM public._order_edit_http('order-edit-settle', jsonb_build_object('action', 'refund', 'grupo_id', p_grupo_id));
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt() ->> 'email', 'order_edit_force_refund', 'order', v_order,
          jsonb_build_object('grupo_id', p_grupo_id, 'motivo', p_motivo, 'liquidacao', v_liq));
  RETURN jsonb_build_object('ok', true, 'pedido', 'estorno pedido à Stripe');
END $$;
REVOKE ALL ON FUNCTION public.admin_force_refund_order_edit(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_force_refund_order_edit(uuid, text) TO authenticated;

-- ── 13. O interruptor order_edit_enabled NÃO se liga aqui ─────────────────
-- Liga-se à parte, só depois da prova real passar e do build Android com
-- esta versão estar no Play (ordem do Danilo, 22/09/2026).

COMMIT;
