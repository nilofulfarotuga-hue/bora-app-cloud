-- PROPOSTA (a tranca bora-mods recusou escrever este ficheiro em supabase/migrations/ a 30/10/2026:
-- "migration que toca tokens/wallet/pagamentos/ledger" — o texto fala da Stripe).
-- Destino: supabase/migrations/20261030145000_gorjeta_checkout_junto_pagamento.sql (carimbo ANTES de
-- 20261030151000 admin_listar_gorjetas, que precisa de tips.cobrada_junto; DEPOIS de
-- 20261030144900_gorjeta_checkout_interruptor.sql, que cria a chave do interruptor).
-- ⚠️ ISTO MEXE EM DINHEIRO (gorjetas) — está tudo pronto. Prova em rollback: supabase/tests/gorjetas_taxa_prova.sql.
--
-- ============================================================================
-- Gorjetas — missão gorjetas-taxa-2026-10-30 (Blocos A servidor, B e C).
-- Autorização do Danilo (30/10/2026 13:40, à Claude.ai): a gorjeta dada no carrinho vai no MESMO
-- pagamento da compra (cartão ou MB Way) e vai inteira para o estafeta; pedido cancelado → a
-- gorjeta volta inteira ao cliente; a taxa da Stripe das gorjetas pagas depois fica sempre gravada.
-- NÃO mexe em preços, comissões, taxas de entrega/serviço, nem no dinheiro de clientes ou
-- prestadores antigos. Nenhum UPDATE/INSERT direto em orders: só tips e tabelas novas.
--
-- Como funciona (compatível com as apps velhas e com as funções da zona vermelha antes dos patches):
--  1. A app nova, ANTES de abrir o ecrã de pagamento, marca a gorjeta:
--     client_preparar_gorjeta_checkout(cêntimos) → gorjeta_checkout_pendente (uma por cliente,
--     válida 20 min; 0/NULL apaga). A app limpa-a quando o ecrã de pagamento fecha (com sucesso ou
--     não). O servidor copia-a ao criar o pagamento do cartão e ao inserir o pedido MB Way — nunca
--     no webhook. Pedidos a dinheiro, pagos só com saldo e Favores/envios (fora do carrinho) não lhe
--     tocam. Com o interruptor desligado responde ok:false e a app continua com a charge-tip à parte.
--  2. Cartão (paga primeiro; o pedido nasce depois, no finalize-order-from-intent): o patch do
--     create-payment-intent lê gorjeta_checkout_para_cobrar(user), soma-a ao valor do pagamento e
--     guarda-a no rascunho (payment_drafts.payload.gorjeta_checkout_cents). Quando o pedido nasce com
--     esse pagamento, o gatilho trg_zz_gorjeta_checkout_na_criacao cria a linha em tips já paga
--     (method card, moment checkout, cobrada_junto). Sem o patch o rascunho não traz gorjeta: nada muda.
--  3. MB Way (o pedido nasce primeiro): o mesmo gatilho cria a gorjeta 'pending' (cobrada_junto)
--     com o interruptor ligado, só em pedidos do carrinho (restaurant/storeShopping/takeaway), e gasta
--     a marcação; o patch do create-mbway-payment-intent soma-a ao valor
--     (gorjeta_checkout_mbway_valor) e grava nela o pagamento (gorjeta_checkout_mbway_pi).
--     trg_zz_gorjeta_checkout_pagamento põe-na 'succeeded' quando o pedido fica pago com esse
--     pagamento (ou quando o cobrado = buffer + gorjeta) e 'failed' quando o pagamento falha.
--     O stripe-webhook não precisa de mudar para isto.
--  4. Pedido cancelado/rejeitado: gorjeta do carrinho cujo pagamento nem foi criado → 'cancelled' (aqui,
--     no gatilho de sempre). Gorjeta já paga, ou com pagamento MB Way criado (o cliente pode ter aprovado
--     antes do webhook) → a Edge Function charge-tip (ação devolver_cancelamento) pergunta à Stripe e
--     devolve-a inteira, uma vez: chamam-na as funções de cancelamento logo a seguir ao reembolso da
--     compra e, como rede de segurança, gorjetas_devolver_cancelados() de 15 em 15 minutos.
--  5. Bloco C: ao domingo, antes do fecho semanal (segunda 00:05 UTC, job 26), a charge-tip vai
--     buscar à Stripe as taxas que faltam (ação taxas_em_falta) e regista no e2e_log.
-- Interruptor: platform_settings.tips_checkout_junto_pagamento (migração 20261030144900, false).
-- ============================================================================

