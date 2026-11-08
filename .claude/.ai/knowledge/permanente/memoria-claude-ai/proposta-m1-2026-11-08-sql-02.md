---
id: memoria-claude-ai-proposta-m1-2026-11-08-sql-02
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 08/11 — SQL 02 aprovação com tecto + finalize remendado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-sql-02`, origem `claude-code`, atualizada em 2026-11-08T20:59:30.92096+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 sql 02 · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08 (Claude Code do PC, 08/11/2026). Ficheiro: docs/propostas/m1-dinheiro-favores-2026-11-08/02_favor_aprovacao_com_tecto.sql. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio) — o ramo ai/2026-11-08-m1-dinheiro-favores está só no PC.

```sql
-- ============================================================================
-- Missão m1-dinheiro-favores-2026-11-08 — Bloco 2 (aplicar DEPOIS do 01; nome final:
-- 20261108210100_m1_favor_aprovacao_com_tecto)
-- Fluxo da diferença do Favor, padrão dos grandes (conselho 08/11, decidido pela Claude.ai):
--   * o estafeta vê o TECTO antes de ir à loja; acima dele pede aprovação com valor e foto;
--   * o cliente tem 3 min (errand_approval_timeout_seconds) com toque persistente para
--     Aprovar / Comprar só até X / Cancelar;
--   * sem resposta o estafeta escolhe "Comprar só até X €" ou "Cancelar Favor" (taxa de
--     deslocação errand_cancel_no_answer_fee_cents no pedido de cancelamento);
--   * MB Way: aprovado → pedido MB Way da diferença; o estafeta só compra acima do tecto
--     depois de favor_diferencas.estado='pago';
--   * dinheiro: tecto = estimativa × errand_cash_ceiling_multiplier; o estafeta nunca paga do
--     bolso acima do tecto;
--   * painel: lista de Favores à espera + "Aprovar pelo cliente" com motivo (admin_audit_log).
-- REUTILIZA (não duplica): errand_budget_status/errand_budget_requested_cents (o finalize já os
-- usa para o consentimento e o charge-extra do cartão), errand_buffer_multiplier (=1.2, o que o
-- cliente já pagou à partida no cartão/MB Way — o tecto do cartão é ESSE valor, não uma 2.ª
-- setting), favor_diferencas/_favor_diferenca_pedir (bloco 1), cancellation_requests.fee_cents.
-- Não muda preços, taxas nem a pré-autorização existente.
-- ============================================================================

-- 1) Definições novas (editáveis no painel /admin/settings) -----------------------------------
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('errand_cash_ceiling_multiplier', '1.15'::jsonb,
   'Favores pagos em dinheiro: tecto da compra = estimativa × este valor (1.15 = até 15% acima da estimativa; acima disso o estafeta só compra com o "Aprovo" do cliente na app)', 'favores'),
  ('errand_approval_timeout_seconds', '180'::jsonb,
   'Favores: segundos que o cliente tem para aprovar um preço acima do tecto (180 = 3 minutos; depois o estafeta pode comprar só até ao tecto ou cancelar)', 'favores'),
  ('errand_cancel_no_answer_fee_cents', '300'::jsonb,
   'Favores: taxa de deslocação em cêntimos quando o estafeta cancela porque o cliente não respondeu à aprovação (300 = 3,00 €; vai no pedido de cancelamento)', 'favores')
ON CONFLICT (key) DO NOTHING;

-- 2) Registo de cada pedido de aprovação --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.favor_aprovacoes (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id      text NOT NULL,
  user_id        uuid NOT NULL,
  driver_uid     uuid,
  teto_cents     integer NOT NULL,
  pedido_cents   integer NOT NULL CHECK (pedido_cents > 0),
  foto_url       text,
  expira_em      timestamptz NOT NULL,
  estado         text NOT NULL DEFAULT 'pendente'
                 CHECK (estado IN ('pendente','aprovado','so_ate_teto','cancelar','substituido')),
  respondido_por text,
  motivo         text,
  taxa_cents     integer,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  respondido_em  timestamptz
);
CREATE INDEX IF NOT EXISTS favor_aprovacoes_pedido ON public.favor_aprovacoes (pedido_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS favor_aprovacoes_pendentes ON public.favor_aprovacoes (expira_em) WHERE estado = 'pendente';
ALTER TABLE public.favor_aprovacoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.favor_aprovacoes FROM anon;
GRANT SELECT ON public.favor_aprovacoes TO authenticated;
DROP POLICY IF EXISTS favor_aprovacoes_ler ON public.favor_aprovacoes;
CREATE POLICY favor_aprovacoes_ler ON public.favor_aprovacoes FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR driver_uid = auth.uid() OR public.is_admin());

