---
id: memoria-claude-ai-proposta-m1-2026-11-08-sql-01
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 08/11 — SQL 01 diferenças MB Way + entregue sem código

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-sql-01`, origem `claude-code`, atualizada em 2026-11-08T20:59:30.92096+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 sql 01 · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08 (Claude Code do PC, 08/11/2026). Ficheiro: docs/propostas/m1-dinheiro-favores-2026-11-08/01_favor_diferencas_e_entrega_sem_codigo.sql. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio) — o ramo ai/2026-11-08-m1-dinheiro-favores está só no PC.

```sql
-- ============================================================================
-- Missão m1-dinheiro-favores-2026-11-08 — Blocos 1 e 3   (aplicar 1.º; nome final da migração:
-- 20261108210000_m1_favor_diferencas_e_entrega_sem_codigo)
-- Autorização do Danilo (literal, 08/11/2026 17:13, 18:59 e 19:30, via Claude.ai):
--   "Eu quero que você faça tudo, cara. Não deixa nada para depois."
--   "Eu sou o dono do aplicativo. É pra forçar e pronto. Tem que tirar essas limitações aí."
-- Base: docs/propostas/PROPOSTA_20261104_favor_diferencas_e_entrega_sem_codigo.md (nunca aplicada:
-- pg_proc confirmado a 08/11). Corrigida ao estado de 08/11:
--   * _favor_diferenca_devida passa a saber o que falta ANTES da compra (aprovação do cliente
--     com MB Way: o estafeta só compra depois de pago) e desconta a diferença já paga;
--   * "entregue sem código" aceita pickedUp e onTheWay e tem uma porta ops_ para o Claude.ai
--     e o Dipsy (só com a frase do Danilo no motivo).
-- Idempotente: CREATE ... IF NOT EXISTS / CREATE OR REPLACE. Não muda preços nem taxas.
-- O pós-entrega (ganho do estafeta, ledger, tokens, fatura) sai dos MESMOS gatilhos de
-- orders que o driver_validate_delivery_pin dispara (o PIN só faz UPDATE status='delivered').
-- ============================================================================

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

