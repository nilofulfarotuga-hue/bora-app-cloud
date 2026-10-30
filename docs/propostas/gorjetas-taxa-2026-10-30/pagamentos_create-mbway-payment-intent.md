# Patch proposto — `create-mbway-payment-intent` (zona vermelha) · gorjetas-taxa-2026-10-30

⚠️ ISTO MEXE EM DINHEIRO (gorjeta do carrinho no mesmo pagamento MB Way) — está tudo pronto.
Autorização do Danilo: 30/10/2026 13:40.

- **Versão no ar:** v30, `verify_jwt=false`.
- **Repo vs ar:** DIFERENTE só na chave (repo `secretKey()`, ar `SUPABASE_SERVICE_ROLE_KEY`). Diff contra o AR.
- **O que muda:** antes de calcular o valor, `gorjeta_checkout_mbway_valor(order_id)` devolve a gorjeta
  do carrinho que o gatilho `trg_zz_gorjeta_checkout_na_criacao` criou 'pending' ao nascer o pedido
  (0 se não há). Soma-se ao `payment_buffer_total`. Depois de criar o PI, `gorjeta_checkout_mbway_pi`
  grava-o na gorjeta. Metadata `gorjeta_cents`. Resposta + `amountCents`, `gorjetaCents`.
- **Pago / falhado:** o webhook NÃO muda. Quando ele marca o pedido `paid` (Mode A, `order_id`), o gatilho
  `trg_zz_gorjeta_checkout_pagamento` põe a gorjeta 'succeeded' (PI igual, ou cobrado = buffer + gorjeta);
  quando marca `failed`, a gorjeta fica 'failed'. Uma nova tentativa no mesmo pedido volta a levá-la
  (uma gorjeta por pedido: nunca duas cobranças).
- **Pré-requisitos:** migrações `20261030144900` e `20261030145000` antes. Sem elas: erro no RPC → sem gorjeta.
- **Prova:** `deno check` do proposto = 0 erros (30/10). Caminho MB Way em `supabase/tests/gorjetas_taxa_prova.sql`.

## Diff (contra a versão no ar)

```diff
--- a/supabase/functions/create-mbway-payment-intent/index.ts (no ar)
+++ b/supabase/functions/create-mbway-payment-intent/index.ts (proposto)
@@ -17,6 +17,12 @@
 //      Se o PI anterior ainda está vivo (à espera da app MB WAY), devolve-se
 //      esse em vez de mandar um segundo pedido ao telemóvel.
 //   Resposta igual à v29 ({ok, paymentIntentId, status, mode}) — compatível.
+// v31 (2026-10-30, missão gorjetas-taxa-2026-10-30, autorização do Danilo 30/10 13:40)
+//   A gorjeta do carrinho vai no MESMO pagamento MB Way: o gatilho trg_zz_gorjeta_checkout_na_criacao
+//   criou-a 'pending' ao nascer o pedido; aqui soma-se ao valor (gorjeta_checkout_mbway_valor) e grava-se
+//   nela o PaymentIntent (gorjeta_checkout_mbway_pi). Fica 'succeeded' quando o webhook marca o pedido
+//   pago (gatilho trg_zz_gorjeta_checkout_pagamento) — o webhook não muda. Sem gorjeta = como a v30.
+//   Resposta: + amountCents, gorjetaCents.
 
 // BUG 13 — Stripe mode toggle. Default 'live'.
 const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
@@ -125,7 +131,15 @@
       return json({ error: 'Order already processed' }, 409);
     }
 
-    const amountCents = Math.round((order.payment_buffer_total as number) * 100);
+    // v31 (gorjetas 30/10): a gorjeta do carrinho deste pedido vai no mesmo pagamento.
+    // Erro a ler (ex.: migração por aplicar) = sem gorjeta, como a v30.
+    let gorjetaCents = 0;
+    {
+      const { data: g, error: gErr } = await supabase.rpc('gorjeta_checkout_mbway_valor', { p_order_id: order_id });
+      if (gErr) console.error('[create-mbway-payment-intent] gorjeta não lida (segue sem gorjeta):', gErr.message);
+      else gorjetaCents = Math.max(0, Math.round(Number(g ?? 0)));
+    }
+    const amountCents = Math.round((order.payment_buffer_total as number) * 100) + gorjetaCents;
     if (amountCents < 50) {
       return json({ error: 'Amount too small (min 0.50 EUR)' }, 400);
     }
@@ -171,9 +185,18 @@
         billing_details: { phone: e164 },
       },
       confirm: true,
-      metadata: { order_id },
+      metadata: { order_id, ...(gorjetaCents > 0 ? { gorjeta_cents: String(gorjetaCents) } : {}) },
     }, { idempotencyKey: `mbway_${order_id}_${anterior ?? 'primeiro'}` });
 
+    // v31: a gorjeta fica a saber qual é o pagamento que a leva. Se falhar, o gatilho reconhece-a na
+    // mesma quando o valor cobrado = buffer + gorjeta.
+    if (gorjetaCents > 0) {
+      const { error: gpErr } = await supabase.rpc('gorjeta_checkout_mbway_pi', {
+        p_order_id: order_id, p_payment_intent: intent.id,
+      });
+      if (gpErr) console.error('[create-mbway-payment-intent] gorjeta sem PI gravado:', gpErr.message, intent.id);
+    }
+
     console.log('[create-mbway-payment-intent] intent confirmed (server-side):',
       intent.id, `order=${order_id}`, `phone=${e164}`, `status=${intent.status}`,
       `mode=${STRIPE_MODE}`, `anterior=${anterior ?? 'nenhum'}`);
@@ -195,6 +218,8 @@
       paymentIntentId: intent.id,
       status: intent.status,
       mode: STRIPE_MODE,
+      amountCents,   // v31: compra + gorjeta do carrinho
+      gorjetaCents,  // v31
     });
   } catch (err) {
     const message = err instanceof Error ? err.message : String(err);
```