-- 3) Tecto da compra (função pura, provada no PGlite) ------------------------------------------
-- cartão/MB Way: o que o cliente já pagou para a compra = payment_buffer_total − taxas do Favor.
-- dinheiro (ou sem pré-pagamento): estimativa × multiplicador. Aprovado acima → sobe ao aprovado.
CREATE OR REPLACE FUNCTION public._favor_teto_calc(
  p_metodo text, p_buffer_cents integer, p_taxas_cents integer, p_estimado_cents integer,
  p_mult_dinheiro numeric, p_aprovado_cents integer)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT GREATEST(
    CASE WHEN p_metodo = 'cash' OR p_buffer_cents IS NULL
         THEN ROUND(COALESCE(p_estimado_cents, 0) * COALESCE(p_mult_dinheiro, 1.15))::int
         ELSE GREATEST(0, p_buffer_cents - COALESCE(p_taxas_cents, 0)) END,
    COALESCE(p_aprovado_cents, 0))
$$;

-- Lê o estado do pedido de aprovação + tecto. Cliente dono, estafeta atribuído ou admin.
CREATE OR REPLACE FUNCTION public.errand_teto_compra(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid      uuid := auth.uid();
  o          record;
  v_mult     numeric;
  v_timeout  integer;
  v_taxa     integer;
  v_dif      text;
  v_devida   integer;
  v_aprovado integer;
  v_espera   boolean := false;
  v_base     integer;
  v_ap       public.favor_aprovacoes;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, service_type, status, payment_method,
         payment_buffer_total, delivery_fee, errand_estimated_purchase_cents, errand_budget_status,
         errand_budget_requested_cents, errand_has_purchase, is_purchase_finalized
    INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR o.service_type IS DISTINCT FROM 'errand' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  IF NOT COALESCE((o.user_id = v_uid OR public.is_admin()
          OR o.assigned_driver_id = v_uid::text OR o.current_driver_offer_id = v_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid)), false) THEN  -- NULL nunca deixa passar
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT COALESCE((SELECT (value #>> '{}')::numeric FROM public.platform_settings WHERE key = 'errand_cash_ceiling_multiplier'), 1.15) INTO v_mult;
  SELECT COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'errand_approval_timeout_seconds'), 180) INTO v_timeout;
  SELECT COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'errand_cancel_no_answer_fee_cents'), 300) INTO v_taxa;
  SELECT f.estado INTO v_dif FROM public.favor_diferencas f WHERE f.pedido_id = o.id ORDER BY f.criado_em DESC LIMIT 1;

  IF o.errand_budget_status = 'approved' AND COALESCE(o.errand_budget_requested_cents, 0) > 0 THEN
    v_devida := public._favor_diferenca_devida(o.id);
    IF o.payment_method = 'mbway' AND v_devida >= 50 AND COALESCE(v_dif, '') <> 'pago' THEN
      v_espera := true;           -- aprovado, mas o MB Way da diferença ainda não está pago
    ELSE
      v_aprovado := o.errand_budget_requested_cents;
    END IF;
  END IF;

  v_base := public._favor_teto_calc(o.payment_method,
              CASE WHEN o.payment_buffer_total IS NULL THEN NULL ELSE ROUND(o.payment_buffer_total * 100)::int END,
              ROUND(COALESCE(o.delivery_fee, 0) * 100)::int, o.errand_estimated_purchase_cents, v_mult, NULL);
  SELECT * INTO v_ap FROM public.favor_aprovacoes a WHERE a.pedido_id = o.id ORDER BY a.criado_em DESC LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'metodo', o.payment_method,
    'tem_compra', COALESCE(o.errand_has_purchase, false),
    'compra_fechada', COALESCE(o.is_purchase_finalized, false),
    'estimado_cents', o.errand_estimated_purchase_cents,
    'teto_base_cents', v_base,
    'teto_cents', GREATEST(v_base, COALESCE(v_aprovado, 0)),
    'aprovado_cents', v_aprovado,
    'budget_status', o.errand_budget_status,
    'pedido_cents', o.errand_budget_requested_cents,
    'espera_pagamento_mbway', v_espera,
    'mbway_diferenca_estado', v_dif,
    'timeout_segundos', v_timeout,
    'taxa_cancelar_sem_resposta_cents', v_taxa,
    'aprovacao', CASE WHEN v_ap.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_ap.id, 'estado', v_ap.estado, 'pedido_cents', v_ap.pedido_cents,
        'teto_cents', v_ap.teto_cents, 'foto_url', v_ap.foto_url, 'expira_em', v_ap.expira_em,
        'segundos_restantes', GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_ap.expira_em - now()))))::int,
        'respondido_por', v_ap.respondido_por, 'taxa_cents', v_ap.taxa_cents) END);
