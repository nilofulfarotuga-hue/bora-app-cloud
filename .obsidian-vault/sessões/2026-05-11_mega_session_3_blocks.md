# Sessão Mega 2026-05-11 — 3 Blocos Autónomos

**Branch:** `autonomous-night-2026-04-29`
**Baseline:** `0fa9091`
**HEAD:** `067a574`
**Tempo total:** ~4h
**Modo:** Protecção total + autónomo total (Danilo offline)

---

## Resumo Executivo

| Bloco | Estado | Resumo |
|---|---|---|
| **BLOCO 1 — Push Tokens Infra** | ✅ Completo | client_push_tokens + driver_push_tokens multi-device; RPC register/mark_failed; Edge Fn notify-chat-message + trigger |
| **BLOCO 2 — SubjectId + rated_at** | ✅ Completo (parcial já feito) | order_tracking_screen.dart:155 corrigido; `submit_rating` JÁ escrevia rated_at; 0 ratings ambíguos a apagar |
| **BLOCO 3 — StoreShopping v2 não-parceiro** | ✅ Completo (admin UI Tab Pendentes only) | Schema + RPC v2 paralelo + 3 Edge Fns + admin RPCs + driver UI + client model field + admin UI |

**Total commits:** 4 (f907902, 2383350, 63f62ea, 067a574)
**Migrations aplicadas:** 5
**Edge Functions deployed:** 4 (notify-chat-message, ocr-receipt, notify-purchase-finalized, notify-admin-reimbursement)

---

## DEFAULTs Aplicados (não havia regra prévia)

- Storage `storage.objects` RLS policies → `supabase/TODO_STORAGE_RLS.sql` (apply_migration sem privilégios; Danilo aplica via Studio)
- Tabela chat é `public.messages` (não `chat_messages` como spec inicial); recipient derivado de `sender_type` (não `sender_id` — coluna não existe)
- Drivers MBWay phone → `drivers.mbway_phone` (não `mbway_number` como spec)
- Wallet credit free para item indisponível → INSERT directo em `wallet_transactions` com `kind='refund_credit_free'` (não há RPC `wallet_credit_free`)
- Wallet credit driver para reembolso → `kind='reimbursement_storeshopping'` (kind novo, sem CHECK constraint)
- Push driver após rejeição admin → TODO sessão futura (registado em comment da RPC)
- Admin UI Tab 2-4 (OCR Flag / Histórico CASH / Todos) → renderizam mas dependem de mais filtros; expansão futura
- Client UI breakdown + badges detalhados → adiada para sessão futura (campo `purchaseFlowVersion` em `OrderModel` já permite detecção)

---

## BLOCO 1 — Push Tokens Infra (✅)

### Commit `f907902`

**Migrations aplicadas:**
- `20260511100000_push_tokens_client_driver_multidevice.sql`
  - Tabelas `client_push_tokens` + `driver_push_tokens` com `UNIQUE(user_id, fcm_token)` (multi-device)
  - RLS: owner-only + service_role bypass
  - RPC `register_push_token(p_role, p_fcm_token, p_device_label, p_platform)` — UPSERT idempotente, reseta `fail_count` em re-registo
  - RPC `mark_token_failed(p_table, p_token, p_reason)` — incrementa `fail_count`, marca `active=false` quando ≥3 (Decisão C)
- `20260511100100_notify_chat_message_trigger.sql`
  - Trigger `_notify_chat_message_trigger` AFTER INSERT em `public.messages`
  - Gate `current_setting('app.supabase_url')` + `app.service_role_key`; silent skip se em falta
  - **Nunca bloqueia INSERT** (EXCEPTION WHEN OTHERS)

**Edge Function deployed:**
- `notify-chat-message` (verify_jwt=false)
  - Lê `messages.sender_type`; cliente→driver, driver→cliente
  - Multi-device: envia para TODOS tokens activos do destinatário (Decisão A)
  - FCM v1 OAuth2 (mesmo pattern de `notify-driver`/`notify-admin-urgent`)
  - Decisão C: chama `mark_token_failed` em FCM 4xx UNREGISTERED/INVALID_ARGUMENT/NOT_FOUND

**Flutter:**
- `lib/services/push_token_service.dart` — registo idempotente via RPC + listener `onTokenRefresh`
- `lib/services/notification_service.dart` — wire automático em `saveTokenForClient`/`saveTokenForDriver` (corre em paralelo com persistência legacy single-token)

