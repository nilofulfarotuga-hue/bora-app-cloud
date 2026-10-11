# PROPOSTA — Botão "Devolver ao meio de pagamento" (painel admin, PT-BR) — NÃO APLICADA

> Missão `chamada-grita-2026-10-10` · agente `pagamentos-wallet` (PROPOSE-ONLY) · 10/10/2026
> SQL completo: `PROPOSTA_devolver_ao_meio_de_pagamento.sql` (tabela `devolucoes_ao_meio` + 4 funções).

## 1. Para que serve

Pedido pago por MB Way ou cartão que foi parar à carteira (saldo + tokens) e tem de voltar ao meio de pagamento.
Hoje há 1 caso reversível: **Divan, d383a09e** — 6,00 € MB Way → 4,80 € saldo + 240 tokens (1,20 €), nada gasto.

## 2. Onde fica

`lib/screens/admin/admin_order_detail_screen.dart`, no cartão **"Reembolso"** (L845-870), por baixo de "Estado/Valor/Stripe Refund".
Aparece só quando: `status in (cancelled, rejected)` **e** `payment_method in (card, mbway)` **e** `refund_method = 'wallet'` (ou há saldo/tokens creditados pelo pedido).

## 3. O que o admin vê (PT-BR) — vem de `admin_devolucao_plano(order_id)` (só leitura)

> **Devolver ao meio de pagamento**
> Cobrado no MB Way: **€ 6,00** · Creditado na carteira: **€ 4,80 saldo + 240 tokens (€ 1,20)**
> Ainda não gasto: **€ 4,80 saldo + 240 tokens** · Já gasto pelo cliente: **€ 0,00**
> Vai voltar ao MB Way: **€ 6,00** e sai da carteira o mesmo valor.
> [ Cancelar ]  [ **Devolver € 6,00 ao MB Way** ]

Se o cliente já gastou parte: "O cliente já usou € X deste crédito. Só dá para devolver € Y ao MB Way; os € X gastos ficam como estão." O botão mostra € Y.
Se `pode=false`: o botão fica cinzento com o motivo (`stripe_nao_cobrou_nada`, `ja_devolvido_por_este_botao`, `abaixo_do_minimo_stripe_0_50`, …).

## 4. Que Edge faz o reembolso — e porque não reaproveitar as que existem

| Edge existente | Serve? | Porquê |
|---|---|---|
| `refund` v25 (zona protegida) | Só por dentro de outra Edge | Exige JWT `role=service_role` (o JWT do Danilo, que é `authenticated`, leva 401). Corpo `{ paymentIntentId, amount (EUROS), userId?, orderId? }`. Chave `refund-${pi}-${amountCents}` (mesmo formato que a v18 da cancel-order-with-choice → colisão em 24 h). Não grava nada na BD e devolve só `{ refundId }` (não diz se a Stripe confirmou). |
| `execute-cancellation` v15 | Não | Só aceita pedidos ainda por cancelar (created…onTheWay) com pedido em `cancellation_requests`. |
| `reprocess-refund` v3 | Não | Só pega em `refund_status='failed'` e manda MB Way para a carteira (L54). |
| `admin-cancel-order` v14 | Não | O pedido tem de estar cancelável. |

**Proposta: Edge nova e pequena `admin-devolver-ao-meio`** (verify_jwt=true), que chama a Stripe diretamente (a `STRIPE_SECRET_KEY` já está nos segredos do projeto). Não toca na `refund` protegida.

```
POST /functions/v1/admin-devolver-ao-meio   { "order_id": "d383a09e-…" }
1. getUser(JWT) + rpc('is_admin') com o JWT do admin → senão 403.
2. lerPagoDoPedido(admin, STRIPE_KEY, order_id)  → stripeDisponivelCents (cobrado − já devolvido, lido na Stripe).
3. rpc('admin_devolucao_iniciar', { p_order_id, p_admin_id, p_admin_email, p_stripe_disponivel_cents })
      → { devolucao_id, a_devolver_cents, idempotency_key: 'admin-devolver-meio-<devolucao_id>' }
      (2.º clique devolve a MESMA devolução → mesma chave → a Stripe devolve o MESMO reembolso)
4. stripe.refunds.create(
      { payment_intent, amount: a_devolver_cents,
        metadata: { order_id, devolucao_id, kind: 'admin_devolver_meio' } },
      { idempotencyKey: 'admin-devolver-meio-<devolucao_id>' })
5. refund.status === 'succeeded' → rpc('admin_devolucao_confirmar', { p_devolucao_id, p_stripe_refund_id: refund.id,
                                                                     p_devolvido_cents: refund.amount, p_stripe_estado: 'succeeded' })
   refund.status === 'pending'   → rpc('admin_devolucao_marcar', { estado: 'aguarda_stripe', … })
                                   (o stripe-webhook, ao receber refund.updated succeeded com metadata.devolucao_id,
                                    chama o admin_devolucao_confirmar — ver PROPOSTA_cancel-order-with-choice.md §6)
   'failed' / 'canceled' / erro  → rpc('admin_devolucao_marcar', { estado: 'falhou', erro }) → NADA sai da carteira.
6. notify-client (push) com o mesmo texto da notificação in-app.
7. Responde { ok, estado, devolvido_cents, saldo_retirado_cents, tokens_revogados, saldo_depois_cents }.
```

