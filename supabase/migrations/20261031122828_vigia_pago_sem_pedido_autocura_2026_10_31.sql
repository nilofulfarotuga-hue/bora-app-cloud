-- 31/10/2026 — o vigia passa a CURAR: ao apanhar pagamento confirmado sem pedido, chama
-- finalize-order-from-intent (idempotente, v15) para criar o pedido; se 5 minutos depois
-- continuar sem pedido, aí avisa o Danilo (sininho + push + Telegram). Regra do Danilo:
-- dinheiro que entrou tem de virar pedido vivo, e o que puder ser automático é automático.
ALTER TABLE public.payment_drafts_alertados
  ADD COLUMN IF NOT EXISTS tentativa_em timestamptz,
  ADD COLUMN IF NOT EXISTS avisado_em timestamptz;

CREATE OR REPLACE FUNCTION public._cron_vigia_pago_sem_pedido()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record; v_nome text; v_tel text; v_pago boolean; v_url text; v_key text; v_ja record;
BEGIN
  v_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1);
  v_key := nullif(public._service_role_key(), '');

  FOR r IN
    SELECT d.id, d.user_id, d.payment_intent_id, d.amount_cents, d.created_at, d.expires_at,
           d.payload->>'vendor_name' AS loja
      FROM public.payment_drafts d
     WHERE d.used_at IS NULL AND d.order_id IS NULL
       AND d.payment_intent_id IS NOT NULL
       AND d.created_at < now() - interval '3 minutes'
       AND d.created_at > now() - interval '3 days'
       AND NOT EXISTS (SELECT 1 FROM public.orders o WHERE o.payment_intent_id = d.payment_intent_id)
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM public.stripe_webhook_events e
       WHERE e.type = 'payment_intent.succeeded'
         AND e.received_at >= r.created_at - interval '1 minute'
         AND e.event_id LIKE 'evt_' || substring(r.payment_intent_id from 4 for 17) || '%'
    ) INTO v_pago;
    IF NOT v_pago THEN CONTINUE; END IF;

    SELECT * INTO v_ja FROM public.payment_drafts_alertados a WHERE a.draft_id = r.id;

    -- 1.ª vez: segura o rascunho e tenta curar
    IF v_ja IS NULL THEN
      UPDATE public.payment_drafts SET expires_at = greatest(expires_at, now() + interval '2 days') WHERE id = r.id;
      INSERT INTO public.payment_drafts_alertados(draft_id, tentativa_em) VALUES (r.id, now()) ON CONFLICT DO NOTHING;
      IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/finalize-order-from-intent',
            headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
            body := jsonb_build_object('payment_intent_id', r.payment_intent_id));
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE '_cron_vigia_pago_sem_pedido cura falhou: %', sqlerrm;
        END;
      END IF;
      INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
      VALUES ('pago-sem-pedido', 'vigia', 'a_curar',
              'rascunho ' || r.id || ' PI ' || r.payment_intent_id || ' ' || r.amount_cents || ' cents pago sem pedido; finalize chamado',
              'pg_cron', 'vigia-pago-sem-pedido');
      CONTINUE;
    END IF;

    -- já tentou curar há mais de 5 min e continua sem pedido: avisar uma vez
    IF v_ja.avisado_em IS NULL AND coalesce(v_ja.tentativa_em, v_ja.alertado_em) < now() - interval '5 minutes' THEN
      BEGIN
        SELECT u.name, u.phone INTO v_nome, v_tel FROM public.users u WHERE u.id = r.user_id;
      EXCEPTION WHEN OTHERS THEN v_nome := NULL; v_tel := NULL; END;
      UPDATE public.payment_drafts_alertados SET avisado_em = now() WHERE draft_id = r.id;
      BEGIN
        PERFORM public.notify_admin_urgent_push(
          'pago_sem_pedido',
          '🚨 PAGOU E NAO TEM PEDIDO · ' || coalesce(nullif(v_nome,''),'cliente')
            || coalesce(' (' || nullif(v_tel,'') || ')', '')
            || ' · ' || coalesce(r.loja,'?') || ' · ' || to_char(r.amount_cents/100.0,'FM999990.00') || ' EUR'
            || ' · pago ha ' || greatest(1, round(extract(epoch from (now() - r.created_at))/60))::int || ' min · a cura automatica falhou · rascunho ' || left(r.id::text,8),
          'payment_draft', r.id::text,
          jsonb_build_object('draft_id', r.id, 'user_id', r.user_id, 'payment_intent_id', r.payment_intent_id,
                             'amount_cents', r.amount_cents, 'client_name', v_nome, 'client_phone', v_tel),
          '/admin/orphans');
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '_cron_vigia_pago_sem_pedido aviso falhou: %', sqlerrm;
      END;
      INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
      VALUES ('pago-sem-pedido', 'vigia', 'alertado',
              'rascunho ' || r.id || ' PI ' || r.payment_intent_id || ' continua sem pedido depois da cura; Danilo avisado',
              'pg_cron', 'vigia-pago-sem-pedido');
    END IF;
  END LOOP;
END
$function$;
