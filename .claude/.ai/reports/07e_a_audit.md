# Sessão 7E-A — Framework E2E Tests — AUDIT (Fase A)

**Data:** 2026-05-07
**Branch:** `autonomous-night-2026-04-29`
**Sub-sessão:** 7E-A (framework + fixtures, 4-6h)
**Sub-sessões seguintes:** 7E-B, 7E-C, 7E-D (lançadas após 7E-A merge)

---

## Sumário executivo

Objectivo da Sessão 7E-A: criar a **infra-estrutura mínima** para uma suite de testes E2E em Python que exercite os fluxos críticos do Bora App contra a Supabase real (com mocks granulares de Stripe/FCM/Gemini). Esta sub-sessão **não escreve testes funcionais** — apenas o esqueleto, fixtures idempotentes 3+3+3, helpers básicos de auth, seed, cleanup e 3 smokes independentes de seed.

**Princípios:**
1. **Single source de credenciais** — service_role_key reutilizado de `scripts/rag/.env` (Decisão #1, abaixo).
2. **Markers obrigatórios** — todo o conteúdo de teste tem marker `is_test=true` ou prefixo `e2e_*@boraapp.test` / `E2E_TEST_*` (não tocar em produção).
3. **Cleanup soft** — `cleanup.py` apaga só registos com markers; modo dry-run por defeito.
4. **Mocks DEFAULT** — Stripe via SQL UPDATE, FCM via logger em memória, Gemini via respostas hardcoded.
5. **Cross-platform** — runner `run_all.sh` corre em Windows (Git Bash/WSL) e Linux/macOS.

**Estado actual (pré-7E-A):**
- ✅ `is_test_order` BOOLEAN existe em `orders` (migration `20260505060000`)
- ❌ `scripts/e2e/` **não existe** — slate limpo
- ❌ Sem suite Flutter (`flutter test` ou `dart test`) no projecto
- ✅ `scripts/rag/.env` contém `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (verificado)
- ✅ Supabase project `ojykpzwqrtusfeakzrna` (EU-West-1)

---

## Decisões arquitecturais

| # | Decisão | Justificação | Trade-off aceite |
|---|---------|--------------|------------------|
| 1 | Service-role key reusada de `scripts/rag/.env` via `load_dotenv("../rag/.env")` em `helpers/auth.py`. **Nunca copiar para `.env.test` nem `.env.test.example`**. | DRY: uma só fonte de credenciais. Aprovado pelo Danilo. | Rotação da chave RAG parte E2E. Mitigação: `helpers/auth.py` falha rápido com mensagem clara se a chave estiver ausente. |
| 2 | Pinned versions: `pytest==8.3.4`, `supabase==2.10.0`, `httpx==0.28.1`, `python-dotenv==1.0.1`. | Evita drift silencioso entre máquinas; lock determinístico para CI futuro. | Updates manuais quando libs evoluem. |
| 3 | Mock Stripe **default = SQL UPDATE** (`payment_status='paid'`, `paid_at=NOW()`). Nunca chamar Stripe live em CI. | Webhook real não é determinístico; testes precisam ser idempotentes. | Não cobre integração real Stripe webhook → 7E-Flutter futuro fará isso. |
| 4 | Mock FCM **default = `push_log` em memória** (lista mutável em `helpers/mocks.py`). | Push real exige device + Firebase setup; complexidade > valor em E2E backend. | Não testa entrega real. |
| 5 | Mock Gemini **default = respostas hardcoded** (dict por skill_id). Opt-in via env `E2E_GEMINI_LIVE=1`. | Gemini quota limitada + flaky em CI. | Cobertura semântica fica para tests dedicados ao Robô A/B. |
| 6 | Mock dispatch-engine **default = chamada directa a RPC `accept_dispatch_offer`**. | Edge Function dispatch corre por pg_cron — não determinístico em E2E. | Não testa o cron orchestration → coberto por monitoring prod. |
| 7 | Cleanup escopo **APENAS markers E2E** (`is_test=true` em orders/users, prefixo `E2E_TEST_` em restaurants, dominio `@boraapp.test` em users). | Garantia formal: cleanup nunca toca dados produção. | Manual periódico se markers escapam. |
| 8 | Fixtures **idempotentes** — re-run não duplica, faz `UPSERT` por `email`/`phone`/`name`. | Permite re-correr `seed.py` sem cleanup intermediário. | Pequena overhead por SELECT antes de INSERT. |
| 9 | Smoke B9 **independente de seed** (3 testes triviais). | Confirma que o boot do framework funciona antes de qualquer fixture; falha rápida em problemas de credenciais. | Não cobre fluxos de domínio (esses ficam para 7E-B). |

---

## Inventário do sistema sob teste

### Tabelas críticas (snapshot 2026-05-07)
- `restaurants` (TEXT id, legado), `products` (TEXT id), `orders` (TEXT id) — ver §32.1 BUG 39 docs
- `drivers`, `driver_locations`, `client_wallets`, `wallet_transactions`
- `ledger_entries` (append-only via trigger), `ratings` (UUID id, com `is_private`/`stars`/`subject_type`)
- `pending_charges`, `partner_reservation_payouts`, `restaurant_menu_credits`
- `support_pending_actions`, `robot_crosstalk`, `complaints`
- `is_test_order` BOOLEAN existe em `orders` (marker formal)

### RPCs (38+ identificadas em migrations)
**Críticos para E2E:**
- `add_tokens(user_id, amount, reason, order_id)` — §32.4 (consumir/awardar)
- `consume_tokens(...)` — disponível
- `submit_rating(p_order_id, p_subject_type, p_subject_id, p_stars, p_tags, p_comment, p_is_private)` — Sessão 6
- `accept_dispatch_offer(p_order_id, p_driver_id)` — fluxo dispatch
- `apply_driver_cash_settlement` (trigger), `apply_order_financial_split` (trigger)
- `auto_payout_pending`, `recompute_user_balance`
- `admin_dashboard_metrics`, `admin_set_product_availability`, `admin_update_product_price`
- `search_products`, `bora_normalize`

**Não testar directamente em 7E-A** (cobertos em sub-sessões):
- `fn_dispatch_on_calling_driver`, `bora_dispatch_maintenance` — pg_cron
- `fn_award_tokens_on_delivery`, `fn_award_cashback` — auto-trigger

### Triggers (25 identificados)
**Append-only/guards (testar em 7E-D RLS/lifecycle):**
- `ledger_no_update`, `ledger_no_delete` — append-only ledger
- `trg_protect_admin_bora_role`, `trg_protect_admin_app_role` — admin metadata
- `orders_storeshopping_pickup_guard` — store-shopping flow
- `trg_enforce_refund_cap` — refund cap (Sessão final consolidated)

**Auto-mutadores (cobrir em 7E-B/C):**
- `orders_financial_split` (depois INSERT) — split fees automatically
- `orders_cash_settlement` (depois UPDATE delivered) — driver_balance
- `orders_post_to_ledger` (depois INSERT) — ledger entries
- `orders_set_delivered_at`, `trg_award_tokens_on_delivery`, `trg_award_cashback`

### Edge Functions (26 funções)
**Verify_jwt = false (testáveis sem auth):**
- `create-payment-intent`, `create-mbway-payment-intent` — mock Stripe via SQL após call

**Verify_jwt = true (testar com user JWT):**
- `client-cancel-order`, `cancel-order-with-choice`, `notify-partner`, `notify-driver`, `notify-client`
- `support-chatbot`, `support-submit-ticket`, `support-password-reset`
- `analyze-conversations`, `reindex-knowledge`, `dispatch-engine`
- `confirm-mbway-payment`, `finalize-order-from-intent`
- `upload-avatar`, `delete-account`, `update-products`
- `notify-admin-urgent`, `notify-partner-low-rating`

**Verify_jwt = true + service_role check (admin-only):**
- `admin-cancel-order`, `admin-force-driver-logout`
- `refund`, `charge-extra`, `execute-cancellation`

**Webhook (não JWT, signature Stripe):**
- `stripe-webhook` — não testável directo; mock via SQL

### RLS policies
- **63 policies** identificadas. Cobertura formal em **7E-D Grupo 13** (5 tests T60-T64).

---

## Matriz §1-§44 → tests E2E

| § | Tema | Fase | Tests planeados | Cobertura via |
|---|------|------|----------------|---------------|
| §1-§5 | Modelos / OrderStatus / Roles | 7E-A smoke + 7E-B | T01 baseline | helpers/auth + seed |
| §6-§10 | Fluxo dispatch / DriverCapacity | 7E-B Grupo 2 | T09-T13 | mock dispatch RPC |
| §11-§14 | Pricing / fees / commission | 7E-B Grupo 1 | T01-T08 | PricingService oracle vs DB |
| §15-§18 | Realtime / OrderStore | — | (UI) | TODO 7E-Flutter |
| §19-§22 | Payments (Stripe/MBWay/Cash) | 7E-B + 7E-C | parte refund T51-T53 | mock Stripe SQL |
| §23-§24 | Notifications (FCM) | indirect | mock FCM logger | helpers/mocks.push_log |
| §25-§27 | Wallet / saldo / topup | 7E-B Grupo 4 | T19-T24 | helpers/wallet |
| §28 | Wallet saldo negativo | 7E-B T22-T24 | 3 cenários split | RPC `create_order` ordem ops |
| §29 | Housekeeping NUMERIC + trg_zz | 7E-D guards | T67 | inspecção schema |
| §30 | Knowledge Infra | n/a (docs) | — | — |
| §31 | Suporte chatbot | 7E-D Grupo 11 | T54-T57 | mock Gemini |
| §32 | Architectural Debt (UUID/TEXT) | 7E-D T67 | smoke `casts` | inspecção orders.id |
| §32.4 | Tokens — discrepância docs/código | **7E-C T25-T29** | descobre GAP | helpers/tokens |
| §33 | Flutter productId integrity | 7E-B (cart pre-flight) | indirect | validar payload pré-RPC |
| §34 | (gap docs) | — | — | — |
| §35 | RAG Knowledge Base | 7E-D opcional | — | mock Gemini |
| §36 | Robô IA Write Shadow | 7E-D Grupo 11 | T54-T57 | helpers/robot |
| §37 | Auto-suggest cron skills | 7E-D Grupo 12 | T58-T59 | helpers/robot |
| §38 | Auto-implement zonas seguras | 7E-D Grupo 11 | T56 | helpers/robot |
| §39 | Robô A↔B crosstalk | 7E-D T57 | mock Gemini | helpers/robot |
| §40 | Notificações urgência admin | 7E-D | mock FCM | helpers/mocks.push_log |
| §41 | Push admin reply UI + email | 7E-D | mock FCM + log | — |
| §42 | pg_net via Vault | n/a | — | — |
| §43 | Painel Admin Inbox Avançado | 7E-D opcional | — | — |
| §44 | Avaliações por Estrelas (Sessão 6) | **7E-C Grupo 8** | T39-T45 | helpers/ratings |

**GAPS identificados:**
- §32.4 — fórmula tokens em docs (`+1 token / 0.5 EUR`) **divergente** do código (`floor(amount / 1)`). 7E-C T25-T29 vai falhar legitimamente para documentar BUG.
- §3 (Order stacking up to 3) — não claro se implementado em prod; 7E-C Grupo 3 (T14-T18) pode falhar e abrir BUG.
- §15-§18 (UI Flutter) — fora de scope E2E backend; abrir TODO 7E-Flutter.

---

## Decisões de mock granular (tabela)

| Sistema | Mock default | Como activar real | Quando preferir real | Fase |
|---------|--------------|-------------------|----------------------|------|
| Stripe `create-payment-intent` | SQL `UPDATE orders SET payment_status='paid', paid_at=NOW() WHERE id=p_order_id` | `E2E_STRIPE_LIVE=1` (manual only, never CI) | Validação manual do webhook end-to-end | 7E-B |
| Stripe `refund` | SQL `UPDATE orders SET refund_amount=p_amount` (sem chamar Edge Fn) | `E2E_STRIPE_LIVE=1` | Validar admin-only enforcement | 7E-C |
| MBWay `create-mbway-payment-intent` | SQL UPDATE simulando `payment_intent.succeeded` | — | Nunca live em CI (telefone real exigido) | 7E-B |
| FCM (`notify-*` family) | `push_log: list[dict]` em memória; Edge Fn invocada mas com `FIREBASE_PROJECT_ID` ausente faz no-op | — | Testes manuais com device | 7E-B/D |
| Gemini (`support-chatbot`, `analyze-conversations`) | `RESPONSE_FIXTURES: dict[skill_id, str]` em `helpers/mocks.py` | `E2E_GEMINI_LIVE=1` | Validar prompts em PR de skill nova | 7E-D |
| dispatch-engine (pg_cron) | RPC `accept_dispatch_offer(p_order_id, p_driver_id)` directa | — | Nunca live (cron) | 7E-B |
| Push admin (notify-admin-urgent) | mesmo padrão FCM (logger) | — | — | 7E-D |

---

## Cobertura RPCs / triggers / Edge Fns

### Cobertura por sub-sessão

| Componente | 7E-A | 7E-B | 7E-C | 7E-D | Não testado |
|------------|------|------|------|------|-------------|
| RPC `add_tokens` / `consume_tokens` / `get_user_tokens` | — | — | ✅ | — | — |
| RPC `submit_rating` | — | — | ✅ | — | — |
| RPC `accept_dispatch_offer` | — | ✅ | — | — | — |
| Trigger `orders_financial_split` | — | ✅ (indirect) | — | — | — |
| Trigger `ledger_no_update`/`ledger_no_delete` | — | — | — | ✅ T62 | — |
| Trigger `trg_award_tokens_on_delivery` | — | — | ✅ T28 | — | — |
| Trigger `trg_enforce_refund_cap` | — | — | ✅ T53 | — | — |
| Edge Fn `create-payment-intent` | — | ✅ (mock SQL) | — | — | — |
| Edge Fn `client-cancel-order` | — | ✅ T35-T38 | — | — | — |
| Edge Fn `support-chatbot` | — | — | — | ✅ T54-T56 | — |
| Edge Fn `dispatch-engine` (cron) | — | — | — | — | ✅ (cron) |
| Edge Fn `stripe-webhook` | — | — | — | — | ✅ (signature) |
| RLS policies (63) | — | — | — | ✅ T60-T64 | — |

---

## Plano de fixtures 3+3+3

### Clientes (`e2e_*@boraapp.test`)
| ID lógico | email | wallet | promo |
|-----------|-------|--------|-------|
| client_A | `e2e_client_a@boraapp.test` | €100.00 | — |
| client_B | `e2e_client_b@boraapp.test` | €0.00 | — |
| client_C | `e2e_client_c@boraapp.test` | €20.00 | €5.00 promo |

### Estafetas (`e2e_*@driver.bora.app` synthetic)
| ID lógico | phone | online | vehicle | partner |
|-----------|-------|--------|---------|---------|
| driver_A | `910000901` | online | car | partner |
| driver_B | `910000902` | offline | bike | non-partner |
| driver_C | `910000903` | online | car | non-partner (GPS Guarda 40.5404, -7.2683) |

### Restaurantes (prefixo `E2E_TEST_`)
| ID lógico | nome | tipo | partner |
|-----------|------|------|---------|
| rest_A | `E2E_TEST_PartnerRest` | restaurant | true |
| rest_B | `E2E_TEST_NonPartnerRest` | restaurant | false |
| rest_C | `E2E_TEST_Market` | supermarket | true |

**Markers:** `is_test=true` em todos os registos onde a coluna existe (orders, restaurants, drivers se possível). Senão usar prefixo do nome ou domínio do email.

**Idempotência:** `seed.py` faz `SELECT ... WHERE email=... LIMIT 1`; se existe → `UPDATE`; senão → `INSERT`. Re-run não duplica.

---

## Smoke tests B9 (3 testes independentes de seed)

```python
# scripts/e2e/tests/test_smoke.py
def test_env_vars_loaded():
    """Confirma que SUPABASE_URL e SERVICE_ROLE_KEY são lidos de scripts/rag/.env"""
    assert os.environ.get("SUPABASE_URL"), "SUPABASE_URL ausente"
    assert os.environ.get("SUPABASE_SERVICE_ROLE_KEY"), "SERVICE_ROLE_KEY ausente"
    assert "ojykpzwqrtusfeakzrna" in os.environ["SUPABASE_URL"]

def test_admin_client_connects(admin_client):
    """Confirma que o cliente Supabase com service_role consegue listar restaurants."""
    resp = admin_client.table("restaurants").select("id").limit(1).execute()
    assert resp.data is not None  # pode estar vazia mas a query tem de funcionar

def test_test_password_constant():
    """Confirma que a password constante de teste está definida e não é trivial."""
    from helpers.auth import TEST_PASSWORD
    assert len(TEST_PASSWORD) >= 12
    assert TEST_PASSWORD != "123456"
```

**Critério de PASS B9:** os 3 testes correm em <5s sem precisar de `seed.py`. Se falham → boot do framework está partido, abortar antes de avançar para 7E-B.

---

## Roadmap sub-sessões 7E-B / 7E-C / 7E-D

### 7E-B (4-6h, tests críticos lançamento)
- helpers/orders.py: `create_test_order`, `advance_status`, `simulate_dispatch_accept`
- helpers/wallet.py: `check_balance`, `simulate_topup`
- helpers/dispatch.py: `simulate_offer_flow`
- **Grupo 1 Pricing** (T01-T08, 8 tests)
- **Grupo 2 Dispatch** (T09-T13, 5 tests, mock simulado)
- **Grupo 4 Wallet** (T19-T24, 6 tests)
- **Grupo 7 Cancellation** (T35-T38, 4 tests)
- **Total ~23 tests**

### 7E-C (4-6h, tests secundários)
- helpers/tokens.py, helpers/ratings.py, helpers/reservations.py, helpers/refunds.py, helpers/store.py
- **Grupo 3 Stacking** (T14-T18) — pode FAIL legitimamente
- **Grupo 5 Tokens** (T25-T29) — descobre §32.4
- **Grupo 6 Store Shopping** (T30-T34)
- **Grupo 8 Ratings** (T39-T45, Sessão 6)
- **Grupo 9 Reservations** (T46-T50)
- **Grupo 10 Refunds** (T51-T53)
- **Total ~30 tests**

### 7E-D (3-5h, terciários + segurança)
- helpers/robot.py (mock Gemini default)
- **Grupo 11 Robot A** (T54-T57, 4 tests)
- **Grupo 12 Skill Suggestions** (T58-T59, 2 tests)
- **Grupo 13 RLS** (T60-T64, 5 tests — segurança crítica)
- **Grupo 14 Status Lifecycle** (T65-T67, 3 tests)
- **Total ~14 tests**

**TOTAL agregado:** ~67 tests em 4 sub-sessões viáveis.

---

## Política de FAIL

- Tests que falham em 7E-B/C/D **NÃO bloqueiam merge**.
- Cada FAIL legítimo abre BUG separado em backlog (referenciar test_id, ex: `T25 — fórmula tokens divergente §32.4`).
- GAPS de implementação documentados em `scripts/e2e/TODO.md` com referência §.

---

## Limitações conhecidas

- **Não testa UI Flutter** — abrir TODO 7E-Flutter (separado).
- **Não testa Stripe live** — mock SQL total.
- **Não testa GPS real driver** — coords fixas em fixture.
- **Não testa push notification real** — `push_log` em memória.
- **Validação manual final com pessoas reais necessária** antes de qualquer release.

---

## Próximo passo

→ **Fase B (7E-A B1-B9):** criar `scripts/e2e/` com:
1. `.gitignore` (`.env.test` + `.venv/` + `reports/*.html` + `reports/*.json` + `__pycache__/` + `*.pyc` + `.pytest_cache/`)
2. `.env.test.example` (committed; **SEM** `SUPABASE_SERVICE_ROLE_KEY` — apenas placeholders dos opt-in flags)
3. `requirements.txt` (PINNED versions)
4. `helpers/__init__.py`, `helpers/auth.py`, `helpers/orders.py` (stub), `helpers/mocks.py`
5. `seed.py` (3+3+3 idempotente)
6. `cleanup.py` (dry-run default)
7. `run_all.sh` (cross-platform)
8. `tests/__init__.py`, `tests/conftest.py`, `tests/test_smoke.py` (3 smokes)
9. Smoke run → confirmar 3 PASS

→ **Fase C:** `business_rules.md §45` + `scripts/e2e/README.md` + `scripts/e2e/TODO.md` + sync Obsidian.

→ **3 commits granulares** + `git push origin autonomous-night-2026-04-29`.
