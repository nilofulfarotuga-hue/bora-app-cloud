# PROPOSTA — cancel-order-with-choice v18 → v19 (NÃO APLICADA)

> Missão `chamada-grita-2026-10-10` · agente `pagamentos-wallet` (PROPOSE-ONLY) · 10/10/2026
> Ficheiro completo da proposta: `PROPOSTA_cancel-order-with-choice_v19_index.ts` (mesma pasta).
> Depende do SQL `PROPOSTA_reembolso_ao_meio_de_pagamento.sql` §3, §4 e §5 (aplicar o SQL primeiro).

## 1. O que está no ar hoje (lido com `get_edge_function`, v18, 325 linhas, verify_jwt=true)

| Linhas v18 | O que faz | Problema face à regra nova |
|---|---|---|
| 51-66 | `refund_method` é **obrigatório** e vem da app (`'stripe'` ou `'wallet'`) | A Edge obedece cegamente: se a app manda `'wallet'`, dinheiro pago por MB Way/cartão vai para a carteira |
| 114-118 | taxa = `computeCancelFeeEur(tier)` | Não olha para `assigned_driver_id`. Hoje dá 0 € só porque `cancel_fee_before_dispatch_cents=0`; se a leitura do setting falhar, o `_shared/platform_settings.ts` L22 usa **1,50 €** sem estafeta |
| 186-213 | ramo `'stripe'`: `refunds.create` com chave `refund-${pi}-${cents}` | Chave igual ao formato da Edge `refund` → dois reembolsos legítimos do mesmo valor no mesmo PI em 24 h contam como um |
| 215-235 | `wallet_credit_refund_split` (80 % saldo + 20 % tokens, `wallet_split_free_pct=0.80`) | **Dinheiro pago vira tokens.** Também apanha os tokens/saldo usados e converte tokens em saldo |
| — | não há `paymentIntents.cancel` | Um MB Way ainda por aprovar não é cancelado; se o cliente aprovar depois, o webhook só grita "Reembolsar à mão" (stripe-webhook v36 L373-382) |
| 258-262 | `refund_status='pending'` no ramo Stripe | Ninguém o passa a `refunded`: o webhook só faz `console.log` em `charge.refunded` (v36 L917-923) |
| 296-297 | mensagem "€X saldo livre + N tokens" | Promete tokens por dinheiro pago |

## 2. Como o pedido do Divan (d383a09e) foi parar à carteira — linha do tempo (SELECT 10/10)

- 22:12:03 pedido Favor (errand) de 6,00 €, MB Way, PI `pi_3UOm1HGlT3R2jCYp0r4RQdwT`. A Stripe cobrou 600 c (`stripe_charge_cents=600`).
- Ainda sem estafeta (`assigned_driver_id` nulo; havia só uma oferta aberta `current_driver_offer_id=4f61dd31…`, sem aceitar).
- 22:15:15 o cliente cancela ("Nao tem estafeta") no ecrã de detalhes → `refund_choice_dialog.dart`.
  - **L61** `String _method = 'wallet'; // default = app (mais valioso para retenção)`
  - **L73-76** `if (widget.originalPaymentMethod != 'card') { _method = 'wallet'; }` e **L135** `canStripe = originalPaymentMethod == 'card'` → para MB Way a opção "Cartão" fica **desligada** ("Indisponível — pedido não foi pago com cartão"). **Quem paga por MB Way é obrigado a receber na carteira.**
- A app chama `cancel-order-with-choice` com `refund_method='wallet'` → v18 L215 `wallet_credit_refund_split(600)` → 480 c saldo livre + 240 tokens (120 c).
- O pedido fica `refund_method='wallet'`, `refund_status='completed'`, `payment_status='refunded'`, `refund_id` nulo — **a Stripe nunca devolveu nada.**
- Extra: a pré-visualização da app (L100) calcula `tokensCount = tokensCents * 20`, mas o servidor dá `× 2` → o ecrã mostrava 2400 tokens e o cliente recebeu 240.

## 3. O que a v19 muda (diff resumido; o ficheiro .ts tem tudo)