-- Não ficar à espera de bloqueios em orders/tips em produção: falha depressa e repete-se.
SET lock_timeout = '3s';

-- ── 1. tips: como foi paga e para onde voltou ───────────────────────────────
ALTER TABLE public.tips ADD COLUMN IF NOT EXISTS cobrada_junto boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.tips.cobrada_junto IS
  'true = gorjeta do carrinho cobrada no MESMO pagamento da compra (o PI é o do pedido). Vai inteira para o prestador.';
ALTER TABLE public.tips ADD COLUMN IF NOT EXISTS devolvida_para text
  CHECK (devolvida_para IS NULL OR devolvida_para IN ('meio', 'carteira'));
COMMENT ON COLUMN public.tips.devolvida_para IS
  'Quando refunded: meio = voltou ao cartão/MB Way; carteira = voltou ao saldo Bora (escolha do cliente no cancelamento).';
ALTER TABLE public.tips ADD COLUMN IF NOT EXISTS devolucao_tentativas integer NOT NULL DEFAULT 0;
COMMENT ON COLUMN public.tips.devolucao_tentativas IS
  'Devoluções falhadas (pedido cancelado). Com 2 a conferência automática pára e o admin é avisado uma vez.';
CREATE INDEX IF NOT EXISTS tips_por_pedido ON public.tips(order_id) WHERE order_id IS NOT NULL;

-- ── 2. Marcação da gorjeta antes de pagar ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gorjeta_checkout_pendente (
  user_id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tip_cents        integer NOT NULL CHECK (tip_cents >= 50),
  criado_em        timestamptz NOT NULL DEFAULT now(),
  expira_em        timestamptz NOT NULL DEFAULT now() + interval '20 minutes',
  usado_em         timestamptz,
  order_id         text,
  gorjeta_aplicada boolean
);
COMMENT ON TABLE public.gorjeta_checkout_pendente IS
  'Gorjeta marcada no carrinho antes de pagar (vale 20 min; copiada para o pagamento do cartão ou gasta pelo pedido MB Way do carrinho; a app limpa-a ao fechar o ecrã de pagamento). Só por funções SECURITY DEFINER.';
ALTER TABLE public.gorjeta_checkout_pendente ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gorjeta_checkout_pendente FROM PUBLIC, anon, authenticated;

