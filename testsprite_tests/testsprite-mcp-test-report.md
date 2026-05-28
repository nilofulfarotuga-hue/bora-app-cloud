# TestSprite AI Testing Report (MCP) — Bora App

---

## 1️⃣ Document Metadata
- **Project Name:** bora_app
- **Date:** 2026-05-28
- **Prepared by:** TestSprite AI Team (orchestrated by Claude Sonnet 4.6 + CEO-AI skill)
- **Branch:** `autonomous-night-2026-04-29`
- **Test scope:** Backend (Supabase cloud at `https://ojykpzwqrtusfeakzrna.supabase.co`)
- **Total tests generated:** 8
- **Total tests passed:** 0
- **Total tests failed:** 8 (all blocked at authentication — see §4 Root Causes)
- **Credits consumed:** ~8 (from 550 starting balance)

---

## 2️⃣ Requirement Validation Summary

### Requirement: Order Lifecycle (Dispatch + Cancellation)

#### Test TC001 — Dispatch engine assigns driver correctly
- **Test Code:** [TC001](TC001_post_functions_v1_dispatch_engine_assigns_driver_correctly.py)
- **Endpoint:** `POST /functions/v1/dispatch-engine`
- **Status:** ❌ Failed
- **Error:** `No API key found in request — No "apikey" request header or url param was found.`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/6e3f2929-cd01-4076-a0d2-b03c358c2a96
- **Analysis:** Blocked at auth layer — TestSprite-generated test used placeholder Supabase anon key (`eyJhbGc...examplekey`) instead of real key. Test logic for FIFO + 200m batching rules never reached.

#### Test TC002 — Client cancel order before driver acceptance
- **Test Code:** [TC002](TC002_post_functions_v1_client_cancel_order_before_driver_acceptance.py)
- **Endpoint:** `POST /functions/v1/client-cancel-order`
- **Status:** ❌ Failed
- **Error:** `Invalid API key — Double check your Supabase anon or service_role API key.`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/0d7dd963-36bf-4d77-87ac-ddb71c275f9e
- **Analysis:** Same auth issue. Cancellation fee validation (€1 pre-dispatch, €2.50 post-accept, 100% post-pickup) not exercised.

### Requirement: Payments (Stripe + MB Way)

#### Test TC003 — Create payment intent validates amount and returns client_secret
- **Test Code:** [TC003](TC003_post_functions_v1_create_payment_intent_validates_amount_and_returns_client_secret.py)
- **Endpoint:** `POST /functions/v1/create-payment-intent`
- **Status:** ❌ Failed
- **Error:** `401 Unauthorized at /auth/v1/token?grant_type=password` (login step)
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/23427aca-8f5e-4700-bda8-9243809f1aa3
- **Analysis:** Test attempted to log in as `cliente@bora.app/123456` but this demo account exists only in the Flutter in-memory `AuthStore`, not in Supabase Auth. ±5% buffer validation and Stripe €0.50 minimum check not exercised.

### Requirement: Wallet & Tokens

#### Test TC004 — wallet_get_balance returns wallet details for authenticated user
- **Test Code:** [TC004](TC004_post_rest_v1_rpc_wallet_get_balance_returns_wallet_details_for_authenticated_user.py)
- **Endpoint:** `POST /rest/v1/rpc/wallet_get_balance`
- **Status:** ❌ Failed
- **Error:** `Invalid API key — Double check your Supabase anon or service_role API key.`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/77848e63-3665-4e77-912e-6be06ee59fe1
- **Analysis:** RPC call blocked at auth. Balance retrieval (free_cents + tokens_balance + last_transactions) not exercised.

### Requirement: Driver Operations

#### Test TC005 — accept_offer atomically assigns first eligible driver
- **Test Code:** [TC005](TC005_post_rest_v1_rpc_accept_offer_atomically_assigns_first_eligible_driver.py)
- **Endpoint:** `POST /rest/v1/rpc/accept_offer`
- **Status:** ❌ Failed
- **Error:** `401 Unauthorized at /auth/v1/token?grant_type=password`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/456878f2-65a0-448a-81dd-0ce5ad042cb8
- **Analysis:** Test attempted driver login with `910000000@driver.bora.app` — not registered in Supabase Auth (demo-only). Atomic offer-claim race condition (primeiro driver ganha) not exercised.

