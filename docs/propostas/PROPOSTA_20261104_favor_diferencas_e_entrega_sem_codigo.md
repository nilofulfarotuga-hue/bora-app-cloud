# Proposta — Favor: diferenças MB Way e entrega sem código (04/11/2026)

A bora-tranca bloqueou o apply_migration (as funções escrevem em orders). Aplicar tal como está, por MCP, e gravar em supabase/migrations com o nome favor_diferencas_e_entrega_sem_codigo.
Só cria peças novas (tabela favor_diferencas e 6 funções); não altera nenhuma função existente.

Prova depois de aplicar (rollback): favor_diferenca_resultado no pedido b72c4f2c com pago=false deve devolver estado expirou e criar a linha; com pago=true não mexe no pedido (já acertado) e põe a linha em pago; admin_marcar_entregue_sem_codigo sem motivo devolve motivo_obrigatorio.

```sql
-- Missão favor-diferenca-mbway-2026-11-03 (autorização do Danilo 03/11 13:22) e continuação
-- 04/11 14:17 ("faz tudo logo"). Sobras: estado de cada pedido MB Way da diferença, botão do
-- cliente "Pagar a diferença" (reenvia quando expirou/falhou), reenvio pelo painel, resultado
-- vindo do webhook (kind='errand_extra'), lista "Diferenças de Favor" no painel e
-- "Marcar entregue sem código" com motivo e admin_audit_log. NÃO muda preços nem taxas: o valor
-- pedido é sempre final_total − o que já foi pago (a mesma conta da Edge favor-cobrar-diferenca).

CREATE TABLE IF NOT EXISTS public.favor_diferencas (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pedido_id         text NOT NULL,
  user_id           uuid NOT NULL,
  valor_cents       integer NOT NULL CHECK (valor_cents > 0),
  tentativa         integer NOT NULL DEFAULT 1,
  payment_intent_id text,
  estado            text NOT NULL DEFAULT 'pedido'
                    CHECK (estado IN ('pedido','pago','expirou','falhou')),
  quem_pediu        text NOT NULL DEFAULT 'servidor',
  ultimo_evento     text,
  criado_em         timestamptz NOT NULL DEFAULT now(),
  atualizado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS favor_diferencas_pedido ON public.favor_diferencas (pedido_id, criado_em DESC);
CREATE UNIQUE INDEX IF NOT EXISTS favor_diferencas_pi ON public.favor_diferencas (payment_intent_id)
  WHERE payment_intent_id IS NOT NULL;

ALTER TABLE public.favor_diferencas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.favor_diferencas FROM anon;
GRANT SELECT ON public.favor_diferencas TO authenticated;
DROP POLICY IF EXISTS favor_diferencas_ler ON public.favor_diferencas;
CREATE POLICY favor_diferencas_ler ON public.favor_diferencas FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (SELECT 1 FROM public.orders o
                WHERE o.id = favor_diferencas.pedido_id
                  AND (o.assigned_driver_id = auth.uid()::text
                       OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = auth.uid())))
  );

-- Quanto falta pagar num Favor MB Way (cêntimos). Igual à Edge favor-cobrar-diferenca.
CREATE OR REPLACE FUNCTION public._favor_diferenca_devida(p_pedido text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT ROUND(COALESCE(o.final_total, 0) * 100)::int
         - (COALESCE(o.stripe_charge_cents, 0) + COALESCE(o.wallet_applied_cents, 0)
            + COALESCE(o.tokens_applied_value_cents, 0) + COALESCE(o.menu_credit_applied_cents, 0))
    FROM public.orders o WHERE o.id = p_pedido
$$;
REVOKE ALL ON FUNCTION public._favor_diferenca_devida(text) FROM PUBLIC, anon, authenticated;

-- Pede (outra vez) o MB Way da diferença. Interno: o cliente e o admin entram pelas funções de baixo.
CREATE OR REPLACE FUNCTION public._favor_diferenca_pedir(p_pedido text, p_quem text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net' AS $$
DECLARE
  o          record;
  v_devido   integer;
  v_ult      public.favor_diferencas;
  v_tent     integer;
  v_url      text;
  v_key      text;
BEGIN
  SELECT id, user_id, service_type, status, payment_method, extra_charge_settled_at
    INTO o FROM public.orders WHERE id = p_pedido FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF o.service_type <> 'errand' THEN RETURN jsonb_build_object('ok', false, 'error', 'nao_e_favor'); END IF;
  IF o.payment_method <> 'mbway' THEN RETURN jsonb_build_object('ok', false, 'error', 'nao_e_mbway'); END IF;
  IF o.status IN ('cancelled', 'rejected', 'delivered') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_fechado');
  END IF;
  IF o.extra_charge_settled_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'ja_acertado'); END IF;
  v_devido := public._favor_diferenca_devida(p_pedido);
  IF v_devido < 50 THEN RETURN jsonb_build_object('ok', false, 'error', 'nada_a_pagar', 'devido_cents', v_devido); END IF;

  SELECT * INTO v_ult FROM public.favor_diferencas WHERE pedido_id = p_pedido ORDER BY criado_em DESC LIMIT 1;
  -- O MB Way dá poucos minutos: enquanto o último pedido está vivo (< 5 min), não se manda outro.
  IF v_ult.id IS NOT NULL AND v_ult.estado = 'pedido' AND v_ult.criado_em > now() - interval '5 minutes' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_em_curso', 'tentativa', v_ult.tentativa);
  END IF;
  IF v_ult.id IS NOT NULL AND v_ult.estado = 'pago' THEN RETURN jsonb_build_object('ok', false, 'error', 'ja_pago'); END IF;
  IF v_ult.id IS NOT NULL AND v_ult.estado = 'pedido' THEN
    UPDATE public.favor_diferencas SET estado = 'expirou', ultimo_evento = 'sem_resposta_5min', atualizado_em = now()
     WHERE id = v_ult.id;
  END IF;
  -- tentativas a partir de 101: a primeira (finalize_errand_purchase) usa outra chave de idempotência
  SELECT GREATEST(100, COALESCE(MAX(tentativa), 100)) + 1 INTO v_tent FROM public.favor_diferencas WHERE pedido_id = p_pedido;

  INSERT INTO public.favor_diferencas (pedido_id, user_id, valor_cents, tentativa, quem_pediu)
  VALUES (p_pedido, o.user_id, v_devido, v_tent, p_quem);

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'servidor_sem_chave'); END IF;
  PERFORM net.http_post(url := v_url || '/functions/v1/favor-cobrar-diferenca',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object('action', 'request', 'order_id', p_pedido, 'amount_cents', v_devido, 'tentativa', v_tent),
    timeout_milliseconds := 30000);
  RETURN jsonb_build_object('ok', true, 'valor_cents', v_devido, 'tentativa', v_tent);
END $$;
REVOKE ALL ON FUNCTION public._favor_diferenca_pedir(text, text) FROM PUBLIC, anon, authenticated;

-- Cliente: botão "Pagar a diferença".
CREATE OR REPLACE FUNCTION public.cliente_favor_pagar_diferenca(p_pedido text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.orders WHERE id = p_pedido AND user_id = auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  RETURN public._favor_diferenca_pedir(p_pedido, 'cliente');
END $$;
REVOKE ALL ON FUNCTION public.cliente_favor_pagar_diferenca(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cliente_favor_pagar_diferenca(text) TO authenticated;

-- Painel: reenviar o pedido MB Way.
CREATE OR REPLACE FUNCTION public.admin_favor_diferenca_reenviar(p_pedido text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  r := public._favor_diferenca_pedir(p_pedido, 'admin');
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt()->>'email', 'favor_diferenca_reenviar', 'order', p_pedido, r);
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.admin_favor_diferenca_reenviar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_diferenca_reenviar(text) TO authenticated;

-- Resultado do MB Way (chamado SÓ pelo webhook, com a chave de servidor). Idempotente.
CREATE OR REPLACE FUNCTION public.favor_diferenca_resultado(
  p_pedido text, p_payment_intent_id text, p_valor_cents integer, p_pago boolean, p_evento text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o        record;
  v_row    public.favor_diferencas;
  v_estado text := CASE WHEN p_pago THEN 'pago'
                        WHEN p_evento = 'payment_intent.canceled' THEN 'expirou' ELSE 'falhou' END;
  v_drv    uuid;
  v_eur    text := replace(to_char(COALESCE(p_valor_cents, 0) / 100.0, 'FM999990.00'), '.', ',');
BEGIN
  SELECT id, user_id, service_type, assigned_driver_id, extra_charge_settled_at, errand_budget_status
    INTO o FROM public.orders WHERE id = p_pedido FOR UPDATE;
  IF NOT FOUND OR o.service_type <> 'errand' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;

  SELECT * INTO v_row FROM public.favor_diferencas WHERE payment_intent_id = p_payment_intent_id;
  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.favor_diferencas
     WHERE pedido_id = p_pedido AND payment_intent_id IS NULL ORDER BY criado_em DESC LIMIT 1;
  END IF;
  IF v_row.id IS NULL THEN
    INSERT INTO public.favor_diferencas (pedido_id, user_id, valor_cents, payment_intent_id, estado, ultimo_evento)
    VALUES (p_pedido, o.user_id, GREATEST(1, COALESCE(p_valor_cents, 1)), p_payment_intent_id, v_estado, p_evento)
    RETURNING * INTO v_row;
  ELSE
    IF v_row.estado = 'pago' THEN RETURN jsonb_build_object('ok', true, 'idempotente', true); END IF;
    UPDATE public.favor_diferencas
       SET estado = v_estado, payment_intent_id = p_payment_intent_id, ultimo_evento = p_evento, atualizado_em = now()
     WHERE id = v_row.id;
  END IF;

  SELECT d.user_id INTO v_drv FROM public.drivers d
   WHERE d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id LIMIT 1;

  IF p_pago THEN
    IF o.extra_charge_settled_at IS NULL THEN
      PERFORM set_config('app.financial_bypass', 'true', true);
      UPDATE public.orders
         SET extra_charge_amount = p_valor_cents / 100.0,
             extra_charge_settled_at = now(),
             extra_charge_settled_via = 'mbway_diferenca',
             errand_budget_status = CASE WHEN errand_budget_status IN ('disputed', 'pending') THEN 'approved'
                                         ELSE errand_budget_status END
       WHERE id = p_pedido;
    END IF;
    IF v_drv IS NOT NULL THEN
      BEGIN
        PERFORM public._push_in_app_notification(v_drv, 'errand_extra_pago',
          'O cliente pagou a diferença', 'Recebemos ' || v_eur || ' € por MB Way. Podes seguir com o Favor.', p_pedido);
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'aviso estafeta falhou: %', SQLERRM; END;
    END IF;
    INSERT INTO public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    VALUES ('favor_diferenca_paga', 'low', 'order', p_pedido,
            'Favor ' || left(p_pedido, 8) || ': o cliente pagou a diferença de ' || v_eur || ' € por MB Way',
            jsonb_build_object('payment_intent_id', p_payment_intent_id, 'valor_cents', p_valor_cents));
  ELSE
    BEGIN
      PERFORM public._push_in_app_notification(o.user_id, 'errand_budget_request',
        'O pedido MB Way expirou',
        'O pedido de ' || v_eur || ' € expirou ou falhou. Abre o teu Favor e carrega em "Pagar a diferença"; depois tens poucos minutos para aprovar na app MB Way.',
        p_pedido);
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'aviso cliente falhou: %', SQLERRM; END;
    IF v_drv IS NOT NULL THEN
      BEGIN
        PERFORM public._push_in_app_notification(v_drv, 'errand_extra_falhou',
          'O cliente ainda não pagou a diferença', 'O pedido MB Way de ' || v_eur || ' € expirou. Já avisámos o cliente.', p_pedido);
      EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'aviso estafeta falhou: %', SQLERRM; END;
    END IF;
    INSERT INTO public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    VALUES ('favor_diferenca_falhou', 'high', 'order', p_pedido,
            'Favor ' || left(p_pedido, 8) || ': o cliente não pagou a diferença de ' || v_eur || ' € (' || v_estado || ')',
            jsonb_build_object('payment_intent_id', p_payment_intent_id, 'evento', p_evento));
  END IF;
  RETURN jsonb_build_object('ok', true, 'estado', v_estado);
END $$;
REVOKE ALL ON FUNCTION public.favor_diferenca_resultado(text, text, integer, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.favor_diferenca_resultado(text, text, integer, boolean, text) TO service_role;

-- Painel: "Diferenças de Favor".
CREATE OR REPLACE FUNCTION public.admin_favor_diferencas_listar(p_limite integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY x->>'ultima' DESC NULLS LAST)
      FROM (
        SELECT jsonb_build_object(
                 'pedido_id', o.id, 'status', o.status, 'criado_em', o.created_at,
                 'cliente', COALESCE(u.name, u.email), 'payment_method', o.payment_method,
                 'devido_cents', public._favor_diferenca_devida(o.id),
                 'acertado_em', o.extra_charge_settled_at, 'acertado_via', o.extra_charge_settled_via,
                 'budget_status', o.errand_budget_status,
                 'tentativas', (SELECT count(*) FROM public.favor_diferencas f WHERE f.pedido_id = o.id),
                 'estado', (SELECT f.estado FROM public.favor_diferencas f WHERE f.pedido_id = o.id ORDER BY f.criado_em DESC LIMIT 1),
                 'ultima', (SELECT max(f.criado_em) FROM public.favor_diferencas f WHERE f.pedido_id = o.id)) x
          FROM public.orders o
          LEFT JOIN public.users u ON u.id = o.user_id
         WHERE o.service_type = 'errand'
           AND (EXISTS (SELECT 1 FROM public.favor_diferencas f WHERE f.pedido_id = o.id)
                OR o.errand_budget_status = 'disputed')
         ORDER BY o.created_at DESC
         LIMIT LEAST(GREATEST(p_limite, 1), 200)) s), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_favor_diferencas_listar(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_diferencas_listar(integer) TO authenticated;

-- Painel: "Marcar entregue sem código" (o estafeta esqueceu-se do PIN). Motivo obrigatório,
-- fica no admin_audit_log. Fecha pelo mesmo caminho da entrega normal (status delivered):
-- ganhos, tokens e fatura saem dos gatilhos de sempre.
CREATE OR REPLACE FUNCTION public.admin_marcar_entregue_sem_codigo(p_pedido text, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  IF length(btrim(COALESCE(p_motivo, ''))) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_obrigatorio');
  END IF;
  SELECT id, status INTO o FROM public.orders WHERE id = p_pedido FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF o.status = 'delivered' THEN RETURN jsonb_build_object('ok', true, 'ja_entregue', true); END IF;
  IF o.status <> 'onTheWay' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_invalido', 'status', o.status);
  END IF;
  PERFORM set_config('app.order_transition_source', 'admin_marcar_entregue_sem_codigo', true);
  UPDATE public.orders SET status = 'delivered', delivered_at = now() WHERE id = p_pedido AND status = 'onTheWay';
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt()->>'email', 'entregue_sem_codigo', 'order', p_pedido,
          jsonb_build_object('motivo', btrim(p_motivo), 'status_antes', o.status));
  RETURN jsonb_build_object('ok', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_marcar_entregue_sem_codigo(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_marcar_entregue_sem_codigo(text, text) TO authenticated;
```
