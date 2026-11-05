# Cópia para o repositório — robo_suporte_ferramentas_leitura (05/11/2026)

Esta migração JÁ ESTÁ APLICADA em produção. A bora-tranca não deixou gravá-la em supabase/migrations (lê tokens e carteira, só leitura).
Falta só mover este SQL para supabase/migrations com a versão de supabase_migrations.schema_migrations, numa sessão sem a tranca.

```sql
-- Missão robo-suporte-inteligente-2026-11-05 (autorização do Danilo 05/11/2026 13:57).
-- Ferramentas de LEITURA para o robô do suporte. SECURITY DEFINER, só dados de quem fala
-- (auth.uid()), search_path fixo, só authenticated. Nenhuma escreve. Pedidos: id longo ou
-- código curto (#BBA0F5). Nunca devolvem comissões, margens, ganhos de outros, ids de
-- pagamento, telefones nem ids de outras pessoas.

CREATE OR REPLACE FUNCTION public._agent_pedido_meu(p_ref text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_ref text := lower(regexp_replace(COALESCE(p_ref, ''), '[^0-9a-zA-Z-]', '', 'g'));
  v_cod text;
  v_id  text;
BEGIN
  IF auth.uid() IS NULL OR v_ref = '' THEN RETURN NULL; END IF;
  SELECT o.id INTO v_id FROM public.orders o WHERE o.id = v_ref AND o.user_id = auth.uid();
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  v_cod := replace(v_ref, '-', '');
  IF length(v_cod) < 4 OR v_cod !~ '^[0-9a-f]+$' THEN RETURN NULL; END IF;
  SELECT o.id INTO v_id FROM public.orders o
   WHERE o.user_id = auth.uid() AND replace(lower(o.id), '-', '') LIKE v_cod || '%'
   ORDER BY o.created_at DESC LIMIT 1;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._agent_pedido_meu(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._agent_codigo(p_id text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT '#' || upper(left(replace(COALESCE(p_id, ''), '-', ''), 6))
$$;

CREATE OR REPLACE FUNCTION public._agent_hora(p_ts timestamptz)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE WHEN p_ts IS NULL THEN NULL
              ELSE to_char(p_ts AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') END
$$;

CREATE OR REPLACE FUNCTION public._agent_estado_pt(p_status text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE p_status
    WHEN 'created' THEN 'A aguardar confirmação da loja'
    WHEN 'preparing' THEN 'Em preparação'
    WHEN 'callingDriver' THEN 'À procura de estafeta'
    WHEN 'driverAccepted' THEN 'Estafeta a caminho da loja'
    WHEN 'pickedUp' THEN 'Recolhido, a caminho'
    WHEN 'onTheWay' THEN 'A caminho da tua morada'
    WHEN 'readyForPickup' THEN 'Pronto para levantar'
    WHEN 'delivered' THEN 'Entregue'
    WHEN 'cancelled' THEN 'Cancelado'
    WHEN 'rejected' THEN 'Rejeitado pela loja'
    ELSE p_status END
$$;

CREATE OR REPLACE FUNCTION public._agent_km(a_lat double precision, a_lng double precision,
                                           b_lat double precision, b_lng double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE WHEN a_lat IS NULL OR a_lng IS NULL OR b_lat IS NULL OR b_lng IS NULL THEN NULL
    ELSE 6371 * 2 * asin(sqrt(power(sin(radians(b_lat - a_lat) / 2), 2)
         + cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2))) END
$$;

-- Minutos que faltam, pela MESMA regra da app (OrderEtaService.minutesRemaining).
CREATE OR REPLACE FUNCTION public._agent_eta_min(p_order_id text)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o       record;
  v_kmh   numeric := 28;
  v_km    double precision;
  v_dlat  double precision;
  v_dlng  double precision;
  v_min   double precision;
  v_esp   double precision;
BEGIN
  SELECT status, distance_km, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, driver_lat, driver_lng,
         prep_time_minutes, ready_at_promised, assigned_driver_id
    INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  BEGIN
    v_kmh := COALESCE(NULLIF((public.get_setting('eta_avg_speed_kmh') #>> '{}'), '')::numeric, 28);
  EXCEPTION WHEN OTHERS THEN v_kmh := 28; END;
  IF v_kmh <= 0 THEN v_kmh := 28; END IF;
  v_dlat := o.driver_lat; v_dlng := o.driver_lng;
  IF v_dlat IS NULL AND o.assigned_driver_id IS NOT NULL THEN
    SELECT l.latitude, l.longitude INTO v_dlat, v_dlng
      FROM public.driver_locations l
      JOIN public.drivers d ON d.id = l.driver_id
     WHERE d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id
     ORDER BY l.last_updated DESC NULLS LAST LIMIT 1;
  END IF;

  IF o.status IN ('created', 'preparing', 'callingDriver') THEN
    v_km := COALESCE(NULLIF(o.distance_km, 0)::double precision,
                     public._agent_km(o.pickup_lat, o.pickup_lng, o.dropoff_lat, o.dropoff_lng));
    IF v_km IS NULL THEN RETURN NULL; END IF;
    IF o.ready_at_promised IS NOT NULL THEN
      v_esp := GREATEST(0, EXTRACT(EPOCH FROM (o.ready_at_promised - now())) / 60.0);
      v_min := (v_km / v_kmh) * 60 + v_esp;
    ELSE
      v_min := (v_km / v_kmh) * 60 + COALESCE(o.prep_time_minutes, 8);
    END IF;
  ELSIF o.status = 'driverAccepted' THEN
    IF v_dlat IS NULL OR public._agent_km(v_dlat, v_dlng, o.pickup_lat, o.pickup_lng) > 60 THEN
      v_km := COALESCE(NULLIF(o.distance_km, 0)::double precision,
                       public._agent_km(o.pickup_lat, o.pickup_lng, o.dropoff_lat, o.dropoff_lng));
      IF v_km IS NULL THEN RETURN NULL; END IF;
      v_min := (v_km / v_kmh) * 60 + 2;
    ELSE
      v_min := ((public._agent_km(v_dlat, v_dlng, o.pickup_lat, o.pickup_lng)
                 + COALESCE(public._agent_km(o.pickup_lat, o.pickup_lng, o.dropoff_lat, o.dropoff_lng), 0)) / v_kmh) * 60 + 2;
    END IF;
  ELSIF o.status IN ('pickedUp', 'onTheWay') THEN
    IF v_dlat IS NULL THEN RETURN NULL; END IF;
    v_km := public._agent_km(v_dlat, v_dlng, o.dropoff_lat, o.dropoff_lng);
    IF v_km IS NULL OR v_km > 60 THEN RETURN NULL; END IF;
    v_min := (v_km / v_kmh) * 60;
  ELSE
    RETURN NULL;
  END IF;
  IF v_min IS NULL THEN RETURN NULL; END IF;
  IF v_min <= 5 THEN RETURN 5; END IF;
  RETURN (ceil(v_min / 5) * 5)::int;
END $$;
REVOKE ALL ON FUNCTION public._agent_eta_min(text) FROM PUBLIC, anon, authenticated;

DO $bkp$
BEGIN
  IF to_regprocedure('public.bkp_fn_agent_get_order_status_20261105(text)') IS NULL THEN
    EXECUTE replace(pg_get_functiondef('public.agent_get_order_status(text)'::regprocedure),
                    'public.agent_get_order_status(', 'public.bkp_fn_agent_get_order_status_20261105(');
    EXECUTE 'REVOKE ALL ON FUNCTION public.bkp_fn_agent_get_order_status_20261105(text) FROM PUBLIC, anon, authenticated';
  END IF;
END $bkp$;

CREATE OR REPLACE FUNCTION public.agent_get_order_status(p_order_id text)
RETURNS TABLE(status text, current_step text, driver_name text, driver_eta_min integer, can_be_cancelled boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  v_id := public._agent_pedido_meu(p_order_id);
  IF v_id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND_OR_NOT_OWNER'; END IF;
  RETURN QUERY
  SELECT o.status,
         public._agent_estado_pt(o.status),
         NULLIF(split_part(btrim(COALESCE(d.name, '')), ' ', 1), ''),
         public._agent_eta_min(o.id),
         o.status IN ('created', 'preparing', 'callingDriver')
    FROM public.orders o
    LEFT JOIN LATERAL (
      SELECT dd.name FROM public.drivers dd
       WHERE dd.user_id::text = o.assigned_driver_id OR dd.id::text = o.assigned_driver_id OR dd.id = o.driver_id
       LIMIT 1) d ON true
   WHERE o.id = v_id;
END $$;
REVOKE ALL ON FUNCTION public.agent_get_order_status(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_order_status(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_order_full(p_order text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_id       text;
  o          record;
  v_items    jsonb;
  v_falta    jsonb;
  v_trocas   jsonb;
  v_mais     jsonb;
  v_total    numeric;
  v_cobrado  numeric;
  v_tok_eur  numeric;
  v_cart_eur numeric;
  v_menu_eur numeric;
  v_tip      numeric;
  v_pickup   timestamptz;
  v_motor    text;
  v_dev_cart numeric;
  v_conta    text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  v_id := public._agent_pedido_meu(p_order);
  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'pedido_nao_encontrado',
      'dica', 'Pede o código do pedido (ex.: #BBA0F5), que aparece em Os meus pedidos.');
  END IF;
  SELECT * INTO o FROM public.orders WHERE id = v_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', it->>'name',
           'quantidade', COALESCE((it->>'quantity')::numeric, 1),
           'preco_unitario_eur', round(COALESCE((it->>'price')::numeric, 0), 2),
           'total_eur', round(COALESCE((it->>'price')::numeric, 0) * COALESCE((it->>'quantity')::numeric, 1), 2))), '[]'::jsonb)
    INTO v_items
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.items) = 'array' THEN o.items ELSE '[]'::jsonb END) it;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('produto', p.original_name, 'quantidade', p.original_qty,
           'valor_eur', round(COALESCE(p.original_price_cents, 0) * COALESCE(p.original_qty, 1) / 100.0, 2)))
           FILTER (WHERE p.status = 'unavailable'), '[]'::jsonb),
         COALESCE(jsonb_agg(jsonb_build_object('pedido', p.original_name, 'veio', p.actual_name))
           FILTER (WHERE p.status = 'replaced'), '[]'::jsonb)
    INTO v_falta, v_trocas
    FROM public.order_purchase_items_v2 p WHERE p.order_id = v_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', COALESCE(a->>'name', a->>'nome'),
           'quantidade', COALESCE((a->>'qty')::numeric, (a->>'quantity')::numeric, 1),
           'valor_eur', CASE WHEN a ? 'price' THEN round((a->>'price')::numeric, 2) END)), '[]'::jsonb)
    INTO v_mais
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.items_added) = 'array' THEN o.items_added ELSE '[]'::jsonb END) a;

  v_total    := round(COALESCE(o.final_total, o.customer_total, o.total, 0), 2);
  v_tok_eur  := round(COALESCE(o.tokens_applied_value_cents, 0) / 100.0, 2);
  v_cart_eur := round(COALESCE(o.wallet_applied_cents, 0) / 100.0, 2);
  v_menu_eur := round(COALESCE(o.menu_credit_applied_cents, 0) / 100.0, 2);
  v_tip      := round(COALESCE(o.tip_amount_cents, 0) / 100.0, 2);
  IF o.payment_method = 'cash' THEN
    v_cobrado := round(COALESCE(o.cash_total_due, v_total - v_tok_eur - v_cart_eur - v_menu_eur), 2);
  ELSE
    v_cobrado := CASE WHEN o.stripe_charge_cents IS NOT NULL THEN round(o.stripe_charge_cents / 100.0, 2) END;
  END IF;

  SELECT min(e.occurred_at) INTO v_pickup FROM public.order_status_events e
   WHERE e.order_id = v_id AND e.to_status = 'pickedUp';
  SELECT NULLIF(split_part(btrim(COALESCE(d.name, '')), ' ', 1), '') INTO v_motor
    FROM public.drivers d
   WHERE d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id OR d.id = o.driver_id
   LIMIT 1;
  SELECT round(COALESCE(sum(w.amount_cents), 0) / 100.0, 2) INTO v_dev_cart
    FROM public.wallet_transactions w
   WHERE w.user_id = auth.uid() AND w.related_order_id = v_id AND w.amount_cents > 0;

  v_conta := 'Produtos ' || to_char(COALESCE(o.subtotal, 0), 'FM999990.00')
    || CASE WHEN COALESCE(o.service_fee, 0) > 0 THEN ' + taxa de serviço ' || to_char(o.service_fee, 'FM999990.00') ELSE '' END
    || CASE WHEN COALESCE(o.delivery_fee, 0) > 0 THEN ' + entrega ' || to_char(o.delivery_fee, 'FM999990.00') ELSE '' END
    || CASE WHEN COALESCE(o.bag_fee, 0) > 0 THEN ' + saco ' || to_char(o.bag_fee, 'FM999990.00') ELSE '' END
    || CASE WHEN COALESCE(o.small_order_fee, 0) > 0 THEN ' + pedido pequeno ' || to_char(o.small_order_fee, 'FM999990.00') ELSE '' END
    || ' = total ' || to_char(v_total, 'FM999990.00') || ' €'
    || CASE WHEN v_tok_eur > 0 THEN '; menos tokens ' || to_char(v_tok_eur, 'FM999990.00') || ' € (' || COALESCE(o.tokens_applied_count, 0) || ' tokens)' ELSE '' END
    || CASE WHEN v_cart_eur > 0 THEN '; menos carteira Bora ' || to_char(v_cart_eur, 'FM999990.00') || ' €' ELSE '' END
    || CASE WHEN v_menu_eur > 0 THEN '; menos crédito ' || to_char(v_menu_eur, 'FM999990.00') || ' €' ELSE '' END
    || CASE WHEN v_cobrado IS NOT NULL THEN '; ' || CASE WHEN o.payment_method = 'cash' THEN 'a pagar em dinheiro ' ELSE 'cobrado ' END
         || to_char(v_cobrado, 'FM999990.00') || ' €' ELSE '' END
    || CASE WHEN v_tip > 0 THEN '; gorjeta ' || to_char(v_tip, 'FM999990.00') || ' €' ELSE '' END;

  RETURN jsonb_build_object(
    'ok', true,
    'codigo', public._agent_codigo(v_id),
    'loja', COALESCE(o.vendor_name, CASE WHEN o.service_type = 'errand' THEN 'Favor' END),
    'tipo', CASE o.service_type WHEN 'restaurant' THEN 'restaurante' WHEN 'storeShopping' THEN 'compra numa loja'
                  WHEN 'errand' THEN 'Favor' WHEN 'takeaway' THEN 'recolha na loja' ELSE o.service_type END,
    'estado', public._agent_estado_pt(o.status),
    'produtos', v_items,
    'produtos_em_falta', v_falta,
    'produtos_trocados', v_trocas,
    'produtos_acrescentados', v_mais,
    'conta', jsonb_build_object(
      'subtotal_produtos_eur', round(COALESCE(o.subtotal, 0), 2),
      'taxa_servico_eur', round(COALESCE(o.service_fee, 0), 2),
      'entrega_eur', round(COALESCE(o.delivery_fee, 0), 2),
      'sacos_eur', round(COALESCE(o.bag_fee, 0), 2),
      'taxa_pedido_pequeno_eur', round(COALESCE(o.small_order_fee, 0), 2),
      'total_eur', v_total,
      'desconto_tokens', jsonb_build_object('tokens', COALESCE(o.tokens_applied_count, 0), 'eur', v_tok_eur),
      'carteira_usada_eur', v_cart_eur,
      'credito_menu_eur', v_menu_eur,
      'gorjeta_eur', v_tip,
      'diferenca_paga_depois_eur', CASE WHEN o.extra_charge_settled_at IS NOT NULL THEN round(COALESCE(o.extra_charge_amount, 0)::numeric, 2) END,
      'divida_antiga_cobrada_eur', CASE WHEN COALESCE(o.debt_collected_cents, 0) > 0 THEN round(o.debt_collected_cents / 100.0, 2) END,
      'taxa_cancelamento_eur', CASE WHEN COALESCE(o.cancel_fee, 0) > 0 THEN round(o.cancel_fee, 2) END,
      'cobrado_eur', v_cobrado,
      'resumo', v_conta),
    'pagamento', jsonb_build_object(
      'meio', CASE o.payment_method WHEN 'mbway' THEN 'MB Way' WHEN 'card' THEN 'cartão' WHEN 'stripe' THEN 'cartão'
                    WHEN 'cash' THEN 'dinheiro' ELSE o.payment_method END,
      'estado', CASE o.payment_status WHEN 'paid' THEN 'pago' WHEN 'pending' THEN 'pendente' WHEN 'failed' THEN 'falhou'
                    WHEN 'refunded' THEN 'reembolsado' WHEN 'partially_refunded' THEN 'reembolsado em parte' ELSE o.payment_status END),
    'horas', jsonb_build_object(
      'feito', public._agent_hora(o.created_at),
      'aceite_pela_loja', public._agent_hora(o.accepted_at),
      'estafeta_atribuido', public._agent_hora(o.driver_assigned_at),
      'recolhido', public._agent_hora(v_pickup),
      'entregue', public._agent_hora(o.delivered_at),
      'cancelado', public._agent_hora(o.cancelled_at),
      'marcado_para', public._agent_hora(o.scheduled_for)),
    'estafeta', v_motor,
    'tempo_previsto_min', public._agent_eta_min(v_id),
    'notas_do_cliente', NULLIF(btrim(COALESCE(o.customer_notes, '')), ''),
    'motivo_cancelamento', NULLIF(btrim(COALESCE(o.cancel_reason, '')), ''),
    'reembolso', CASE WHEN o.refund_status IS NULL AND COALESCE(o.refund_amount, 0) = 0 AND v_dev_cart = 0 THEN NULL
      ELSE jsonb_build_object(
        'estado', CASE o.refund_status WHEN 'succeeded' THEN 'feito' WHEN 'pending' THEN 'a processar'
                       WHEN 'failed' THEN 'falhou' ELSE o.refund_status END,
        'valor_eur', round(COALESCE(o.refund_amount, 0)::numeric, 2),
        'para', CASE o.refund_method WHEN 'wallet' THEN 'carteira Bora' WHEN 'original' THEN 'cartão/MB Way'
                     WHEN 'card' THEN 'cartão' WHEN 'mbway' THEN 'MB Way' ELSE o.refund_method END,
        'quando', public._agent_hora(o.refunded_at),
        'devolvido_na_carteira_eur', v_dev_cart) END
  );
END $$;
REVOKE ALL ON FUNCTION public.agent_get_order_full(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_order_full(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_my_tokens_history()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_saldo  int;
  v_exp    jsonb;
  v_ganhos jsonb;
  v_gastos jsonb;
  v_expirados int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT COALESCE(sum(t.amount), 0)::int INTO v_saldo
    FROM public.bora_tokens t
   WHERE t.user_id = v_uid AND COALESCE(t.role, 'client') = 'client'
     AND COALESCE(t.is_used, false) = false AND t.expires_at > now();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('dia', to_char(x.d, 'DD/MM'), 'tokens', x.n) ORDER BY x.d), '[]'::jsonb)
    INTO v_exp
    FROM (SELECT (t.expires_at AT TIME ZONE 'Europe/Lisbon')::date d, sum(t.amount)::int n
            FROM public.bora_tokens t
           WHERE t.user_id = v_uid AND COALESCE(t.role, 'client') = 'client'
             AND COALESCE(t.is_used, false) = false
             AND t.expires_at > now() AND t.expires_at < now() + interval '30 days'
           GROUP BY 1) x;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('quando', public._agent_hora(x.created_at), 'tokens', x.amount,
           'pedido', CASE WHEN x.source_order_id IS NOT NULL THEN public._agent_codigo(x.source_order_id) END,
           'expira', to_char(x.expires_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY'),
           'usado', COALESCE(x.is_used, false)) ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_ganhos
    FROM (SELECT * FROM public.bora_tokens t
           WHERE t.user_id = v_uid AND COALESCE(t.role, 'client') = 'client'
           ORDER BY t.created_at DESC LIMIT 10) x;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('pedido', public._agent_codigo(o.id), 'loja', o.vendor_name,
           'quando', public._agent_hora(o.created_at), 'tokens', o.tokens_applied_count,
           'eur', round(COALESCE(o.tokens_applied_value_cents, 0) / 100.0, 2),
           'estado_pedido', public._agent_estado_pt(o.status)) ORDER BY o.created_at DESC), '[]'::jsonb)
    INTO v_gastos
    FROM (SELECT * FROM public.orders oo
           WHERE oo.user_id = v_uid AND COALESCE(oo.tokens_applied_count, 0) > 0
           ORDER BY oo.created_at DESC LIMIT 10) o;
  SELECT COALESCE(sum(t.amount), 0)::int INTO v_expirados
    FROM public.bora_tokens t
   WHERE t.user_id = v_uid AND COALESCE(t.role, 'client') = 'client'
     AND COALESCE(t.is_used, false) = false
     AND t.expires_at <= now() AND t.expires_at > now() - interval '60 days';
  RETURN jsonb_build_object(
    'saldo_tokens', v_saldo,
    'valor_eur', round(v_saldo * 0.005, 2),
    'pode_usar_na_proxima_compra_eur', floor(v_saldo * 0.005 / 2 * 100) / 100.0,
    'pode_usar_na_proxima_compra_tokens', floor(v_saldo / 2.0)::int,
    'regra', '100 tokens = 0,50 €. Numa compra usas no máximo metade do valor dos tokens que tens. Os tokens expiram 60 dias depois de os ganhares.',
    'a_expirar_30_dias', v_exp,
    'expirados_ultimos_60_dias', v_expirados,
    'ganhos_recentes', v_ganhos,
    'usados_em_pedidos', v_gastos);
END $$;
REVOKE ALL ON FUNCTION public.agent_get_my_tokens_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_my_tokens_history() TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_my_wallet_history()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_saldo int;
  v_mov   jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT COALESCE(w.free_balance_cents, 0) INTO v_saldo FROM public.client_wallets w WHERE w.user_id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'quando', public._agent_hora(x.created_at),
           'valor_eur', round(x.amount_cents / 100.0, 2),
           'motivo', CASE x.kind
              WHEN 'refund_credit_free' THEN 'Devolução de um pedido para a carteira'
              WHEN 'refund_credit_tokens' THEN 'Devolução de um pedido'
              WHEN 'reimbursement_storeshopping' THEN 'Devolução de uma compra'
              WHEN 'order_payment' THEN 'Usado para pagar um pedido'
              WHEN 'debit' THEN 'Usado para pagar'
              WHEN 'cancel_fee_debit' THEN 'Taxa de cancelamento'
              WHEN 'settlement' THEN CASE WHEN x.amount_cents > 0 THEN 'Pagamento de valor em dívida' ELSE 'Acerto' END
              WHEN 'forgive' THEN 'Valor perdoado pela equipa'
              WHEN 'admin_grant' THEN 'Crédito dado pela equipa'
              WHEN 'adjustment' THEN 'Correção feita pela equipa'
              ELSE 'Movimento da carteira' END,
           'pedido', CASE WHEN x.related_order_id IS NOT NULL THEN public._agent_codigo(x.related_order_id) END,
           'saldo_depois_eur', CASE WHEN x.balance_after_cents IS NOT NULL THEN round(x.balance_after_cents / 100.0, 2) END)
           ORDER BY x.created_at DESC), '[]'::jsonb)
    INTO v_mov
    FROM (SELECT * FROM public.wallet_transactions t WHERE t.user_id = v_uid ORDER BY t.created_at DESC LIMIT 20) x;
  RETURN jsonb_build_object('saldo_eur', round(COALESCE(v_saldo, 0) / 100.0, 2), 'movimentos', v_mov);
END $$;
REVOKE ALL ON FUNCTION public.agent_get_my_wallet_history() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_my_wallet_history() TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_my_bookings()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_r   jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  WITH t AS (
    SELECT 'limpeza'::text tipo, c.scheduled_at quando,
           initcap(COALESCE(c.cleaning_type, 'standard')) || COALESCE(' · ' || c.hours || ' h', '') descricao,
           c.status estado, round(COALESCE(c.total_cents, 0) / 100.0, 2) valor_eur, c.payment_status pagamento,
           NULLIF(split_part(btrim(COALESCE(cl.name, '')), ' ', 1), '') quem
      FROM public.cleaning_bookings c LEFT JOIN public.cleaners cl ON cl.id = c.cleaner_id
     WHERE c.client_user_id = v_uid AND COALESCE(c.scheduled_at, c.created_at) > now() - interval '30 days'
    UNION ALL
    SELECT 'lavagem do carro', COALESCE(w.scheduled_at, w.created_at), COALESCE(w.service_type, 'lavagem'),
           w.status, round(COALESCE(w.total_cents, 0) / 100.0, 2), w.payment_status,
           NULLIF(split_part(btrim(COALESCE(wa.name, '')), ' ', 1), '')
      FROM public.carwash_bookings w LEFT JOIN public.washers wa ON wa.id = w.washer_id
     WHERE w.client_user_id = v_uid AND COALESCE(w.scheduled_at, w.created_at) > now() - interval '30 days'
    UNION ALL
    SELECT 'reserva de mesa', r.reserved_for, COALESCE(rs.name, 'restaurante') || ' · ' || r.people || ' pessoas',
           r.status, round(COALESCE(r.prepayment_cents, 0) / 100.0, 2), NULL::text, NULL::text
      FROM public.reservations r LEFT JOIN public.restaurants rs ON rs.id = r.restaurant_id
     WHERE r.client_user_id = v_uid AND r.reserved_for > now() - interval '30 days'
    UNION ALL
    SELECT 'serviço (marcação)', a.scheduled_at, COALESCE(sp.name, 'serviço') || COALESCE(' · ' || ps.name, ''),
           a.status, round(COALESCE(a.service_price_cents, 0) / 100.0, 2), a.deposit_status, NULL::text
      FROM public.appointments a
      LEFT JOIN public.service_providers sp ON sp.id::text = a.provider_id
      LEFT JOIN public.provider_services ps ON ps.id::text = a.service_id
     WHERE a.client_user_id = v_uid AND a.scheduled_at > now() - interval '30 days'
    UNION ALL
    SELECT 'serviço em casa', COALESCE(p.scheduled_at, p.created_at), COALESCE(p.oficio, 'serviço'),
           p.estado, round(COALESCE(p.total_cents, 0) / 100.0, 2), p.payment_status, NULL::text
      FROM public.casa_pedidos p
     WHERE p.client_user_id = v_uid AND COALESCE(p.scheduled_at, p.created_at) > now() - interval '30 days'
    UNION ALL
    SELECT CASE WHEN o.service_type = 'errand' THEN 'Favor' ELSE 'encomenda marcada' END,
           COALESCE(o.scheduled_for, o.created_at),
           public._agent_codigo(o.id) || ' · ' || COALESCE(left(o.errand_description, 80), o.vendor_name, ''),
           public._agent_estado_pt(o.status), round(COALESCE(o.final_total, o.customer_total, 0), 2), o.payment_status, NULL::text
      FROM public.orders o
     WHERE o.user_id = v_uid AND (o.service_type = 'errand' OR o.scheduled_for IS NOT NULL)
       AND COALESCE(o.scheduled_for, o.created_at) > now() - interval '30 days'
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'tipo', t.tipo, 'quando', public._agent_hora(t.quando), 'descricao', t.descricao,
           'estado', t.estado, 'valor_eur', t.valor_eur, 'pagamento', t.pagamento, 'profissional', t.quem,
           'ja_passou', t.quando < now()) ORDER BY t.quando DESC), '[]'::jsonb)
    INTO v_r FROM t;
  RETURN jsonb_build_object('marcacoes', v_r,
    'nota', 'Corridas de carro marcadas (TVDE) vêm de agent_get_my_tvde_reservations.');
END $$;
REVOKE ALL ON FUNCTION public.agent_get_my_bookings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_my_bookings() TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_store_info(p_query text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $$
DECLARE
  v_q    text := lower(extensions.unaccent(btrim(COALESCE(p_query, ''))));
  v_res  jsonb;
  v_min  int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(v_q) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o nome da loja'); END IF;
  BEGIN v_min := (public.get_setting('min_order_cents') #>> '{}')::int; EXCEPTION WHEN OTHERS THEN v_min := NULL; END;
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.ord), '[]'::jsonb) INTO v_res FROM (
    SELECT CASE WHEN lower(extensions.unaccent(r.name)) = v_q THEN 0
                WHEN lower(extensions.unaccent(r.name)) LIKE v_q || '%' THEN 1 ELSE 2 END ord,
      jsonb_build_object(
        'loja', r.name,
        'tipo', CASE WHEN r.is_partner THEN 'parceira' ELSE 'compra pelo estafeta' END,
        'categoria', r.category,
        'em_breve', COALESCE(r.coming_soon, false),
        'aceita_pedidos_agora', CASE WHEN COALESCE(r.coming_soon, false) THEN false
                                     ELSE COALESCE((st.v->>'is_open')::boolean, false) AND COALESCE(r.is_online, false) END,
        'em_pausa', COALESCE((st.v->>'em_pausa')::boolean, false),
        'abre', CASE WHEN st.v->>'opens_at' IS NOT NULL THEN COALESCE(st.v->>'opens_dia', '') || ' às ' || (st.v->>'opens_at') END,
        'fecha_em_minutos', (st.v->>'closes_in_minutes')::int,
        'muito_movimento_mais_minutos', CASE WHEN r.busy_until > now() THEN r.busy_extra_minutes END,
        'horario_semana', (SELECT jsonb_object_agg(dn.pt,
             CASE WHEN COALESCE((r.business_hours->dn.k->>'closed')::boolean, false) THEN 'fechado'
                  WHEN r.business_hours->dn.k IS NULL THEN 'sem horário'
                  ELSE (r.business_hours->dn.k->>'open') || '–' || (r.business_hours->dn.k->>'close')
                       || CASE WHEN r.business_hours->dn.k->>'break_start' IS NOT NULL
                               THEN ' (pausa ' || (r.business_hours->dn.k->>'break_start') || '–' || (r.business_hours->dn.k->>'break_end') || ')'
                               ELSE '' END END)
           FROM (VALUES ('mon','segunda'),('tue','terça'),('wed','quarta'),('thu','quinta'),
                        ('fri','sexta'),('sat','sábado'),('sun','domingo')) dn(k, pt)),
        'entrega_gratis_a_partir_de_eur', CASE WHEN r.free_delivery_min_cents IS NOT NULL THEN round(r.free_delivery_min_cents / 100.0, 2) END,
        'taxa_pedido_pequeno_abaixo_de_eur', CASE WHEN NOT COALESCE(r.is_partner, false)
             THEN round(COALESCE(r.min_order_cents_override, v_min) / 100.0, 2) END,
        'tempo_preparo_min', r.takeaway_default_prep_minutes,
        'aceita_reservas_de_mesa', COALESCE(r.reservations_enabled, false),
        'recolha_na_loja', COALESCE(r.takeaway_enabled, false),
        'morada', r.address,
        'aviso_da_loja', NULLIF(btrim(COALESCE(r.about_text, '')), '')) j
      FROM public.restaurants r
      LEFT JOIN LATERAL (SELECT public.is_partner_open(r.id) v) st ON true
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
       AND lower(extensions.unaccent(r.name)) LIKE '%' || v_q || '%'
     ORDER BY 1 LIMIT 5) x;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'lojas', v_res,
    'agora_em_portugal', to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI'));
END $$;
REVOKE ALL ON FUNCTION public.agent_get_store_info(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_store_info(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_search_products(p_query text, p_loja text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $$
DECLARE
  v_loja text;
  v_res  jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(btrim(COALESCE(p_query, ''))) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o produto'); END IF;
  IF NULLIF(btrim(COALESCE(p_loja, '')), '') IS NOT NULL THEN
    SELECT r.id INTO v_loja FROM public.restaurants r
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
       AND lower(extensions.unaccent(r.name)) LIKE '%' || lower(extensions.unaccent(btrim(p_loja))) || '%'
     ORDER BY length(r.name) LIMIT 1;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', s.name, 'loja', s.restaurant_name,
           'preco_na_app_eur', round(COALESCE(s.display_price, s.price), 2),
           'unidade', s.unit, 'so_maiores_18', COALESCE(s.maior_18, false))), '[]'::jsonb)
    INTO v_res
    FROM public.assistant_search_products(btrim(p_query), v_loja, 8, NULL, false) s;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'produtos', v_res,
    'nota', 'Preços da app. Nos mercados o valor final é o do talão.');
END $$;
REVOKE ALL ON FUNCTION public.agent_search_products(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_search_products(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_my_driver_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_ganho jsonb;
  v_ped   jsonb;
  v_tok   int;
  v_ent   int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nao_es_estafeta');
  END IF;
  v_ganho := public.driver_earnings_summary();
  SELECT COALESCE(sum(t.amount), 0)::int INTO v_tok FROM public.bora_tokens t
   WHERE t.user_id = v_uid AND t.role = 'driver';
  SELECT count(*)::int INTO v_ent FROM public.orders o
   WHERE o.status = 'delivered'
     AND o.delivered_at >= (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon')
     AND (o.assigned_driver_id = v_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid));
  SELECT COALESCE(jsonb_agg(jsonb_build_object('pedido', public._agent_codigo(o.id), 'loja', o.vendor_name,
           'estado', public._agent_estado_pt(o.status), 'morada_entrega', o.dropoff_address)), '[]'::jsonb)
    INTO v_ped FROM public.orders o
   WHERE o.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
     AND (o.assigned_driver_id = v_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid));
  RETURN jsonb_build_object('ok', true,
    'hoje_eur', round(COALESCE((v_ganho #>> '{dia,total_cents}')::numeric, 0) / 100.0, 2),
    'hoje_tokens', COALESCE((v_ganho #>> '{dia,tokens}')::int, 0),
    'semana_eur', round(COALESCE((v_ganho #>> '{semana,total_cents}')::numeric, 0) / 100.0, 2),
    'semana_tokens', COALESCE((v_ganho #>> '{semana,tokens}')::int, 0),
    'semana_passada_eur', round(COALESCE((v_ganho #>> '{semana_passada,total_cents}')::numeric, 0) / 100.0, 2),
    'entregas_hoje', v_ent,
    'tokens_de_estafeta_total', v_tok,
    'pedidos_em_curso', v_ped,
    'nota', 'São os números do ecrã Ganhos da app de estafeta. O acerto é semanal.');
END $$;
REVOKE ALL ON FUNCTION public.agent_get_my_driver_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_my_driver_summary() TO authenticated;

CREATE OR REPLACE FUNCTION public.agent_get_my_partner_today()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'loja', r.name,
           'ligada', COALESCE(r.is_online, false),
           'aberta_agora', COALESCE((public.is_partner_open(r.id)->>'is_open')::boolean, false),
           'em_pausa_ate', CASE WHEN r.pausa_ate > now() THEN to_char(r.pausa_ate AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') END,
           'aprovada', r.approval_status = 'approved',
           'pedidos_hoje', (SELECT COALESCE(jsonb_object_agg(e.estado, e.n), '{}'::jsonb) FROM (
               SELECT public._agent_estado_pt(o.status) estado, count(*) n FROM public.orders o
                WHERE o.restaurant_id = r.id
                  AND o.created_at >= (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon')
                GROUP BY 1) e),
           'pedidos_por_aceitar', (SELECT count(*) FROM public.orders o
                WHERE o.restaurant_id = r.id AND o.status = 'created'))), '[]'::jsonb)
    INTO v_res
    FROM public.restaurants r WHERE r.user_id = v_uid;
  IF jsonb_array_length(v_res) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'sem_loja_nesta_conta'); END IF;
  RETURN jsonb_build_object('ok', true, 'lojas', v_res,
    'como_fazer', jsonb_build_object(
      'mudar_preco', 'No painel da loja, carrega em "Gerir produtos"; no produto, "Editar produto"; muda o "Preço que recebes" e carrega em "Guardar alterações".',
      'pausar_loja', 'No painel da loja, carrega em "Pausar a loja" e escolhe quantos minutos (ou "Até fechar hoje"). Volta sozinha.',
      'horario', 'No painel da loja, "Horários de funcionamento".',
      'ligar_desligar', 'No topo do painel, o botão ONLINE/OFFLINE.',
      'sair_da_conta', 'No topo do painel, o ícone "A minha conta" (a pessoa) e, no fim, "Terminar sessão".'));
END $$;
REVOKE ALL ON FUNCTION public.agent_get_my_partner_today() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_my_partner_today() TO authenticated;
```
