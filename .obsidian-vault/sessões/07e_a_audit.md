# Sessão 7E-A — Framework E2E Tests — AUDIT (Fase A)

> **Sync source:** `.claude/.ai/reports/07e_a_audit.md` (canónico no repo)
> **Data:** 2026-05-07
> **Branch:** `autonomous-night-2026-04-29`

---

## Sumário executivo

Sessão 7E-A é a **infra-estrutura mínima** para uma suite de testes E2E em Python contra a Supabase real. Não escreve testes funcionais — apenas o esqueleto + fixtures 3+3+3 + 3 smokes independentes de seed. Os testes funcionais ficam para 7E-B (críticos), 7E-C (secundários) e 7E-D (segurança/RLS).

**5 princípios:**
1. Single source de credenciais → `scripts/rag/.env` (Decisão #1)
2. Markers obrigatórios → `is_test=true` / `e2e_*@boraapp.test` / `E2E_TEST_*`
3. Cleanup soft → só apaga registos com markers; dry-run default
4. Mocks DEFAULT → Stripe SQL UPDATE, FCM logger, Gemini hardcoded
5. Cross-platform → Windows + Linux + macOS

---

## Decisões arquitecturais (9)

1. **Service-role key reusada de `scripts/rag/.env`** via `load_dotenv("../rag/.env")` em `helpers/auth.py`. NUNCA copiar para `.env.test*`. Aprovado pelo Danilo.
2. **Pinned versions:** `pytest==8.3.4`, `supabase==2.10.0`, `httpx==0.28.1`, `python-dotenv==1.0.1`.
3. **Mock Stripe default = SQL UPDATE** `payment_status='paid'` + `paid_at=NOW()`. Live opt-in via `E2E_STRIPE_LIVE=1`.
4. **Mock FCM default = `push_log: list[dict]` em memória.**
5. **Mock Gemini default = respostas hardcoded** (`RESPONSE_FIXTURES: dict[skill_id, str]`). Live opt-in via `E2E_GEMINI_LIVE=1`.
6. **Mock dispatch-engine default = chamada directa a RPC `accept_dispatch_offer`** (evita pg_cron não-determinístico).
7. **Cleanup escopo APENAS markers E2E.** Garantia formal: nunca toca produção.
8. **Fixtures idempotentes** — UPSERT por email/phone/name; re-run sem duplicar.
9. **Smoke B9 independente de seed** (3 testes triviais antes de qualquer fixture).

---

## Inventário do sistema sob teste

- **Tabelas:** `restaurants` (TEXT id), `products` (TEXT id), `orders` (TEXT id, com `is_test_order` BOOLEAN), `drivers`, `client_wallets`, `wallet_transactions`, `ledger_entries`, `ratings`, `pending_charges`, `partner_reservation_payouts`, `support_pending_actions`, `robot_crosstalk`, `complaints`.
- **RPCs (38+):** `add_tokens`, `consume_tokens`, `submit_rating`, `accept_dispatch_offer`, `apply_order_financial_split`, `auto_payout_pending`, `recompute_user_balance`, `admin_dashboard_metrics`, `search_products`, etc.
- **Triggers (25):** `ledger_no_update/delete`, `orders_financial_split`, `orders_cash_settlement`, `orders_post_to_ledger`, `trg_award_tokens_on_delivery`, `trg_award_cashback`, `trg_enforce_refund_cap`, `trg_protect_admin_*`.
- **Edge Functions (26):** 11 públicas/auth, 5 admin-only, 1 webhook (Stripe), 1 cron (dispatch-engine).
- **RLS policies:** 63 (cobertas em 7E-D Grupo 13).

---

## Mock granular

| Sistema | Mock default | Como activar real |
|---|---|---|
| Stripe `create-payment-intent` | SQL UPDATE | `E2E_STRIPE_LIVE=1` |
| Stripe `refund` | SQL UPDATE | `E2E_STRIPE_LIVE=1` |
| MBWay | SQL UPDATE | nunca live em CI |
| FCM (`notify-*`) | `push_log` lista | — |
| Gemini | dict hardcoded | `E2E_GEMINI_LIVE=1` |
| dispatch-engine | RPC directa | nunca live (cron) |

---

## Fixtures 3+3+3

**Clientes:** `e2e_client_a@boraapp.test` (€100), `e2e_client_b@boraapp.test` (€0), `e2e_client_c@boraapp.test` (€20+€5 promo).

**Estafetas:** `910000901` (online/car/partner), `910000902` (offline/bike/non-partner), `910000903` (online/car/non-partner, GPS Guarda 40.5404, -7.2683).

**Restaurantes:** `E2E_TEST_PartnerRest` (partner restaurant), `E2E_TEST_NonPartnerRest` (non-partner restaurant), `E2E_TEST_Market` (partner supermarket).

---

## Smoke B9 (3 tests independentes)

1. `test_env_vars_loaded` — `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` lidos
2. `test_admin_client_connects` — `restaurants` query funciona
3. `test_test_password_constant` — `TEST_PASSWORD` ≥ 12 chars e ≠ `"123456"`

---

## Roadmap

| Sub-sessão | Esforço | Tests | Foco |
|---|---|---|---|
| 7E-A (esta) | 4-6h | 3 smokes | framework + fixtures |
| 7E-B | 4-6h | ~23 | pricing + dispatch + wallet + cancellation |
| 7E-C | 4-6h | ~30 | stacking + tokens + ratings + store + reservations + refunds |
| 7E-D | 3-5h | ~14 | robot + suggestions + RLS + lifecycle |

**TOTAL:** ~67 tests.

---

## Política de FAIL

- Tests que falham em 7E-B/C/D **NÃO bloqueiam merge**.
- Cada FAIL legítimo abre BUG separado.
- GAPS documentados em `scripts/e2e/TODO.md`.

---

## Limitações conhecidas

- Não testa UI Flutter (TODO 7E-Flutter).
- Não testa Stripe live (mock total).
- Não testa GPS real.
- Não testa push real.
- Validação manual com pessoas reais ainda necessária antes de release.

---

## Próximos passos

Fase B → criar `scripts/e2e/` (9 ficheiros) + smoke run.
Fase C → `business_rules.md §45` + README + TODO + sync Obsidian.
3 commits granulares + push.
