# 5F-β AUDIT — Push Admin Urgente + Reply UI + Email

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Pré-requisito:** 5F-α completo em prod (commit `108b60b`)
**Estimativa restante:** 3-4h execução (Fase B)

---

## A0 — Regressão & Pré-requisitos

### Skills (target ≥21)
| Mode          | Count |
|---------------|-------|
| `escalate`    | 3     |
| `read_only`   | 11    |
| `write_shadow`| 7     |
| **Total**     | **21**|

✅ 21 skills active intactas.

### `robot_crosstalk` schema
- Coluna `urgency text NOT NULL DEFAULT 'normal'` (5F-α) ✅
- Tabela vazia em prod actualmente (sem distribuição para reportar)
- Schema completo: `id, asked_by, direction, question, question_context, rag_chunks_used, session_id, skill_triggered, status, urgency, answer, answered_at, answered_by, created_at`

### `pg_net` settings
- `app.supabase_url`: **MISSING** ❌
- `app.service_role_key`: **MISSING** ❌
- ⚠️ Trigger em B1 será criado mas **silent skip** até config manual (TODO §41.8)

### Supabase Secrets disponíveis
✅ `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT` (FCM v1 OAuth2 — pattern existing)
✅ `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
❌ `RESEND_API_KEY` — **não configurado**. Email graceful skip.
❌ `FCM_SERVER_KEY` — não existe (não é necessário; v1 usa service account JSON)

### Estado-alvo (deve ser NO/MISSING)
✅ `admin_push_tokens` → NO (não existe)
✅ `admin_register_push_token` RPC → NO (não existe)
✅ `admin_respond_to_crosstalk` RPC → NO (não existe)
✅ `is_admin()` helper → YES (já existe, usado em RPCs SECURITY DEFINER)

### `business_rules.md`
- Última secção: §40 (5F-α) — confirmado
- Total: 2382 linhas
- Footer: "Última atualização: 2026-05-06 (§40 — Sessão 5F-α)"
- **Próxima §41 5F-β** — actualizar footer ao terminar B4

---

## A1 — `push_broadcasts` reuse?

Schema actual:
```
id, body, completed_at, created_at, created_by, failed_count,
scheduled_at, segment, sent_count, status, title
```

**Decisão:** **NÃO reusar.** `push_broadcasts` é per-broadcast/segment (1 row por campanha), não per-token. Modelo errado para registo de tokens. Confirma decisão arquitectural: `admin_push_tokens` separada (pattern UNIQUE em `fcm_token`, multi-device por admin).

`users.fcm_token` (text NULL) também não serve — é 1-token-per-user.

---

## A2 — Pattern FCM existing (`notify-driver`)

**Descoberta crítica:** O prompt da sessão sugere `FCM_SERVER_KEY` (legacy). O pattern em prod é **FCM HTTP v1 + OAuth2 Service Account JWT** (mais recente, Google recomendado).

### Pattern reuse para `notify-admin-urgent`
- **Env vars:** `FIREBASE_PROJECT_ID` + `FIREBASE_SERVICE_ACCOUNT` (JSON inteiro do service account)
- **Endpoint:** `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`
- **Auth:** Bearer access_token obtido via JWT RS256 (helper `getFirebaseAccessToken`)
- **Message format:** `{ message: { token, notification, data, android, apns } }`
- **Cleanup token stale:** `errorCode == 'UNREGISTERED' || 'INVALID_ARGUMENT'` → DELETE row em `admin_push_tokens` (vs `notify-driver` que apenas faz `UPDATE drivers SET fcm_token = null`)
- **Graceful no-op:** sempre retorna 200 com `{ok:false, reason}` quando Firebase não configurado / token vazio
- **CORS:** headers padrão (POST, OPTIONS, Authorization)
- **Helpers:** `getFirebaseAccessToken(serviceAccount)`, `b64url`, `b64urlBytes` — copiar verbatim

⚠️ **Desvio do prompt original:** uso v1 + OAuth2 (consistente com codebase) em vez de legacy `FCM_SERVER_KEY`. Mais seguro e aligned com Google.

### Edge Fns audit (regressão check)
- `support-chatbot` v8 sha `e351ab629847ff0edcea3b7719acc41418cf728426373917f67f0a9f68f9a108` ✅ INTACTO
- `analyze-conversations` v2 (5D) ✅
- 25 Edge Fns total
- `notify-admin-urgent` → não existe (esperado)

---

## A3 — `AdminCrosstalkScreen` (5F-α)

**Ficheiro:** `lib/screens/admin/admin_crosstalk_screen.dart` (647 linhas)

### Pontos de inserção 5F-β
| Linha | Acção |
|-------|-------|
| 432   | Actualizar texto do banner observador: "Reply UI será adicionada em 5F-β" → "Reply UI activa via botão Responder" |
| ~555  | Adicionar `TextButton.icon` "💬 Responder" no Row de actions, **gate `status=='pending'`**, dentro do `_buildCard` |
| ~580  | Adicionar chip "✋ Respondido por admin" quando `answered_by == 'admin'` (vs robô em respostas existing) |
| topo  | Adicionar dialog state `_buildReplyDialog()` (helper privado) |

### Não tocar
- Filtros existentes (`_statusFilter`, `_directionFilter`, `_urgencyFilter`)
- Realtime subscription (`_subscribeRealtime`)
- Critical banner (5F-α)
- Inline `JsonEncoder` shim (linhas 617-646)
- Drill-down RAG / context dialogs

### Constantes disponíveis
- `_boraGreen = 0xFF1B5E20` (verde Bora) — usar no botão Responder
- `_critical = 0xFFD32F2F`, `_amber = 0xFFFF8F00` (warnings)
- Sem `dart:convert` import directo (usa shim) — manter pattern

---

## A4 — FCM init + admin auth pattern

### `NotificationService` (singleton existente)
**Path:** `lib/services/notification_service.dart`

**API pública relevante:**
- `NotificationService.instance` (singleton)
- `String? get fcmToken` (linha 47) — getter público ✅
- `init()` (chamado em `main.dart:63` — JÁ ACTIVO)
- `_consentGranted` (default true, controla persistência)
- `_boundRole` + `_boundId` para refresh token
- `saveTokenForClient/Driver/Partner(id)` — UPSERT em users/drivers/restaurants

### `main.dart:62-63` — Firebase init
```dart
await Firebase.initializeApp();
await NotificationService.instance.init();
```
✅ **Já activo** (não comentado). Permission + getToken corre na app start.

### `AuthAdminService.isAdmin()` (`lib/services/auth_admin_service.dart`)
- Static, **não async** — usar para gate UI
- 2-tier fallback: `app_metadata.role == 'admin'` (canónico) → `user_metadata.bora_role == 'admin'` (legacy)
- Server-side `admin_*` RPCs enforçam strictly via `is_admin()` (existente)

### Routes (`main.dart:191`)
- `/admin` registada → `AdminDashboardScreen`
- `/admin/crosstalk` **NÃO registada** — AdminCrosstalkScreen actualmente navegado via `MaterialPageRoute(builder)` em `admin_dashboard_screen.dart:538`
- **Decisão:** registar rota nomeada `/admin/crosstalk` para deep link FCM (`Navigator.pushNamed`)

### `pubspec.yaml`
- `firebase_core: ^3.0.0` ✅
- `firebase_messaging: ^15.0.0` ✅
- `device_info_plus`: **NÃO listado** — usar fallback `Platform.operatingSystem` em vez de adicionar dep

### Decisão arquitectural revista — `AdminPushService`
Em vez de duplicar `init()`, **reusar** `NotificationService.instance.fcmToken`:

```dart
class AdminPushService {
  static StreamSubscription<String>? _refreshSub;