### Requirement: Partner Management

#### Test TC006 — register-partner validates IBAN and creates account
- **Test Code:** [TC006](TC006_post_functions_v1_register_partner_validates_iban_and_creates_account.py)
- **Endpoint:** `POST /functions/v1/register-partner`
- **Status:** ❌ Failed
- **Error:** `Expected 200 or 201, got 401` + `Invalid API key`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/c9fe99fb-d781-4e74-b0fe-02496309ac01
- **Analysis:** IBAN PT+21 dígitos validation (BUG-PARTNER-IBAN fix em 2026-05-26) não exercitada — bloqueado em apikey header missing.

### Requirement: Notifications

#### Test TC007 — notify-client sends FCM and email fallback
- **Test Code:** [TC007](TC007_post_functions_v1_notify_client_sends_fcm_and_email_fallback.py)
- **Endpoint:** `POST /functions/v1/notify-client`
- **Status:** ❌ Failed
- **Error:** `Signup failed: 401 — Invalid API key`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/1e9cfcd9-37da-4282-8587-3c7532f7fc44
- **Analysis:** FCM delivery + email fallback path not exercised. notify-client requires service_role JWT which test couldn't obtain.

### Requirement: RLS Security

#### Test TC008 — GET /rest/v1/orders returns only client orders (RLS)
- **Test Code:** [TC008](TC008_get_rest_v1_orders_returns_only_client_orders_due_to_rls.py)
- **Endpoint:** `GET /rest/v1/orders`
- **Status:** ❌ Failed
- **Error:** `401 Unauthorized at /auth/v1/token`
- **Visualization:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/3c398c8c-c8b8-41e1-9aa2-294171ad8461
- **Analysis:** RLS verification (cliente A não vê orders de cliente B) — teste fundamental de segurança — não exercitado.

---

## 3️⃣ Coverage & Matching Metrics

- **0.00%** of tests passed (0 / 8)

| Requirement | Total Tests | ✅ Passed | ❌ Failed |
|---|---|---|---|
| Order Lifecycle (Dispatch + Cancellation) | 2 | 0 | 2 |
| Payments (Stripe + MB Way) | 1 | 0 | 1 |
| Wallet & Tokens | 1 | 0 | 1 |
| Driver Operations | 1 | 0 | 1 |
| Partner Management | 1 | 0 | 1 |
| Notifications | 1 | 0 | 1 |
| RLS Security | 1 | 0 | 1 |
| **TOTAL** | **8** | **0** | **8** |

**Coverage gap:** Cobertura funcional efectiva = 0%. Cobertura de superfície (endpoints visados pelo plano) = 8 funcionalidades de backend × 1 caso cada.

---

## 4️⃣ Key Gaps / Risks

### Root cause 1: Supabase anon key não foi entregue ao TestSprite
- **Sintoma:** 8/8 testes falharam com `No apikey request header` / `Invalid API key`.
- **Causa:** O test runner gerado pelo TestSprite usa placeholder `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.examplekey` em vez do anon key real (`SUPABASE_ANON_KEY`). Eu não inclui o anon key no `additionalInstruction` ao invocar `generateCodeAndExecute`.
- **Fix:** Re-correr passando `additionalInstruction` com `SUPABASE_ANON_KEY=eyJ...real...` e o `SUPABASE_URL`. Está no `.env` do projecto (gitignored) — não pude expor automaticamente.