END $$;
REVOKE ALL ON FUNCTION public.errand_teto_compra(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.errand_teto_compra(text) TO authenticated;

-- Aviso ao estafeta (push + sininho). Interno.
CREATE OR REPLACE FUNCTION public._favor_avisar_estafeta(p_order_id text, p_titulo text, p_corpo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net' AS $$
DECLARE v_drv_txt text; v_drv uuid; v_url text; v_key text;
BEGIN
  SELECT assigned_driver_id INTO v_drv_txt FROM public.orders WHERE id = p_order_id;
  SELECT d.user_id INTO v_drv FROM public.drivers d
   WHERE d.user_id::text = v_drv_txt OR d.id::text = v_drv_txt LIMIT 1;
  IF v_drv IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(v_drv, 'errand_budget_answer', p_titulo, p_corpo, p_order_id);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'sininho estafeta: %', SQLERRM; END;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/notify-driver',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('driverId', v_drv_txt, 'orderId', p_order_id, 'title', p_titulo, 'body', p_corpo));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-driver: %', SQLERRM; END;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._favor_avisar_estafeta(text, text, text) FROM PUBLIC, anon, authenticated;

-- Aviso ao cliente (push normal ou com toque persistente + sininho). Interno.
CREATE OR REPLACE FUNCTION public._favor_avisar_cliente(p_order_id text, p_titulo text, p_corpo text, p_tocar_segundos integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net' AS $$
DECLARE v_user uuid; v_url text; v_key text;
BEGIN
  SELECT user_id INTO v_user FROM public.orders WHERE id = p_order_id;
  IF v_user IS NULL THEN RETURN; END IF;
  BEGIN
    PERFORM public._push_in_app_notification(v_user, 'errand_budget_request', p_titulo, p_corpo, p_order_id);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'sininho cliente: %', SQLERRM; END;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('clientId', v_user, 'orderId', p_order_id, 'status', 'errand_budget_request',
                                   'type', 'errand_budget_request', 'title', p_titulo, 'body', p_corpo,
                                   'ring', COALESCE(p_tocar_segundos, 0) > 0,
                                   'ring_seconds', COALESCE(p_tocar_segundos, 0)));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-client: %', SQLERRM; END;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._favor_avisar_cliente(text, text, text, integer) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._eur(p_cents integer)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT replace(to_char(COALESCE(p_cents, 0) / 100.0, 'FM999990.00'), '.', ',') || ' €'
$$;

-- 4) Estafeta: "O preço é maior" (valor + foto da etiqueta) -------------------------------------
CREATE OR REPLACE FUNCTION public.estafeta_favor_pedir_aprovacao(
  p_order_id text, p_novo_total_cents integer, p_foto_url text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid     uuid := auth.uid();
  o         record;
  v_teto    jsonb;
  v_tc      integer;
  v_timeout integer;
  v_ap      public.favor_aprovacoes;
  v_exp     timestamptz;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF p_novo_total_cents IS NULL OR p_novo_total_cents <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'valor_invalido');
  END IF;
  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, service_type, status, errand_has_purchase,
         is_purchase_finalized
    INTO o FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR o.service_type IS DISTINCT FROM 'errand' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  IF NOT COALESCE((o.assigned_driver_id = v_uid::text OR o.current_driver_offer_id = v_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid)), false) THEN  -- NULL nunca deixa passar
    RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido');
  END IF;
  IF o.status IN ('delivered', 'cancelled', 'rejected') THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_fechado'); END IF;
  IF NOT COALESCE(o.errand_has_purchase, false) THEN RETURN jsonb_build_object('ok', false, 'error', 'favor_sem_compra'); END IF;
  IF COALESCE(o.is_purchase_finalized, false) THEN RETURN jsonb_build_object('ok', false, 'error', 'compra_ja_fechada'); END IF;

  v_teto := public.errand_teto_compra(p_order_id);
  v_tc := (v_teto->>'teto_cents')::int;
  IF p_novo_total_cents <= v_tc THEN
    RETURN jsonb_build_object('ok', true, 'dentro_do_teto', true, 'teto_cents', v_tc);
  END IF;

  SELECT * INTO v_ap FROM public.favor_aprovacoes
   WHERE pedido_id = p_order_id AND estado = 'pendente' ORDER BY criado_em DESC LIMIT 1 FOR UPDATE;
  IF v_ap.id IS NOT NULL AND v_ap.expira_em > now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_em_curso', 'expira_em', v_ap.expira_em,
      'segundos_restantes', GREATEST(0, CEIL(EXTRACT(EPOCH FROM (v_ap.expira_em - now()))))::int);
  END IF;
  UPDATE public.favor_aprovacoes SET estado = 'substituido', respondido_em = now()
   WHERE pedido_id = p_order_id AND estado = 'pendente';

  v_timeout := (v_teto->>'timeout_segundos')::int;
  v_exp := now() + make_interval(secs => v_timeout);
  -- Mesmo estado que o errand_request_budget_increase grava (o finalize lê-o para o consentimento).
  UPDATE public.orders SET errand_budget_status = 'pending', errand_budget_requested_cents = p_novo_total_cents
   WHERE id = p_order_id;
  INSERT INTO public.favor_aprovacoes (pedido_id, user_id, driver_uid, teto_cents, pedido_cents, foto_url, expira_em)
  VALUES (p_order_id, o.user_id, v_uid, v_tc, p_novo_total_cents, NULLIF(btrim(COALESCE(p_foto_url, '')), ''), v_exp)
  RETURNING * INTO v_ap;

  PERFORM public._favor_avisar_cliente(p_order_id,
    'Aprova o preço do teu Favor',
    'O estafeta está na loja: o total é ' || public._eur(p_novo_total_cents) || ' e podia comprar até '
      || public._eur(v_tc) || '. Abre a app e escolhe: aprovar, comprar só até ' || public._eur(v_tc)
      || ' ou cancelar. Tens ' || CEIL(v_timeout / 60.0)::int || ' minutos.',
    v_timeout);
  INSERT INTO public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
  VALUES ('favor_aprovacao_pedida', 'low', 'order', p_order_id,
          'Favor ' || left(p_order_id, 8) || ': o estafeta pede ' || public._eur(p_novo_total_cents)
            || ' (tecto ' || public._eur(v_tc) || '). O cliente tem ' || v_timeout || ' s.',
          jsonb_build_object('aprovacao_id', v_ap.id, 'pedido_cents', p_novo_total_cents, 'teto_cents', v_tc));
  RETURN jsonb_build_object('ok', true, 'aprovacao_id', v_ap.id, 'expira_em', v_exp, 'segundos', v_timeout,
                            'teto_cents', v_tc, 'pedido_cents', p_novo_total_cents);