-- Gorjetas ligadas E gorjeta do carrinho no mesmo pagamento ligada.
CREATE OR REPLACE FUNCTION public._gorjeta_checkout_ligada()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
  SELECT COALESCE((public.get_setting('tips_enabled') #>> '{}')::boolean, false)
     AND COALESCE((public.get_setting('tips_checkout_junto_pagamento') #>> '{}')::boolean, false);
$f$;

-- A app chama antes de pagar (cartão ou MB Way). 0/NULL = sem gorjeta (apaga a marcação).
CREATE OR REPLACE FUNCTION public.client_preparar_gorjeta_checkout(p_tip_cents integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
DECLARE
  v_uid uuid := auth.uid();
  v_max integer := COALESCE((public.get_setting('tip_max_cents') #>> '{}')::integer, 5000);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  IF COALESCE(p_tip_cents, 0) = 0 THEN
    DELETE FROM public.gorjeta_checkout_pendente WHERE user_id = v_uid;
    RETURN jsonb_build_object('ok', true, 'gorjeta_cents', 0);
  END IF;
  IF NOT public._gorjeta_checkout_ligada() THEN
    DELETE FROM public.gorjeta_checkout_pendente WHERE user_id = v_uid;
    RETURN jsonb_build_object('ok', false, 'motivo', 'junto_desligado');
  END IF;
  IF p_tip_cents < 50 OR p_tip_cents > v_max THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'valor_invalido', 'min', 50, 'max', v_max);
  END IF;
  INSERT INTO public.gorjeta_checkout_pendente (user_id, tip_cents)
  VALUES (v_uid, p_tip_cents)
  ON CONFLICT (user_id) DO UPDATE
     SET tip_cents = EXCLUDED.tip_cents, criado_em = now(),
         expira_em = now() + interval '20 minutes',
         usado_em = NULL, order_id = NULL, gorjeta_aplicada = NULL;
  RETURN jsonb_build_object('ok', true, 'gorjeta_cents', p_tip_cents,
                            'expira_em', now() + interval '20 minutes');
END $f$;

-- Para o create-payment-intent (cartão, patch proposto): quanto somar ao pagamento. Não gasta a
-- marcação (o cliente pode fechar a folha e tentar outra vez): o patch copia-a para o rascunho e
-- a app limpa-a quando o ecrã de pagamento fecha.
CREATE OR REPLACE FUNCTION public.gorjeta_checkout_para_cobrar(p_user_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
  SELECT CASE WHEN public._gorjeta_checkout_ligada() THEN COALESCE((
           SELECT g.tip_cents FROM public.gorjeta_checkout_pendente g
            WHERE g.user_id = p_user_id AND g.usado_em IS NULL AND g.expira_em > now()
              AND g.tip_cents BETWEEN 50 AND COALESCE((public.get_setting('tip_max_cents') #>> '{}')::integer, 5000)
         ), 0) ELSE 0 END;
$f$;

-- Para o create-mbway-payment-intent (patch proposto): a gorjeta do carrinho por pagar deste pedido.
-- Se o pedido ainda está à espera de pagamento e a gorjeta tinha ficado 'failed' (pagamento anterior
-- falhou), volta a 'pending' para ir na nova tentativa — nunca duas vezes: só há uma gorjeta por pedido.
CREATE OR REPLACE FUNCTION public.gorjeta_checkout_mbway_valor(p_order_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
DECLARE v_cents integer;
BEGIN
  UPDATE public.tips t SET status = 'pending', failure_reason = NULL
   WHERE t.order_id = p_order_id AND t.cobrada_junto AND t.method = 'mbway' AND t.status = 'failed'
     AND EXISTS (SELECT 1 FROM public.orders o
                  WHERE o.id = p_order_id AND COALESCE(o.payment_status, 'pending') = 'pending'
                    AND o.status NOT IN ('delivered', 'cancelled', 'rejected'));
  SELECT COALESCE(SUM(t.amount_cents), 0)::integer INTO v_cents
    FROM public.tips t
   WHERE t.order_id = p_order_id AND t.cobrada_junto AND t.method = 'mbway'
     AND t.status IN ('pending', 'requires_action');
  RETURN v_cents;
EXCEPTION WHEN unique_violation THEN
  RETURN 0;
END $f$;

-- Grava na gorjeta o pagamento MB Way que a leva (para o gatilho a marcar paga com esse pagamento).
CREATE OR REPLACE FUNCTION public.gorjeta_checkout_mbway_pi(p_order_id text, p_payment_intent text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
BEGIN
  IF p_payment_intent IS NULL OR p_payment_intent = '' THEN RETURN false; END IF;
  UPDATE public.tips SET stripe_payment_intent_id = p_payment_intent
   WHERE order_id = p_order_id AND cobrada_junto AND method = 'mbway'
     AND status IN ('pending', 'requires_action');
  RETURN FOUND;
END $f$;

-- ── 3. O pedido nasce: cartão já pago (rascunho com gorjeta) ou MB Way por pagar ─
CREATE OR REPLACE FUNCTION public._orders_gorjeta_checkout_na_criacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
DECLARE
  c_sem   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_marca public.gorjeta_checkout_pendente%ROWTYPE;
  v_cents integer;
  v_prest uuid;
  v_n     integer := 0;
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  v_prest := COALESCE(NULLIF(NEW.assigned_driver_id, '')::uuid, c_sem);

  SELECT * INTO v_marca FROM public.gorjeta_checkout_pendente
   WHERE user_id = NEW.user_id AND usado_em IS NULL
   FOR UPDATE;

  IF NEW.payment_intent_id IS NOT NULL AND auth.uid() IS NULL
     AND COALESCE(NEW.payment_status, '') = 'paid' THEN
    -- Cartão: só o servidor cria o pedido já pago (finalize-order-from-intent). A gorjeta só existe
    -- se o rascunho DESTE pagamento a trouxer — então o valor cobrado já a incluía. Regista-se mesmo
    -- com o interruptor entretanto desligado: o dinheiro já entrou.
    SELECT NULLIF(d.payload->>'gorjeta_checkout_cents', '')::integer INTO v_cents
      FROM public.payment_drafts d
     WHERE d.payment_intent_id = NEW.payment_intent_id AND d.user_id = NEW.user_id
     ORDER BY d.created_at DESC
     LIMIT 1;
    IF COALESCE(v_cents, 0) >= 50 THEN
      INSERT INTO public.tips (target, order_id, client_user_id, provider_user_id, amount_cents,
                               method, moment, status, stripe_payment_intent_id, paid_at, cobrada_junto)
      VALUES ('order', NEW.id, NEW.user_id, v_prest, v_cents,
              'card', 'checkout', 'succeeded', NEW.payment_intent_id, now(), true)
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
  ELSIF NEW.payment_method = 'mbway' AND COALESCE(NEW.payment_status, 'pending') = 'pending'
        AND NEW.service_type IN ('restaurant', 'storeShopping', 'takeaway')
        AND v_marca.user_id IS NOT NULL AND v_marca.expira_em > now()
        AND public._gorjeta_checkout_ligada()
        AND v_marca.tip_cents BETWEEN 50 AND COALESCE((public.get_setting('tip_max_cents') #>> '{}')::integer, 5000) THEN
    -- MB Way do carrinho: o pedido nasce antes do pagamento; a gorjeta fica à espera dele.
    -- (Favores e envios abrem o pagamento sem passar pelo carrinho: não levam a marcação.)
    INSERT INTO public.tips (target, order_id, client_user_id, provider_user_id, amount_cents,
                             method, moment, status, cobrada_junto)
    VALUES ('order', NEW.id, NEW.user_id, v_prest, v_marca.tip_cents,
            'mbway', 'checkout', 'pending', true)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    -- Gasta-se só aqui, quando foi para o pedido (dinheiro, saldo e Favores nunca a gastam: a app
    -- usa tip_registar_dinheiro / charge-tip, como antes).
    IF v_n > 0 THEN
      UPDATE public.gorjeta_checkout_pendente
         SET usado_em = now(), order_id = NEW.id, gorjeta_aplicada = true
       WHERE user_id = NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Nunca impedir um pedido por causa da gorjeta. Fica no registo; a conferência de 15 em 15 min
  -- regista a gorjeta de cartão que falte (gorjetas_devolver_cancelados, passo 1).
  RAISE WARNING '_orders_gorjeta_checkout_na_criacao: pedido % — %', NEW.id, SQLERRM;
  BEGIN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe)
    VALUES ('gorjetas-taxa-2026-10-30', 'gorjeta_na_criacao', 'erro',
            left(format('pedido %s: %s', NEW.id, SQLERRM), 500));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END $f$;

-- AFTER INSERT: corre depois de todos os BEFORE INSERT (a0*, agendamento, guardas) — o pedido já
-- existe (a chave estrangeira de tips.order_id fica satisfeita).
DROP TRIGGER IF EXISTS trg_zz_gorjeta_checkout_na_criacao ON public.orders;
CREATE TRIGGER trg_zz_gorjeta_checkout_na_criacao
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_gorjeta_checkout_na_criacao();

-- ── 4. MB Way pago / falhado (sem tocar no webhook) ──────────────────────────
CREATE OR REPLACE FUNCTION public._orders_gorjeta_checkout_pagamento()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
BEGIN
  IF COALESCE(NEW.payment_status, '') = 'paid' AND NEW.payment_intent_id IS NOT NULL THEN
    -- Paga só se o pagamento que entrou é o que levava a gorjeta (gravado pelo patch do
    -- create-mbway-payment-intent) ou, se esse registo faltar, se o cobrado = buffer + gorjeta.
    -- 'failed'/'cancelled' também: o webhook reativa pedidos cancelados por payment_failed
    -- quando o MB Way acaba por ser pago.
    UPDATE public.tips t
       SET status = 'succeeded', paid_at = COALESCE(t.paid_at, now()),
           stripe_payment_intent_id = NEW.payment_intent_id, failure_reason = NULL
     WHERE t.order_id = NEW.id AND t.cobrada_junto AND t.method = 'mbway'
       AND t.status IN ('pending', 'requires_action', 'failed', 'cancelled')
       AND (t.stripe_payment_intent_id = NEW.payment_intent_id
            OR (t.stripe_payment_intent_id IS NULL
                AND COALESCE(NEW.stripe_charge_cents, 0) > 0
                AND NEW.stripe_charge_cents
                    = ROUND(COALESCE(NEW.payment_buffer_total, 0) * 100)::integer + t.amount_cents));
  ELSIF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NEW.payment_status = 'failed' THEN
    UPDATE public.tips
       SET status = 'failed', failure_reason = 'o pagamento MB Way do pedido não foi concluído'
     WHERE order_id = NEW.id AND cobrada_junto AND status IN ('pending', 'requires_action');
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_orders_gorjeta_checkout_pagamento: pedido % — %', NEW.id, SQLERRM;
  BEGIN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe)
    VALUES ('gorjetas-taxa-2026-10-30', 'gorjeta_pagamento', 'erro',
            left(format('pedido %s: %s', NEW.id, SQLERRM), 500));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS trg_zz_gorjeta_checkout_pagamento ON public.orders;
CREATE TRIGGER trg_zz_gorjeta_checkout_pagamento
  AFTER UPDATE OF payment_status, stripe_charge_cents, payment_intent_id ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_gorjeta_checkout_pagamento();

-- ── 5. Pedido cancelado/rejeitado (Bloco B) ─────────────────────────────────
-- Igual à de 04/10 (20261004100000_gorjetas.sql) + a gorjeta do carrinho ainda SEM pagamento criado morre
-- com o pedido. Com pagamento criado (MB Way enviado ao telemóvel) NÃO se toca aqui: o cliente pode ter
-- aprovado antes de o webhook chegar — a charge-tip (devolver_cancelamento) pergunta à Stripe e, se
-- entrou, devolve-a inteira; se não, cancela-a. A já paga também volta pela charge-tip.
CREATE OR REPLACE FUNCTION public.fn_orders_gorjeta_acompanha()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
BEGIN
  IF NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id
     AND NULLIF(NEW.assigned_driver_id, '') IS NOT NULL THEN
    UPDATE public.tips SET provider_user_id = NEW.assigned_driver_id::uuid
     WHERE order_id = NEW.id AND status IN ('cash_due', 'pending', 'requires_action');
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'delivered' THEN
      -- A gorjeta é de quem ENTREGOU (pode ter havido troca de estafeta).
      UPDATE public.tips
         SET provider_user_id = COALESCE(NULLIF(NEW.assigned_driver_id, '')::uuid, provider_user_id)
       WHERE order_id = NEW.id AND status NOT IN ('refunded', 'cancelled', 'failed');
      UPDATE public.tips
         SET status = 'cash_collected', paid_at = now()
       WHERE order_id = NEW.id AND status = 'cash_due';
    ELSIF NEW.status IN ('cancelled', 'rejected') THEN
      UPDATE public.tips SET status = 'cancelled'
       WHERE order_id = NEW.id AND status = 'cash_due';
      -- 30/10: gorjeta do carrinho que ia no pagamento do pedido e cujo pagamento nem chegou a ser criado.
      UPDATE public.tips
         SET status = 'cancelled', failure_reason = 'pedido cancelado antes de a gorjeta ser paga'
       WHERE order_id = NEW.id AND cobrada_junto AND status IN ('pending', 'requires_action')
         AND stripe_payment_intent_id IS NULL;
    END IF;
  END IF;
  RETURN NEW;
END $f$;

-- ── 6. Rede de segurança (de 15 em 15 min) ───────────────────────────────────
-- (1) cartão: rascunho com gorjeta, pedido criado e a linha em tips em falta (o gatilho falhou)
--     → regista-a (o dinheiro já entrou).
--     paid_at = hora em que o pedido nasceu: o pedido do cartão só nasce no finalize-order-from-intent
--     DEPOIS de a Stripe confirmar o pagamento — é a mesma hora que o gatilho grava no caminho normal.
-- (2) pedidos cancelados/rejeitados há mais de p_espera (os mais antigos primeiro) com gorjeta paga ou
--     com pagamento criado (MB Way à espera do webhook / à parte) → pede à charge-tip que a devolva
--     (devolver_cancelamento). A charge-tip pergunta à Stripe, reserva cada gorjeta antes de mexer no
--     dinheiro, procura reembolsos já feitos (nunca devolve duas vezes) e escolhe o caminho: saldo Bora
--     se o reembolso do pedido foi para o saldo, senão o cartão/MB Way. Com 2 tentativas falhadas
--     (tips.devolucao_tentativas) pára e o admin já foi avisado uma vez — não volta a tentar sozinha.
-- (3) gorjeta paga num pedido cancelado há mais de 2 h e ainda por devolver → aviso ao admin (uma vez:
--     só quando passa as 2 h, na volta de 15 min em que isso acontece).
CREATE OR REPLACE FUNCTION public.gorjetas_devolver_cancelados(p_espera interval DEFAULT interval '10 minutes')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
DECLARE
  c_sem    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_url    text;
  v_key    text;
  v_cartao integer := 0;
  v_env    integer := 0;
  v_atras  integer := 0;
  v_erro   text;
  r        record;
BEGIN
  -- (1) não deixa a conferência parar se este passo falhar
  BEGIN
    INSERT INTO public.tips (target, order_id, client_user_id, provider_user_id, amount_cents,
                             method, moment, status, stripe_payment_intent_id, paid_at, cobrada_junto)
    SELECT 'order', o.id, o.user_id, COALESCE(NULLIF(o.assigned_driver_id, '')::uuid, c_sem), x.cents,
           'card', 'checkout', 'succeeded', o.payment_intent_id, o.created_at, true
      FROM public.orders o
      CROSS JOIN LATERAL (
        -- só rascunhos que o finalize-order-from-intent fechou com ESTE pedido (o pagamento entrou)
        SELECT NULLIF(d.payload->>'gorjeta_checkout_cents', '')::integer AS cents
          FROM public.payment_drafts d
         WHERE d.payment_intent_id = o.payment_intent_id AND d.user_id = o.user_id
           AND d.used_at IS NOT NULL AND d.order_id = o.id
         ORDER BY d.created_at DESC LIMIT 1) x
     WHERE o.created_at > now() - interval '7 days'
       AND o.payment_intent_id IS NOT NULL
       AND COALESCE(o.payment_status, '') NOT IN ('pending', 'failed')
       AND COALESCE(x.cents, 0) >= 50
       AND NOT EXISTS (SELECT 1 FROM public.tips t WHERE t.stripe_payment_intent_id = o.payment_intent_id)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_cartao = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_erro := SQLERRM;
    RAISE WARNING 'gorjetas_devolver_cancelados passo 1: %', SQLERRM;
  END;

  -- (3) aviso ao admin: gorjeta paga em pedido cancelado há mais de 2 h (só na volta em que passa as 2 h)
  BEGIN
    SELECT count(*) INTO v_atras
      FROM public.tips t JOIN public.orders o ON o.id = t.order_id
     WHERE t.status = 'succeeded' AND t.method IN ('card', 'mbway')
       AND o.status IN ('cancelled', 'rejected')
       AND COALESCE(o.cancelled_at, o.status_updated_at, o.created_at) <= now() - interval '2 hours'
       AND COALESCE(o.cancelled_at, o.status_updated_at, o.created_at) >  now() - interval '2 hours 15 minutes';
    IF v_atras > 0 THEN
      PERFORM public.notify_admin_event('tip_refund_overdue', 'critical',
        format('%s gorjeta(s) paga(s) em pedidos cancelados há mais de 2 h ainda por devolver ao cliente', v_atras),
        'order', NULL, jsonb_build_object('quantas', v_atras), '/admin/gorjetas');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'gorjetas_devolver_cancelados aviso: %', SQLERRM;
  END;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'cofre_sem_url_ou_chave', 'cartao_registadas', v_cartao);
  END IF;

  -- (2) os mais antigos primeiro; só gorjetas com menos de 2 tentativas falhadas
  FOR r IN
    SELECT t.order_id, min(COALESCE(o.cancelled_at, o.status_updated_at, o.created_at)) AS quando
      FROM public.tips t
      JOIN public.orders o ON o.id = t.order_id
     WHERE t.method IN ('card', 'mbway')
       AND (t.status = 'succeeded'
            OR (t.status IN ('pending', 'requires_action') AND t.stripe_payment_intent_id IS NOT NULL))
       AND t.devolucao_tentativas < 2
       AND o.status IN ('cancelled', 'rejected')
       AND COALESCE(o.cancelled_at, o.status_updated_at, o.created_at) < now() - p_espera
       AND COALESCE(o.cancelled_at, o.status_updated_at, o.created_at) > now() - interval '30 days'
     GROUP BY t.order_id
     ORDER BY quando
     LIMIT 20
  LOOP
    PERFORM net.http_post(
      url := v_url || '/functions/v1/charge-tip',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('action', 'devolver_cancelamento', 'orderId', r.order_id,
                                 'motivo', 'pedido cancelado (conferência automática)'));
    v_env := v_env + 1;
  END LOOP;

  IF v_cartao > 0 OR v_env > 0 OR v_atras > 0 OR v_erro IS NOT NULL THEN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe)
    VALUES ('gorjetas-taxa-2026-10-30', 'conferencia_cancelados', CASE WHEN v_erro IS NULL THEN 'ok' ELSE 'erro' END,
            left(format('gorjetas de cartão registadas: %s · pedidos cancelados enviados à charge-tip: %s · pagas há mais de 2 h: %s%s',
                        v_cartao, v_env, v_atras, COALESCE(' · passo 1 falhou: ' || v_erro, '')), 1000));
  END IF;
  RETURN jsonb_build_object('ok', v_erro IS NULL, 'cartao_registadas', v_cartao, 'pedidos_enviados', v_env,
                            'pagas_ha_mais_de_2h', v_atras, 'erro_passo_1', v_erro);
END $f$;

-- ── 7. Bloco C: taxas da Stripe em falta, ao domingo antes do fecho ─────────
CREATE OR REPLACE FUNCTION public.gorjetas_pedir_taxas_em_falta()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $f$
DECLARE
  v_url text;
  v_key text;
  v_req bigint;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe)
    VALUES ('gorjetas-taxa-2026-10-30', 'taxas_em_falta', 'erro', 'cofre sem project_url ou service_role_key');
    RETURN jsonb_build_object('ok', false, 'motivo', 'cofre_sem_url_ou_chave');
  END IF;
  SELECT net.http_post(
    url := v_url || '/functions/v1/charge-tip',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object('action', 'taxas_em_falta')) INTO v_req;
  RETURN jsonb_build_object('ok', true, 'pedido_http', v_req);
END $f$;

-- ── 8. Permissões ────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public._gorjeta_checkout_ligada() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_preparar_gorjeta_checkout(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_preparar_gorjeta_checkout(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.gorjeta_checkout_para_cobrar(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gorjeta_checkout_para_cobrar(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.gorjeta_checkout_mbway_valor(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gorjeta_checkout_mbway_valor(text) TO service_role;
REVOKE ALL ON FUNCTION public.gorjeta_checkout_mbway_pi(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gorjeta_checkout_mbway_pi(text, text) TO service_role;
REVOKE ALL ON FUNCTION public._orders_gorjeta_checkout_na_criacao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._orders_gorjeta_checkout_pagamento() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gorjetas_devolver_cancelados(interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gorjetas_pedir_taxas_em_falta() FROM PUBLIC, anon, authenticated;

-- ── 9. Tarefas agendadas ─────────────────────────────────────────────────────
-- Conferência dos cancelados: de 15 em 15 min. Taxas em falta: domingo 22:00 e 23:00 UTC (o fecho
-- semanal, job 26, corre segunda 00:05 UTC).
SELECT cron.schedule('gorjetas-devolver-cancelados', '*/15 * * * *',
                     $c$SELECT public.gorjetas_devolver_cancelados();$c$);
SELECT cron.schedule('gorjetas-taxas-em-falta-domingo', '0 22,23 * * 0',
                     $c$SELECT public.gorjetas_pedir_taxas_em_falta();$c$);
