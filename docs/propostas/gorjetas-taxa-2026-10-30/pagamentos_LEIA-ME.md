# Servidor das gorjetas (Blocos A, B, C) — o que está pronto e por que ordem aplicar

Missão `gorjetas-taxa-2026-10-30` · agente de pagamentos · 30/10/2026. Nada foi aplicado em produção.
⚠️ ISTO MEXE EM DINHEIRO — está tudo pronto. Autorização do Danilo: 30/10/2026 13:40.

## Ordem para pôr no ar
1. `supabase/migrations/20261030144900_gorjeta_checkout_interruptor.sql` (no repo; a tranca deixou) — chave
   `tips_checkout_junto_pagamento` = false, categoria `tips`, não secreta (como `tips_enabled`).
2. `pagamentos_20261030145000_gorjeta_checkout_junto_pagamento.sql` → copiar para
   `supabase/migrations/20261030145000_gorjeta_checkout_junto_pagamento.sql` e aplicar (antes da 20261030151000 do admin).
   Começa com `SET lock_timeout = '3s'`. Com o interruptor desligado e sem os patches, só muda: (a) gorjeta do
   carrinho sem pagamento criado morre com o pedido cancelado; (b) a conferência de 15 em 15 min pede à
   `charge-tip` que devolva gorjetas pagas (ou com pagamento criado) de pedidos cancelados — os mais antigos
   primeiro, nunca mais de 2 tentativas por gorjeta, aviso ao admin quando uma passa 2 h por devolver
   (hoje: 0 casos — ver G9); (c) cron das taxas ao domingo.
3. Edge Functions fora da zona vermelha (já editadas no repo; publicar com `_shared/cobranca_stripe.ts` v3 e
   `_shared/gorjeta_devolver.ts`): `charge-tip`, `cancel-order-with-choice`, `execute-cancellation`,
   `admin-cancel-order`, `auto-refund-order`, `payments-reconciler`.
4. Zona vermelha (diffs contra o AR, `pagamentos_<função>.md`): `create-payment-intent`, `create-mbway-payment-intent`,
   `stripe-webhook`, `client-cancel-order` (este com os dois `_shared`).
5. Prova em rollback: `supabase/tests/gorjetas_taxa_prova.sql` (sem DML em orders; G0–G9). O MB Way a passar a
   pago/falhado NÃO se prova aqui: o webhook faz isso com UPDATE direto em orders e não há função SQL que o faça
   (a tranca recusa DML em orders) — está provado no PGlite e prova-se no ar com o 1.º MB Way real com gorjeta.
   Prova local já feita: `pagamentos_prova_local_pglite.mjs` → 25/25 (`.saida.txt`); `deno test
   supabase/functions/_shared/gorjeta_test.ts` → 16/16 (Stripe e banco de brincar).
6. Só depois ligar `tips_checkout_junto_pagamento` (painel / `admin_update_setting`).

## Contrato com a app (nomes fixos)
- `client_preparar_gorjeta_checkout(p_tip_cents int) → jsonb` (só `authenticated`): `{ok:true, gorjeta_cents}`;
  `{ok:false, motivo:'junto_desligado'|'valor_invalido'}`; 0/NULL apaga. Válida 20 min.
- Cartão: o servidor copia-a para o rascunho ao criar o PaymentIntent; MB Way: ao inserir o pedido (só
  restaurant/storeShopping/takeaway). Dinheiro, só-saldo e Favores/envios NUNCA a gastam. Nunca no webhook.
- `charge-tip create` (moment checkout) responde `{ok:true, note:'already_exists'}` sem cobrar quando: o pedido já
  tem a gorjeta do carrinho (junto, paga, ou pedida com PI); OU o pedido existe e o rascunho do PI DESSE pedido
  traz a gorjeta; OU o pedido mandado ainda não existe e há um rascunho de cartão do cliente (≤30 min, por usar)
  com a gorjeta. "Tentou cartão, desistiu, pagou com saldo" → cobra à parte (provado no deno test).

## Bloco A — tudo o que compara o cobrado com o pedido (verificado no código do AR)
- `finalize-order-from-intent` v14 e `stripe-webhook` v36: NÃO comparam o valor do PI com o total — só o estado.
  `registar_cobranca_stripe` grava `amount_received` (passa a incluir a gorjeta: é o que a Stripe cobrou).
