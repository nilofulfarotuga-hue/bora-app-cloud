---
id: memoria-claude-ai-proposta-m1-2026-11-08-patch-notify-client
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 08/11 — remendo notify-client (toque persistente)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-patch-notify-client`, origem `claude-code`, atualizada em 2026-11-08T20:59:30.92096+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 patch notify client · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08 (Claude Code do PC, 08/11/2026). Ficheiro: docs/propostas/m1-dinheiro-favores-2026-11-08/05_notify-client_toque_persistente.patch. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio) — o ramo ai/2026-11-08-m1-dinheiro-favores está só no PC.

```diff
diff --git a/supabase/functions/notify-client/index.ts b/supabase/functions/notify-client/index.ts
index 0f24cf50..919eeba9 100644
--- a/supabase/functions/notify-client/index.ts
+++ b/supabase/functions/notify-client/index.ts
@@ -103,6 +103,10 @@ Deno.serve(async (req) => {
   const status         = payload.status        as string | undefined
   const kind           = payload.kind          as string | undefined
   const notifType      = payload.type          as string | undefined
+  // M1 08/11/2026: { ring: true, ring_seconds } → canal de alarme das ofertas (bora_offers_alarm_v4,
+  // som bora_alert) e o mesmo pedido de toque no payload de dados. Só para a aprovação do Favor.
+  const tocar          = payload.ring === true || payload.ring === 'true'
+  const tocarSegundos  = Math.min(600, Math.max(10, Number(payload.ring_seconds ?? 180) || 180))
   let title            = payload.title         as string | undefined
   let body             = payload.body          as string | undefined
 
@@ -212,6 +216,9 @@ Deno.serve(async (req) => {
     ...(appointmentId ? { appointmentId: String(appointmentId) } : {}),
     ...(status        ? { status:        String(status) }        : {}),
     ...(kind          ? { kind:          String(kind) }          : {}),
+    // M1 08/11/2026: aprovação do preço do Favor — a app do cliente toca como as ofertas do
+    // estafeta (IncomingJobAlert) durante ring_seconds.
+    ...(tocar         ? { ring: 'true', ring_seconds: String(tocarSegundos) } : {}),
   }
 
   let enviados = 0
@@ -226,7 +233,9 @@ Deno.serve(async (req) => {
         data: dataPayload,
         android: {
           priority: 'high',
-          notification: { channel_id: 'bora_orders', sound: 'default' },
+          notification: tocar
+            ? { channel_id: 'bora_offers_alarm_v4', sound: 'bora_alert' }
+            : { channel_id: 'bora_orders', sound: 'default' },
         },
         apns: {
           headers: { 'apns-priority': '10' },

```

