-- =============================================================================
-- PROPOSTA 🔴 ZONA VERMELHA — TVDE: tokens que descontam a serio + taxa de
-- cancelamento justa.  Missao `tvde-pagamento-tokens-despacho` (2026-08-13).
-- =============================================================================
-- NAO APLICAR sem o "vai" do Danilo. Mexe em `bora_tokens` (consumo real) e no
-- valor cobrado ao cliente num cancelamento — Lista Vermelha do CLAUDE.md.
--
-- Contexto provado por MCP em 2026-08-13:
--   * `tvde_request_ride` JA aplica o desconto de tokens (1 token = 5 cents,
--     tecto 50%) e ja grava `est_fare_cents` LIQUIDO. O que faltava era (a)
--     registar quantos tokens foram usados e (b) CONSUMI-LOS de facto.
--   * `tvde_rides.tokens_applied_count` / `tokens_applied_value_cents` estao a
--     0 em 100% das corridas online — so o caminho CASH (`tvde_finish_ride`)
--     os escrevia.
--   * Nenhuma funcao TVDE chamava `consume_tokens`. O desconto era OFERECIDO
--     mas os tokens do cliente NUNCA baixavam — dinheiro a sair de graca.
--   * `tvde_cancel_ride` cobrava 100% da tarifa passados 180s
--     (`cancel_grace_seconds`) sem verificar se algum motorista chegou a ser
--     oferecido. Corrida 09c01c88 (13/08 19:01, Danilo): cancel_fee_cents=500
--     com tried_driver_ids = {} e current_offer_driver_id = NULL.
--
-- NOTA sobre `cancel_grace_seconds`: o briefing chamava-lhe
-- `tvde_ride_grace_seconds`. Essa chave NAO existe em platform_settings — a
-- que a funcao le e `cancel_grace_seconds` (= 180). Fica aqui o registo para
-- o painel admin apontar a chave certa.
-- =============================================================================

BEGIN;

-- ── 1. Marca de consumo (idempotencia) ──────────────────────────────────────
-- Sem isto, qualquer re-entrada do trigger (webhook + poll do cliente a
-- correrem os dois) consumiria os tokens duas vezes.
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS tokens_consumed_at timestamptz;

COMMENT ON COLUMN public.tvde_rides.tokens_consumed_at IS
  'Quando os Bora Tokens desta corrida foram descontados do saldo do cliente. '
  'NULL = ainda nao descontados (corrida por pagar, ou sem tokens).';


-- ── 2. `tvde_request_ride` — passa a REGISTAR os tokens aplicados ───────────
-- Unica alteracao face a versao em producao: as 2 colunas no INSERT.
-- O calculo do desconto e do `est_fare_cents` fica EXACTAMENTE igual.
CREATE OR REPLACE FUNCTION public.tvde_request_ride(
  p_origin_lat double precision, p_origin_lng double precision, p_origin_label text,
  p_dest_lat double precision, p_dest_lng double precision, p_dest_label text,
  p_est_distance_km numeric, p_payment_method text DEFAULT 'cash'::text,
  p_tokens_to_apply integer DEFAULT 0)
