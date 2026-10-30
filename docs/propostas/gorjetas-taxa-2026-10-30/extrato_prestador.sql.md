# Proposta — extrato do estafeta/motorista com a gorjeta líquida (Bloco D)

Missão `gorjetas-taxa-2026-10-30`, 30/10/2026. Agente da app (Bloco D).

**Porque é proposta:** a bora-tranca recusou o `Write` de
`supabase/migrations/20261030150000_gorjetas_extrato_prestador.sql` ("migration que toca
tokens/wallet/pagamentos/ledger" — a função lê `bora_tokens`, `ledger_entries` e
`driver_transactions`, como já lia). Não se contornou nem se reescreveu para passar.
**Não está aplicada em produção.** Quem a copiar para `supabase/migrations/` (Claude.ai pelo
GitHub web) usa o nome `20261030150000_gorjetas_extrato_prestador.sql` e o SQL abaixo tal e qual.

**O que muda em `public._prestador_trabalhos`** (lida por `extrato_prestador`, que é o extrato
do ecrã Ganhos e do painel "Extratos das pessoas"):

1. Entregas: a linha informativa "Gorjeta do cliente" deixa de ler o bruto
   `orders.tip_amount_cents` e passa a ler `public.tips`: o valor da linha é o que ele recebe
   (`liquido_prestador_cents`) e, quando houve taxa, o nome diz
   "Gorjeta do cliente 2,00 € · taxa do pagamento −0,28 €" (valor 1,72 €). Mesmos estados que o
   espelho `fn_tips_espelho_no_pedido` (`succeeded`, `cash_due`, `cash_collected`).
   Confirmado por SELECT a 30/10: 0 pedidos com `tip_amount_cents > 0` sem linha em `tips`.
2. Corridas TVDE: até hoje a gorjeta da corrida **não aparecia** no extrato do motorista
   (só no acerto, pela `gorjetas_online_do_prestador`). Passa a aparecer, com a mesma regra.
   Ex.: corrida b36ecbb4 (29/10) → "Gorjeta do cliente 2,00 € · taxa do pagamento −0,28 €", 1,72 €.

Tudo o resto da função fica igual à definição de produção (`pg_get_functiondef`, 30/10/2026).
Só apresentação: não mexe em acertos, saldos nem cobranças. `CREATE OR REPLACE` com o mesmo
`RETURNS TABLE`: as permissões ficam como estão (`postgres`, `service_role`).

A app não precisa de mudar para isto: o extrato já mostra `nome` e `valor_cents` de cada parcela
(`lib/widgets/extrato_prestador_section.dart`).