### Root cause 2: Demo accounts são in-memory only no Flutter
- **Sintoma:** Login com `cliente@bora.app/123456` e `910000000@driver.bora.app/123456` devolveu HTTP 401.
- **Causa:** Estas contas vivem em `lib/auth/auth_store.dart` no `_clientsByEmail` / `_driversByPhone` — não estão em `auth.users` no Supabase cloud. Foram mencionadas no PRD (`testsprite-prd.md` §1.5) como "Sempre disponíveis offline".
- **Risco:** A documentação induz em erro — TestSprite (e qualquer cliente HTTP externo) não consegue fazer login com estas credenciais.
- **Fix:** Ou (a) criar utilizadores reais de teste no Supabase Auth (e.g. `test-client@bora.app`, `test-driver@bora.app`) e documentá-los como "fixtures para testes externos"; ou (b) adicionar nota explícita no PRD que demo accounts são in-app only.

### Risk 3: Testes não cobriram regras de negócio críticas
Mesmo com auth resolvida, **8 testes em 1 caso cada** não cobre:
- ❌ Stripe webhook idempotency (BUG-MN-004 cap + idempotency key pendente).
- ❌ orders_financial_lock trigger (imutabilidade financeira pós-criação).
- ❌ Cancelamento com motivo (cancel-order-with-choice — falta TC).
- ❌ Token expiry (60 dias) e idempotency UNIQUE(source_order_id, role).
- ❌ Batching rules — partner max 2 / non-partner max 3 / logistics nunca batched.
- ❌ Refund 80% wallet + 20% tokens conversion.
- ❌ Bag fee €0.30 restaurante / €0.10 mercado (BUG-MN-015 fix).
- ❌ Trigger `protect_admin_app_role` (admin role imutável).
- ❌ Stripe €0.50 minimum + ±5% buffer.

### Risk 4: Plano de teste enviesado para happy-path
Os 8 testes gerados são todos "verifica que X funciona". Faltam **negative tests** para:
- Pagar amount inflado vs `payment_buffer_total`.
- Race condition double-accept em `accept_offer`.
- Insert order com `user_id` de outro user (RLS bypass attempt).
- Update `profiles.role` directamente (trigger reversion).
- Refund duplicado (idempotency).

### Risk 5: Custo arquitectural — TestSprite assume backend HTTP local
TestSprite foi desenhado para Next.js/Vite/Express apps. O Bora App tem:
- Cliente: Flutter mobile (não testável por TestSprite Python runner).
- Backend: Supabase cloud (testável apenas se anon key + utilizadores reais).
- Realtime: WebSocket — não suportado pelos testes Python gerados.
- Push FCM / CallKit / Stripe MB Way — requerem device físico.

**Recomendação:** Para o Bora App, considerar alternativas complementares:
- **Postman / Newman collections** para Edge Functions + RPCs (mais directo).
- **Supabase pg_tap** para RLS policies (test in-database).
- **Flutter integration_test** para fluxos UI cliente/driver.
- TestSprite tem valor para **regression** de Edge Functions HTTP, mas só com:
  1. Anon key real entregue.
  2. Utilizadores reais de teste em `auth.users`.
  3. Cleanup automático após cada test run (caso contrário acumula lixo na DB prod).

---

## 5️⃣ Reproduce / Re-run

Para correr novamente:

```bash
# 1. Garantir API_KEY TestSprite carregado (env ou config)
$env:API_KEY = "sk-user-..."

# 2. Verificar config em testsprite_tests/tmp/config.json:
#    "localEndpoint": "https://ojykpzwqrtusfeakzrna.supabase.co"

# 3. Garantir prd_files e code_summary preenchidos em testsprite_tests/tmp/

# 4. Correr CLI
cd C:/Users/danil/Desktop/projetosflutter/bora_app
testsprite-mcp-plugin generateCodeAndExecute
```

**Antes de re-correr deve fazer-se:**
1. Adicionar `SUPABASE_ANON_KEY=eyJ...real_key...` ao `additionalInstruction`.
2. Criar utilizadores fixture em `auth.users` (ex. `test-client@bora.app` / `test-driver@bora.app` com password forte).
3. Pôr os fixtures no PRD em vez dos demo accounts in-memory.
4. Considerar uso de Supabase branch (`mcp__supabase__create_branch`) para isolar a DB de teste da prod.

---

**Fim do relatório.**