- `_shared/cobranca_stripe.ts` v3 (editado): `stripeCents`/`stripeDisponivelCents` deixam de contar a gorjeta cobrada
  junto → cancelamentos e taxas só mexem na compra (client-cancel-order, cancel-order-with-choice, execute-cancellation,
  admin-cancel-order usam-no).
- `payments-reconciler` (editado): nunca comparou valores; PI com `gorjeta_cents` sem a linha em `tips` → achado
  CRÍTICO `gorjeta_cobrada_sem_registo`; PI de gorjeta à parte não confirmada → só `info`, como antes.
- Sem mudança (a gorjeta não entra): `finalize_storeshopping_purchase` (diferença orig−final; o pago só serve de teto),
  `finalize_errand_purchase` e `fn_excedente_preautorizacao` (buffer, que não tem a gorjeta), `finalizar_talao_nao_parceiro`
  (totais do pedido), `order-edit-settle`/`_order_edit_apply` (só a diferença), `charge-extra` (valor dado),
  `refund` (valor dado pela app = diferença da compra, teto = cobrado), `reprocess-refund` v4 (refund_amount, teto =
  disponível na Stripe), `_fecho_pedidos` (pago = final_total). `_enforce_refund_cap` fica com a gorjeta no teto (o
  reembolso total do `auto-refund-order` devolve-a junto). `compute_refund_split`: ninguém a chama.
- `fn_reembolso_cancelado_pelo_sistema` usa `stripe_charge_cents` (com a gorjeta) → o `auto-refund-order` devolve o PI
  todo, gorjeta incluída: depois de a Stripe confirmar, a gorjeta junto só fica marcada 'refunded'
  (`marcarGorjetaJuntoNoReembolsoTotal`, explícito — sem adivinhar pelo disponível).
- Mode A (legacy `order_id`+`amount`) do `create-payment-intent`: o único chamador na app é `PaymentService.payWithCard`
  com ids `direct-…`, que o Mode A do ar recusa (404) — na prática não é usado. Sem gorjeta lá.

## Bloco B — cancelamentos
- Mapa: `client-cancel-order` (cliente, `refund_target` card|wallet), `cancel-order-with-choice` (cliente,
  `refund_method` stripe|wallet), `execute-cancellation` (admin aprova pedido, stripe|wallet|none),
  `admin-cancel-order` (admin, tudo ao meio original), `auto-refund-order` (sistema, tudo ao meio original, chamado por
  `fn_reembolso_cancelado_pelo_sistema`), `refund`/`reprocess-refund` (genéricos). Todos agora devolvem a gorjeta
  INTEIRA, fora da taxa, pelo mesmo caminho (saldo se o cliente escolheu saldo; senão cartão/MB Way); a rede de
  segurança `gorjetas_devolver_cancelados()` apanha o que escapar (ex.: rejeições pelo parceiro, falhas).
- MB Way cancelado entre o pagamento e o webhook: o gatilho só cancela gorjetas SEM pagamento criado; com PI, a
  charge-tip pergunta à Stripe — pago → marca paga e devolve inteira (uma vez); à espera → fica; falhou → cancelada.
- Nunca em dobro: reserva antes; antes de reembolsar procura na Stripe um reembolso desse PI com
  `metadata.tip_id`; valor sempre = gorjeta inteira (disponível menor → erro + aviso ao admin, nunca meia gorjeta);
  `tips.devolucao_tentativas` (2 → pára, aviso ao admin uma só vez).
- Acerto semanal: proposta separada `pagamentos_acerto_por_entrega.md` (gorjeta de pedido conta na semana da
  entrega). Não aplicada nem mudada no repo — decide a Claude.ai.
- Dados antigos (SELECT 30/10): há 2 gorjetas — dinheiro 1,00 € já 'cancelled' (pedido bd26d6e0) e TVDE MB Way
  2,00 € 'succeeded' (corrida b36ecbb4, entregue). Nenhuma gorjeta paga em pedido cancelado: nada a devolver.

## Bloco C — taxa da Stripe
- `charge-tip` (editado) e `stripe-webhook` (patch): gorjeta já 'succeeded' sem taxa → grava só a taxa.
- `charge-tip` ação `taxas_em_falta` (só servidor) + cron `gorjetas-taxas-em-falta-domingo` (domingo 22:00 e 23:00
  UTC; o fecho, job 26, corre segunda 00:05 UTC) → regista no e2e_log (`gorjetas-taxa-2026-10-30 / taxas_em_falta`).
