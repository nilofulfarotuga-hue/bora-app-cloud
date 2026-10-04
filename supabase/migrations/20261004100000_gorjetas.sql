-- ============================================================================
-- Missão única 2026-10-03 · Bloco 3 — GORJETA (gratificação) igual à Uber
-- 🔴 ZONA DE DINHEIRO — "vai" do Danilo a 03/10/2026 22h15 para este bloco.
-- Escrita 04/10 no PC; APLICAR pela Claude.ai (conector do PC prende nas escritas;
-- PAT do CLI expirado). Depois de aplicar: correr supabase/provas/20261004_b3_prova_gorjeta.sql.
--
-- CAUSA de "nunca ficou gravada nenhuma gorjeta" (achado 03/10, 0 pedidos):
--   1) Checkout: o carrinho somava a gorjeta ao total no ecrã, mas o pedido é criado
--      pela RPC create_order(p_input) e a app NUNCA lhe envia a gorjeta (nem a RPC a
--      conhece). A gorjeta ficava só no telemóvel e nunca era cobrada.
--   2) Ecrã de avaliação: só escrevia orders.tip_amount_cents (UPDATE direto) — não
--      cobrava nada; e o seletor está escondido em pedidos a dinheiro (quase todos).
--      Em toda a história houve só 2 avaliações de estafeta em pedidos não-dinheiro.
--   3) TVDE: não existia gorjeta.
--
-- DESENHO (regra do Danilo 03/10, substitui o 80/20 do BR §4.5 → PARA CONFIRMAR no BR):
--   • 100% da gorjeta para o estafeta/motorista; sem comissão da Bora.
--   • Cartão/MB Way: cobrança SEPARADA (PaymentIntent próprio, metadata kind=tip) pela
--     Edge Function charge-tip (isolada; stripe-webhook e create-payment-intent intactos).
--   • Dinheiro: só no checkout; o cliente entrega a gorjeta em mão com o pedido.
--     Fica registada (cash_due → cash_collected na entrega) e NÃO entra no saldo
--     semanal (o estafeta já a tem na mão).
--   • Fecho semanal: compute_driver_settlement passa a somar as gorjetas online pagas
--     da semana ao que a Bora deve ao estafeta (patch por âncora, com cópia antes).
--   • Interruptor: platform_settings.tips_enabled (começa FALSE). A app esconde o
--     seletor enquanto estiver false, para não voltar a mostrar gorjeta que não cobra.
-- ============================================================================

-- ── 1. Definições ───────────────────────────────────────────────────────────
INSERT INTO public.platform_settings(key, value, category, description) VALUES
  ('tips_enabled', 'false'::jsonb, 'tips',
   'Gorjetas ligadas na app (checkout, avaliação de entrega e fim de corrida TVDE). false = seletor escondido.'),
  ('tip_max_cents', '5000'::jsonb, 'tips',
   'Gorjeta máxima por pedido/corrida, em cêntimos (5000 = 50 €). Mínimo é sempre 50 (mínimo da Stripe).')
ON CONFLICT (key) DO NOTHING;

-- ── 2. Tabela ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tips (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target                    text NOT NULL CHECK (target IN ('order', 'tvde')),
  order_id                  text REFERENCES public.orders(id),
  tvde_ride_id              uuid REFERENCES public.tvde_rides(id),
  client_user_id            uuid NOT NULL,
  provider_user_id          uuid NOT NULL,
  amount_cents              integer NOT NULL CHECK (amount_cents >= 50),
  method                    text NOT NULL CHECK (method IN ('card', 'mbway', 'cash')),
  moment                    text NOT NULL CHECK (moment IN ('checkout', 'after')),
  status                    text NOT NULL DEFAULT 'pending' CHECK (status IN
                              ('pending', 'requires_action', 'succeeded', 'failed',
                               'refunded', 'cash_due', 'cash_collected', 'cancelled')),
  stripe_payment_intent_id  text,
  stripe_fee_cents          integer,
  failure_reason            text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  paid_at                   timestamptz,
  refunded_at               timestamptz,
  refunded_by               uuid,
  refund_reason             text,
  CHECK ((target = 'order' AND order_id IS NOT NULL AND tvde_ride_id IS NULL)
      OR (target = 'tvde'  AND tvde_ride_id IS NOT NULL AND order_id IS NULL)),
  CHECK (method <> 'cash' OR moment = 'checkout')
);

-- Uma gorjeta viva por pedido/corrida (falhada/cancelada não conta: pode tentar outra vez).
CREATE UNIQUE INDEX IF NOT EXISTS tips_uma_viva_por_pedido
  ON public.tips(order_id) WHERE order_id IS NOT NULL AND status NOT IN ('failed', 'cancelled');
CREATE UNIQUE INDEX IF NOT EXISTS tips_uma_viva_por_corrida
  ON public.tips(tvde_ride_id) WHERE tvde_ride_id IS NOT NULL AND status NOT IN ('failed', 'cancelled');