Alternativa se o Danilo preferir reaproveitar a `refund`: no passo 4, `admin.functions.invoke('refund', { body: { paymentIntentId: pi, amount: a_devolver_cents / 100 } })` (sem `userId`, para não mandar o "Reembolso processado" genérico) com a service key — mas aí a chave é `refund-<pi>-<cents>` e é preciso um `stripe.refunds.retrieve(refundId)` a seguir para saber o `status`.

## 5. A função SQL atómica e idempotente — `admin_devolucao_confirmar`

- Só corre com `p_stripe_estado = 'succeeded'` (senão erro `so_confirma_com_stripe_succeeded`).
- Tranca a devolução (`FOR UPDATE`) e a carteira do cliente; se já está `confirmada` → `already_applied=true` e não mexe em nada.
- Retira **o que esse pedido creditou**, nesta ordem: **tokens livres** criados pelo reembolso do pedido (`bora_tokens.source_order_id = pedido`, com linha `refund_credit_tokens` do mesmo pedido → nunca tokens ganhos numa entrega) e depois **saldo** (`wallet_transactions` kind `adjustment`, valor negativo, chave `devolver_meio_saldo_<pedido>`). Nunca retira mais do que o pedido creditou (`devolvido_acima_do_creditado` → erro).
- Marca os tokens revogados no histórico (`refund_credit_tokens` negativo, chave `devolver_meio_tokens_<pedido>`; esse kind não conta para o saldo).
- Pedido: `refund_method='stripe'`, `refund_id`, `refund_status='refunded'`, `refunded_at`, `refund_amount`, `payment_status='refunded'` (ou `partial_refund`). O gatilho `_enforce_refund_cap` continua a proteger (devolvido ≤ pago).
- Auditoria: `admin_audit_log` (`action='devolver_ao_meio_de_pagamento'`, `entity_id_text=<pedido>`, detalhes com o plano). Notificação in-app ao cliente.
- Divan, conta exata: devolvido 600 c → revoga 240 tokens (120 c) → retira 480 c de saldo → saldo passa de 1031 c para **551 c** (os 5,51 € do dcc8c509, que são outra decisão).

## 6. E se o cliente já gastou parte?

- **No plano** (antes de carregar): só se devolve ao MB Way o que ainda não foi gasto — `a_devolver = mín( cobrado na Stripe , saldo ainda por gastar deste pedido + valor dos tokens ainda livres )`. O que foi gasto fica como está (o cliente já recebeu esse valor em compras). Se sobrar menos de 0,50 € (mínimo da Stripe), o botão fica desligado.
- **Corrida** (gasta entre o plano e a confirmação da Stripe, segundos ou horas se o reembolso ficar `pending`): a confirmação retira na mesma o valor devolvido; o saldo fica negativo nessa diferença (a carteira aceita até −40 €), e o admin recebe aviso `devolucao_saldo_negativo`. O Danilo escolhe perdoar (`forgive`, já existe) ou deixar como dívida para o próximo pedido.
- Para pedidos já todos gastos (bba0f503, 6c102c39) o plano dá `a_devolver = 0` e o botão não aparece ativo.

## 7. Paridade admin (PT-BR)

- Ficha do pedido: botão + linha "Devolvido ao meio de pagamento em DD/MM por <admin> — € X (Stripe re_…)".
- Página Carteiras (`/admin/wallets`): as linhas novas aparecem no extrato do cliente com o motivo escrito.
- Página Cancelamentos (`/admin/cancellations`): filtro "Na carteira por pedido pago" = pedidos `refund_method='wallet'` com `payment_method in (card,mbway)` e sem `refund_choices` (= sem consentimento). Hoje: d383a09e e bba0f503.
- Consentimentos: ver a escolha do cliente (`refund_choices`) na ficha do pedido.

## 8. Prova (depois do "vai")

Em transação desfeita (ver §G do .sql): plano 600/480/240/0 → iniciar (2× = mesma devolução) → confirmar com 'pending' = erro → confirmar com 'succeeded' = 240 tokens + 480 c retirados, saldo 551 c → 2.ª confirmação = already_applied → rollback e confirmar que o saldo do Divan continua 1031 c.
Depois do deploy, primeiro uso real = o pedido do Divan, com o Danilo a ver: prova = `refunds.create` devolve `re_…`, `orders.refund_id` preenchido, `client_wallets.free_balance_cents` = 551, token `26074f4b…` `is_used=true`, e o Divan recebe o dinheiro no MB Way.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