END $$;
REVOKE ALL ON FUNCTION public.estafeta_favor_pedir_aprovacao(text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_favor_pedir_aprovacao(text, integer, text) TO authenticated;

-- Núcleo da resposta (cliente, admin ou estafeta sem resposta). Interno.
CREATE OR REPLACE FUNCTION public._favor_aplicar_resposta(
  p_order_id text, p_resposta text, p_quem text, p_motivo text, p_requester uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o       record;
  v_ap    public.favor_aprovacoes;
  v_taxa  integer;
  v_mb    jsonb;
  v_teto  integer;
  v_ped   integer;
  v_role  text;
BEGIN
  IF p_resposta NOT IN ('aprovar', 'so_ate_teto', 'cancelar') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'resposta_invalida');
  END IF;
  SELECT id, user_id, status, payment_method, errand_budget_status, errand_budget_requested_cents
    INTO o FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF o.status IN ('delivered', 'cancelled', 'rejected') THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_fechado'); END IF;
  IF o.errand_budget_status IS DISTINCT FROM 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sem_pedido_pendente', 'budget_status', o.errand_budget_status);
  END IF;
  SELECT * INTO v_ap FROM public.favor_aprovacoes
   WHERE pedido_id = p_order_id AND estado = 'pendente' ORDER BY criado_em DESC LIMIT 1 FOR UPDATE;
  v_teto := COALESCE(v_ap.teto_cents, 0);
  v_ped  := COALESCE(v_ap.pedido_cents, o.errand_budget_requested_cents);

  IF p_resposta = 'aprovar' THEN
    UPDATE public.orders SET errand_budget_status = 'approved' WHERE id = p_order_id AND errand_budget_status = 'pending';
    UPDATE public.favor_aprovacoes SET estado = 'aprovado', respondido_por = p_quem, motivo = p_motivo, respondido_em = now()
     WHERE id = v_ap.id;
    IF o.payment_method = 'mbway' THEN
      v_mb := public._favor_diferenca_pedir(p_order_id, p_quem || '_aprovou');
      PERFORM public._favor_avisar_estafeta(p_order_id, 'Preço aprovado: espera o MB Way',
        'O cliente aprovou ' || public._eur(v_ped) || '. Pedimos-lhe a diferença por MB Way: compra só quando a app disser que está paga.');
    ELSE
      PERFORM public._favor_avisar_estafeta(p_order_id, 'Preço aprovado',
        'O cliente aprovou ' || public._eur(v_ped) || '. Podes comprar.');
    END IF;
  ELSIF p_resposta = 'so_ate_teto' THEN
    UPDATE public.orders SET errand_budget_status = 'so_ate_teto' WHERE id = p_order_id AND errand_budget_status = 'pending';
    UPDATE public.favor_aprovacoes SET estado = 'so_ate_teto', respondido_por = p_quem, motivo = p_motivo, respondido_em = now()
     WHERE id = v_ap.id;
    IF p_quem = 'estafeta_sem_resposta' THEN
      PERFORM public._favor_avisar_cliente(p_order_id, 'O estafeta compra só até ' || public._eur(v_teto),
        'Não recebemos a tua resposta. O estafeta compra só até ' || public._eur(v_teto) || '.', 0);
    ELSE
      PERFORM public._favor_avisar_estafeta(p_order_id, 'Compra só até ' || public._eur(v_teto),
        'O cliente pediu: compra só até ' || public._eur(v_teto) || '. Não pagues mais do que isso.');
    END IF;
  ELSE -- cancelar
    SELECT COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'errand_cancel_no_answer_fee_cents'), 300)
      INTO v_taxa;
    IF p_quem <> 'estafeta_sem_resposta' THEN v_taxa := 0; END IF;  -- a taxa é só para "sem resposta"
    UPDATE public.orders SET errand_budget_status = 'rejected' WHERE id = p_order_id AND errand_budget_status = 'pending';
    UPDATE public.favor_aprovacoes SET estado = 'cancelar', respondido_por = p_quem, motivo = p_motivo,
           taxa_cents = v_taxa, respondido_em = now()
     WHERE id = v_ap.id;
    v_role := CASE WHEN p_quem = 'cliente' THEN 'client' ELSE 'driver' END;
    BEGIN
      INSERT INTO public.cancellation_requests (order_id, requester_role, requester_id, reason, status, fee_cents)
      VALUES (p_order_id, v_role, p_requester,
              CASE WHEN p_quem = 'estafeta_sem_resposta'
                   THEN 'Favor: o cliente não respondeu ao preço maior (' || public._eur(v_ped) || ') — taxa de deslocação ' || public._eur(v_taxa)
                   ELSE 'Favor: o cliente não aceitou o preço na loja (' || public._eur(v_ped) || ')' END,
              'pending', NULLIF(v_taxa, 0));
    EXCEPTION WHEN unique_violation THEN
      UPDATE public.cancellation_requests SET fee_cents = GREATEST(COALESCE(fee_cents, 0), v_taxa)
       WHERE order_id = p_order_id AND status = 'pending';
    END;
    IF p_quem = 'cliente' THEN
      PERFORM public._favor_avisar_estafeta(p_order_id, 'O cliente cancelou o Favor', 'Não compres nada. O suporte fecha o pedido.');
    ELSE
      PERFORM public._favor_avisar_cliente(p_order_id, 'O teu Favor vai ser cancelado',
        'Não recebemos a tua resposta ao preço na loja. O Favor vai ser cancelado'
          || CASE WHEN v_taxa > 0 THEN ' com a taxa de deslocação de ' || public._eur(v_taxa) ELSE '' END || '.', 0);
    END IF;
    INSERT INTO public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    VALUES ('favor_cancelar_por_preco', 'high', 'order', p_order_id,
            'Favor ' || left(p_order_id, 8) || ': cancelamento pedido (' || p_quem || '), taxa ' || public._eur(v_taxa)
              || '. Aprovar em Cancelamentos.',
            jsonb_build_object('aprovacao_id', v_ap.id, 'taxa_cents', v_taxa, 'quem', p_quem));
  END IF;
  RETURN jsonb_build_object('ok', true, 'resposta', p_resposta, 'teto_cents', v_teto, 'pedido_cents', v_ped,
                            'mbway', v_mb, 'taxa_cents', v_taxa);