1. `refund_method` deixa de ser obrigatório. `'wallet'` passa a significar "o cliente carregou em **Quero já em saldo na carteira**".
2. **MB Way → sempre meio original** (ignora `'wallet'`). **Cartão → meio original por defeito**; `'wallet'` só com consentimento: grava `refund_choices` (texto mostrado, versão da app, plataforma) e credita com `wallet_credit_refund_100(..., 'consentimento_cliente')` → 100 % saldo, 0 tokens.
3. **Sem estafeta → taxa 0 sempre** (`semEstafeta ? 0 : computeCancelFeeEur(...)`).
4. **PI ainda não cobrado** (`requires_action`, `requires_payment_method`, `requires_confirmation`, `requires_capture`) → `stripe.paymentIntents.cancel(pi, {cancellation_reason:'requested_by_customer'}, {idempotencyKey:'cowc-v19-cancel-<pi>'})`.
5. Reembolso Stripe com chave **por pedido**: `cowc-v19-<orderId>` e `metadata {order_id, kind:'order_cancel_client'}` (o webhook usa a metadata para avisar o cliente).
6. Parte paga com saldo → `wallet_credit_refund_100(..., 'parte_paga_com_carteira')` (100 % saldo, idempotente).
7. Tokens usados → `devolver_tokens_do_pedido` (voltam como tokens, só com prova de consumo; nunca viram saldo).
8. Mensagens PT-PT: MB Way "Devolvemos X € ao teu MB Way. Avisamos-te quando estiver confirmado."; cartão "Devolvemos X € ao teu cartão. Pode demorar 5 a 10 dias úteis a aparecer no extrato."; consentimento "X € já estão no teu saldo Bora."
9. `refund_status='pending'` no ramo Stripe — fechado pelo webhook (§6) com `notificar_reembolso_confirmado`.

Matemática (sem estafeta, `fee=0`): `stripeADevolver = stripeDisponível − 0`; `walletADevolver = walletPago`; tokens à parte.
Divan com a v19: 600 c → `refunds.create(amount=600)` ao MB Way; 0 saldo; 0 tokens. ✔
Com estafeta (`after_accept`, `fee=250`): pago 600 c Stripe → devolve 350 c à Stripe; a taxa nunca é paga com tokens.

## 4. As outras 4 Edges que hoje põem dinheiro pago na carteira (mudança mínima proposta)

O `§2` do SQL (`wallet_split_free_pct = 1.00`) já tira os **tokens** de todas elas no mesmo dia. Falta tirar o **destino carteira**:

| Edge (versão no ar) | Hoje | Proposta |
|---|---|---|
| `execute-cancellation` v15 (admin aprova pedido de cancelamento) | L134 método escolhido pelo admin; o ecrã `admin_cancellation_requests_screen.dart:44` tem `'wallet'` por defeito; L165/168 split 80/20 | Ecrã: defeito `'stripe'`; Edge: se `payment_method in (card,mbway)` e não há `refund_choices` do cliente → força `'stripe'` |
| `admin-cancel-order` v14 | L231-233 parte carteira/tokens → split 80/20 | Trocar por `wallet_credit_refund_100('parte_paga_com_carteira')` + `devolver_tokens_do_pedido`; acrescentar `paymentIntents.cancel` quando o MB Way está pendente |
| `reprocess-refund` v3 | **L54** `refund_method === 'wallet' \|\| payment_method !== 'card'` → **MB Way vai para a carteira** (é aqui que acabam as falhas do `auto-refund-order`) | Trocar a condição por `payment_method in ('card','mbway')` → Stripe (`refunds.create`, chave `reprocess-<orderId>-<cents>`) |
| `client-cancel-order` v29 | por defeito `refund_target='card'` → Stripe ✔; `'wallet'` fora da graça → split; parte carteira fora da graça → split | Mesmo tratamento da v19: `'wallet'` só para cartão e com `refund_choices`; parte carteira → `wallet_credit_refund_100`; tokens → `devolver_tokens_do_pedido`; `paymentIntents.cancel` se pendente |

## 5. App (vai no próximo build Android + web + iPhone)