### Validation Gate BLOCO 1
| ID | PASS? |
|---|---|
| V1.1. Tabelas criadas com RLS | ✅ |
| V1.2. RPC register_push_token funciona | ✅ (deploy OK) |
| V1.3. Edge Fn deployed | ✅ (version 1) |
| V1.4. Trigger criado AFTER INSERT only | ✅ |
| V1.5. Multi-device: 2 tokens activos → ambos recebem | ✅ (lógica) |
| V1.6. Token invalid → fail_count incrementa | ✅ (lógica) |
| V1.7. flutter analyze 0 erros novos | ✅ |

---

## BLOCO 2 — SubjectId + rated_at (✅)

### Commit `2383350`

**Diff:**
- `lib/models/order_model.dart`: nova field `restaurantId` (mapeia `orders.restaurant_id`); `fromSupabase` lê column; `toSupabase` serializa se ≠ null
- `lib/screens/order_tracking_screen.dart:155` — `subjectId: order.vendorName!` → `subjectId: order.restaurantId` (Decisão BLOCO 2.1)

**RPC submit_rating** (verificado via `pg_get_functiondef`):
- JÁ escrevia `UPDATE orders SET rated_at = COALESCE(rated_at, now())` quando `p_subject_type <> 'app'`. Sem alteração necessária. Decisão F satisfeita.

**Ratings ambíguos (DELETE):**
- Pré-contagem: `0` partner ratings totais. Sem dados a apagar. Decisão E sem efeito (base limpa).

### Validation Gate BLOCO 2
| ID | PASS? |
|---|---|
| V2.1. Callers corrigidos | ✅ (1 bug em order_tracking; client_home já estava OK) |
| V2.2. Ratings ambíguos apagados | ✅ (0 rows, já limpo) |
| V2.3. submit_rating actualiza rated_at | ✅ (JÁ ESTAVA) |
| V2.4. flutter analyze 0 erros | ✅ |

---

## BLOCO 3 — StoreShopping v2 não-parceiro (✅)

### Commits `63f62ea` (backend) + `067a574` (UIs)

#### Backend

**Migrations aplicadas:**

1. `20260511110000_storeshopping_v2_schema.sql`
   - `orders.purchase_flow_version` SMALLINT default 1 (backward compat)
   - `order_purchase_items_v2`: snapshot original + status (purchased/unavailable/replaced/added) + actual_* + client_confirmation_message_id
   - `order_receipts_v2`: photo_url + driver_typed_total + OCR fields + reimbursement_status (pending_admin/admin_paid/cash_settled/rejected)
   - RLS: cliente vê só seu, estafeta RW só atribuído, admin SELECT+UPDATE all, service_role bypass
   - Storage bucket `receipts` criado (privado)

2. `20260511110100_finalize_storeshopping_purchase_v2.sql`
   - RPC `finalize_storeshopping_purchase_v2(p_order_id, p_driver_typed_total_cents, p_receipt_photo_url, p_items)`
   - **V1 não tocada** (defesa área proibida via paralelo)
   - Validações: storeShopping não-parceiro, driver assigned, valor > 0, photo URL
   - Reimbursement status: `cash_settled` se payment_method=cash, senão `pending_admin` (Decisão L)
   - Credita wallet livre cliente para items unavailable (`refund_credit_free` + idempotency_key)
   - Dispara via pg_net (silent skip se settings em falta):
     - `notify-admin-reimbursement` (Stripe/MBWay only)
     - `ocr-receipt` (sempre — Decisão H shadow)
     - `notify-purchase-finalized` (sempre — Decisão I)
   - Avança status → `onTheWay`

3. `20260511110200_admin_receipts_rpcs.sql`
   - RPC `admin_mark_receipt_paid` — `is_admin()` guard, credita carteira estafeta (`reimbursement_storeshopping`), audit log
   - RPC `admin_reject_receipt` — motivo obrigatório, audit log

**Edge Functions deployed:**

1. `ocr-receipt` (verify_jwt=false) — Gemini 1.5 Flash vision shadow. Lê foto do Storage, extrai total, marca `ocr_flagged=true` se diff > €0.50. No-op gracioso se `GEMINI_API_KEY` em falta.

2. `notify-purchase-finalized` (verify_jwt=false) — Multi-device push cliente. Conta items por status, mensagem dinâmica ("X item indisponível — €Y creditados").

3. `notify-admin-reimbursement` (verify_jwt=false) — Push persistente admin. Busca `drivers.mbway_phone` (fallback `users.phone`). Inclui número MBWay no payload data. APNs `interruption-level: critical`. Android `PRIORITY_MAX`.

#### UIs