  static Future<void> registerForAdmin() async {
    if (!AuthAdminService.isAdmin()) return; // gate
    String? token = NotificationService.instance.fcmToken;
    token ??= await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await _registerRpc(token);
    _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(_registerRpc);
  }

  static Future<void> _registerRpc(String token) async { /* RPC */ }

  static void setupDeepLinks(BuildContext context) {
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (msg.data['type'] == 'crosstalk_critical') {
        Navigator.of(context).pushNamed('/admin/crosstalk');
      }
    });
  }
}
```

**Hook point:** `AdminDashboardScreen.initState()` (linha 67) chama `AdminPushService.registerForAdmin()` + `setupDeepLinks(context)`.

---

## A5 — Análise impacto + rollback

### Mudanças DB (1 migration)
- **CREATE** tabela `admin_push_tokens` (uuid id, admin_id FK, fcm_token UNIQUE, device_label, platform, last_used_at, created_at)
- **RLS** + 2 policies: `admin_own` (FOR ALL using admin_id=auth.uid() AND is_admin()) + `service_role_all`
- **Index** `idx_admin_push_tokens_admin` (admin_id)
- **CREATE** RPC `admin_register_push_token(p_fcm_token, p_device_label, p_platform)` SECURITY DEFINER, GRANT authenticated
- **CREATE** RPC `admin_respond_to_crosstalk(p_crosstalk_id, p_answer)` SECURITY DEFINER, GRANT authenticated
- **CREATE** trigger function `_notify_admin_urgent_trigger()` SECURITY DEFINER (silent skip se pg_net MISSING; EXCEPTION WHEN OTHERS para nunca bloquear INSERT)
- **CREATE** trigger `trg_robot_crosstalk_notify_urgent AFTER INSERT ON robot_crosstalk`
- **TRY** `ALTER DATABASE postgres SET app.supabase_url/service_role_key` em DO block — provavelmente falha por privilege; documenta TODO

### Mudanças Edge Functions (1 nova)
- **DEPLOY** `notify-admin-urgent` (verify_jwt=false; auth interna via service_role match)
  - FCM v1 paralelo via `Promise.allSettled`
  - Resend opcional (skip se `RESEND_API_KEY` missing)
  - Cleanup tokens FCM stale via DELETE em `admin_push_tokens`

### Mudanças Flutter (3 ficheiros)
| Ficheiro | Acção |
|---|---|
| `lib/services/admin_push_service.dart` | **NEW** — registerForAdmin + onTokenRefresh + setupDeepLinks |
| `lib/screens/admin/admin_crosstalk_screen.dart` | **EDIT** — botão Responder + dialog + chip admin |
| `lib/screens/admin/admin_dashboard_screen.dart` | **EDIT** — initState chama AdminPushService.registerForAdmin() + setupDeepLinks |
| `lib/main.dart` | **EDIT** — registar rota nomeada `/admin/crosstalk` |

### Riscos & mitigações

| Risco | Probabilidade | Mitigação |
|-------|---------------|-----------|
| `ALTER DATABASE` falha por privilege via MCP | **Alta** | Try/catch DO block + RAISE NOTICE; documentar TODO §41.8 BLOQUEANTE; não bloqueia execução |
| Trigger silent fail sem pg_net settings | **Alta** (esperado) | Gate explícito; INSERT nunca bloqueia; Edge Fn callable manual via curl service_role para teste |
| `RESEND_API_KEY` ausente | **Confirmado** | Skip graceful + log warning; FCM continua primário |
| FCM admin tokens vazios em deploy | **Alta** (1ª vez) | TODO §41.8 #4: admin abre app uma vez para registo |
| Quebrar `support-chatbot` v8 (CRÍTICO) | **Baixa** | NÃO toca Edge Fn (sha confirmado intacto) |
| Quebrar 21 skills | **Baixa** | NÃO toca `support_skills`; smoke S14 valida |
| Realtime `AdminCrosstalkScreen` regredir | **Baixa** | Apenas adiciona elementos UI; não toca subscription |
| Token refresh pattern duplica subscription | **Média** | Guard `_refreshSub ??=` para idempotência |
| Deep link route não registada | **Mitigado** | Adicionar `/admin/crosstalk` em main.dart routes |
| `device_info_plus` ausente | **Resolvido** | Usar `Platform.operatingSystem` fallback (já em dart:io) |

### Plano rollback (se algo correr mal em B)

**DB:**
```sql
DROP TRIGGER IF EXISTS trg_robot_crosstalk_notify_urgent ON robot_crosstalk;
DROP FUNCTION IF EXISTS public._notify_admin_urgent_trigger();
DROP FUNCTION IF EXISTS public.admin_respond_to_crosstalk(uuid, text);
DROP FUNCTION IF EXISTS public.admin_register_push_token(text, text, text);
DROP TABLE IF EXISTS public.admin_push_tokens CASCADE;
ALTER DATABASE postgres RESET app.supabase_url;
ALTER DATABASE postgres RESET app.service_role_key;
```

**Edge Fn:**
- Delete via Dashboard (`notify-admin-urgent` é nova; sem predecessor)

**Flutter:**
- `git revert <commit>` ou `git checkout HEAD -- <ficheiros>`
- Ficheiros impactados (4 ao todo)

### Análise transversal — features que poderiam ser afectadas
- ✅ `support-chatbot` (não toca)
- ✅ `analyze-conversations` (não toca)
- ✅ `dispatch-engine`, `notify-driver/client/partner` (não toca)
- ✅ Stripe, MBWay, Wallet, TOKENS (não toca)
- ✅ 21 skills + RAG 534 chunks (não toca)
- ✅ 4 RPCs crosstalk 5F (não toca; só adiciona 2 novos)
- ✅ `_anonymize_pii` helper 5F (não toca)
- ✅ `users.fcm_token` clientes/estafetas (não toca; tabela separada)
- ⚠️ `AdminCrosstalkScreen` — risco médio (apenas adiciona elementos; preserva filtros/realtime/banners)
- ⚠️ `AdminDashboardScreen` — risco baixo (initState ganha 2 chamadas idempotentes)
- ⚠️ `main.dart` routes — risco mínimo (adiciona 1 entrada)

---

## A6 — Skill identification

**Skill primária a invocar:** `ceo-ai` (decision engine; já invocada implicitamente).

**Skills secundárias relevantes na execução B:**
- Nenhuma skill custom directa. Tasks padrão: SQL migration via MCP `apply_migration`, Edge Fn deploy via `deploy_edge_function`, Flutter edits.

**Skills tocadas por regressão:**
- `ASK_ROBOT_B` v2 (5F-α) — verificar intacta (S19)
- 21 skills total — verificar count (S14)

---

## Próximos passos (Gate 2)

⛔ **STOP em A6.** Aguardo luz verde para arrancar Fase B.

Se aprovado, ordem de execução:
1. **B1** — migration via `apply_migration` (table + RPCs + trigger + try ALTER DATABASE)
2. **Smokes DB** S1-S5 (validar B1 antes de avançar)
3. **B2** — `notify-admin-urgent` Edge Fn deploy
4. **Smokes Edge Fn** S6-S8
5. **B3** — `AdminPushService` Flutter
6. **B4** — `AdminCrosstalkScreen` reply UI + dashboard initState + main routes
7. **Smokes Flutter** S9-S13 + flutter analyze
8. **Smokes regressão** S14-S21
9. **Commits granulares** (1 por bloco lógico)
10. **business_rules.md §41** (5F-β)
11. **TODO §41.8 manual Danilo** (`pg_net`, RESEND, abrir admin app)
12. **Sync Obsidian** (relatório final)

---

**Gerado por:** Opus 4.7 (1M context) · Sessão 5F-β/7 audit
