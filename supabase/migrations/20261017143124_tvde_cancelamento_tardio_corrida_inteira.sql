-- =============================================================================
-- 17/10/2026 · TVDE · CANCELAMENTO TARDIO DO CLIENTE = CORRIDA INTEIRA + COMPENSAÇÃO AO MOTORISTA
-- -----------------------------------------------------------------------------
-- Regra do Danilo (17/10/2026): se o cliente cancelar depois dos 3 minutos
-- (cancel_grace_seconds, contados desde a ACEITAÇÃO do motorista), cobra-se a
-- corrida completa e o motorista recebe 3,75 € (tvde_cancel_driver_fee_cents),
-- pagos no acerto da semana.
--
-- ADITIVO. O que NÃO muda (continua exactamente como estava):
--   · corridas de plano, de pacote ida-e-volta, marcadas (reserva), de balcão e
--     em fila  -> taxa fixa de antes (tvde_cancel_fee_cents) e sem compensação;
--   · cancelamento feito pelo admin em nome do cliente;
--   · no-show do passageiro e desistência do motorista;
--   · todas as semanas já fechadas/pagas (a tabela nova nasce vazia).
-- A compensação vive numa tabela PRÓPRIA (não no livro-razão: o alarme diário
-- _cron_check_orphan_ledger dispararia por cada linha sem pedido de entrega).
-- Esta migração só ACRESCENTA e remenda funções: não apaga nem altera linhas de dados existentes.
-- =============================================================================

-- ---------------------------------------------------------------- utilitário
CREATE OR REPLACE FUNCTION pg_temp._patch(p_def text, p_anchor text, p_repl text, p_label text)
RETURNS text LANGUAGE plpgsql AS $p$
DECLARE v_n int;
BEGIN
  v_n := (length(p_def) - length(replace(p_def, p_anchor, ''))) / NULLIF(length(p_anchor), 0);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ancora "%": % ocorrencias (esperava exactamente 1)', p_label, v_n;
  END IF;
  RETURN replace(p_def, p_anchor, p_repl);
END $p$;

-- ------------------------------------------------------------ 1) definição nova
INSERT INTO public.platform_settings (key, value, description, category, is_secret, updated_at)
VALUES (
  'tvde_cancel_driver_fee_cents',
  to_jsonb(375),
  'DINHEIRO. TVDE: quanto o motorista recebe (em cêntimos: 375 = 3,75 €) quando o cliente cancela DEPOIS da janela de graça (cancel_grace_seconds, contada desde a aceitação), com o motorista já aceite e antes de apanhar o passageiro. Nesse caso o cliente paga a corrida INTEIRA; o motorista recebe este valor no acerto da semana; o resto fica para a Bora. Só vale nas corridas normais (não plano, pacote ida-e-volta, marcada, balcão, em fila). Nesses outros casos, e quando o admin cancela em nome do cliente, continua a valer a taxa fixa tvde_cancel_fee_cents (2,50 €) e o motorista não recebe nada.',
  'tvde', false, now())
ON CONFLICT (key) DO NOTHING;

-- o painel passa a poder editar o valor novo (com motivo e auditoria, como as outras)
DO $mig$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.admin_update_cancel_setting(text,numeric,text)'::regprocedure);
  v_def := pg_temp._patch(v_def,
    $a$'cancel_fee_after_accept_driver_cents','cancel_fee_after_pickup_ratio'$a$,
    $a$'cancel_fee_after_accept_driver_cents','cancel_fee_after_pickup_ratio','tvde_cancel_driver_fee_cents'$a$,
    'whitelist');
  EXECUTE v_def;
END $mig$;

