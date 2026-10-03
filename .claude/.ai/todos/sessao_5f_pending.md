# Sessão 5F — Pendentes (5F-α / 5F-β)

**Data 5F:** 2026-05-06
**Branch base:** `autonomous-night-2026-04-29`

---

## 5F-α (próxima) — Push admin urgência crítica

Notificações **push notification + email** (sem WhatsApp) para admin quando
cliente reporta urgência crítica via chatbot. Sem dependência externa
WhatsApp (decisão Danilo: simplicidade + privacidade GDPR).

### Categorias de urgência

- **🔴 Crítico** — push + email imediatos. Triggers:
  - Termos no `question`: `urgente`, `urgência`, `emergência`, `acidente`,
    `não consigo pagar`, `roubaram-me`, `polícia`, `hospital`.
  - `support_skills.criticality='critical'` (já existe coluna).
  - Anomalias detectáveis: muitos `agent_ask_robot_b` da mesma sessão em <5min.
- **🟡 Médio** — só email diário (digest). Default para problemas técnicos
  app sem termos críticos.
- **🟢 Normal** — sem notificação; admin vê apenas em
  `AdminCrosstalkScreen` (5F).

### Implementação prevista

1. Coluna `urgency` em `robot_crosstalk` (default `'normal'` — popular pelo
   trigger de classificação).
2. Trigger BEFORE INSERT classifica via regex no `question` + skill
   criticality.
3. Edge Function `notify-admin-crosstalk` (verify_jwt=false; service_role
   no body):
   - Push admin via FCM token (`profiles.fcm_token` para admins
     hardcoded em `auth_admin_service.dart`).
   - Email via Resend / Supabase SMTP para `nilofulfarotuga@gmail.com`
     + `nilofulfaro@gmail.com`.
4. Trigger AFTER INSERT chama Edge Fn (HTTP via `pg_net` ou
   `supabase_functions.http_request`).
5. Banner urgência crítica destacado em `AdminCrosstalkScreen` (vermelho).

### Defesas

- Rate limit: máx 5 push críticos por hora por admin (evita flood).
- Override DB (`support_settings.urgent_push_enabled`).
- Logs em `support_audit_log` ou tabela equivalente.
- Sem PII no payload push (só `crosstalk_id` + categoria).

---

## 5F-β — Auto-resposta + reply UI + correções

### admin_respond_to_crosstalk + UI reply

- RPC `admin_respond_to_crosstalk(crosstalk_id, answer)` GRANT authenticated
  + `is_admin()` check.
- Botão "Responder" em `AdminCrosstalkScreen` para rows pending → modal
  textarea → submit RPC.
- Sair do "modo observador" actual (banner 5F).

### Fix anonimização JS

- `analyze-conversations` (5D, JS) tem mesmo bug ordem UUID que foi
  corrigido em PG na hotfix 5F-B1.
- Replicar ordem `email → phone PT → UUID → phone genérico → dígitos 4+`
  no `_anonymizePII()` JS.
- Adicionar smoke test reusável (PG + JS espelho).

### Auto-resposta Claude Code

- Skill `ask-knowledge-base` corre em loop scheduled (cron / hook
  `SessionStart` ou `loop` slash command).
- Lê `a_to_b` pending → query_knowledge.ts → respond.ts automático se
  `min_similarity > 0.7` em pelo menos 2 chunks.
- Threshold + override admin via flag em `support_settings`.

### Métricas

- View `crosstalk_metrics`: rate respondido / ignored, tempo médio
  resposta, top skills accionadas, top RAG chunks reutilizados.
- Card no `AdminDashboardScreen` ou nova página
  `AdminCrosstalkStatsScreen`.

---

## Notas de implementação

- 5F-α deve preceder 5F-β: push admin é mais urgente que UI reply
  (admin vê crosstalk no telemóvel mesmo sem entrar na app).
- Push admin deve ser opt-in via `profiles.notif_admin_crosstalk` (default
  `true` para admins hardcoded; configurável).
- Manter regra **sem WhatsApp** — Danilo decisão 2026-05-06.

---

*Pendentes Sessão 5F — actualizar quando 5F-α / 5F-β forem iniciadas.*
