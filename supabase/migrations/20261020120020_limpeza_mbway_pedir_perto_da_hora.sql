-- 20/10/2026 (Claude.ai, ordem do Danilo): o pedido MB Way da limpeza tem de chegar "em tempo",
-- perto da hora da limpeza, e não logo no dia da marcação (o Divan recusava o pedido de segunda
-- para uma limpeza de sábado, e ao 4.º pedido o robô desistia — no sábado já não havia pedido).
-- Regra nova: pedido imediato só se a limpeza for dentro de 48 h; depois um pedido em cada marco
-- (24 h, 12 h, 4 h e 2 h antes), nunca entre as 22:00 e as 08:00 de Lisboa (adia para a corrida seguinte).
-- O aviso ao admin às 24 h mantém-se igual.
CREATE OR REPLACE FUNCTION public._cleaning_cron_unpaid_retry()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_pedidos int := 0;
  v_avisos  int := 0;
  v_hora_lisboa int := extract(hour from (now() at time zone 'Europe/Lisbon'))::int;
  v_silencio boolean := (v_hora_lisboa >= 22 OR v_hora_lisboa < 8);
  v_marcos int[] := ARRAY[24,12,4,2];
  v_marco int;
  v_pedir boolean;
BEGIN
  FOR r IN
    SELECT b.id, b.client_user_id, b.scheduled_at, b.total_cents,
           b.payment_requested_at, b.payment_request_count, b.unpaid_admin_alerted_at,
           u.email, pu.name AS cliente_nome
    FROM cleaning_bookings b
    LEFT JOIN auth.users u ON u.id = b.client_user_id
    LEFT JOIN public.users pu ON pu.id = b.client_user_id
    WHERE b.status = 'scheduled'
      AND b.payment_method = 'mbway'
      AND b.payment_status = 'unpaid'
      AND b.cancelled_at IS NULL
      AND b.scheduled_at > now() + interval '2 hours'
      AND NOT COALESCE(b.is_test_order, false)
  LOOP
    v_pedir := false;

    -- 1) nunca pediu e a limpeza é dentro de 48 h → pede já
    IF (r.payment_requested_at IS NULL OR COALESCE(r.payment_request_count,0) = 0)
       AND r.scheduled_at <= now() + interval '48 hours' THEN
      v_pedir := true;
    END IF;

    -- 2) marcos antes da hora: um pedido por marco já ultrapassado e ainda não coberto
    IF NOT v_pedir THEN
      FOREACH v_marco IN ARRAY v_marcos LOOP
        IF now() >= r.scheduled_at - make_interval(hours => v_marco)
           AND (r.payment_requested_at IS NULL
                OR r.payment_requested_at < r.scheduled_at - make_interval(hours => v_marco))
           AND (r.payment_requested_at IS NULL OR r.payment_requested_at < now() - interval '90 minutes') THEN
          v_pedir := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    -- 3) horas de silêncio: só não adia o último marco (2 h antes), para a limpadora poder ser chamada
    IF v_pedir AND v_silencio AND r.scheduled_at > now() + interval '4 hours' THEN
      v_pedir := false;
    END IF;

    IF v_pedir THEN
      PERFORM public.cleaning_request_payment(r.id);
      v_pedidos := v_pedidos + 1;
    END IF;

    IF r.scheduled_at < now() + interval '24 hours' AND r.unpaid_admin_alerted_at IS NULL THEN
      BEGIN
        PERFORM public.notify_admin_urgent_push(
          'cleaning_unpaid',
          '💶 LIMPEZA POR PAGAR (MB Way) · ' || COALESCE(NULLIF(r.cliente_nome, ''), r.email, 'cliente')
            || E'\n' || 'Cliente ' || COALESCE(r.email, r.client_user_id::text)
            || ' — limpeza de ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
            || ', ' || (r.total_cents / 100.0)::numeric(10,2) || ' €. Ainda não pagou; a profissional não foi chamada. '
            || 'Pedidos MB Way enviados: ' || COALESCE(r.payment_request_count,0) || '.',
          'cleaning_booking', r.id::text,
          jsonb_build_object('booking_id', r.id, 'client_user_id', r.client_user_id,
                             'email', r.email, 'scheduled_at', r.scheduled_at,
                             'total_cents', r.total_cents,
                             'payment_request_count', r.payment_request_count),
          '/admin/limpeza/' || r.id::text);
        UPDATE cleaning_bookings SET unpaid_admin_alerted_at = now() WHERE id = r.id;
        v_avisos := v_avisos + 1;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '_cleaning_cron_unpaid_retry: aviso ao admin falhou (booking=%): %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('pedidos', v_pedidos, 'avisos_admin', v_avisos);
END $function$;

INSERT INTO public.e2e_log(fluxo, passo, estado, detalhe, run_id)
VALUES ('limpeza-semanal-pagamento-19-10', 'mbway-pedir-perto-da-hora', 'ok',
 '20/10 Claude.ai por MCP: _cleaning_cron_unpaid_retry passou a pedir MB Way em marcos (24h/12h/4h/2h antes, imediato só se <48h), sem pedidos entre 22h-8h. Sábado 24/10 13:30 do Divan: pedidos previstos sex ~14:20, sáb ~08:20, ~10:20 e ~12:20.', 'claude-ai-20-10');