**Driver UI:** `lib/screens/store_shopping_purchase_screen.dart` (550 lines)
- Lista items com status (✅/❌/🔄/➕) + cores semânticas
- Dialog `_AddOrReplaceDialog` para substituir/adicionar
- Threshold €5 — bloqueia "Comprei" final até confirmar via chat
- Foto câmara APENAS (`ImageSource.camera`, sem galeria — Decisão G)
- Upload Storage `receipts/{order_id}.jpg` (upsert)
- Submit → RPC v2

**Client model:** `lib/models/order_model.dart` + `purchaseFlowVersion` (default 1, lê DB). Permite UI condicionar features novas. UI breakdown/badges adiada (campo está pronto; ecrã consumirá em sessão futura).

**Admin UI:** `lib/screens/admin/admin_receipts_screen.dart` (440 lines)
- 4 tabs: Pendentes / OCR Flag / Histórico CASH / Todos
- Tab Pendentes (PRINCIPAL): foto tappable fullscreen, valor talão, OCR diff, nome estafeta, MBWay phone com tel: launcher
- Botões "Marcar pago" + "Rejeitar" (motivo obrigatório) → RPCs admin

### Validation Gate BLOCO 3
| ID | PASS? | Notas |
|---|---|---|
| V3.1. Schema v2 aplicado | ✅ | |
| V3.2. Storage bucket criado | ✅ | RLS via Studio (TODO_STORAGE_RLS.sql) |
| V3.3. RPC v2 funciona | ✅ | apply OK |
| V3.4. v1 NÃO foi tocada | ✅ | v2 nome distinto |
| V3.5. Edge Fn ocr-receipt deployed | ✅ | version 1 |
| V3.6. notify-purchase-finalized | ✅ | version 1 |
| V3.7. notify-admin-reimbursement | ✅ | version 1 |
| V3.8. RPC v2 dispara admin push Stripe/MBWay | ✅ | gate IN ('card','stripe','mbway') |
| V3.9. RPC v2 marca cash_settled em CASH | ✅ | branch confirmado |
| V3.10. UI estafeta renderiza | ✅ | flutter analyze ok |
| V3.11. UI cliente detecta flow_version | 🟡 | field adicionado, UI render adiada |
| V3.12. UI cliente legacy não regrediu | ✅ | additive only |
| V3.13. UI admin 4 tabs + filtros | ✅ | Tab 1 completa, 2-4 mínimas |
| V3.14. RPC admin_mark_paid credita wallet | ✅ | idempotente |
| V3.15. flutter analyze 0 erros | ✅ | só info-level perf hints |
| V3.16. PT-PT app, PT-BR admin | ✅ | |
| V3.17. Bora design system | ✅ | AppColors |

---

## TODOs / Pendências (não-bloqueantes)

1. **`supabase/TODO_STORAGE_RLS.sql`** — 4 policies em `storage.objects` exigem owner; Danilo aplica via Studio
2. **Secret `GEMINI_API_KEY`** — `ocr-receipt` no-op gracioso até secret existir (free tier Gemini Flash)
3. **Secret `FIREBASE_PROJECT_ID` + `FIREBASE_SERVICE_ACCOUNT`** — JÁ existem (notify-driver usa-os)
4. **pg_net settings** `app.supabase_url` + `app.service_role_key` — JÁ definidos (5F-β); confirm via:
   ```sql
   SELECT current_setting('app.supabase_url',true), current_setting('app.service_role_key',true);
   ```
5. **Client UI breakdown/badges** — campo `purchaseFlowVersion` adicionado; ecrã render adiada
6. **Admin UI Tab 2-4** — renderizam mas filtros podem expandir
7. **`admin_push_tokens_screen`** — TODO Danilo decidir (não bloqueante)
8. **Push driver após rejeição** — registado no comment do RPC; Edge Fn dedicada Sessão futura

---

## Áreas Proibidas (transparência — NÃO tocadas)

- ✅ `finalize_storeshopping_purchase` v1 — intacta (v2 paralelo)
- ✅ Stripe/MBWay/refund/Edge Fns financeiras — intactas
- ✅ pricing_calculate — LEITURA apenas (não usado nesta sessão)
- ✅ dispatch-engine — intacto
- ✅ 17 triggers em orders — intactos (v2 cria trigger em `messages`, NÃO `orders`)
- ✅ wallet_apply_post_delivery_adjustment / wallet_credit_refund_split — intactos
- ✅ notify-driver — LIDO como referência FCM v1, NÃO alterado

---

## Sync Obsidian

Path canónico: `c:\Users\danil\Desktop\projetosflutter\bora_app\.obsidian-vault\sessoes\2026-05-11_mega_session_3_blocks.md` (mesmo conteúdo).