-- Quanto falta pagar num Favor MB Way (cêntimos). Fonte única: a Edge favor-cobrar-diferenca
-- chama esta função (service_role) em vez de refazer a conta.
--   * compra já fechada (is_purchase_finalized): final_total − o que já foi pago;
--   * antes da compra, com aumento aprovado: (valor aprovado + taxas do Favor) − o que já foi pago;
--   * a diferença já paga por MB Way (extra_charge_settled_at) conta como pago.
CREATE OR REPLACE FUNCTION public._favor_diferenca_devida(p_pedido text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT (CASE
            WHEN COALESCE(o.is_purchase_finalized, false) THEN ROUND(COALESCE(o.final_total, 0) * 100)::int
            WHEN o.errand_budget_status = 'approved' AND COALESCE(o.errand_budget_requested_cents, 0) > 0
              THEN o.errand_budget_requested_cents + ROUND(COALESCE(o.delivery_fee, 0) * 100)::int
            ELSE 0
          END)
         - (COALESCE(o.stripe_charge_cents, 0) + COALESCE(o.wallet_applied_cents, 0)
            + COALESCE(o.tokens_applied_value_cents, 0) + COALESCE(o.menu_credit_applied_cents, 0))
         - (CASE WHEN o.extra_charge_settled_at IS NOT NULL
                 THEN ROUND(COALESCE(o.extra_charge_amount, 0) * 100)::int ELSE 0 END)
    FROM public.orders o WHERE o.id = p_pedido
$$;
REVOKE ALL ON FUNCTION public._favor_diferenca_devida(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._favor_diferenca_devida(text) TO service_role;

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

-- ── Bloco 3: "entregue sem código" ────────────────────────────────────────────
-- Núcleo único (o painel e a porta ops_ entram aqui). Fecha pelo MESMO caminho do PIN:
-- UPDATE status='delivered' → os gatilhos de sempre (ganho, ledger, tokens, fatura, talão
-- obrigatório nas lojas não-parceiras, recibo). Motivo ≥ 5 letras no admin_audit_log.
CREATE OR REPLACE FUNCTION public._entregue_sem_codigo(
  p_pedido text, p_motivo text, p_quem text, p_admin_id uuid, p_admin_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE o record;
BEGIN
  IF length(btrim(COALESCE(p_motivo, ''))) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_obrigatorio');
  END IF;
  SELECT id, status, assigned_driver_id INTO o FROM public.orders WHERE id = p_pedido FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF o.status = 'delivered' THEN RETURN jsonb_build_object('ok', true, 'ja_entregue', true); END IF;
  IF o.status NOT IN ('pickedUp', 'onTheWay') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_invalido', 'status', o.status);
  END IF;
  IF o.assigned_driver_id IS NULL OR o.assigned_driver_id = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sem_estafeta');
  END IF;
  PERFORM set_config('app.order_transition_source', 'entregue_sem_codigo:' || p_quem, true);
  UPDATE public.orders SET status = 'delivered', delivered_at = now()
   WHERE id = p_pedido AND status IN ('pickedUp', 'onTheWay');
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (p_admin_id, p_admin_email, 'entregue_sem_codigo', 'order', p_pedido,
          jsonb_build_object('motivo', btrim(p_motivo), 'status_antes', o.status, 'quem', p_quem));
  RETURN jsonb_build_object('ok', true, 'status_antes', o.status);
END $$;
REVOKE ALL ON FUNCTION public._entregue_sem_codigo(text, text, text, uuid, text) FROM PUBLIC, anon, authenticated;

-- Painel: botão "Marcar entregue sem código" (o estafeta não tem o PIN). Só admin.
CREATE OR REPLACE FUNCTION public.admin_marcar_entregue_sem_codigo(p_pedido text, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  RETURN public._entregue_sem_codigo(p_pedido, p_motivo, 'painel', auth.uid(), auth.jwt()->>'email');
END $$;
REVOKE ALL ON FUNCTION public.admin_marcar_entregue_sem_codigo(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_marcar_entregue_sem_codigo(text, text) TO authenticated;

-- Porta para o Claude.ai e o Dipsy (MCP, chave de servidor). Só por ordem do Danilo dada na
-- conversa: o p_motivo leva a frase dele (≥ 10 letras) e fica no admin_audit_log.
CREATE OR REPLACE FUNCTION public.ops_marcar_entregue_sem_codigo(p_pedido text, p_motivo text, p_quem text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(p_quem, '') NOT IN ('claude-ai', 'claude-code', 'dipsy', 'hermes') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'quem_invalido');
  END IF;
  IF length(btrim(COALESCE(p_motivo, ''))) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_com_a_frase_do_danilo');
  END IF;
  RETURN public._entregue_sem_codigo(p_pedido, p_motivo, p_quem, NULL, 'ops:' || p_quem);
END $$;
REVOKE ALL ON FUNCTION public.ops_marcar_entregue_sem_codigo(text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_marcar_entregue_sem_codigo(text, text, text) TO service_role;
COMMENT ON FUNCTION public.ops_marcar_entregue_sem_codigo(text, text, text) IS
  'Forçar entrega sem o PIN de 4 dígitos. SÓ com ordem do Danilo dada na conversa (08/11/2026: "Eu sou o dono do aplicativo. É pra forçar e pronto."). p_motivo = a frase dele + o porquê; p_quem = claude-ai|claude-code|dipsy|hermes. Fecha pelo mesmo caminho do PIN (gatilhos de entrega). Regra em regras-operacao-agentes do livro.';
COMMENT ON FUNCTION public.admin_marcar_entregue_sem_codigo(text, text) IS
  'Painel: marcar entregue sem código (pickedUp/onTheWay), motivo ≥ 5 letras, admin_audit_log. Mesmo pós-entrega do PIN.';

```