`lib/widgets/refund_choice_dialog.dart`:
- L61 `_method = 'stripe'` (meio original por defeito).
- L73-76 apagar o "força wallet" para não-cartão.
- MB Way: sem escolha — só o texto "Devolvemos ao teu MB Way." (botão "Confirmar cancelamento").
- Cartão: texto fixo "Devolvemos ao teu cartão. Pode demorar 5 a 10 dias úteis a aparecer no extrato." + botão secundário **"Quero já em saldo na carteira"** que manda `refund_method:'wallet'`, `consent_text:<texto exato do botão>`, `app_version`, `platform`.
- Tirar a linha "saldo livre + tokens" (L162) e o cálculo errado `× 20` (L100).
- `order_details_screen.dart` L441-443: mensagens novas.
Frases novas com `.tr` precisam de inglês no dicionário (lição "Frase .tr nova exige inglês").

## 6. stripe-webhook (zona protegida — só proposta)

Hoje v36: `charge.refunded` só faz log (L917-923); `refund.*` cai no `default` (L925). Proposta:
```ts
case 'refund.updated':
case 'refund.created': {
  const r = event.data.object as Stripe.Refund;
  const pi = typeof r.payment_intent === 'string' ? r.payment_intent : r.payment_intent?.id;
  if (r.metadata?.devolucao_id && r.status === 'succeeded') {
    await supabase.rpc('admin_devolucao_confirmar', { p_devolucao_id: r.metadata.devolucao_id,
      p_stripe_refund_id: r.id, p_devolvido_cents: r.amount, p_stripe_estado: 'succeeded' });
  }
  if (pi && (r.status === 'succeeded' || r.status === 'failed' || r.status === 'canceled')) {
    const { data } = await supabase.rpc('notificar_reembolso_confirmado', {
      p_payment_intent_id: pi, p_refund_id: r.id, p_cents: r.amount, p_estado: r.status });
    if (data?.user_id && data?.body) await supabase.functions.invoke('notify-client',
      { body: { user_id: data.user_id, title: data.title, body: data.body, data: { order_id: data.order_id } } });
  }
  break;
}
```
- Juntar `refund.updated` aos eventos do endpoint no painel da Stripe (**POR CONFIRMAR** quais eventos o endpoint subscreve hoje — o conector Stripe não está autorizado nesta sessão).
- `payment_intent.succeeded` num pedido cancelado pelo cliente/admin (L373-382): em vez de só avisar, reembolsar já (`refunds.create`, chave `late-succeeded-<pi>`), como já faz para TVDE (L194-218).

## 7. Prova antes do deploy (molde "Simular Edge Function com Deno e base falsa")

O guião tem de **falhar contra a v18** e passar na v19:
1. MB Way pago 600 c, sem estafeta, `refund_method:'wallet'` → v19 chama `refunds.create(600)`, 0 chamadas a `wallet_credit_refund_*`, 0 tokens. (v18: split 480+240 → falha o guião.)
2. Cartão pago 600 c, sem campo `refund_method` → `refunds.create(600)`. (v18: 400 `refund_method must be…` → falha.)
3. Cartão 600 c com `'wallet'` → 1 linha em `refund_choices` + `wallet_credit_refund_100(600,'consentimento_cliente')`; 0 tokens.
4. MB Way com `piStatus='requires_action'` → `paymentIntents.cancel`, 0 reembolsos, `payment_status='cancelled_no_charge'`.
5. Com estafeta (`driverAccepted`), 600 c → `refunds.create(350)`, `cancel_fee=2.5`.
6. Leitura de `platform_settings` a falhar, sem estafeta → taxa 0 (v18 daria 1,50 €).
7. Duplo toque → 2.º pedido 409 `cancellation_in_progress`.
Deploy (depois do "vai"): `supabase functions deploy cancel-order-with-choice --use-api` com os `_shared` (`platform_settings.ts`, `cors.ts`, `cobranca_stripe.ts`), verify_jwt=true; confirmar a versão 19 com `list_edge_functions`. Um pedido de prova pago em dinheiro (cash) não exercita o reembolso; o primeiro teste real é um MB Way pequeno feito pelo Danilo, com o "vai" dele, cancelado antes de haver estafeta — prova: `orders.refund_id` preenchido, `refund_status` passa a `refunded` pelo webhook, e o dinheiro aparece no MB Way.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
