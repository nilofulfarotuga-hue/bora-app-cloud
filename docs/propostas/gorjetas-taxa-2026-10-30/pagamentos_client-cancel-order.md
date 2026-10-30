# Patch proposto — `client-cancel-order` (zona vermelha) · gorjetas-taxa-2026-10-30 · Bloco B

⚠️ ISTO MEXE EM DINHEIRO (a gorjeta volta ao cliente quando ele cancela) — está tudo pronto.
Autorização do Danilo: 30/10/2026 13:40 ("devolver a gorjeta em cancelamentos").

- **Versão no ar:** v30 (28/10), `verify_jwt=true`. **Repo vs ar:** DIFERENTE — o repo ainda tem a v29.
  O diff abaixo é contra o AR (v30). Ao publicar, o ficheiro do repo deve passar a ser o do ar + este diff.
- **O que muda:** depois de gravar o cancelamento, `devolverGorjetasDoPedido` (`_shared/gorjeta_devolver.ts`,
  novo) devolve a gorjeta INTEIRA, fora da taxa de cancelamento, pelo caminho que o cliente escolheu
  (`refund_target` 'wallet' → saldo Bora; senão cartão/MB Way). Gorjeta do carrinho no mesmo pagamento →
  reembolso PARCIAL do PI do pedido no valor da gorjeta; gorjeta à parte → reembolso do PI dela. Cada
  gorjeta é reservada antes (nunca 2x); falhou → a conferência de 15 em 15 min tenta outra vez.
  Resposta + `gorjeta_devolvida_cents`, `gorjeta_carteira_cents`.
- **E o reembolso da compra?** Fica igual no código; muda o `_shared/cobranca_stripe.ts` (v3, fora da zona
  vermelha, já no repo): `stripeCents`/`stripeDisponivelCents` deixam de contar a gorjeta cobrada junto,
  por isso a taxa e o reembolso da compra nunca mexem na gorjeta.
- **Publicar com:** `_shared/cobranca_stripe.ts` v3 + `_shared/gorjeta_devolver.ts`, DEPOIS da migração
  `20261030145000` (coluna `tips.cobrada_junto` e `devolvida_para`). Sem a migração, o helper não lê as
  gorjetas (erro tratado) e o cancelamento segue como hoje.
- **Prova:** `deno check` do proposto (com os `_shared` do repo) = 0 erros (30/10).

## Diff (contra a versão no ar)

```diff
--- a/supabase/functions/client-cancel-order/index.ts (no ar)
+++ b/supabase/functions/client-cancel-order/index.ts (proposto)
@@ -9,6 +9,11 @@
 // Os tokens gastos voltam como TOKENS pelo gatilho do banco (trg_orders_devolver_tokens) quando
 // o servidor registou quais (tokens_applied_count > 0): então a taxa sai do dinheiro e o valor
 // dos tokens sai da base do reembolso. PUBLICAR com o _shared/cobranca_stripe.ts v2.
+// v31 (30/10/2026, missão gorjetas-taxa-2026-10-30, autorização do Danilo 30/10 13:40): a gorjeta do
+// pedido volta INTEIRA, fora da taxa de cancelamento, pelo caminho que o cliente escolheu para o resto
+// (refund_target: saldo Bora ou cartão/MB Way) — _shared/gorjeta_devolver.ts. A gorjeta cobrada no
+// mesmo pagamento da compra já não entra no reembolso da compra (_shared/cobranca_stripe.ts v3).
+// PUBLICAR com os dois _shared, DEPOIS da migração 20261030145000 (tips.cobrada_junto).
 // ============================================================================
 import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
 import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
@@ -16,6 +21,7 @@
 import { corsHeaders } from '../_shared/cors.ts';
 import { lerPagoDoPedido, repartirReembolso, type Pago } from '../_shared/cobranca_stripe.ts'; // v29 (ronda 04/10 A.2)
 import { secretKey } from '../_shared/keys.ts'
+import { devolverGorjetasDoPedido } from '../_shared/gorjeta_devolver.ts'; // v31 (gorjetas 30/10)
 
 const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
   apiVersion: '2023-10-16',
@@ -270,6 +276,14 @@
   const { error: updateErr } = await admin.from('orders').update(patch).eq('id', orderId).eq('user_id', user.id);
   if (updateErr) return jsonResponse({ error: 'db_update_failed', details: updateErr.message }, 500);
 
+  // v31 (gorjetas 30/10): a gorjeta volta INTEIRA, fora da taxa, pelo caminho escolhido. Nunca falha
+  // o cancelamento: o que ficar por devolver a conferência de 15 em 15 min volta a tentar.
+  const gorjeta = await devolverGorjetasDoPedido(
+    admin, Deno.env.get('STRIPE_SECRET_KEY') ?? '', orderId,
+    refundTarget === 'wallet' ? 'carteira' : 'meio', `cancelado pelo cliente (${tier})`, user.id,
+  );
+  if (gorjeta.erros > 0) console.error('[client-cancel] gorjeta por devolver:', JSON.stringify(gorjeta.itens));
+
   return jsonResponse({
     ok: true, tier, fee_eur: (cancelFeeDebited || !nothingToRefund) ? feeEur : 0,
     refund_eur: (refundExecuted || walletCredited) ? (refundStripeCents + refundCarteiraCents) / 100 : 0,
@@ -277,6 +291,8 @@
     refund_card_eur: refundStripeCents / 100, refund_wallet_eur: refundCarteiraCents / 100, // v29 (ronda 04/10 A.2)
     refund_meio: order.payment_method ?? null, // v30: 'mbway' = na hora; 'card' = 5 a 10 dias úteis
     tokens_devolvidos: tokensDevolvidos,      // v30: voltam como tokens (gatilho do banco)
+    gorjeta_devolvida_cents: gorjeta.devolvidaCents, // v31: gorjeta inteira, fora da taxa
+    gorjeta_carteira_cents: gorjeta.carteiraCents,   // v31: parte que foi para o saldo
     refund_pending: refundFailed,
     refund_id: refundId ?? null, charge_missing: chargeMissing,
     nothing_to_refund: nothingToRefund, cancel_fee_debited: cancelFeeDebited, cancel_fee_debit: cancelFeeDebitResult,
```