```sql
-- Missão gorjetas-taxa-2026-10-30 · Bloco D — o que o estafeta/motorista vê no extrato.
-- Regra do Danilo (30/10/2026): gorjeta paga DEPOIS (avaliação) com cartão/MB Way chega ao
-- prestador MENOS a taxa exata da Stripe desse pagamento (ex.: 2,00 € − 0,28 € = 1,72 €);
-- a do carrinho e a de dinheiro chegam inteiras. O líquido vem de tips.liquido_prestador_cents.

CREATE OR REPLACE FUNCTION public._prestador_trabalhos(p_uid uuid, p_de timestamp with time zone)
 RETURNS TABLE(tipo text, ref_id text, quando timestamp with time zone, descricao text, de text, para text, pagamento text, cliente_pagou_cents integer, ganhou_cents integer, parte_bora_cents integer, pagou_na_loja_cents integer, recebeu_em_mao_cents integer, fica_para_a_bora_cents integer, acerto_cents integer, distancia_km numeric, tokens integer, parcelas jsonb, entra_no_acerto boolean, nota text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT 'entrega'::text,
         o.id::text,
         COALESCE(o.delivered_at, o.status_updated_at, o.created_at),
         (CASE WHEN o.service_type IN ('storeShopping','carryGroceries','sendPackage') THEN 'Favor · ' ELSE 'Entrega · ' END)
           || COALESCE(NULLIF(o.vendor_name,''), NULLIF(o.pickup_address,''), 'Pedido'),
         COALESCE(NULLIF(o.pickup_address,''), o.vendor_name, ''),
         COALESCE(o.dropoff_address, ''),
         o.payment_method,
         ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int,
         ROUND(COALESCE(o.driver_earnings, 0) * 100)::int,
         ROUND(COALESCE(o.platform_commission, 0) * 100)::int,
         ROUND(public.order_driver_reimbursement(o.id) * 100)::int,
         CASE WHEN o.payment_method = 'cash' THEN ROUND(COALESCE(o.final_total, o.price, 0) * 100)::int ELSE 0 END,
         CASE WHEN o.payment_method = 'cash'
              THEN COALESCE(
                     (SELECT ROUND(dt.amount * 100)::int FROM public.driver_transactions dt
                       WHERE dt.order_id::text = o.id AND dt.type = 'cash_adjustment' LIMIT 1),
                     ROUND((COALESCE(o.final_total, o.price, 0) - COALESCE(o.driver_earnings, 0)
                            - public.order_driver_reimbursement(o.id)) * 100)::int)
              ELSE 0 END,
         CASE WHEN o.payment_method = 'cash'
              THEN COALESCE(
                     (SELECT ROUND(dt.amount * 100)::int FROM public.driver_transactions dt
                       WHERE dt.order_id::text = o.id AND dt.type = 'cash_adjustment' LIMIT 1),
                     ROUND((COALESCE(o.final_total, o.price, 0) - COALESCE(o.driver_earnings, 0)
                            - public.order_driver_reimbursement(o.id)) * 100)::int)
              ELSE -(ROUND(COALESCE(o.driver_earnings, 0) * 100)::int) END,
         o.distance_km,
         COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                    WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id), 0)::int,
         (SELECT jsonb_agg(p) FROM (
            SELECT jsonb_build_object('nome', 'Ganho da entrega' ||
                     CASE WHEN o.distance_km IS NOT NULL THEN ' (' || replace(ROUND(o.distance_km, 1)::text, '.', ',') || ' km)' ELSE '' END,
                     'valor_cents', ROUND(COALESCE(o.driver_earnings, 0) * 100)::int) AS p
            UNION ALL
            -- 30/10/2026: o que ele recebe da gorjeta (e a taxa, quando a houve).
            SELECT jsonb_build_object('nome', 'Gorjeta do cliente' ||
                     CASE WHEN g.valor > g.recebe
                          THEN ' ' || replace(to_char(g.valor / 100.0, 'FM999990.00'), '.', ',') || ' €'
                               || ' · taxa do pagamento −'
                               || replace(to_char((g.valor - g.recebe) / 100.0, 'FM999990.00'), '.', ',') || ' €'
                          ELSE '' END,
                     'valor_cents', g.recebe, 'informativo', true)
              FROM (SELECT SUM(tp.amount_cents)::int AS valor,
                           SUM(tp.liquido_prestador_cents)::int AS recebe
                      FROM public.tips tp
                     WHERE tp.order_id = o.id
                       AND tp.status IN ('succeeded', 'cash_due', 'cash_collected')) g
             WHERE COALESCE(g.valor, 0) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Adiantou na loja (talão)', 'valor_cents', ROUND(public.order_driver_reimbursement(o.id) * 100)::int)
             WHERE public.order_driver_reimbursement(o.id) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Tokens ganhos', 'valor_cents', NULL, 'tokens',
                     COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                                WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id), 0)::int)
             WHERE EXISTS (SELECT 1 FROM public.bora_tokens t WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = o.id)
         ) s),
         true,
         NULL::text
    FROM public.orders o
   WHERE o.assigned_driver_id = p_uid::text
     AND o.status = 'delivered'
     AND COALESCE(o.delivered_at, o.status_updated_at, o.created_at) >= p_de
     AND COALESCE(o.is_test_order, false) = false

  UNION ALL

  SELECT 'compensacao'::text,
         l.order_id::text,
         l.created_at,
         'Compensação · pedido cancelado depois de aceite' || COALESCE(' · ' || NULLIF(o.vendor_name, ''), ''),
         COALESCE(o.pickup_address, o.vendor_name, ''),
         COALESCE(o.dropoff_address, ''),
         NULL::text,
         0, ROUND(l.amount * 100)::int, 0, 0, 0, 0,
         -(ROUND(l.amount * 100)::int),
         NULL::numeric, 0,
         jsonb_build_array(jsonb_build_object('nome', 'Compensação de cancelamento', 'valor_cents', ROUND(l.amount * 100)::int)),
         false,
         'Está no livro-razão e aqui; ainda não entra no acerto semanal (achado contas-claras 20/09/2026).'
    FROM public.ledger_entries l
    LEFT JOIN public.orders o ON o.id = l.order_id::text
   WHERE l.user_type = 'driver' AND l.type = 'earning'
     AND l.user_id = p_uid::text
     AND l.created_at >= p_de
     AND (o.id IS NULL OR o.status <> 'delivered')

  UNION ALL

  SELECT 'compensacao'::text,
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

  SELECT 'corrida'::text,
         r.id::text,
         r.updated_at,
         'Corrida · ' || COALESCE(NULLIF(r.origin_label, ''), 'Origem') || ' → ' || COALESCE(NULLIF(r.dest_label, ''), 'Destino')
           || CASE WHEN r.roundtrip_credit_id IS NOT NULL THEN (CASE WHEN COALESCE(r.is_return_leg, false) THEN ' · volta do pacote' ELSE ' · ida do pacote' END)
                   WHEN COALESCE(r.used_subscription_ride, false) THEN ' · plano' ELSE '' END,
         COALESCE(r.origin_label, ''),
         COALESCE(r.dest_label, ''),
         COALESCE(r.payment_method, 'cash'),
         CASE WHEN r.roundtrip_credit_id IS NOT NULL AND NOT COALESCE(r.is_return_leg, false)
              THEN COALESCE((SELECT c.paid_cents FROM public.tvde_roundtrip_credits c WHERE c.id = r.roundtrip_credit_id), 0) + COALESCE(r.extra_stops_fee_cents, 0)
              ELSE COALESCE(r.final_fare_cents, 0) END,
         COALESCE(r.driver_earn_cents, 0),
         COALESCE(r.bora_cut_cents, 0),
         0,
         COALESCE(r.cash_in_hand_cents, (SELECT h.cash_in_hand_cents FROM public.tvde_ride_cash_in_hand(r.id) h), 0),
         GREATEST(COALESCE(r.cash_in_hand_cents, (SELECT h.cash_in_hand_cents FROM public.tvde_ride_cash_in_hand(r.id) h), 0) - COALESCE(r.driver_earn_cents, 0), 0),
         COALESCE(r.cash_in_hand_cents, (SELECT h.cash_in_hand_cents FROM public.tvde_ride_cash_in_hand(r.id) h), 0) - COALESCE(r.driver_earn_cents, 0),
         r.final_distance_km,
         COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                    WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text), 0)::int,
         (SELECT jsonb_agg(p) FROM (
            SELECT jsonb_build_object('nome', 'Ganho da corrida' ||
                     CASE WHEN r.final_distance_km IS NOT NULL THEN ' (' || replace(ROUND(r.final_distance_km, 1)::text, '.', ',') || ' km)' ELSE '' END,
                     'valor_cents', COALESCE(r.driver_earn_cents, 0) - COALESCE(r.extra_stops_driver_cents, 0)) AS p
            UNION ALL
            SELECT jsonb_build_object('nome', 'Paragens extra', 'valor_cents', r.extra_stops_driver_cents)
             WHERE COALESCE(r.extra_stops_driver_cents, 0) > 0
            UNION ALL
            -- 30/10/2026: a gorjeta da corrida passa a aparecer no extrato do motorista.
            SELECT jsonb_build_object('nome', 'Gorjeta do cliente' ||
                     CASE WHEN g.valor > g.recebe
                          THEN ' ' || replace(to_char(g.valor / 100.0, 'FM999990.00'), '.', ',') || ' €'
                               || ' · taxa do pagamento −'
                               || replace(to_char((g.valor - g.recebe) / 100.0, 'FM999990.00'), '.', ',') || ' €'
                          ELSE '' END,
                     'valor_cents', g.recebe, 'informativo', true)
              FROM (SELECT SUM(tp.amount_cents)::int AS valor,
                           SUM(tp.liquido_prestador_cents)::int AS recebe
                      FROM public.tips tp
                     WHERE tp.tvde_ride_id = r.id
                       AND tp.status IN ('succeeded', 'cash_due', 'cash_collected')) g
             WHERE COALESCE(g.valor, 0) > 0
            UNION ALL
            SELECT jsonb_build_object('nome', 'Tokens ganhos', 'valor_cents', NULL, 'tokens',
                     COALESCE((SELECT SUM(t.amount) FROM public.bora_tokens t
                                WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text), 0)::int)
             WHERE EXISTS (SELECT 1 FROM public.bora_tokens t WHERE t.user_id = p_uid AND t.role = 'driver' AND t.source_order_id = r.id::text)
         ) s),
         true,
         CASE WHEN r.fare_deduced THEN 'Corrida a dinheiro sem tarifa gravada: o valor em mão foi deduzido (ganho + parte da Bora).'
              WHEN r.roundtrip_credit_id IS NOT NULL AND COALESCE(r.is_return_leg, false) THEN 'Volta do pacote: o passageiro pagou tudo na ida; nesta perna não há dinheiro a receber.'
              ELSE NULL END
    FROM public.tvde_rides r
   WHERE (r.driver_id = p_uid OR r.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = p_uid))
     AND r.status = 'finalizada'
     AND r.updated_at >= p_de
$function$;
```

## Prova antes de aplicar (só leitura, em transação desfeita)

Correr o `CREATE OR REPLACE` acima dentro de `BEGIN; … ROLLBACK;` e, antes do `ROLLBACK`:

```sql
select parcelas from public._prestador_trabalhos(
  (select provider_user_id from public.tips where id::text like '51d1b251%'),
  '2026-10-26'::timestamptz)
 where tipo = 'corrida' and ref_id like 'b36ecbb4%';
-- esperado: uma parcela {"nome": "Gorjeta do cliente 2,00 € · taxa do pagamento −0,28 €", "valor_cents": 172, "informativo": true}
```