RETURNS public.tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_fare INTEGER; v_ride public.tvde_rides;
  v_cov JSONB; v_covered BOOLEAN; v_sub_id UUID; v_is_member BOOLEAN;
  v_d_base INT; v_d_perkm INT; v_extra_km INT; v_base_km INT; v_perkm_client INT;
  v_driver_normal INT; v_driver_earn INT; v_client_fare INT; v_bora_cut INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT; v_token_value_x100 INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_payment_method NOT IN ('cash','card','mbway') THEN
    RAISE EXCEPTION 'invalid_payment_method: %', p_payment_method;
  END IF;
  IF p_payment_method <> 'cash'
     AND NOT COALESCE((public.get_setting('tvde_card_payments_enabled') #>> '{}')::boolean, false) THEN
    RAISE EXCEPTION 'card_payments_not_enabled';
  END IF;
  -- 2026-08-01: categoria TVDE aberta a TODOS os clientes (gate tvde_access removido por decisao do Danilo).
  IF EXISTS (SELECT 1 FROM public.tvde_rides WHERE client_id = v_uid
             AND status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')) THEN
    RAISE EXCEPTION 'ride_in_progress'; END IF;

  v_base_km := (public.get_setting('tvde_base_distance_km') #>> '{}')::int;
  v_perkm_client := (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_est_distance_km - v_base_km))::int;
  v_fare := public.tvde_calculate_fare(p_est_distance_km);
  v_d_base  := (public.get_setting('tvde_driver_base_cents')  #>> '{}')::int;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_driver_normal := v_d_base + v_extra_km * v_d_perkm;

  v_cov := public.tvde_preview_coverage(v_uid);
  v_covered := COALESCE((v_cov->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_cov->>'subscription_id','')::uuid;
  SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
    WHERE client_id = v_uid AND active = true AND now() BETWEEN starts_at AND ends_at)
    INTO v_is_member;

  IF v_covered THEN
    v_client_fare := v_extra_km * v_perkm_client;
    v_driver_earn := ROUND(v_driver_normal * 0.85)::int;
    v_bora_cut    := v_client_fare + (v_driver_normal - v_driver_earn) - v_driver_normal;
  ELSIF v_is_member THEN
    v_client_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int + v_extra_km * v_perkm_client;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_client_fare - v_driver_normal;
  ELSE
    v_client_fare := v_fare;
    v_driver_earn := v_driver_normal;
    v_bora_cut    := v_fare - v_driver_normal;
  END IF;

  -- === DESCONTO DE TOKENS (paridade com tvde_finish_ride) ===
  -- Valor e tecto SEMPRE das definicoes. NUNCA cravar numeros aqui.
  --
  -- 2026-08-13 — estavam os DOIS cravados: `* 5` (5 centimos/token) e `50`.
  --   * o tecto cravado fazia o botao `token_payment_max_pct` do painel admin
  --     nao ter efeito nenhum no TVDE (so nas entregas, que ja liam a chave);
  --   * o `* 5` dava ao token **10x** o valor documentado: o resto do sistema
  --     usa `token_value_cents_x100 = 50` -> 0,5 centimos (100 tokens = 0,50 EUR,
  --     CLAUDE.md §5, `wallet_service.dart:172`, `payment_method_screen.dart:270`).
  --     Ninguem perdeu dinheiro com isso porque os tokens nunca chegavam a ser
  --     consumidos (o outro lado desta mesma migration) — mas a partir do
  --     momento em que passam a sair do saldo real, tinha de ficar certo.
  --     Exposicao medida antes de alinhar: 3.233 tokens activos em 5 pessoas
  --     = 16,17 EUR a 0,5c (eram 161,65 EUR a 5c).
  -- Decisao do Danilo (2026-08-13): 0,5 centimos por token, em todo o lado.
  IF p_tokens_to_apply > 0 AND v_client_fare > 0 THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_discount_cents := GREATEST(0, (v_client_fare
      * COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50)) / 100);
    v_tokens_discount_cents := LEAST((p_tokens_to_apply * v_token_value_x100) / 100, v_max_discount_cents);
    v_client_fare := v_client_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  INSERT INTO public.tvde_rides (
    client_id, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
    est_distance_km, est_fare_cents, driver_earn_cents, bora_cut_cents,
    used_subscription_ride, subscription_id, payment_method, status,
    -- ⭐ 2026-08-13: registar os tokens. `est_fare_cents` acima JA vem liquido
    -- destes cents — quem cobrar NAO pode subtrair outra vez (ver
    -- tvde_ride_charge_cents, deixada intacta de proposito).
    tokens_applied_count, tokens_applied_value_cents)
  VALUES (v_uid, p_origin_lat, p_origin_lng, p_origin_label, p_dest_lat, p_dest_lng, p_dest_label,
    p_est_distance_km, v_client_fare, v_driver_earn, v_bora_cut, v_covered, v_sub_id,
    p_payment_method, 'solicitada',
    CASE WHEN v_tokens_discount_cents > 0 THEN p_tokens_to_apply ELSE 0 END,
    v_tokens_discount_cents)
  RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (v_ride.id, 'solicitada', 'client',
      jsonb_build_object('est_distance_km', p_est_distance_km, 'est_fare_cents', v_client_fare,
        'covered', v_covered, 'is_member', v_is_member, 'extra_km', v_extra_km,
        'driver_earn_cents', v_driver_earn, 'payment_method', p_payment_method,
        'tokens_requested', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));
  RETURN v_ride;
END; $function$;


-- ── 2-bis. `tvde_finish_ride` — o outro sitio com o valor cravado ───────────
-- Mesma correcao da funcao acima, no fecho da corrida (caminho DINHEIRO).
-- Unica alteracao face a producao: as 3 linhas do bloco de tokens (declaracao
-- de `v_token_value_x100` + valor e tecto lidos das definicoes). Todo o resto
-- — tarifa, pernas do pacote, paradas, liquidacao do saldo do motorista — fica
-- byte a byte igual. Assinatura identica, por isso CREATE OR REPLACE e seguro
-- (nao cria overload).
CREATE OR REPLACE FUNCTION public.tvde_finish_ride(
  p_ride_id uuid, p_final_distance_km numeric,
  p_distance_source text DEFAULT NULL::text, p_tokens_to_apply integer DEFAULT 0)
RETURNS public.tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_ride public.tvde_rides;
  v_fare INT; v_d_base INT; v_d_perkm INT; v_extra_km INT; v_driver_earn INT; v_bora_cut INT;
  v_sub JSONB; v_covered BOOLEAN; v_sub_id UUID; v_next UUID; v_is_member BOOLEAN;
  v_stops_fee INT; v_stops_drv INT; v_prepaid BOOLEAN; v_settle INT;
  v_tokens_discount_cents INT; v_max_discount_cents INT; v_token_value_x100 INT;
  v_pm TEXT; v_rt_cash BOOLEAN := false; v_rt_price INT;
  v_stops_cash INT;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id <> v_uid THEN RAISE EXCEPTION 'not_ride_driver'; END IF;
  IF v_ride.status <> 'em_andamento' THEN RAISE EXCEPTION 'invalid_transition: %', v_ride.status; END IF;

  v_stops_fee := COALESCE(v_ride.extra_stops_fee_cents, 0);
  v_stops_drv := COALESCE(v_ride.extra_stops_driver_cents, 0);
  v_prepaid   := v_ride.roundtrip_credit_id IS NOT NULL;
  v_pm        := COALESCE(v_ride.payment_method, 'cash');

  SELECT COALESCE(SUM(fee_cents),0) INTO v_stops_cash
    FROM public.tvde_ride_stops
   WHERE ride_id = p_ride_id AND payment_intent_id IS NULL;

  v_fare := public.tvde_calculate_fare(p_final_distance_km);
  IF v_ride.is_return_leg THEN
    v_d_base := (public.get_setting('tvde_roundtrip_return_driver_cents') #>> '{}')::int;
  ELSE
    v_d_base := (public.get_setting('tvde_driver_base_cents') #>> '{}')::int;
  END IF;
  v_d_perkm := (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int;
  v_extra_km := GREATEST(0, CEIL(p_final_distance_km - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int;
  v_driver_earn := v_d_base + v_extra_km * v_d_perkm;

  v_sub := public.tvde_consume_subscription_ride(v_ride.client_id);
  v_covered := COALESCE((v_sub->>'covered')::boolean, false);
  v_sub_id := NULLIF(v_sub->>'subscription_id','')::uuid;

  IF v_prepaid THEN
    v_fare        := v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  ELSIF v_covered THEN
    v_bora_cut    := (v_driver_earn - ROUND(v_driver_earn * 0.85)::int) + (v_stops_fee - v_stops_drv);
    v_driver_earn := ROUND(v_driver_earn * 0.85)::int + v_stops_drv;
    v_fare        := v_stops_fee;
  ELSE
    SELECT EXISTS (SELECT 1 FROM public.tvde_subscriptions
      WHERE client_id = v_ride.client_id AND active = true AND now() BETWEEN starts_at AND ends_at)
      INTO v_is_member;
    IF v_is_member THEN
      v_fare := (public.get_setting('tvde_extra_ride_cents') #>> '{}')::int;
    END IF;
    v_fare        := v_fare + v_stops_fee;
    v_driver_earn := v_driver_earn + v_stops_drv;
    v_bora_cut    := v_fare - v_driver_earn;
  END IF;

  -- ⭐ 2026-08-13 — valor e tecto do token vindos das DEFINICOES.
  -- Era `p_tokens_to_apply * 5` (10x o valor real) e `(v_fare * 50) / 100`.
  -- Ver nota extensa em `tvde_request_ride`, mais acima.
  IF p_tokens_to_apply > 0 AND v_fare > 0 THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_discount_cents := GREATEST(0, (v_fare
      * COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50)) / 100);
    v_tokens_discount_cents := LEAST((p_tokens_to_apply * v_token_value_x100) / 100, v_max_discount_cents);
    v_fare := v_fare - v_tokens_discount_cents;
    v_bora_cut := v_bora_cut - v_tokens_discount_cents;
  ELSE
    v_tokens_discount_cents := 0;
  END IF;

  UPDATE public.tvde_rides SET status = 'finalizada', final_distance_km = p_final_distance_km,
    final_fare_cents = v_fare, driver_earn_cents = v_driver_earn, bora_cut_cents = v_bora_cut,
    used_subscription_ride = v_covered, subscription_id = v_sub_id,
    final_distance_source = COALESCE(p_distance_source, final_distance_source),
    tokens_applied_count = CASE WHEN p_tokens_to_apply > 0 THEN p_tokens_to_apply ELSE tokens_applied_count END,
    tokens_applied_value_cents = CASE WHEN p_tokens_to_apply > 0 THEN v_tokens_discount_cents ELSE tokens_applied_value_cents END,
    updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;

  -- Pacote pago em DINHEIRO deteta-se pelo vale SEM payment_intent_id (so na IDA).
  -- v_rt_price = o valor REAL do vale (varia com a distancia), nao o setting fixo.
  IF v_prepaid AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    SELECT (payment_intent_id IS NULL), paid_cents INTO v_rt_cash, v_rt_price
      FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
  END IF;

  -- === LIQUIDACAO DO SALDO DO MOTORISTA (tvde_driver_balances) ===
  -- +v_settle = motorista DEVE a Bora ; -v_settle = Bora DEVE ao motorista.
  IF v_pm = 'cash' AND NOT v_prepaid AND NOT v_covered THEN
    v_settle := v_bora_cut;
  ELSIF v_prepaid AND COALESCE(v_rt_cash, false) AND NOT COALESCE(v_ride.is_return_leg, false) THEN
    v_settle := (COALESCE(v_rt_price, (public.get_setting('tvde_roundtrip_price_cents') #>> '{}')::int) + v_stops_cash) - v_driver_earn;
  ELSE
    v_settle := v_stops_cash - v_driver_earn;
  END IF;
  IF v_settle <> 0 THEN
    INSERT INTO public.tvde_driver_balances (driver_id, balance, updated_at)
      VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
      ON CONFLICT (driver_id) DO UPDATE
        SET balance = public.tvde_driver_balances.balance + ROUND(v_settle / 100.0, 2), updated_at = now();
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'finalizada', 'driver', jsonb_build_object('final_distance_km', p_final_distance_km,
      'final_fare_cents', v_fare, 'driver_earn_cents', v_driver_earn, 'bora_cut_cents', v_bora_cut,
      'extra_stops_fee_cents', v_stops_fee, 'extra_stops_driver_cents', v_stops_drv,
      'stops_cash_cents', v_stops_cash,
      'is_return_leg', v_ride.is_return_leg, 'prepaid', v_prepaid, 'rt_cash', v_rt_cash, 'payment_method', v_pm,
      'roundtrip_price_cents', v_rt_price,
      'settle_cents', v_settle,
      'distance_source', p_distance_source, 'subscription', v_sub,
      'tokens_applied_count', p_tokens_to_apply, 'tokens_discount_cents', v_tokens_discount_cents));

  UPDATE public.tvde_rides SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
   WHERE id = (SELECT r3.id FROM public.tvde_rides r3 WHERE r3.driver_id = v_uid AND r3.is_queued = true
               AND r3.status = 'motorista_atribuido' ORDER BY r3.created_at ASC LIMIT 1)
   RETURNING id INTO v_next;
  IF v_next IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_next, 'motorista_a_caminho', 'system', jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id));
  END IF;

  RETURN v_ride;
END; $function$;


-- ── 3. Consumo dos tokens — SO depois de o dinheiro entrar ──────────────────
-- Regra do briefing: "consumir os tokens so depois do pagamento confirmado —
-- se a corrida falhar ou for cancelada antes de pagar, os tokens VOLTAM ao
-- cliente". Cumprido por construcao: se nunca chegamos a consumir, nao ha nada
-- a devolver. O saldo do cliente so baixa quando o pagamento passou (online)
-- ou quando a corrida terminou (dinheiro em mao).
CREATE OR REPLACE FUNCTION public.tvde_consume_ride_tokens(p_ride_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_ride public.tvde_rides; v_ok BOOLEAN;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF COALESCE(v_ride.tokens_applied_count, 0) <= 0 THEN RETURN false; END IF;
  IF v_ride.tokens_consumed_at IS NOT NULL THEN RETURN false; END IF;  -- idempotente

  -- `consume_tokens` devolve FALSE (sem excepcao) se o saldo nao chegar.
  -- Nesse caso NAO marcamos como consumido: o desconto ja foi dado, fica o
  -- evento a dizer que os tokens nao existiam — visivel no painel admin.
  v_ok := public.consume_tokens(v_ride.client_id, v_ride.tokens_applied_count);

  IF v_ok THEN
    UPDATE public.tvde_rides SET tokens_consumed_at = now() WHERE id = p_ride_id;
  END IF;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_ride.status, 'system',
      jsonb_build_object('tokens_consumed', v_ok,
        'tokens_count', v_ride.tokens_applied_count,
        'tokens_value_cents', v_ride.tokens_applied_value_cents));
  RETURN v_ok;
END; $function$;

-- Gatilho unico para os dois caminhos:
--   * online (cartao/MB Way) -> payment_status = 'succeeded' (webhook ou poll)
--   * dinheiro               -> status = 'finalizada' (tvde_finish_ride)
CREATE OR REPLACE FUNCTION public.fn_tvde_consume_tokens()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF (NEW.payment_status = 'succeeded' AND OLD.payment_status IS DISTINCT FROM 'succeeded')
     OR (NEW.status = 'finalizada' AND OLD.status IS DISTINCT FROM 'finalizada')
  THEN
    PERFORM public.tvde_consume_ride_tokens(NEW.id);
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS tr_tvde_consume_tokens ON public.tvde_rides;
CREATE TRIGGER tr_tvde_consume_tokens
  AFTER UPDATE OF payment_status, status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.fn_tvde_consume_tokens();


-- ── 4. `tvde_cancel_ride` — taxa SO se houve motorista envolvido ────────────
-- Unica alteracao face a producao: a nova variavel `v_had_driver` e a condicao
-- extra no bloco da taxa (+ `had_driver` no evento, para auditoria). Todo o
-- resto do corpo — re-fila do motorista que desiste, activacao da corrida
-- seguinte — fica byte a byte igual.
CREATE OR REPLACE FUNCTION public.tvde_cancel_ride(
  p_ride_id uuid, p_actor text, p_reason text DEFAULT NULL::text)
RETURNS public.tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.tvde_rides;
  v_new_status TEXT;
  v_fee INT := 0;
  v_is_admin BOOLEAN := public.is_admin();
  v_was_active_of_driver BOOLEAN := false;
  v_next UUID;
  v_quit_driver UUID;
  v_grace INT;
  v_before_pickup BOOLEAN;
  v_had_driver BOOLEAN;
BEGIN
  IF p_actor NOT IN ('cliente','motorista','no_show') THEN RAISE EXCEPTION 'invalid_actor: %', p_actor; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF NOT (v_is_admin OR v_ride.client_id = v_uid OR v_ride.driver_id = v_uid) THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status; END IF;

  IF p_actor = 'motorista'
     AND v_ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou')
  THEN
    v_quit_driver := v_ride.driver_id;
    UPDATE public.tvde_rides
       SET status = 'solicitada', driver_id = NULL, is_queued = false,
           current_offer_driver_id = NULL, offer_expires_at = NULL, no_driver_since = NULL,
           tried_driver_ids = CASE WHEN v_quit_driver IS NOT NULL
             THEN array_append(COALESCE(tried_driver_ids, '{}'::uuid[]), v_quit_driver)
             ELSE tried_driver_ids END,
           updated_at = now()
     WHERE id = p_ride_id RETURNING * INTO v_ride;
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, 'motorista_desistiu', 'motorista',
        jsonb_build_object('reason', p_reason, 'released_driver', v_quit_driver, 'requeued', true));
    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_quit_driver AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
          jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_driver_giveup', true));
    END IF;
    PERFORM public.tvde_offer_to_next(p_ride_id);
    RETURN v_ride;
  END IF;

  v_was_active_of_driver := v_ride.driver_id IS NOT NULL AND v_ride.is_queued = false
    AND v_ride.status IN ('motorista_a_caminho','motorista_chegou','em_andamento');
  v_new_status := CASE p_actor WHEN 'cliente' THEN 'cancelada_cliente' WHEN 'motorista' THEN 'cancelada_motorista' ELSE 'no_show' END;

  v_before_pickup := v_ride.status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou');

  -- ⭐ 2026-08-13 — a corrida chegou a envolver ALGUM motorista?
  -- Nao cobrar cancelamento de um servico que nunca foi prestado nem
  -- sequer oferecido. Sem isto, o BUG 1 (webhook cego ao TVDE) convertia-se
  -- automaticamente em taxa de 100%: o cliente pagava, ninguem era chamado
  -- porque a corrida nunca era marcada como paga, e passados 180s o proprio
  -- sistema cobrava-lhe a corrida inteira. Foi o que aconteceu a corrida
  -- 09c01c88 (cancel_fee_cents = 500, elapsed_seconds = 219, tried = {}).
  v_had_driver := v_ride.driver_id IS NOT NULL
               OR v_ride.current_offer_driver_id IS NOT NULL
               OR COALESCE(array_length(v_ride.tried_driver_ids, 1), 0) > 0;

  IF p_actor = 'cliente' AND v_before_pickup AND v_had_driver THEN
    v_grace := (public.get_setting('cancel_grace_seconds') #>> '{}')::int;
    IF COALESCE((public.get_setting('tvde_cancel_full_after_grace') #>> '{}')::boolean, false)
       AND EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int > v_grace THEN
      -- Cancelamento tardio (fora da graca).
      v_fee := v_ride.est_fare_cents;
      -- Corrida coberta pelo plano tem tarifa 0 -> aplica penalidade fixa (mesmo valor do no-show)
      -- para nao ficar €0 e manter consistencia no relatorio/receita.
      IF COALESCE(v_ride.used_subscription_ride, false) OR COALESCE(v_fee, 0) = 0 THEN
        v_fee := COALESCE((public.get_setting('tvde_noshow_driver_fee_cents') #>> '{}')::int, 350);
      END IF;
    ELSE
      v_fee := 0;
    END IF;
  ELSE
    v_fee := 0;
  END IF;

  UPDATE public.tvde_rides SET status = v_new_status, cancel_reason = p_reason, cancel_fee_cents = v_fee,
    is_queued = false, current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_new_status, CASE WHEN v_is_admin THEN 'admin' ELSE p_actor END,
            jsonb_build_object('reason', p_reason, 'cancel_fee_cents', v_fee,
              'grace_seconds', v_grace, 'had_driver', v_had_driver,
              'elapsed_seconds', EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int));

  IF v_was_active_of_driver THEN
    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_ride.driver_id AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
                jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_cancel', true));
    END IF;
  END IF;

  RETURN v_ride;
END; $function$;


-- ── 5. Corridas presas no pagamento (painel admin) ──────────────────────────
-- Read-only. `solicitada` + pagamento por fechar ha mais de N minutos.
CREATE OR REPLACE FUNCTION public.admin_tvde_stuck_payments(p_minutes integer DEFAULT 5)
RETURNS TABLE (
  id uuid, created_at timestamptz, minutes_stuck integer,
  client_id uuid, client_email text,
  payment_method text, payment_status text,
  est_fare_cents integer, tokens_applied_count integer,
  tokens_applied_value_cents integer, tokens_consumed_at timestamptz,
  payment_intent_id text, origin_label text, dest_label text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT r.id, r.created_at,
         (EXTRACT(EPOCH FROM (now() - r.created_at)) / 60)::int,
         r.client_id, u.email::text,
         r.payment_method, r.payment_status,
         r.est_fare_cents, r.tokens_applied_count,
         r.tokens_applied_value_cents, r.tokens_consumed_at,
         r.payment_intent_id, r.origin_label, r.dest_label
  FROM public.tvde_rides r
  LEFT JOIN auth.users u ON u.id = r.client_id
  WHERE public.is_admin()
    AND r.status = 'solicitada'
    AND COALESCE(r.payment_status, '') IN ('requires_action', 'processing', 'requires_payment_method', 'requires_confirmation')
    AND r.created_at < now() - make_interval(mins => GREATEST(1, p_minutes))
  ORDER BY r.created_at DESC
  LIMIT 200;
$function$;

REVOKE ALL ON FUNCTION public.admin_tvde_stuck_payments(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tvde_stuck_payments(integer) TO authenticated;

COMMIT;