-- ---------------------------------------------------------------- 2) tabela
CREATE TABLE IF NOT EXISTS public.tvde_cancel_compensations (
  ride_id        uuid PRIMARY KEY REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  driver_id      uuid NOT NULL,
  client_id      uuid,
  fee_cents      integer NOT NULL DEFAULT 0 CHECK (fee_cents >= 0),
  driver_cents   integer NOT NULL CHECK (driver_cents > 0 AND driver_cents <= 100000),
  bora_cents     integer NOT NULL,
  collected_via  text NOT NULL CHECK (collected_via IN ('pagamento_retido','carteira','nao_cobrado','admin')),
  payment_method text,
  origem         text NOT NULL DEFAULT 'regra' CHECK (origem IN ('regra','admin')),
  reason         text,
  created_by     uuid,
  created_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.tvde_cancel_compensations IS
  'TVDE: compensação paga ao motorista quando o cliente cancela tarde (regra 17/10/2026) ou dada à mão pelo admin. Uma linha por corrida. Entra no acerto semanal do motorista (compute_driver_settlement) e no extrato (_prestador_trabalhos). fee_cents = o que o cliente paga; driver_cents = o que o motorista recebe; bora_cents = o que fica para a Bora (pode ser negativo quando a Bora cobre a diferença).';
CREATE INDEX IF NOT EXISTS tvde_cancel_comp_driver_idx  ON public.tvde_cancel_compensations (driver_id, created_at);
CREATE INDEX IF NOT EXISTS tvde_cancel_comp_created_idx ON public.tvde_cancel_compensations (created_at DESC);

ALTER TABLE public.tvde_cancel_compensations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tvde_cancel_compensations FROM anon, authenticated;
GRANT SELECT ON public.tvde_cancel_compensations TO authenticated;
CREATE POLICY tvde_cancel_comp_admin_select ON public.tvde_cancel_compensations
  FOR SELECT TO authenticated USING (public.is_admin());

-- ------------------------------------------------- 3) a regra, num só sítio
-- Usada pelo cancelamento a sério E pelo orçamento que a app mostra ao cliente:
-- assim o ecrã nunca diz uma coisa e o servidor cobra outra.
CREATE OR REPLACE FUNCTION public._tvde_client_cancel_terms(
  p_ride public.tvde_rides, p_accepted_at timestamptz, p_now timestamptz DEFAULT now())
