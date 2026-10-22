# Proposta — 2.ª migração da limpeza semanal (NÃO aplicada)

19/10/2026 · missão `limpeza-semanal-pagamento-19-10`. A `bora-tranca` recusou o `Write` em
`supabase/migrations/` ("migration que toca tokens/wallet/pagamentos/ledger") porque os
comentários citavam a Stripe. O SQL só mexe em `cleaning_bookings` e em funções da limpeza.
Não foi contornado. Para aplicar: ordem do Danilo → Claude.ai (MCP `apply_migration`) ou sessão
com a tranca afinada; depois guardar a cópia em `supabase/migrations/` com a versão que o MCP der.

O que faz (correções do revisor de contexto limpo à migração `20261019083907`):

1. Colunas `payment_request_pi_id` e `payment_request_last_status` (para o painel mostrar o que
   a Edge respondeu de verdade). Precisa também de a Edge `cleaning-request-payment` as escrever
   — ainda não escreve.
2. `_trg_cleaning_paid_offer`: se a chamada da limpadora rebentar depois de pago, avisa o admin.
3. `generate_recurring_bookings`: copia `is_test_order`; série de teste nunca manda MB Way real;
   série com cartão avisa o cliente de que tem de pagar na app.
4. `_cleaning_cron_unpaid_retry`: avisa o admin também das séries com cartão por pagar; pedidos
   MB Way só entre as 09:00 e as 21:00 de Lisboa; o aviso conta o pedido do próprio ciclo.

```sql
ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS payment_request_pi_id text,
  ADD COLUMN IF NOT EXISTS payment_request_last_status text;

CREATE OR REPLACE FUNCTION public._trg_cleaning_paid_offer()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_err text;
BEGIN
  IF OLD.payment_status = 'unpaid' AND NEW.payment_status = 'held'
     AND NEW.status = 'scheduled'
     AND NEW.cleaner_id IS NULL AND NEW.offer_cleaner_id IS NULL THEN
    BEGIN
      PERFORM public._cleaning_next_offer(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;
      RAISE WARNING '_trg_cleaning_paid_offer: oferta falhou (booking=%): %', NEW.id, v_err;
      BEGIN
        PERFORM public._cleaning_notify_admin(
          'Limpeza paga sem profissional',
          'Reserva ' || NEW.id::text || ' para ' ||
          to_char(NEW.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
          ' foi paga, mas a chamada da profissional falhou (' || left(v_err, 160) ||
          '). Escolha a profissional manualmente.');
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '_trg_cleaning_paid_offer: aviso ao admin falhou (booking=%): %', NEW.id, SQLERRM;
      END;
    END;
  END IF;
  RETURN NULL;
END $function$;

-- generate_recurring_bookings: igual à de 20261019083907 com 3 diferenças —
--   (a) no INSERT acrescentar a coluna is_test_order = COALESCE(v_last.is_test_order, false);
--   (b) no ramo mbway: IF NOT COALESCE(v_last.is_test_order, false) THEN
--         PERFORM public.cleaning_request_payment(v_id); END IF;
--   (c) novo ramo ELSIF v_last.payment_method = 'card' com a notificação ao cliente:
--       'A tua limpeza recorrente de <DD/MM às HH:MI> foi criada. Abre a app e conclui o
--        pagamento para confirmarmos a profissional.'

CREATE OR REPLACE FUNCTION public._cleaning_cron_unpaid_retry()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  r record; v_pedidos int := 0; v_avisos int := 0; v_n int; v_res jsonb;
  v_hora int := extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int;
  v_resumo text;
BEGIN
  FOR r IN
    SELECT b.id, b.client_user_id, b.scheduled_at, b.total_cents, b.payment_method,
           b.payment_requested_at, b.payment_request_count, b.unpaid_admin_alerted_at,
           u.email, pu.name AS cliente_nome
    FROM cleaning_bookings b
    LEFT JOIN auth.users u ON u.id = b.client_user_id
    LEFT JOIN public.users pu ON pu.id = b.client_user_id
    WHERE b.status = 'scheduled' AND b.payment_method IN ('mbway','card')
      AND b.payment_status = 'unpaid' AND b.cancelled_at IS NULL
      AND b.scheduled_at > now() + interval '2 hours'
      AND NOT COALESCE(b.is_test_order, false)
  LOOP
    v_n := r.payment_request_count;
    IF r.payment_method = 'mbway' AND v_hora BETWEEN 9 AND 20
       AND (r.payment_requested_at IS NULL OR r.payment_request_count = 0
            OR (r.payment_requested_at < now() - interval '12 hours' AND r.payment_request_count < 4)) THEN
      v_res := public.cleaning_request_payment(r.id);
      IF COALESCE((v_res ->> 'ok')::boolean, false) THEN
        v_n := COALESCE((v_res ->> 'tentativa')::int, v_n + 1);
      END IF;
      v_pedidos := v_pedidos + 1;
    END IF;
    IF r.scheduled_at < now() + interval '24 hours' AND r.unpaid_admin_alerted_at IS NULL THEN
      v_resumo := CASE WHEN r.payment_method = 'mbway'
          THEN '💶 LIMPEZA POR PAGAR (MB Way) · ' ELSE '💳 LIMPEZA POR PAGAR (cartão) · ' END
        || COALESCE(NULLIF(r.cliente_nome, ''), r.email, 'cliente')
        || E'\n' || 'Cliente ' || COALESCE(r.email, r.client_user_id::text)
        || ' — limpeza de ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI')
        || ', ' || (r.total_cents / 100.0)::numeric(10,2) || ' €. Ainda não pagou; a profissional não foi chamada. '
        || CASE WHEN r.payment_method = 'mbway' THEN 'Pedidos MB Way enviados: ' || v_n || '.'
                ELSE 'Cartão não é cobrado sozinho: o cliente tem de pagar na app.' END;
      BEGIN
        PERFORM public.notify_admin_urgent_push('cleaning_unpaid', v_resumo, 'cleaning_booking', r.id::text,
          jsonb_build_object('booking_id', r.id, 'client_user_id', r.client_user_id, 'email', r.email,
                             'scheduled_at', r.scheduled_at, 'total_cents', r.total_cents,
                             'payment_method', r.payment_method, 'payment_request_count', v_n),
          '/admin/limpeza/' || r.id::text);
        UPDATE cleaning_bookings SET unpaid_admin_alerted_at = now() WHERE id = r.id;
        v_avisos := v_avisos + 1;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '_cleaning_cron_unpaid_retry: aviso ao admin falhou (booking=%): %', r.id, SQLERRM;
      END;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('pedidos', v_pedidos, 'avisos_admin', v_avisos, 'hora_lisboa', v_hora);
END $function$;

REVOKE ALL ON FUNCTION public._cleaning_cron_unpaid_retry() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._trg_cleaning_paid_offer() FROM PUBLIC, anon, authenticated;
```

Proposta para a regra da tranca (`zonas-vermelhas.json` → `migracoes.padrao_conteudo`): tirar
os comentários SQL (`-- …` e `COMMENT ON … IS '…'`) antes de procurar as palavras, com um teste
novo em `verificar/regras.verificar.ts`. Quem aplica é o Danilo (o plugin protege-se a si próprio).
