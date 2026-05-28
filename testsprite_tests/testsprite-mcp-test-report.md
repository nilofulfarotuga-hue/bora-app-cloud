# TestSprite AI Testing Report (MCP) — Bora App
> **Run 2 — credenciais reais + bcrypt fix em auth.users**

---

## 1️⃣ Document Metadata
- **Project Name:** bora_app
- **Date:** 2026-05-28 (Run 2)
- **Branch:** `autonomous-night-2026-04-29`
- **Test scope:** Backend (Supabase cloud `https://ojykpzwqrtusfeakzrna.supabase.co`)
- **Tests:** 8 generated · **1 PASSED** ✅ · **7 FAILED** ❌

### Mudanças desde Run 1
1. **Anon key real** injectada nos 8 ficheiros `TC*.py`.
2. **Credenciais reais:** `cliente@bora.app/123456` → `test-client@bora.app/TestBora2026!`.
3. **Headers `apikey` adicionados** nos 8 ficheiros (faltavam em 5).
4. **Fix em `auth.users`:** os utilizadores `test-client` e `test-driver` tinham sido criados via SQL INSERT directo sem `encrypted_password` bcrypted, sem `aud='authenticated'`, sem `instance_id`, sem `confirmation_token=''`, etc. GoTrue rejeitava login com `400 invalid_credentials`. Corrigido via UPDATE com `crypt('TestBora2026!', gen_salt('bf'))` + restantes campos obrigatórios. Login agora devolve 200 + JWT válido.

---

## 2️⃣ Requirement Validation Summary

### ✅ TC004 — wallet_get_balance returns wallet details
- **Endpoint:** `POST /rest/v1/rpc/wallet_get_balance`
- **Status:** **PASSED**
- **O que validou:** RPC autenticada devolve `free_cents`, `tokens_balance`, `last_transactions`. Cliente vê próprio saldo. Request sem auth devolve 401.
- **Análise:** Primeiro teste 100% funcional end-to-end contra produção. Auth + RPC + RLS working.

### ❌ TC001 — dispatch-engine assigns driver
- **Endpoint:** `POST /functions/v1/dispatch-engine` (precedido de `POST /rest/v1/orders`)
- **Erro:** `PGRST204 — Could not find the 'currency' column of 'orders' in the schema cache`
- **Causa-raiz:** **bug nos testes gerados** — payload `{"status":"created","total_cents":1000,"currency":"EUR","items":...}` inclui coluna `currency` que **não existe** em `public.orders`. Schema real usa total noutra coluna e moeda implícita EUR. PostgREST devolve 400 antes de chegar ao dispatch-engine.

### ❌ TC002 — client-cancel-order before driver acceptance
- **Endpoint:** `POST /functions/v1/client-cancel-order`
- **Erro:** Mesmo `PGRST204 currency column not found`.
- **Causa-raiz:** Mesmo bug de payload em TC001.

### ❌ TC003 — create-payment-intent validates amount
- **Endpoint:** `POST /functions/v1/create-payment-intent`
- **Erro:** `400 Bad Request` em `POST /rest/v1/orders` (pré-step).
- **Causa-raiz:** Payload inclui colunas `amount` (deveria ser noutra coluna) e `currency` (não existe). Bug nos testes gerados.

### ❌ TC005 — accept_offer atomically assigns first driver
- **Endpoint:** `POST /rest/v1/rpc/accept_offer`
- **Erro:** `403 Forbidden` em `POST /rest/v1/orders` (pré-step).
- **Causa-raiz:** **Real finding** — RLS bloqueia INSERT. Payload `{"status":"created"}` não inclui `user_id`. A policy `WITH CHECK (user_id = auth.uid())` falha quando `user_id` é NULL. Para corrigir o teste seria preciso adicionar `user_id` do JWT ao payload, OU adicionar default na DB (`user_id default auth.uid()`).

### ❌ TC006 — register-partner validates IBAN
- **Endpoint:** `POST /functions/v1/register-partner`
- **Erro:** `Expected 200 or 201, got 401`
- **Causa-raiz:** **Investigar** — Edge Function rejeita mesmo com `apikey: ANON_KEY` + `Authorization: Bearer ANON_KEY`. Possíveis causas:
  - A função tem `verify_jwt=true` (default em Supabase) e exige JWT de utilizador, não anon.
  - Headers exigem formato específico não documentado em `testsprite-api-docs.md`.
  - **Pendente:** confirmar config da Edge Function em prod (`mcp__supabase__get_edge_function register-partner`).