RETURNS TABLE (
  regra text, taxa_cents integer, motorista_cents integer, como_cobra text,
  graca_segundos integer, segundos_desde_aceitacao integer,
  tinha_motorista boolean, antes_da_recolha boolean, tarifa_cents integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_grace  int     := COALESCE((public.get_setting('cancel_grace_seconds') #>> '{}')::int, 180);
  v_full   boolean := COALESCE((public.get_setting('tvde_cancel_full_after_grace') #>> '{}')::boolean, false);
  v_fixed  int     := COALESCE((public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int, 250);
  -- aceita 375 e também 3.75 (arredonda), nunca negativo nem absurdo
  v_drv    int     := LEAST(GREATEST(COALESCE(round((public.get_setting('tvde_cancel_driver_fee_cents') #>> '{}')::numeric), 375), 0), 100000)::int;
  v_secs   int     := GREATEST(0, EXTRACT(EPOCH FROM (p_now - p_accepted_at))::int);
  -- o mesmo valor que a cobrança e o reembolso usam (tvde_ride_charge_cents / auto_refund_ride)
  v_fare   int     := COALESCE(p_ride.final_fare_cents, p_ride.est_fare_cents, 0);
  v_had    boolean := p_ride.driver_id IS NOT NULL;
  v_before boolean := p_ride.status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou');
  v_online boolean := COALESCE(p_ride.payment_method, 'cash') IN ('mbway','card');
  v_paid   boolean := COALESCE(p_ride.payment_status, '') = 'succeeded';
  v_elig   boolean;
BEGIN
  -- sem motorista, já em viagem, regra desligada, ou balcão (nunca paga taxa): sem custo
  IF NOT (v_had AND v_before) OR NOT v_full OR COALESCE(p_ride.source, 'app') = 'balcao' THEN
    RETURN QUERY SELECT 'sem_custo'::text, 0, 0, NULL::text, v_grace, v_secs, v_had, v_before, v_fare;
    RETURN;
  END IF;
  IF v_secs <= v_grace THEN
    RETURN QUERY SELECT 'dentro_da_graca'::text, 0, 0, NULL::text, v_grace, v_secs, v_had, v_before, v_fare;
    RETURN;
  END IF;
  -- corrida NORMAL: nem plano, nem pacote, nem marcada, nem em fila.
  -- Pagamento online que ainda NÃO entrou (pendente): não se cobra mais nada por cima
  -- (evita cobrar duas vezes se o cliente ainda aprovar o MB Way) -> fica a taxa fixa de antes.
  v_elig := NOT COALESCE(p_ride.is_queued, false)
        AND NOT COALESCE(p_ride.used_subscription_ride, false)
        AND p_ride.roundtrip_credit_id IS NULL
        AND p_ride.agreed_fare_cents IS NULL
        AND p_ride.reservation_status IS NULL
        AND p_ride.scheduled_at IS NULL
        AND (NOT v_online OR v_paid);
  IF v_elig AND v_fare > 0 THEN
    RETURN QUERY SELECT 'corrida_inteira'::text, v_fare, v_drv,
      CASE WHEN v_online THEN 'pagamento_retido' ELSE 'carteira' END,
      v_grace, v_secs, v_had, v_before, v_fare;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'taxa_fixa'::text, v_fixed, 0, NULL::text, v_grace, v_secs, v_had, v_before, v_fare;
END $fn$;

-- Orçamento para a app: "se cancelares agora, quanto pagas?" (só leitura)
CREATE OR REPLACE FUNCTION public.tvde_cancel_quote(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid  uuid := auth.uid();
  v_ride public.tvde_rides;
  v_acc  timestamptz;
  t      record;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ride_not_found');
  END IF;
  IF NOT (public.is_admin() OR v_ride.client_id = v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authorized');
  END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista') THEN
    RETURN jsonb_build_object('ok', true, 'terminal', true, 'status', v_ride.status,
                              'fee_cents', COALESCE(v_ride.cancel_fee_cents, 0));
  END IF;
  SELECT max(e.at) INTO v_acc FROM public.tvde_ride_events e
   WHERE e.ride_id = p_ride_id AND e.status = 'motorista_atribuido';
  v_acc := COALESCE(v_acc, v_ride.created_at);
  BEGIN
    SELECT * INTO t FROM public._tvde_client_cancel_terms(v_ride, v_acc, now());
  EXCEPTION WHEN OTHERS THEN
    -- uma definição estragada nunca deve rebentar o ecrã: a app volta ao cálculo local
    RETURN jsonb_build_object('ok', false, 'error', 'quote_failed');
  END;
  RETURN jsonb_build_object(
    'ok', true, 'terminal', false,
    'regra', t.regra,
    'fee_cents', t.taxa_cents,
    'fare_cents', t.tarifa_cents,
    'como_cobra', t.como_cobra,
    'grace_seconds', t.graca_segundos,
    'seconds_since_accept', t.segundos_desde_aceitacao,
    'seconds_left_free', CASE WHEN t.regra = 'dentro_da_graca'
                              THEN GREATEST(0, t.graca_segundos - t.segundos_desde_aceitacao) ELSE 0 END,
    'had_driver', t.tinha_motorista,
    'accepted_at', v_acc);
END $fn$;

-- --------------------------------------------- 4) o cancelamento (remendo)
DO $mig$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public.tvde_cancel_ride(uuid,text,text)'::regprocedure);

  -- variáveis novas
  v_def := pg_temp._patch(v_def,
    $a$  v_accepted_at TIMESTAMPTZ;$a$,
    $a$  v_accepted_at TIMESTAMPTZ;
  v_terms RECORD;
  v_comp_cents INT := 0;
  v_how TEXT;
  v_collect TEXT;
  v_wallet_err TEXT;
  v_comp_saved BOOLEAN := false;
  v_nkey TEXT;
  v_nurl TEXT;$a$,
    'decl');

  -- a taxa: o PRÓPRIO cliente, depois da graça, em corrida normal -> corrida inteira
  v_def := pg_temp._patch(v_def,
    $a$      v_fee := COALESCE((public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int, 250);$a$,
    $a$      v_fee := COALESCE((public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int, 250);
      -- 17/10/2026 · REGRA NOVA (Danilo): quem cancela é o próprio cliente, já passou a
      -- graça (desde a aceitação) e a corrida é normal -> paga a CORRIDA INTEIRA e o
      -- motorista recebe a compensação fixa. Tudo o resto fica com a taxa fixa de antes.
      IF v_uid IS NOT NULL AND v_uid = v_ride.client_id THEN
        BEGIN
          SELECT * INTO v_terms FROM public._tvde_client_cancel_terms(v_ride, v_accepted_at, now());
          IF v_terms.regra = 'corrida_inteira' AND v_terms.taxa_cents > 0 THEN
            v_fee := v_terms.taxa_cents;
            v_comp_cents := v_terms.motorista_cents;
            v_how := v_terms.como_cobra;
          END IF;
        EXCEPTION WHEN OTHERS THEN
          -- a regra nova nunca pode impedir um cancelamento: se algo falhar, vale a taxa fixa de antes
          v_comp_cents := 0;
          v_how := NULL;
        END;
      END IF;$a$,
    'taxa');

  -- o rasto no evento do cancelamento
  v_def := pg_temp._patch(v_def,
    $a$'seconds_since_accept', EXTRACT(EPOCH FROM (now() - v_accepted_at))::int));$a$,
    $a$'seconds_since_accept', EXTRACT(EPOCH FROM (now() - v_accepted_at))::int)
            || CASE WHEN v_how IS NOT NULL
                    THEN jsonb_build_object('regra', 'corrida_inteira', 'driver_comp_cents', v_comp_cents, 'como_cobra', v_how)
                    ELSE '{}'::jsonb END);$a$,
    'evento');

  -- cobrar o cliente + compensar o motorista (nada aqui pode impedir o cancelamento)
  v_def := pg_temp._patch(v_def,
    $a$  IF v_was_active_of_driver THEN$a$,
    $a$  -- 17/10/2026 · cancelamento tardio do cliente: corrida inteira + compensação ao motorista.
  -- Cada passo falha sozinho (e avisa o admin); nenhum impede o cancelamento.
  IF v_how IS NOT NULL AND COALESCE(v_ride.cancel_fee_cents, 0) > 0 AND v_ride.driver_id IS NOT NULL THEN
    v_collect := v_how;
    IF v_how = 'carteira' THEN
      -- corrida a dinheiro (ou pagamento ainda não confirmado): fica como dívida na carteira
      BEGIN
        PERFORM public.wallet_debit_cancel_fee(v_ride.client_id, v_ride.id::text, v_ride.cancel_fee_cents, 'after_accept');
      EXCEPTION WHEN OTHERS THEN
        v_collect := 'nao_cobrado';
        v_wallet_err := left(SQLERRM, 200);
      END;
    END IF;
    IF v_comp_cents > 0 THEN
      BEGIN
        INSERT INTO public.tvde_cancel_compensations
          (ride_id, driver_id, client_id, fee_cents, driver_cents, bora_cents,
           collected_via, payment_method, origem, reason, created_by)
        VALUES
          (v_ride.id, v_ride.driver_id, v_ride.client_id, v_ride.cancel_fee_cents, v_comp_cents,
           v_ride.cancel_fee_cents - v_comp_cents,
           v_collect, v_ride.payment_method, 'regra', p_reason, v_uid)
        ON CONFLICT (ride_id) DO NOTHING;
        INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
          VALUES (p_ride_id, 'compensacao_cancelamento', 'system',
                  jsonb_build_object('fee_cents', v_ride.cancel_fee_cents, 'driver_cents', v_comp_cents,
                                     'bora_cents', v_ride.cancel_fee_cents - v_comp_cents,
                                     'como_cobra', v_collect, 'carteira_erro', v_wallet_err));
        v_comp_saved := true;
      EXCEPTION WHEN OTHERS THEN
        BEGIN
          PERFORM public.notify_admin_event('tvde_compensacao_falhou', 'high',
            'Cancelamento tardio: a corrida foi cancelada mas NÃO consegui registar a compensação ao motorista. Compensar à mão.',
            'tvde_ride', v_ride.id::text,
            jsonb_build_object('ride_id', v_ride.id, 'driver_id', v_ride.driver_id,
                               'driver_cents', v_comp_cents, 'erro', left(SQLERRM, 200)),
            '/admin/tvde/cancelamentos');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
      END;
    END IF;
    IF v_collect = 'nao_cobrado' THEN
      BEGIN
        PERFORM public.notify_admin_event('tvde_cancel_fee_nao_cobrada', 'high',
          'Cancelamento tardio: não consegui cobrar ' || replace(to_char(v_ride.cancel_fee_cents / 100.0, 'FM990.00'), '.', ',')
            || ' € ao cliente (carteira no limite).' || CASE WHEN v_comp_saved THEN ' O motorista foi compensado.' ELSE '' END,
          'tvde_ride', v_ride.id::text,
          jsonb_build_object('ride_id', v_ride.id, 'client_id', v_ride.client_id,
                             'fee_cents', v_ride.cancel_fee_cents, 'erro', v_wallet_err),
          '/admin/tvde/cancelamentos');
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
    -- avisa o motorista (caixa da app + push); falhar aqui nunca estraga o cancelamento
    IF v_comp_saved THEN
      BEGIN
        PERFORM public._push_in_app_notification(v_ride.driver_id, 'tvde_cancel_comp',
          'Corrida cancelada · recebes ' || replace(to_char(v_comp_cents / 100.0, 'FM990.00'), '.', ',') || ' €',
          'O cliente cancelou depois dos ' || round(COALESCE(v_terms.graca_segundos, 180) / 60.0)::int
            || ' minutos. A compensação entra no teu acerto desta semana.',
          v_ride.id::text);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      BEGIN
        SELECT decrypted_secret INTO v_nkey FROM vault.decrypted_secrets WHERE name = 'service_role_key';
        SELECT decrypted_secret INTO v_nurl FROM vault.decrypted_secrets WHERE name = 'project_url';
        IF v_nkey IS NOT NULL THEN
          PERFORM net.http_post(
            url := COALESCE(v_nurl, 'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/notify-admin-message',
            headers := jsonb_build_object('Authorization', 'Bearer ' || v_nkey, 'Content-Type', 'application/json'),
            body := jsonb_build_object(
              'targetUserId', v_ride.driver_id::text,
              'title', 'Corrida cancelada · recebes ' || replace(to_char(v_comp_cents / 100.0, 'FM990.00'), '.', ',') || ' €',
              'body', 'O cliente cancelou depois dos ' || round(COALESCE(v_terms.graca_segundos, 180) / 60.0)::int
                      || ' minutos. A compensação entra no teu acerto desta semana.',
              'kind', 'tvde_cancel_compensation',
              'relatedId', v_ride.id::text));
        END IF;
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;

  IF v_was_active_of_driver THEN$a$,
    'compensacao');

  EXECUTE v_def;
END $mig$;

-- ------------------------------------------- 5) o acerto da semana (remendos)
DO $mig$
DECLARE v_def text;
BEGIN
  -- 5a) quanto o motorista ganha na semana: soma as compensações (dentro de "Corridas")
  v_def := pg_get_functiondef('public.compute_driver_settlement(uuid,timestamptz,boolean)'::regprocedure);
  v_def := pg_temp._patch(v_def,
    $a$  v_tvde_sem_tarifa INT := 0;$a$,
    $a$  v_tvde_sem_tarifa INT := 0;
  v_cancel_comp NUMERIC := 0;$a$,
    'settle_decl');
  v_def := pg_temp._patch(v_def,
    $a$  v_total_earnings      := v_total_earnings + v_tvde_earnings$a$,
    $a$  -- 17/10/2026 · compensações de cancelamento tardio (o cliente cancelou depois da graça):
  -- o motorista recebe a compensação fixa; entra em "Corridas" do acerto da semana.
  SELECT COALESCE(SUM(c.driver_cents), 0) / 100.0
    INTO v_cancel_comp
    FROM public.tvde_cancel_compensations c
   WHERE c.driver_id = p_driver_id
     AND c.created_at >= v_bounds.week_start
     AND c.created_at <= v_bounds.week_end;
  v_tvde_earnings := v_tvde_earnings + v_cancel_comp;

  v_total_earnings      := v_total_earnings + v_tvde_earnings$a$,
    'settle_soma');
  v_def := pg_temp._patch(v_def,
    $a$    'tvde_sem_dinheiro_em_mao_gravado', v_tvde_sem_tarifa,$a$,
    $a$    'tvde_sem_dinheiro_em_mao_gravado', v_tvde_sem_tarifa,
    'tvde_cancel_comp', v_cancel_comp,$a$,
    'settle_ret');
  EXECUTE v_def;

  -- 5b) o fecho de segunda-feira também percorre quem só teve compensações
  v_def := pg_get_functiondef('public.close_previous_week_settlements()'::regprocedure);
  v_def := pg_temp._patch(v_def,
    $a$) todos$a$,
    $a$UNION
      SELECT c.driver_id AS id
      FROM public.tvde_cancel_compensations c, public.driver_settlement_week_bounds(v_anchor) b
      WHERE c.created_at >= b.week_start
        AND c.created_at <= b.week_end
    ) todos$a$,
    'close_loop');
  EXECUTE v_def;

  -- 5c) o extrato do motorista mostra a compensação (e diz que entra no acerto)
  v_def := pg_get_functiondef('public._prestador_trabalhos(uuid,timestamptz)'::regprocedure);
  v_def := pg_temp._patch(v_def,
    $a$  SELECT 'corrida'::text,$a$,
    $a$  SELECT 'compensacao'::text,
         c.ride_id::text,
         c.created_at,
         'Compensação · corrida cancelada pelo cliente',
         COALESCE(r.origin_label, ''),
         COALESCE(r.dest_label, ''),
         COALESCE(r.payment_method, 'cash'),
         CASE WHEN c.collected_via = 'pagamento_retido' THEN c.fee_cents ELSE 0 END,
         c.driver_cents,
         GREATEST(c.bora_cents, 0),
         0, 0, 0,
         -c.driver_cents,
         NULL::numeric, 0,
         jsonb_build_array(jsonb_build_object('nome', 'Compensação de cancelamento', 'valor_cents', c.driver_cents)),
         true,
         CASE WHEN c.origem = 'admin' THEN 'Compensação dada pela Bora. Entra no acerto semanal.'
              ELSE 'O cliente cancelou depois da janela de graça, com o motorista já a caminho. Entra no acerto semanal.' END
    FROM public.tvde_cancel_compensations c
    JOIN public.tvde_rides r ON r.id = c.ride_id
   WHERE (c.driver_id = p_uid OR c.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = p_uid))
     AND c.created_at >= p_de

  UNION ALL

  SELECT 'corrida'::text,$a$,
    'trabalhos');
  EXECUTE v_def;
END $mig$;

-- ------------------------------------------------ 6) painel admin (ver / dar)
CREATE OR REPLACE FUNCTION public.admin_tvde_cancel_comps(p_limit integer DEFAULT 100)
RETURNS TABLE (
  ride_id uuid, created_at timestamptz, driver_id uuid, driver_name text,
  client_id uuid, client_name text, fee_cents integer, driver_cents integer, bora_cents integer,
  collected_via text, payment_method text, origem text, reason text,
  ride_status text, payment_status text, est_fare_cents integer,
  client_wallet_cents integer, week_status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT c.ride_id, c.created_at, c.driver_id,
         COALESCE((SELECT d.name FROM public.drivers d WHERE d.user_id = c.driver_id OR d.id = c.driver_id LIMIT 1),
                  (SELECT u.name FROM public.users u WHERE u.id = c.driver_id)),
         c.client_id,
         (SELECT u.name FROM public.users u WHERE u.id = c.client_id),
         c.fee_cents, c.driver_cents, c.bora_cents, c.collected_via, c.payment_method, c.origem, c.reason,
         r.status, r.payment_status, r.est_fare_cents,
         (SELECT w.free_balance_cents FROM public.client_wallets w WHERE w.user_id = c.client_id),
         (SELECT s.status FROM public.driver_weekly_settlements s
           WHERE s.driver_id = c.driver_id AND c.created_at >= s.week_start_at AND c.created_at <= s.week_end_at
           LIMIT 1)
    FROM public.tvde_cancel_compensations c
    JOIN public.tvde_rides r ON r.id = c.ride_id
   ORDER BY c.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500));
END $fn$;

-- Compensação dada à mão pelo admin (corrida cancelada pelo cliente ou no-show).
CREATE OR REPLACE FUNCTION public.admin_tvde_cancel_comp_grant(
  p_ride_id uuid, p_driver_cents integer, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_admin record;
  v_ride  public.tvde_rides;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN RAISE EXCEPTION 'reason_required'; END IF;
  IF p_driver_cents IS NULL OR p_driver_cents <= 0 OR p_driver_cents > 5000 THEN
    RAISE EXCEPTION 'invalid_value';
  END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_ride.driver_id IS NULL THEN RAISE EXCEPTION 'ride_without_driver'; END IF;
  IF v_ride.status NOT IN ('cancelada_cliente','no_show') THEN
    RAISE EXCEPTION 'ride_not_cancelled_by_client: %', v_ride.status;
  END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_cancel_compensations WHERE ride_id = p_ride_id) THEN
    RAISE EXCEPTION 'compensation_already_exists';
  END IF;
  INSERT INTO public.tvde_cancel_compensations
    (ride_id, driver_id, client_id, fee_cents, driver_cents, bora_cents,
     collected_via, payment_method, origem, reason, created_by)
  VALUES
    (v_ride.id, v_ride.driver_id, v_ride.client_id, 0, p_driver_cents, -p_driver_cents,
     'admin', v_ride.payment_method, 'admin', trim(p_reason), v_admin.admin_id);
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'tvde_cancel_comp_grant', 'tvde_ride', v_ride.id,
          jsonb_build_object('driver_id', v_ride.driver_id, 'client_id', v_ride.client_id,
                             'driver_cents', p_driver_cents, 'reason', trim(p_reason),
                             'ride_status', v_ride.status));
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (v_ride.id, 'compensacao_cancelamento', 'admin',
          jsonb_build_object('driver_cents', p_driver_cents, 'origem', 'admin', 'reason', trim(p_reason)));
  BEGIN
    PERFORM public._push_in_app_notification(v_ride.driver_id, 'tvde_cancel_comp',
      'Compensação · recebes ' || replace(to_char(p_driver_cents / 100.0, 'FM990.00'), '.', ',') || ' €',
      'A Bora deu-te uma compensação por uma corrida cancelada. Entra no teu acerto desta semana.',
      v_ride.id::text);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN jsonb_build_object('ok', true, 'ride_id', v_ride.id, 'driver_cents', p_driver_cents);
END $fn$;

-- ------------------------------------------------------------- 7) permissões
REVOKE ALL ON FUNCTION public._tvde_client_cancel_terms(public.tvde_rides, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_cancel_quote(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_cancel_quote(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_tvde_cancel_comps(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_cancel_comps(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_tvde_cancel_comp_grant(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_cancel_comp_grant(uuid, integer, text) TO authenticated;
