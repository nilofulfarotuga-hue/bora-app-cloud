---
id: memoria-claude-ai-proposta-m1-2026-11-08-patch-charge-tip
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 08/11 — remendo charge-tip (taxa proporcional das gorjetas junto)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-patch-charge-tip`, origem `claude-code`, atualizada em 2026-11-08T20:59:30.92096+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 patch charge tip · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08 (Claude Code do PC, 08/11/2026). Ficheiro: C:/Users/danil/AppData/Local/Temp/claude/383480322ea6ce8c/2205b2c0-b356-467b-893d-709bc52cb5f0/scratchpad/charge-tip.patch. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio) — o ramo ai/2026-11-08-m1-dinheiro-favores está só no PC.

```diff
diff --git a/supabase/functions/charge-tip/index.ts b/supabase/functions/charge-tip/index.ts
index fab415c6..b2a0e1f2 100644
--- a/supabase/functions/charge-tip/index.ts
+++ b/supabase/functions/charge-tip/index.ts
@@ -161,15 +161,28 @@ async function devolverCancelamento(admin: any, body: any, quem: string | null):
   return json({ ok: r.erros === 0, orderId, destino, ...r });
 }
 
+/** M1 08/11/2026: gorjeta cobrada JUNTO com o pedido (mesmo PaymentIntent) — a taxa é a parte
+ *  proporcional da taxa do pagamento inteiro (só contabilidade: o líquido do prestador nestas
+ *  gorjetas é sempre o valor inteiro, ver tips.liquido_prestador_cents). Caso BK 56fa8623:
+ *  80 × 200 / 3662 → 4 cêntimos. */
+async function taxaProporcional(stripe: Stripe, piId: string, gorjetaCents: number): Promise<number | null> {
+  const full = await stripe.paymentIntents.retrieve(piId, { expand: ['latest_charge.balance_transaction'] });
+  // deno-lint-ignore no-explicit-any
+  const fee = (full.latest_charge as any)?.balance_transaction?.fee;
+  const total = Number(full.amount_received ?? full.amount ?? 0);
+  if (typeof fee !== 'number' || total <= 0) return null;
+  return Math.round(fee * gorjetaCents / total);
+}
+
 // deno-lint-ignore no-explicit-any
 async function taxasEmFalta(admin: any): Promise<Response> {
-  // Gorjetas pagas à parte (as do mesmo pagamento da compra não têm taxa própria) dos últimos 60 dias.
+  // Gorjetas pagas à parte (taxa própria) e, desde 08/11, as pagas junto com o pedido (parte
+  // proporcional da taxa do pagamento) dos últimos 60 dias.
   const desde = new Date(Date.now() - 60 * 24 * 3600 * 1000).toISOString();
   const { data: tips, error } = await admin.from('tips')
-    .select('id, stripe_payment_intent_id, stripe_account')
+    .select('id, stripe_payment_intent_id, stripe_account, cobrada_junto, amount_cents')
     .in('status', ['succeeded', 'refunded'])
     .in('method', ['card', 'mbway'])
-    .eq('cobrada_junto', false)
     .is('stripe_fee_cents', null)
     .not('stripe_payment_intent_id', 'is', null)
     .gte('created_at', desde)
@@ -181,9 +194,11 @@ async function taxasEmFalta(admin: any): Promise<Response> {
   let gravadas = 0;
   let semTaxa = 0;
   const erros: string[] = [];
-  for (const t of (tips ?? []) as { id: string; stripe_payment_intent_id: string; stripe_account?: string | null }[]) {
+  for (const t of (tips ?? []) as { id: string; stripe_payment_intent_id: string; stripe_account?: string | null; cobrada_junto?: boolean; amount_cents?: number }[]) {
     try {
-      const fee = await taxaDoPagamento(stripeDaLinha(t).stripe, t.stripe_payment_intent_id); // duas contas
+      const fee = t.cobrada_junto === true
+        ? await taxaProporcional(stripeDaLinha(t).stripe, t.stripe_payment_intent_id, Number(t.amount_cents ?? 0))
+        : await taxaDoPagamento(stripeDaLinha(t).stripe, t.stripe_payment_intent_id); // duas contas
       if (fee === null) { semTaxa++; continue; }
       const { data: up, error: ue } = await admin.from('tips').update({ stripe_fee_cents: fee })
         .eq('id', t.id).is('stripe_fee_cents', null).select('id');

```

