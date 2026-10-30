# Patch proposto — `create-payment-intent` (zona vermelha) · gorjetas-taxa-2026-10-30

⚠️ ISTO MEXE EM DINHEIRO (gorjeta do carrinho no mesmo pagamento do cartão) — está tudo pronto.
Autorização do Danilo: 30/10/2026 13:40 (gorjeta do carrinho no mesmo pagamento da compra).

- **Versão no ar:** v34, `verify_jwt=false` (lida com `get_edge_function` a 30/10).
- **Repo vs ar:** DIFERENTE só na chave — o repo usa `secretKey()` de `_shared/keys.ts`; o ar lê
  `SUPABASE_SERVICE_ROLE_KEY` e não importa `keys.ts`. O diff abaixo é feito contra o AR.
  Ao publicar: partir do ficheiro do ar + este diff (ou aplicar o mesmo diff ao repo, que só muda a chave).
- **O que muda (só o Mode B, `cart_input`):** depois da cotação (`quote_order_pricing` intacta), chama
  `gorjeta_checkout_para_cobrar(user)` (só pedidos do carrinho: restaurant/storeShopping/takeaway) e soma a
  gorjeta ao valor do PaymentIntent. Guarda-a no rascunho (`payload.gorjeta_checkout_cents`,
  `amount_cents` = compra + gorjeta) e na metadata (`gorjeta_cents`). Resposta: `amountCents` passa a
  ser o total cobrado e vem `gorjetaCents`. Mode A (legacy) intacto. Sem marcação / interruptor
  desligado / erro a ler → exatamente como hoje.
- **Pré-requisitos:** migrações `20261030144900` (interruptor) e `20261030145000` (proposta
  `pagamentos_20261030145000_gorjeta_checkout_junto_pagamento.sql`) aplicadas ANTES. Sem a função SQL,
  o RPC dá erro → segue sem gorjeta (não parte o pagamento).
- **Quem cria a linha em `tips`:** o gatilho `trg_zz_gorjeta_checkout_na_criacao`, quando o
  `finalize-order-from-intent` cria o pedido com este PI (sem mexer no finalize nem no webhook).
- **Prova:** `deno check` do ficheiro proposto = 0 erros (30/10). Prova SQL do caminho do cartão
  (rascunho com gorjeta → pedido pago → gorjeta paga, cobrada_junto) em `supabase/tests/gorjetas_taxa_prova.sql`.

## Diff (contra a versão no ar)

```diff
--- a/supabase/functions/create-payment-intent/index.ts (no ar)
+++ b/supabase/functions/create-payment-intent/index.ts (proposto)
@@ -7,6 +7,10 @@
 //
 // CRITICAL: getOrCreateCustomer usa service-role admin client para SELECT/UPDATE
 // em users (RLS bloqueia user-side updates a stripe_customer_id). Falha = non-blocking.
+//
+// v29 (30/10/2026, missão gorjetas-taxa-2026-10-30, autorização do Danilo 30/10 13:40): Mode B soma
+//   ao valor do PaymentIntent a gorjeta do carrinho marcada antes de pagar
+//   (gorjeta_checkout_para_cobrar); guarda-a no rascunho e na metadata (gorjeta_cents). Mode A intacto.
 
 import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
 import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
@@ -167,13 +171,29 @@
   const admin = createClient(supabaseUrl, serviceKey);
   const customerId = await getOrCreateCustomer(admin, user.id);
 
+  // v29 (gorjetas 30/10, autorização do Danilo 30/10 13:40): a gorjeta do carrinho vai no MESMO
+  // pagamento. Lê a marcação que a app fez antes de abrir o pagamento (client_preparar_gorjeta_checkout):
+  // 0 se não há, se o interruptor tips_checkout_junto_pagamento está desligado ou se não é pedido do
+  // carrinho (Favores/envios). Soma-se DEPOIS da cotação: nunca entra em margens, buffers, comissões
+  // nem taxas. Fica no rascunho (payload.gorjeta_checkout_cents): quando o pedido nascer, o gatilho
+  // trg_zz_gorjeta_checkout_na_criacao cria a linha em tips (paga, cobrada_junto). Erro a ler = sem gorjeta.
+  let gorjetaCents = 0;
+  if (['restaurant', 'storeShopping', 'takeaway'].includes(String(cart.service_type ?? ''))) {
+    const { data: g, error: gErr } = await admin.rpc('gorjeta_checkout_para_cobrar', { p_user_id: user.id });
+    if (gErr) console.error('[create-payment-intent new] gorjeta não lida (segue sem gorjeta):', gErr.message);
+    else gorjetaCents = Math.max(0, Math.round(Number(g ?? 0)));
+  }
+  const totalCents = amountCents + gorjetaCents;
+  const payload = gorjetaCents > 0 ? { ...cart, gorjeta_checkout_cents: gorjetaCents } : cart;
+  const metaGorjeta = gorjetaCents > 0 ? { gorjeta_cents: String(gorjetaCents) } : {};
+
   const { data: draftRow, error: insertErr } = await admin
     .from('payment_drafts')
     .insert({
       payment_intent_id: 'pending_' + crypto.randomUUID(),
       user_id: user.id,
-      payload: cart,
-      amount_cents: amountCents,
+      payload,
+      amount_cents: totalCents,
       wallet_applied_cents: walletCents,
     })
     .select('id').single();
@@ -187,18 +207,18 @@
   try {
     if (savedPmId && customerId) {
       paymentIntent = await stripe.paymentIntents.create({
-        amount: amountCents, currency: 'eur',
+        amount: totalCents, currency: 'eur',
         customer: customerId, payment_method: savedPmId,
         confirm: true, off_session: true,
         automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
-        metadata: { draft_id: draftId, user_id: user.id },
+        metadata: { draft_id: draftId, user_id: user.id, ...metaGorjeta },
       });
     } else {
       paymentIntent = await stripe.paymentIntents.create({
-        amount: amountCents, currency: 'eur',
+        amount: totalCents, currency: 'eur',
         ...(customerId ? { customer: customerId, setup_future_usage: 'off_session' as const } : {}),
         automatic_payment_methods: { enabled: true },
-        metadata: { draft_id: draftId, user_id: user.id },
+        metadata: { draft_id: draftId, user_id: user.id, ...metaGorjeta },
       });
     }
   } catch (e) {
@@ -216,15 +236,17 @@
     return json({ error: 'draft_update_failed', details: updateErr.message }, 500);
   }
 
-  console.log('[create-payment-intent new v28] PI=', paymentIntent.id, 'draft=', draftId,
+  console.log('[create-payment-intent new v29] PI=', paymentIntent.id, 'draft=', draftId,
     'customer=', customerId ?? 'none', 'savedPm=', savedPmId ?? 'none',
-    'status=', paymentIntent.status, 'amount=€', (amountCents / 100).toFixed(2));
+    'status=', paymentIntent.status, 'amount=€', (totalCents / 100).toFixed(2),
+    'gorjeta=€', (gorjetaCents / 100).toFixed(2));
 
   return json({
     clientSecret: paymentIntent.client_secret,
     paymentIntentId: paymentIntent.id,
     draftId,
-    amountCents,
+    amountCents: totalCents,   // v29: o que se cobra (compra + gorjeta do carrinho)
+    gorjetaCents,              // v29: 0 = sem gorjeta no mesmo pagamento
     status: paymentIntent.status,
     requiresAction: paymentIntent.status === 'requires_action',
   });
```
