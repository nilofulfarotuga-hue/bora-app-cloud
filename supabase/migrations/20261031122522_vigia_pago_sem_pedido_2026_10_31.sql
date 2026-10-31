-- 31/10/2026 (Claude.ai via MCP, autorizado pelo Danilo 12:19) — VIGIA "PAGOU E FICOU SEM PEDIDO".
-- Caso Dayane: 18,41 EUR cobrados às 11:41, pedido nunca criado, ninguém avisado (só ela, pelo suporte).
-- Um rascunho de pagamento (payment_drafts) que tem PI, passou 3 minutos e continua sem order_id é
-- dinheiro cobrado (ou a cobrar) sem pedido vivo. O vigia confirma na Stripe pelo registo do webhook
-- (stripe_webhook_events payment_intent.succeeded), avisa o Danilo pelo caminho provado
-- (notify_admin_urgent_push → sininho + push + Telegram) uma vez por rascunho, e SEGURA o rascunho
-- (expires_at +2 dias) para a limpeza das :05/:20/:35/:50 não o apagar antes de alguém o recuperar.
CREATE TABLE IF NOT EXISTS public.payment_drafts_alertados (
  draft_id uuid PRIMARY KEY,
  alertado_em timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public._cron_vigia_pago_sem_pedido()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record; v_nome text; v_tel text; v_pago boolean;
BEGIN
  FOR r IN
    SELECT d.id, d.user_id, d.payment_intent_id, d.amount_cents, d.created_at, d.expires_at,
           d.payload->>'vendor_name' AS loja
      FROM public.payment_drafts d
     WHERE d.used_at IS NULL AND d.order_id IS NULL
       AND d.payment_intent_id IS NOT NULL
       AND d.created_at < now() - interval '3 minutes'
       AND d.created_at > now() - interval '3 days'
       AND NOT EXISTS (SELECT 1 FROM public.payment_drafts_alertados a WHERE a.draft_id = d.id)
       AND NOT EXISTS (SELECT 1 FROM public.orders o WHERE o.payment_intent_id = d.payment_intent_id)
  LOOP
    -- só interessa se a Stripe disse que o dinheiro entrou
    SELECT EXISTS (
      SELECT 1 FROM public.stripe_webhook_events e
       WHERE e.type = 'payment_intent.succeeded'
         AND e.event_id IS NOT NULL
         AND e.received_at >= r.created_at - interval '1 minute'
         AND e.received_at <= now()
         AND e.event_id LIKE 'evt_' || substring(r.payment_intent_id from 4 for 24) || '%'
    ) INTO v_pago;
    IF NOT v_pago THEN
      -- sem prova de cobrança ainda: deixa para a próxima volta (cliente pode ter desistido no MB Way)
      CONTINUE;
    END IF;

    BEGIN
      SELECT u.name, u.phone INTO v_nome, v_tel FROM public.users u WHERE u.id = r.user_id;
    EXCEPTION WHEN OTHERS THEN v_nome := NULL; v_tel := NULL; END;

    UPDATE public.payment_drafts SET expires_at = greatest(expires_at, now() + interval '2 days') WHERE id = r.id;
    INSERT INTO public.payment_drafts_alertados(draft_id) VALUES (r.id) ON CONFLICT DO NOTHING;

    BEGIN
      PERFORM public.notify_admin_urgent_push(
        'pago_sem_pedido',
        '🚨 PAGOU E NAO TEM PEDIDO · ' || coalesce(nullif(v_nome,''),'cliente')
          || coalesce(' (' || nullif(v_tel,'') || ')', '')
          || ' · ' || coalesce(r.loja,'?') || ' · ' || to_char(r.amount_cents/100.0,'FM999990.00') || ' EUR'
          || ' · pago ha ' || greatest(1, round(extract(epoch from (now() - r.created_at))/60))::int || ' min · rascunho ' || left(r.id::text,8),
        'payment_draft', r.id::text,
        jsonb_build_object('draft_id', r.id, 'user_id', r.user_id, 'payment_intent_id', r.payment_intent_id,
                           'amount_cents', r.amount_cents, 'client_name', v_nome, 'client_phone', v_tel),
        '/admin/orphans');
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '_cron_vigia_pago_sem_pedido aviso falhou: %', sqlerrm;
    END;

    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
    VALUES ('pago-sem-pedido', 'vigia', 'alertado',
            'rascunho ' || r.id || ' PI ' || r.payment_intent_id || ' ' || r.amount_cents || ' cents sem pedido; Danilo avisado',
            'pg_cron', 'vigia-pago-sem-pedido');
  END LOOP;
END
$function$;

SELECT cron.schedule('vigia_pago_sem_pedido', '*/5 * * * *', 'SELECT public._cron_vigia_pago_sem_pedido();');
