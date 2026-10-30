# Patch proposto — `stripe-webhook` (zona vermelha) · gorjetas-taxa-2026-10-30 · Bloco C

⚠️ ISTO MEXE EM DINHEIRO (a taxa da Stripe passa a contar no líquido do prestador) — está tudo pronto.

- **Versão no ar:** v36, `verify_jwt=false`. **Repo vs ar:** IGUAL.
- **O que muda (só `tipGravarEstado`):** com a gorjeta já 'succeeded' (o `confirm` da charge-tip chegou
  primeiro) e a taxa por gravar, grava SÓ a taxa (`.is('stripe_fee_cents', null)`). O filtro
  `.not('status','in','(succeeded,refunded)')` do resto fica igual. Sem taxa no momento → o cron de
  domingo (`charge-tip` ação `taxas_em_falta`) vai buscá-la.
- **Nada mais muda no webhook para as gorjetas do carrinho:** a gorjeta do cartão nasce paga com o pedido
  (gatilho no INSERT); a do MB Way passa a paga/falhada por gatilho quando o webhook marca o pedido.
- **Valor do PI ≠ total do pedido:** verificado no código do ar (v36) e no `finalize-order-from-intent`
  (v14): NENHUM compara o valor cobrado com o total do pedido (o finalize só exige `status=succeeded`;
  o Mode A só marca `paid`; `registar_cobranca_stripe` grava `amount_received`, que passa a incluir a
  gorjeta — certo, é o que a Stripe cobrou). Por isso a gorjeta junto não parte o pagamento.
- **Prova:** `deno check` do proposto = 0 erros (30/10).

## Diff (contra a versão no ar)

```diff
--- a/supabase/functions/stripe-webhook/index.ts (no ar)
+++ b/supabase/functions/stripe-webhook/index.ts (proposto)
@@ -66,7 +66,7 @@
       // deno-lint-ignore no-explicit-any
       const fee = (full.latest_charge as any)?.balance_transaction?.fee;
       if (typeof fee === 'number') patch.stripe_fee_cents = fee;
-    } catch (_) { /* taxa é informativa */ }
+    } catch (_) { /* v37: sem taxa agora → o cron de domingo (charge-tip taxas_em_falta) vai buscá-la */ }
   }
   if (intent.last_payment_error?.message) {
     patch.failure_reason = String(intent.last_payment_error.message).slice(0, 300);
@@ -74,6 +74,14 @@
   const { error } = await supabase.from('tips').update(patch).eq('id', tipId)
     .not('status', 'in', '(succeeded,refunded)');
   if (error) falha(`tips update: ${error.message} (${tipId})`);
+  // v37 (gorjetas 30/10, Bloco C): a taxa conta dinheiro — o prestador recebe a gorjeta paga depois
+  // MENOS a taxa exata (tips.liquido_prestador_cents). Se a gorjeta já estava 'succeeded' (o confirm
+  // da charge-tip chegou primeiro) com a taxa por gravar, grava-se SÓ a taxa.
+  if (typeof patch.stripe_fee_cents === 'number') {
+    const { error: feeErr } = await supabase.from('tips').update({ stripe_fee_cents: patch.stripe_fee_cents })
+      .eq('id', tipId).is('stripe_fee_cents', null);
+    if (feeErr) console.error('[stripe-webhook] tip: taxa não gravada (fica para o cron de domingo):', feeErr.message, tipId);
+  }
   console.log('[stripe-webhook] tip', tipId, '->', status, intent.id);
 }
 
```
