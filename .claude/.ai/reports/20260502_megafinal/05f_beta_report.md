# 5F-β REPORT — Push Admin Urgente + Reply UI + Email

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Pré-requisito:** 5F-α completo (commit `108b60b`)
**Duração efectiva:** ~3h (audit + execução)
**Estado:** ✅ Deploy completo. ⏸️ Activação real depende de configs manuais Danilo.

---

## Componentes entregues (5)

### 1. DB migration (`20260506_5f_beta_b1_admin_push_infra`)

✅ Aplicado via MCP `apply_migration`.

**Criados:**
- Tabela `public.admin_push_tokens` (8 cols, RLS, 2 policies, 2 indexes)
- RPC `public.admin_register_push_token(text, text, text)` SECURITY DEFINER
- RPC `public.admin_respond_to_crosstalk(uuid, text)` SECURITY DEFINER
- Função trigger `public._notify_admin_urgent_trigger()` SECURITY DEFINER
- Trigger `trg_robot_crosstalk_notify_urgent` AFTER INSERT em `robot_crosstalk`

**Tentativa `ALTER DATABASE pg_net`:** falhou por privilege (esperado).
Documentado como TODO §41.8 #1 BLOQUEANTE.

### 2. Edge Function `notify-admin-urgent` (v1, ACTIVE)

✅ Deploy via MCP `deploy_edge_function`.
- `verify_jwt: false` (auth interna por service_role match)
- Pattern FCM HTTP v1 + OAuth2 Service Account JWT (consistente com `notify-driver`)
- Cleanup tokens stale (`UNREGISTERED`/`INVALID_ARGUMENT`) → DELETE
- Email Resend opcional (skip silent se key missing)
- SHA: `d7d0ac6deb95a0e34bc4ac98d9d4bc5073bfd33455c7aad87cfba90c5723f71f`

### 3. Flutter `AdminPushService`

✅ Novo ficheiro `lib/services/admin_push_service.dart`.
- Reusa `NotificationService.instance.fcmToken` (sem duplicar permission)
- Listener `onTokenRefresh` idempotente
- Deep links `/admin/crosstalk` em foreground/background/cold-start
- `device_label` via `Platform.operatingSystem` (sem `device_info_plus` dep)

### 4. Flutter UI updates

✅ **AdminCrosstalkScreen** (`lib/screens/admin/admin_crosstalk_screen.dart`):
- Botão "💬 Responder" em cards `status='pending' AND direction='a_to_b'`
- `_openReplyDialog` com TextField multiline + validator
- Mapeamento de erros RPC (NOT_ADMIN, ANSWER_REQUIRED, CROSSTALK_NOT_FOUND_OR_NOT_PENDING)
- Chip distintivo "✋ Respondido por admin" vs "🤖 Respondido por Robô B/A"
- Banner topo actualizado: "Reply UI activa (5F-β)"

✅ **AdminDashboardScreen** (`lib/screens/admin/admin_dashboard_screen.dart`):
- Import `AdminPushService`
- `WidgetsBinding.addPostFrameCallback` em `initState` chama
  `AdminPushService.registerForAdmin() + setupDeepLinks(context)`

✅ **main.dart** (`lib/main.dart`):
- Import `AdminCrosstalkScreen`
- Rota nomeada nova `/admin/crosstalk` para deep link push

### 5. Documentação

✅ `business_rules.md` §41 (10 sub-secções: §41.1-§41.10)
✅ `sessao_5f_beta_pending.md` (4 TODOs manuais Danilo + smoke teste)
✅ `05f_beta_report.md` (este ficheiro)
✅ Sync Obsidian `sessões/05f_beta_prompt.md`

---

## Smoke results