END $$;
REVOKE ALL ON FUNCTION public._favor_aplicar_resposta(text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;

-- 5) Cliente: Aprovar / Comprar só até X / Cancelar --------------------------------------------
CREATE OR REPLACE FUNCTION public.cliente_favor_responder(p_order_id text, p_resposta text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND user_id = auth.uid() AND service_type = 'errand') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  RETURN public._favor_aplicar_resposta(p_order_id, p_resposta, 'cliente', NULL, auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.cliente_favor_responder(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cliente_favor_responder(text, text) TO authenticated;

-- 6) Estafeta: o cliente não respondeu no prazo → "Comprar só até X" ou "Cancelar Favor" ------
CREATE OR REPLACE FUNCTION public.estafeta_favor_sem_resposta(p_order_id text, p_escolha text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); o record; v_ap public.favor_aprovacoes;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF p_escolha NOT IN ('so_ate_teto', 'cancelar') THEN RETURN jsonb_build_object('ok', false, 'error', 'escolha_invalida'); END IF;
  SELECT id, assigned_driver_id, current_driver_offer_id INTO o FROM public.orders WHERE id = p_order_id AND service_type = 'errand';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF NOT COALESCE((o.assigned_driver_id = v_uid::text OR o.current_driver_offer_id = v_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid)), false) THEN  -- NULL nunca deixa passar
    RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido');
  END IF;
  SELECT * INTO v_ap FROM public.favor_aprovacoes
   WHERE pedido_id = p_order_id AND estado = 'pendente' ORDER BY criado_em DESC LIMIT 1;
  IF v_ap.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_pedido_pendente'); END IF;
  IF v_ap.expira_em > now() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ainda_a_espera',
      'segundos_restantes', CEIL(EXTRACT(EPOCH FROM (v_ap.expira_em - now())))::int);
  END IF;
  RETURN public._favor_aplicar_resposta(p_order_id, p_escolha, 'estafeta_sem_resposta', NULL, v_uid);
