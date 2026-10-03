# Sessão 1 — TODOs adiados

## Sessão 1B (dedicada — push notifications)
**Razão:** escopo removido do prompt original; volume + risco fora dos 7 bugs desta sessão.
- Verificar deploy `google-services.json` (Android) + `GoogleService-Info.plist` (iOS) em produção.
- Configurar Supabase secrets `FIREBASE_*` para Edge Functions `notify-driver` / `notify-partner` / `notify-client`.
- Smoke fim-a-fim: dispatch → driver recebe push; partner accept → cliente recebe push.

## BUG 6f — Email parceiro (aprovação/rejeição)
**Estado:** infra de email **NÃO existe** em `supabase/functions/`. Há `notify-driver`, `notify-partner`, `notify-client` mas todas usam Firebase FCM (push), não email.

Spec breve quando se decidir:
- Provider: Resend (preferido) ou SendGrid.
- Edge Function `send-partner-decision-email(p_restaurant_id, p_decision, p_reason)`.
- Template aprovado: "Olá {{nome}}, a tua loja {{nome_loja}} foi aprovada e já está visível na Bora App."
- Template rejeitado: "Olá {{nome}}, a tua candidatura {{nome_loja}} foi rejeitada. Motivo: {{motivo}}. Podes voltar a candidatar-te corrigindo o motivo."
- Hook em `approve_partner` / `reject_partner` para invocar a Edge Fn (fire-and-forget, não bloqueia RPC).

Acréscimo desejável: registar email enviado em `admin_audit_log.details->>'email_sent'`.