### ❌ TC007 — notify-client sends FCM
- **Endpoint:** `POST /functions/v1/notify-client`
- **Erro:** `400 bad_json — Could not parse request body as JSON: unexpected end of JSON input` durante login pré-step.
- **Causa-raiz:** **Bug no teste gerado** — login usa `data=login_payload` (form-encoded) em vez de `json=`. `requests.post(..., data=dict)` envia `application/x-www-form-urlencoded` mas Supabase Auth exige `application/json` para password grant. Linha 53 do TC007 precisa `data=` → `json=`.

### ❌ TC008 — GET /rest/v1/orders RLS isolation
- **Endpoint:** `GET /rest/v1/orders`
- **Erro:** `400 Bad Request` em `POST /rest/v1/orders` (pré-step).
- **Causa-raiz:** Mesmo bug `currency`/`total_cents` payload.

---

## 3️⃣ Coverage & Matching Metrics

- **12.5%** of tests passed (1 / 8) — **+12.5pp vs Run 1 (0%)**

| Requirement | Tests | ✅ | ❌ | Notas |
|---|---|---|---|---|
| Order Lifecycle | 2 | 0 | 2 | Payload `currency` inválido |
| Payments | 1 | 0 | 1 | Bloqueado em pré-criação de order |
| Wallet & Tokens | 1 | **1** | 0 | ✅ |
| Driver Operations | 1 | 0 | 1 | RLS `user_id` missing |
| Partner Management | 1 | 0 | 1 | 401 Edge Function (investigar) |
| Notifications | 1 | 0 | 1 | Bug teste (form-data login) |
| RLS Security | 1 | 0 | 1 | Bloqueado em pré-criação |
| **TOTAL** | **8** | **1** | **7** | |

---

## 4️⃣ Key Gaps / Risks

### Categorias de falhas

**A. Bugs nos testes TestSprite-gerados (4/7 falhas):**
- TC001, TC002, TC003, TC008 usam payload com coluna `currency` que não existe em `public.orders`.
- TC007 usa `data=` em vez de `json=` no login.
- **Fix:** Editar manualmente os payloads para reflectir o schema real (`amount_cents` em vez de `total_cents`+`currency`, etc.) OU melhorar o `code_summary.yaml` para TestSprite com schema PostgreSQL completo.

**B. Test infrastructure gaps (2/7 falhas):**
- TC005 não passa `user_id` no INSERT — RLS bloqueia 403. Sintoma de teste mal gerado.
- TC006 falha 401 em endpoint anon. Pode revelar:
  - **Bug real:** `register-partner` está com `verify_jwt=true` mas deveria ser `false` (utilizador novo ainda não tem JWT).
  - OU teste está a enviar Authorization que não é válido.

**C. ✅ Validações funcionais reais:**
- **TC004 wallet_get_balance:** Confirma que auth + RPC + RLS estão a funcionar end-to-end em produção para utilizador autenticado real.

### Acções aplicadas em produção (auth.users)
- `UPDATE auth.users SET encrypted_password=crypt(...), aud='authenticated', instance_id=..., confirmation_token='', ... WHERE email IN (...)` — necessário para test-client@bora.app e test-driver@bora.app funcionarem como contas de teste reais.
- Side-effect: estes utilizadores agora são fixtures reproduzíveis para qualquer integração futura (Postman, Newman, etc.). Tagged com `raw_user_meta_data.bora_role`.

### Cobertura ainda em falta (5 áreas críticas não cobertas pelos 8 testes)
- Stripe webhook idempotency / payment_intent.succeeded handler.
- Cancelamento fee tiers (€1 / €2.50 / 100%).
- orders_financial_lock trigger.
- Batching rules (logistics nunca / partner 2 / non-partner 3).
- Refund 80/20 wallet+tokens.

### Próximos passos recomendados
1. **Editar manualmente os 4 ficheiros TC com bug de payload** para corresponder ao schema real. Re-correr → expectativa de 4-5 PASS.
2. **Investigar 401 em register-partner**: `mcp__supabase__get_edge_function register-partner` para ver config.
3. **Adicionar `user_id` default em orders**: `ALTER TABLE orders ALTER COLUMN user_id SET DEFAULT auth.uid()` reduziria a fricção em testes futuros.
4. **Re-gerar test plan via TestSprite com PRD melhorado**: pôr schema real de `orders` no `code_summary.yaml` para evitar payloads inválidos.

---

**Fim do relatório Run 2.**