END $$;
REVOKE ALL ON FUNCTION public.estafeta_favor_sem_resposta(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_favor_sem_resposta(text, text) TO authenticated;

-- 7) Painel: "Aprovar pelo cliente" (o Danilo falou com ele por telefone) ----------------------
CREATE OR REPLACE FUNCTION public.admin_favor_aprovar_pelo_cliente(p_order_id text, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  IF length(btrim(COALESCE(p_motivo, ''))) < 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'motivo_obrigatorio'); END IF;
  r := public._favor_aplicar_resposta(p_order_id, 'aprovar', 'admin', btrim(p_motivo), auth.uid());
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt()->>'email', 'favor_aprovar_pelo_cliente', 'order', p_order_id,
          jsonb_build_object('motivo', btrim(p_motivo), 'resultado', r));
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.admin_favor_aprovar_pelo_cliente(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_aprovar_pelo_cliente(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_favor_aprovacoes_listar(p_so_pendentes boolean DEFAULT true, p_limite integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY x->>'criado_em' DESC)
      FROM (
        SELECT jsonb_build_object(
                 'aprovacao_id', a.id, 'pedido_id', a.pedido_id, 'estado', a.estado,
                 'pedido_cents', a.pedido_cents, 'teto_cents', a.teto_cents, 'foto_url', a.foto_url,
                 'criado_em', a.criado_em, 'expira_em', a.expira_em,
                 'segundos_restantes', GREATEST(0, CEIL(EXTRACT(EPOCH FROM (a.expira_em - now()))))::int,
                 'respondido_por', a.respondido_por, 'motivo', a.motivo, 'taxa_cents', a.taxa_cents,
                 'status_pedido', o.status, 'payment_method', o.payment_method,
                 'descricao', o.errand_description,
                 'cliente', COALESCE(u.name, u.email), 'cliente_telefone', u.phone) x
          FROM public.favor_aprovacoes a
          JOIN public.orders o ON o.id = a.pedido_id
          LEFT JOIN public.users u ON u.id = a.user_id
         WHERE (NOT p_so_pendentes OR a.estado = 'pendente')
         ORDER BY a.criado_em DESC
         LIMIT LEAST(GREATEST(p_limite, 1), 200)) s), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_favor_aprovacoes_listar(boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_aprovacoes_listar(boolean, integer) TO authenticated;

-- 8) finalize_errand_purchase — remendo mínimo (resto IGUAL ao que está no ar a 08/11, md5
--    efd5e65eb415523c032a60f66a58d2b8): a diferença MB Way já paga ANTES da compra (aprovação
--    do bloco 2) conta como pago → não se pede outra vez. Marcado "M1 08/11".
CREATE OR REPLACE FUNCTION public.finalize_errand_purchase(p_order_id text, p_driver_typed_total_cents integer, p_receipt_photo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'auth'
AS $function$
DECLARE
  v_order               RECORD;
  v_reimb_status        text;
  v_url                 text;
  v_key                 text;
  v_charge_extra_cents  integer := 0;
  v_final_total_eur     numeric;
  v_consent_ok          boolean := false;
  v_dispute             boolean := false;
  v_is_cash             boolean;
  v_devido_cents        integer := 0;   -- NOVO 03/11
  v_pago_cents          integer := 0;   -- NOVO 03/11
  v_mbway_pedido        boolean := false; -- NOVO 03/11
  v_txt                 text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;

  SELECT id, user_id, assigned_driver_id, service_type, status,
         payment_method, delivery_fee, payment_buffer_total, errand_has_purchase,
         current_driver_offer_id,
         errand_budget_status, errand_budget_requested_cents,
         wallet_applied_cents, tokens_applied_value_cents, menu_credit_applied_cents,
         stripe_charge_cents,
         extra_charge_amount, extra_charge_settled_at   -- M1 08/11
    INTO v_order FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND: %', p_order_id; END IF;
  IF v_order.service_type IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'WRONG_SERVICE_TYPE: % (expected errand)', v_order.service_type;
  END IF;
  IF v_order.status IN ('delivered','cancelled','rejected') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_TERMINAL: %', v_order.status;
  END IF;
  IF v_order.assigned_driver_id IS DISTINCT FROM auth.uid()::text
     AND v_order.current_driver_offer_id IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER';
  END IF;
  IF NOT v_order.errand_has_purchase THEN
    RAISE EXCEPTION 'ERRAND_NO_PURCHASE: cannot finalize purchase on errand without has_purchase';
  END IF;
  IF p_driver_typed_total_cents IS NULL OR p_driver_typed_total_cents <= 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL: %', p_driver_typed_total_cents;
  END IF;
  IF p_receipt_photo_url IS NULL OR length(trim(p_receipt_photo_url)) = 0 THEN
    RAISE EXCEPTION 'RECEIPT_URL_REQUIRED';
  END IF;

  v_is_cash := (v_order.payment_method = 'cash');
  v_reimb_status := CASE WHEN v_is_cash THEN 'cash_settled' ELSE 'pending_admin' END;

  INSERT INTO public.order_receipts_v2 (
    order_id, photo_url, photo_taken_at, driver_typed_total_cents,
    reimbursement_status, reimbursement_amount_cents
  ) VALUES (
    p_order_id, p_receipt_photo_url, now(), p_driver_typed_total_cents,
    v_reimb_status, p_driver_typed_total_cents
  )
  ON CONFLICT (order_id) DO UPDATE
    SET photo_url = EXCLUDED.photo_url, photo_taken_at = EXCLUDED.photo_taken_at,
        driver_typed_total_cents = EXCLUDED.driver_typed_total_cents,
        reimbursement_status = EXCLUDED.reimbursement_status,
        reimbursement_amount_cents = EXCLUDED.reimbursement_amount_cents;

  v_final_total_eur := COALESCE(v_order.delivery_fee, 0) + (p_driver_typed_total_cents / 100.0);

  IF v_order.payment_method IN ('card','stripe','mbway') AND v_order.payment_buffer_total IS NOT NULL THEN
    v_charge_extra_cents := GREATEST(0,
      ROUND((v_final_total_eur - v_order.payment_buffer_total) * 100)::int);
  END IF;

  IF v_charge_extra_cents > 0 THEN
    IF v_order.errand_budget_status = 'approved'
       AND v_order.errand_budget_requested_cents IS NOT NULL
       AND p_driver_typed_total_cents <= v_order.errand_budget_requested_cents THEN
      v_consent_ok := true;
    ELSE
      v_dispute := true;
    END IF;
  END IF;

  -- NOVO 03/11/2026: MB Way com a compra acima do que o cliente já pagou → pede-lhe a diferença
  -- por MB Way (nunca zero). Mesma conta que a Edge favor-cobrar-diferenca confere.
  -- M1 08/11: a diferença já paga (aprovação antes da compra) conta como pago; com ela acertada
  -- não se pede outra (a Edge recusa 'ja_acertado'); o resto vai para disputa no painel.
  IF v_order.payment_method = 'mbway' AND v_charge_extra_cents > 0 THEN
    v_pago_cents := COALESCE(v_order.stripe_charge_cents, 0) + COALESCE(v_order.wallet_applied_cents, 0)
                  + COALESCE(v_order.tokens_applied_value_cents, 0) + COALESCE(v_order.menu_credit_applied_cents, 0)
                  + CASE WHEN v_order.extra_charge_settled_at IS NOT NULL
                         THEN ROUND(COALESCE(v_order.extra_charge_amount, 0) * 100)::int ELSE 0 END;
    v_devido_cents := ROUND(v_final_total_eur * 100)::int - v_pago_cents;
    -- M1 08/11: nunca dois MB Way ao mesmo tempo — se o da aprovação ainda está vivo (< 5 min),
    -- não se manda outro (o cliente podia pagar os dois).
    IF v_devido_cents >= 50 AND v_order.extra_charge_settled_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.favor_diferencas f
                        WHERE f.pedido_id = p_order_id AND f.estado = 'pedido'
                          AND f.criado_em > now() - interval '5 minutes') THEN
      v_mbway_pedido := true;
    END IF;
    IF v_order.extra_charge_settled_at IS NOT NULL THEN
      v_dispute := v_devido_cents >= 50;
      v_consent_ok := false;
    END IF;
  END IF;

  PERFORM set_config('app.financial_bypass', 'true', true);

  UPDATE public.orders SET
    final_total = v_final_total_eur,
    final_purchase_value = p_driver_typed_total_cents / 100.0,
    is_purchase_finalized = true,
    errand_budget_status = CASE WHEN v_dispute THEN 'disputed' ELSE v_order.errand_budget_status END,
    subtotal       = CASE WHEN v_is_cash THEN p_driver_typed_total_cents / 100.0 ELSE subtotal END,
    price          = CASE WHEN v_is_cash THEN v_final_total_eur ELSE price END,
    cash_total_due = CASE WHEN v_is_cash THEN GREATEST(0, v_final_total_eur
                       - (COALESCE(v_order.wallet_applied_cents, 0)
                          + COALESCE(v_order.tokens_applied_value_cents, 0)
                          + COALESCE(v_order.menu_credit_applied_cents, 0)) / 100.0)
                     ELSE cash_total_due END
  WHERE id = p_order_id;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NOT NULL AND v_url <> '' AND v_key IS NOT NULL AND v_key <> '' THEN
    IF v_order.payment_method IN ('card','stripe','mbway') THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-admin-reimbursement',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id',p_order_id,'driver_id',v_order.assigned_driver_id,'amount_cents',p_driver_typed_total_cents,'dispute',v_dispute));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-admin-reimbursement (errand) failed: %', SQLERRM; END;
    END IF;
    BEGIN
      PERFORM net.http_post(url := v_url || '/functions/v1/ocr-receipt',
        headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
        body := jsonb_build_object('order_id', p_order_id));
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'ocr-receipt (errand) failed: %', SQLERRM; END;
    IF v_consent_ok AND v_charge_extra_cents > 0 AND NOT v_mbway_pedido THEN
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/charge-extra',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('order_id', p_order_id, 'amount_cents', v_charge_extra_cents, 'reason', 'errand_purchase_over_buffer'));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'charge-extra (errand) failed: %', SQLERRM; END;
    END IF;
    -- NOVO 03/11/2026: pedido MB Way da diferença + aviso ao cliente com a explicação.
    IF v_mbway_pedido THEN
      -- M1 08/11: pelo mesmo caminho do bloco 1 (regista em favor_diferencas, guarda dos 5 min,
      -- tentativa a partir de 101) em vez de chamar a Edge à parte.
      BEGIN
        PERFORM public._favor_diferenca_pedir(p_order_id, 'finalize');
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'favor-cobrar-diferenca failed: %', SQLERRM; END;
      v_txt := 'O estafeta comprou o teu pedido por ' || replace(to_char(p_driver_typed_total_cents/100.0,'FM999990.00'),'.',',') || ' €. Já pagaste '
               || replace(to_char(v_pago_cents/100.0,'FM999990.00'),'.',',') || ' €, faltam ' || replace(to_char(v_devido_cents/100.0,'FM999990.00'),'.',',')
               || ' €. Aprova o pedido MB Way que chegou ao teu telemóvel para podermos fazer a entrega.';
      BEGIN
        PERFORM net.http_post(url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Authorization','Bearer '||v_key,'Content-Type','application/json'),
          body := jsonb_build_object('clientId', v_order.user_id, 'orderId', p_order_id, 'status', 'errand_budget_request',
            'title', 'Falta pagar ' || replace(to_char(v_devido_cents/100.0,'FM999990.00'),'.',',') || ' € do teu Favor',
            'body', v_txt));
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify-client (diferenca) failed: %', SQLERRM; END;
      BEGIN
        PERFORM public._push_in_app_notification(
          p_user_id := v_order.user_id, p_kind := 'errand_budget_request',
          p_title := 'Falta pagar ' || replace(to_char(v_devido_cents/100.0,'FM999990.00'),'.',',') || ' € do teu Favor',
          p_body := v_txt, p_related_id := p_order_id);
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'in-app (diferenca) failed: %', SQLERRM; END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'service_type', 'errand',
    'final_total_eur', v_final_total_eur,
    'final_purchase_value_cents', p_driver_typed_total_cents,
    'reimbursement_status', v_reimb_status,
    'charge_extra_cents', CASE WHEN v_mbway_pedido THEN v_devido_cents WHEN v_consent_ok THEN v_charge_extra_cents ELSE 0 END,
    'mbway_diferenca_pedida', v_mbway_pedido,
    'budget_status', CASE WHEN v_dispute THEN 'disputed' WHEN v_consent_ok THEN 'approved' ELSE v_order.errand_budget_status END,
    'dispute', v_dispute,
    'payment_method', v_order.payment_method,
    'is_purchase_finalized', true
  );
END;
$function$;

```