CREATE INDEX IF NOT EXISTS tips_prestador_pago ON public.tips(provider_user_id, paid_at);
CREATE UNIQUE INDEX IF NOT EXISTS tips_pi_unico ON public.tips(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

ALTER TABLE public.tips ENABLE ROW LEVEL SECURITY;

-- Leitura: o cliente vê as suas, o prestador vê as que recebeu, o admin vê tudo.
-- Escrita: NINGUÉM pela app (só a Edge Function charge-tip com service_role e as RPCs abaixo).
DROP POLICY IF EXISTS tips_ler_proprias ON public.tips;
CREATE POLICY tips_ler_proprias ON public.tips FOR SELECT TO authenticated
  USING (client_user_id = auth.uid() OR provider_user_id = auth.uid() OR public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.tips FROM anon, authenticated;
GRANT SELECT ON public.tips TO authenticated;

-- orders.tip_amount_cents passa a ser espelho (só leitura para a app): mostra a
-- gorjeta no detalhe do pedido. Escrito só pelo gatilho abaixo.
CREATE OR REPLACE FUNCTION public.fn_tips_espelho_no_pedido()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  IF NEW.order_id IS NOT NULL THEN
    PERFORM set_config('app.financial_bypass', 'true', true);
    UPDATE public.orders
       SET tip_amount_cents = CASE WHEN NEW.status IN ('succeeded', 'cash_due', 'cash_collected')
                                   THEN NEW.amount_cents ELSE 0 END,
           tip_added_at     = CASE WHEN NEW.status IN ('succeeded', 'cash_due', 'cash_collected')
                                   THEN COALESCE(NEW.paid_at, NEW.created_at) ELSE NULL END
     WHERE id = NEW.order_id;
    PERFORM set_config('app.financial_bypass', 'false', true);
  END IF;
  RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS trg_tips_espelho_no_pedido ON public.tips;
CREATE TRIGGER trg_tips_espelho_no_pedido
  AFTER INSERT OR UPDATE OF status ON public.tips
  FOR EACH ROW EXECUTE FUNCTION public.fn_tips_espelho_no_pedido();

-- A app deixava o cliente escrever tip_amount_cents direto (UPDATE do ecrã de
-- avaliação, sem cobrar). Fecha-se: só o servidor escreve. (REVOKE por coluna não
-- serve — authenticated tem UPDATE na tabela inteira — por isso é um gatilho.)
CREATE OR REPLACE FUNCTION public.fn_orders_gorjeta_so_servidor()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $f$
BEGIN
  IF (NEW.tip_amount_cents IS DISTINCT FROM OLD.tip_amount_cents
      OR NEW.tip_added_at IS DISTINCT FROM OLD.tip_added_at)
     AND COALESCE(auth.role(), '') <> 'service_role'
     AND COALESCE(current_setting('app.financial_bypass', true), 'false') <> 'true' THEN
    RAISE EXCEPTION 'GORJETA_SO_PELO_SERVIDOR: usa a Edge Function charge-tip'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS trg_orders_gorjeta_so_servidor ON public.orders;
CREATE TRIGGER trg_orders_gorjeta_so_servidor
  BEFORE UPDATE OF tip_amount_cents, tip_added_at ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_gorjeta_so_servidor();

-- ── 3. Gorjeta em DINHEIRO no checkout ─────────────────────────────────────
-- O cliente escolheu gorjeta e paga em dinheiro: regista-se e soma-se ao que
-- entrega em mão. Respeita o limite de dinheiro (cash máx, BR) com a gorjeta.
CREATE OR REPLACE FUNCTION public.tip_registar_dinheiro(p_order_id text, p_amount_cents integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE
  o public.orders%ROWTYPE;
  v_max int := COALESCE((public.get_setting('tip_max_cents') #>> '{}')::int, 5000);
  v_on  boolean := COALESCE((public.get_setting('tips_enabled') #>> '{}')::boolean, false);
  v_cash_max numeric := COALESCE((public.get_setting('max_cash_amount_cents') #>> '{}')::numeric, 4000) / 100.0;
  v_id uuid;
BEGIN
  IF NOT v_on THEN RETURN jsonb_build_object('ok', false, 'motivo', 'gorjetas_desligadas'); END IF;
  IF p_amount_cents IS NULL OR p_amount_cents < 50 OR p_amount_cents > v_max THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'valor_invalido');
  END IF;
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR o.user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'pedido_nao_e_teu');
  END IF;
  IF o.payment_method IS DISTINCT FROM 'cash' THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nao_e_dinheiro');
  END IF;
  IF o.status IN ('delivered', 'cancelled', 'rejected') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'pedido_fechado');
  END IF;
  IF COALESCE(o.price, 0) + p_amount_cents / 100.0 > v_cash_max THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'passa_limite_dinheiro', 'limite_eur', v_cash_max);
  END IF;
  INSERT INTO public.tips(target, order_id, client_user_id, provider_user_id, amount_cents, method, moment, status)
  VALUES ('order', o.id, o.user_id,
          COALESCE(NULLIF(o.assigned_driver_id, '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid),
          p_amount_cents, 'cash', 'checkout', 'cash_due')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'tip_id', v_id);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok', false, 'motivo', 'ja_tem_gorjeta');
END $f$;
REVOKE ALL ON FUNCTION public.tip_registar_dinheiro(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tip_registar_dinheiro(text, integer) TO authenticated;

-- O estafeta só é conhecido depois: acerta o prestador e fecha/cancela a de dinheiro
-- conforme o pedido anda.
CREATE OR REPLACE FUNCTION public.fn_orders_gorjeta_acompanha()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
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
    END IF;
  END IF;
  RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS trg_orders_gorjeta_acompanha ON public.orders;
CREATE TRIGGER trg_orders_gorjeta_acompanha
  AFTER UPDATE OF status, assigned_driver_id ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_gorjeta_acompanha();

-- ── 4. Soma para o fecho semanal ───────────────────────────────────────────
-- Gorjetas ONLINE (cartão/MB Way) pagas na semana → a Bora deve ao prestador.
-- As de dinheiro ficam de fora: já estão na mão dele.
CREATE OR REPLACE FUNCTION public.gorjetas_online_do_prestador(
  p_user_id uuid, p_ini timestamptz, p_fim timestamptz)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
  SELECT COALESCE(SUM(amount_cents), 0) / 100.0
    FROM public.tips
   WHERE provider_user_id = p_user_id
     AND status = 'succeeded'
     AND method IN ('card', 'mbway')
     AND paid_at >= p_ini AND paid_at <= p_fim;
$f$;
REVOKE ALL ON FUNCTION public.gorjetas_online_do_prestador(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

-- Patch por âncora de compute_driver_settlement (backup + contagem exata = 1).
CREATE TABLE IF NOT EXISTS public.bkp_compute_driver_settlement_20261004 (
  guardado_em timestamptz DEFAULT now(), definicao text);
ALTER TABLE public.bkp_compute_driver_settlement_20261004 ENABLE ROW LEVEL SECURITY;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.compute_driver_settlement(uuid,timestamp with time zone,boolean)'::regprocedure);
  v_ancora text := 'v_total_earnings      := v_total_earnings + v_tvde_earnings;';
  v_novo text := 'v_total_earnings      := v_total_earnings + v_tvde_earnings'
              || E'\n    + public.gorjetas_online_do_prestador(p_driver_id, v_bounds.week_start, v_bounds.week_end); -- gorjetas 100% prestador (04/10)';
  v_n int;
BEGIN
  IF position('gorjetas_online_do_prestador' IN v_def) > 0 THEN
    RAISE NOTICE 'compute_driver_settlement já soma gorjetas — nada a fazer';
    RETURN;
  END IF;
  v_n := (length(v_def) - length(replace(v_def, v_ancora, ''))) / length(v_ancora);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'âncora encontrada % vezes (esperado 1) — patch abortado', v_n;
  END IF;
  INSERT INTO public.bkp_compute_driver_settlement_20261004(definicao) VALUES (v_def);
  EXECUTE replace(v_def, v_ancora, v_novo);
END $patch$;

-- ── 5. Painel admin ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_listar_gorjetas(
  p_desde timestamptz DEFAULT now() - interval '90 days',
  p_ate   timestamptz DEFAULT now())
RETURNS TABLE (
  id uuid, criada_em timestamptz, paga_em timestamptz, alvo text, pedido text, corrida uuid,
  cliente_id uuid, cliente_nome text, prestador_id uuid, prestador_nome text,
  valor_cents integer, metodo text, momento text, estado text,
  stripe_pi text, taxa_stripe_cents integer, reembolsada_em timestamptz, motivo_reembolso text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT t.id, t.created_at, t.paid_at, t.target, t.order_id, t.tvde_ride_id,
         t.client_user_id, COALESCE(uc.name, uc.email, ''),
         t.provider_user_id, COALESCE(d.name, up.name, up.email, ''),
         t.amount_cents, t.method, t.moment, t.status,
         t.stripe_payment_intent_id, t.stripe_fee_cents, t.refunded_at, t.refund_reason
    FROM public.tips t
    LEFT JOIN public.users uc ON uc.id = t.client_user_id
    LEFT JOIN public.users up ON up.id = t.provider_user_id
    LEFT JOIN public.drivers d ON d.user_id = t.provider_user_id
   WHERE t.created_at BETWEEN p_desde AND p_ate
   ORDER BY t.created_at DESC;
END $f$;
REVOKE ALL ON FUNCTION public.admin_listar_gorjetas(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_listar_gorjetas(timestamptz, timestamptz) TO authenticated;