### DB (S1-S5) ✅
| Test | Result |
|------|--------|
| S1 table + RLS + 2 policies + 4 indexes | ✅ |
| S2 RPC `admin_register_push_token` + grants (authenticated yes, anon revoked) | ✅ |
| S3 RPC `admin_respond_to_crosstalk` + grant authenticated | ✅ |
| S4 trigger function + trigger registered | ✅ |
| S5 pg_net url + key | MISSING (esperado — TODO §41.8 #1) |

### Edge Fn (S6-S8) ✅
| Test | Result |
|------|--------|
| S6 ACTIVE (deploy v1) | ✅ |
| S7 service_role 200 | DEFERIDO — testado quando trigger real disparar |
| S8 anon → 403 | ✅ (3 cenários: anon key, no auth, wrong key) |

### Flutter (S9-S13) ✅
| Test | Result |
|------|--------|
| S9 AdminPushService compila + analyze 0 issues novos | ✅ |
| S10 AdminCrosstalkScreen botão Responder visível | ✅ (gate `pending+a_to_b`) |
| S11 Dialog responder + SnackBar | ✅ |
| S12 Chip "respondido por admin" | ✅ |
| S13 `flutter analyze`: **55 issues** (baseline 55) | ✅ ZERO regressões |

### Regressão (S14-S21) ✅
| Test | Result |
|------|--------|
| S14 21 skills active | ✅ (3 escalate + 11 RO + 7 write_shadow) |
| S15 RAG 534 chunks (`support_knowledge_chunks`) | ✅ |
| S16 RPCs crosstalk 5F (`agent_ask_robot_b` 5 args, `admin_list_crosstalk` 4 args, `robot_b_respond`, `agent_propose_action`) | ✅ |
| S17 `support-chatbot` v8 sha `e351ab62...` NÃO tocado | ✅ |
| S18 5E `agent_propose_action` exists | ✅ |
| S19 `urgency` text + `ASK_ROBOT_B` v2 active | ✅ |
| S20 `admin_resolve_ticket` + `skill_suggestions` + `support_pending_actions` | ✅ |
| S21 `final_total` numeric (BUG 35) | ✅ |

---

## TODOs manuais Danilo (4 acções pós-deploy)

⚠️ **Detalhes em `sessao_5f_beta_pending.md`**

1. **`pg_net` settings** (BLOQUEANTE — trigger inactivo até config) —
   `ALTER DATABASE postgres SET app.supabase_url/service_role_key`
   no Dashboard SQL editor + `SELECT pg_reload_conf()`.
2. **`RESEND_API_KEY`** (opcional, só email) —
   `supabase secrets set RESEND_API_KEY=...`
3. **Domínio email Resend** — confirmar `noreply@boraapp.com` verificado.
4. **Admin abrir admin app** uma vez para registar 1º FCM token.

---

## Bugs colaterais

Nenhum bug novo encontrado.
- BUG 35 (final_total numeric) — preservado ✅
- BUG 38 (Sessão 7 reservado) — não tocado
- BUG 39 (Sessão 7 reservado) — não tocado

---

## Não-tocado (preservado intacto)

- ✅ `support-chatbot` Edge Fn v8 sha `e351ab62...`
- ✅ 21 skills active (count + activos)
- ✅ `robot_crosstalk` schema (apenas adicionado trigger; coluna `urgency` 5F-α intacta)
- ✅ 4 RPCs crosstalk 5F/5F-α (`agent_ask_robot_b` 5 args, `admin_list_crosstalk` 4 args, `robot_b_respond`, `agent_propose_action`)
- ✅ `_anonymize_pii` helper (5F)
- ✅ `users.fcm_token` (clientes/estafetas não afectados)
- ✅ `push_broadcasts` table (genérico)
- ✅ 6 RPCs agente IA + `admin_resolve_ticket`
- ✅ `analyze-conversations` Edge Fn
- ✅ `skill_suggestions` + RPCs 5D/5E
- ✅ `support_pending_actions` + RPCs shadow 5B
- ✅ Dispatch engine, pricing, Stripe, wallet, TOKENS
- ✅ Reservation RPCs + cancel Edge Fns

---

## Decisões arquitecturais notáveis

1. **FCM HTTP v1 + OAuth2** (não legacy `FCM_SERVER_KEY`) — alinhado com `notify-driver`
2. **`AdminPushService` thin wrapper** sobre `NotificationService.instance.fcmToken` (singleton reuse)
3. **Tabela própria** `admin_push_tokens` (vs reuse `users.fcm_token`) — multi-device admin justifica
4. **Trigger silent skip** quando `pg_net` MISSING (padrão 5D) — aceitável
5. **Email Resend opcional** — graceful skip mantém push funcional
6. **Rota nomeada `/admin/crosstalk`** — deep link push em vez de Navigator.push global key
7. **Sem `device_info_plus`** — `Platform.operatingSystem` suficiente para `device_label`

---

## Próximas sessões

- **5G** — Painel admin inbox propostas avançado (~3h)
- **Sessão 6** — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor (~6-8h, BUG 38/39)

---

**Gerado por:** Opus 4.7 (1M context) · Sessão 5F-β/7 deploy
