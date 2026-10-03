# Sessão 5F-β — Push Admin Urgente + Reply UI + Email

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Pré-requisito:** 5F-α completo em prod (commit `108b60b`)
**Estimativa:** 4-5h (Fase A audit ~30min + Fase B ~3-4h)
**Estado:** ✅ Fase B concluída em prod — ⏸️ activação real depende de TODO §41.8 manual Danilo

---

## Objectivo

Estender 5F-α (badges urgência + banner crítico) com:
1. **Push notification real** quando cliente reporta crítico (mesmo com app fechada)
2. **Reply UI** para admin responder via app (vs scripts/crosstalk/respond.ts)
3. **Email Resend** opcional como fallback secundário

---

## Decisões arquitecturais

### Tabela `admin_push_tokens` separada
Não reusa `users.fcm_token` (1-per-user) nem `push_broadcasts` (per-segment). Admin tem múltiplos devices (PC + telemóvel) → tabela própria com `fcm_token UNIQUE`.

### FCM v1 + OAuth2 Service Account (não legacy)
Pattern existente em `notify-driver` usa `FIREBASE_PROJECT_ID` + `FIREBASE_SERVICE_ACCOUNT` JSON via JWT RS256 → access_token. Reusar verbatim em `notify-admin-urgent` (consistency + recomendação Google).

### `AdminPushService` Flutter — thin wrapper
Reusa `NotificationService.instance.fcmToken` em vez de duplicar permission/getToken. Adiciona apenas chamada RPC + listener token refresh + deep link `/admin/crosstalk`.

### Trigger inactivo aceitável
`pg_net` settings MISSING em prod. Trigger é registado mas faz silent skip via `RAISE NOTICE`. Activa-se automaticamente quando Danilo configurar settings no Dashboard (TODO §41.8 BLOQUEANTE).

---

## Componentes (5)

1. **DB migration** `20260506_5f_beta_b1_admin_push_infra`
   - Tabela `admin_push_tokens` + RLS + 2 policies + index
   - RPC `admin_register_push_token` (UPSERT por fcm_token)
   - RPC `admin_respond_to_crosstalk` (status pending → answered)
   - Trigger `_notify_admin_urgent_trigger()` AFTER INSERT
   - Tentativa `ALTER DATABASE` pg_net (provavelmente falha; documentar)

2. **Edge Fn** `notify-admin-urgent` (verify_jwt=false)
   - Auth interna: service_role match
   - FCM v1 paralelo via `Promise.allSettled`
   - Email Resend opcional (skip se RESEND_API_KEY missing)
   - Cleanup tokens stale (UNREGISTERED/INVALID_ARGUMENT) → DELETE

3. **`AdminPushService`** Flutter (novo)
   - `registerForAdmin()` — gate `AuthAdminService.isAdmin()` + RPC
   - `setupDeepLinks(context)` — `onMessageOpenedApp` → pushNamed `/admin/crosstalk`

4. **`AdminCrosstalkScreen`** reply UI (estende 5F-α)
   - Botão "💬 Responder" em cards `status='pending'`
   - Dialog TextField multiline → RPC
   - Chip "✋ Respondido por admin" quando `answered_by='admin'`
   - Banner texto actualizado (Reply UI activa)

5. **Routes + dashboard hook**
   - `main.dart` registar `/admin/crosstalk`
   - `admin_dashboard_screen.dart` initState chama `AdminPushService.registerForAdmin() + setupDeepLinks(context)`

---

## TODOs manuais Danilo (pós-deploy)

⚠️ **§41.8 BLOQUEANTE crítico**

1. **`pg_net` settings** (Supabase Dashboard SQL editor):
   ```sql
   ALTER DATABASE postgres SET app.supabase_url = 'https://ojykpzwqrtusfeakzrna.supabase.co';
   ALTER DATABASE postgres SET app.service_role_key = '<service_role_key>';
   SELECT pg_reload_conf();
   ```
   Activa: 5D cron + 5B-β1 trigger + 5F-β trigger + PASSWORD_RESET.

2. **`RESEND_API_KEY`** (opcional, só email):
   ```
   supabase secrets set RESEND_API_KEY=<key> --project-ref ojykpzwqrtusfeakzrna
   ```

3. **Domínio email** Resend: confirmar `noreply@boraapp.com` verificado.

4. **Admin abrir admin app uma vez** pós-deploy para registar 1º FCM token.

---

## Limitações 5F-β

- Trigger inactivo até `pg_net` config (TODO crítico)
- Email skip se Resend missing
- 1ª notificação só após admin abrir app
- WhatsApp não suportado (decisão Danilo)

---

## Próximas sessões

- **5G** — Painel admin inbox propostas avançado (~3h)
- **Sessão 6** — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor (~6-8h)

---

## Relatórios

- **Audit:** `bora_app/.claude/.ai/reports/20260502_megafinal/05f_beta_audit.md`
- **Final report (após B):** `bora_app/.claude/.ai/reports/20260502_megafinal/05f_beta_report.md` (TODO)

## Commits relacionados

- `108b60b` 5F-α (urgência crítica/médio/normal + AdminCrosstalkScreen banner)
- `14c0462` 5F (comunicação A↔B + tool agent_ask_robot_b + AdminCrosstalkScreen)
- 5F-β commits — ver `git log autonomous-night-2026-04-29`

## Resultados smokes

- DB S1-S5: 4/5 ✅ (S5 pg_net MISSING esperado)
- Edge Fn S6-S8: S6 ACTIVE, S8 403 ✅ (S7 deferido)
- Flutter S9-S13: 5/5 ✅ (analyze 55 baseline)
- Regressão S14-S21: 8/8 ✅ (21 skills, RAG 534, support-chatbot v8 intacto)
