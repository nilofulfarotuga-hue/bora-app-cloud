# Framework E2E — Bora App (Sessão 7E-A)

Suite de testes end-to-end em Python contra a Supabase real (com mocks granulares de Stripe / FCM / Gemini).

> **Estado actual:** apenas o esqueleto + 3 smokes independentes de seed. Os testes funcionais ficam para 7E-B (críticos), 7E-C (secundários) e 7E-D (segurança/RLS) em sub-sessões separadas. Ver `TODO.md`.

---

## Setup rápido

```bash
cd scripts/e2e

# 1. cria venv e instala deps (cross-platform)
./run_all.sh smoke      # corre só smokes (não toca em fixtures)
./run_all.sh seed       # cria fixtures 3+3+3 (idempotente)
./run_all.sh all        # seed + smoke
./run_all.sh cleanup    # apaga fixtures (--confirm aplicado automaticamente)
```

Em Windows usa **Git Bash** ou **WSL**. PowerShell/CMD não correm `run_all.sh`.

Alternativa manual (qualquer plataforma):
```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt   # Windows
# ou: source .venv/bin/activate && pip install -r requirements.txt
.venv/Scripts/python -m pytest tests/ -v
```

---

## Credenciais

**Não precisas de criar `.env.test` nem `.env`.**

O framework lê `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` directo de `scripts/rag/.env` (single source — Decisão arquitectural #1, ver `.claude/.ai/reports/07e_a_audit.md`).

Se algum dia precisares de overrides locais (raro), copia `.env.test.example` → `.env.test` e descomenta:
- `E2E_STRIPE_LIVE=1` — chama Stripe real em vez de mockar (nunca em CI)
- `E2E_GEMINI_LIVE=1` — chama Gemini real em vez de respostas hardcoded
- `E2E_RAG_ENV_PATH=...` — override do path para `scripts/rag/.env`

---

## Arquitectura

```
scripts/e2e/
├── .env.test.example        # opt-in flags; SEM service_role_key
├── .gitignore
├── README.md                # este ficheiro
├── TODO.md                  # roadmap 7E-B/C/D
├── requirements.txt         # pinned (pytest, supabase, httpx, dotenv)
├── run_all.sh               # runner cross-platform
├── seed.py                  # 3+3+3 fixtures idempotentes
├── cleanup.py               # dry-run default; --confirm apaga real
├── helpers/
│   ├── auth.py              # load_env, admin_client, user_client
│   ├── mocks.py             # push_log FCM, fixtures Gemini
│   └── orders.py            # stubs (implementação em 7E-B)
└── tests/
    ├── conftest.py          # admin_client fixture
    └── test_smoke.py        # 3 smokes B9 independentes de seed
```

### Markers obrigatórios

Todo o conteúdo de teste tem marker:

| Tabela | Marker |
|---|---|
| `auth.users` (clientes) | email termina em `@boraapp.test` |
| `auth.users` (estafetas) | email = `91000090{1,2,3}@driver.bora.app` |
| `orders` | `is_test_order = true` |
| `restaurants` | `id LIKE 'E2E_TEST_%'` |

`cleanup.py` apaga **APENAS** registos com estes markers — nunca toca produção.

---

## Fixtures 3+3+3 (depois de `python seed.py`)

| Tipo | Slug | Identificador | Detalhes |
|---|---|---|---|
| Cliente | `client_a` | `e2e_client_a@boraapp.test` | wallet €100 |
| Cliente | `client_b` | `e2e_client_b@boraapp.test` | wallet €0 |
| Cliente | `client_c` | `e2e_client_c@boraapp.test` | wallet €20 + promo €5 |
| Estafeta | `driver_a` | `910000901@driver.bora.app` | car · online · partner |
| Estafeta | `driver_b` | `910000902@driver.bora.app` | bike · offline · non-partner |
| Estafeta | `driver_c` | `910000903@driver.bora.app` | car · online · GPS Guarda |
| Restaurante | rest_A | `E2E_TEST_PartnerRest` | restaurant · partner |
| Restaurante | rest_B | `E2E_TEST_NonPartnerRest` | restaurant · non-partner |
| Restaurante | rest_C | `E2E_TEST_Market` | supermarket · partner |

Password de todas as contas: `E2E_TestPassword_2026!` (constante em `helpers/auth.py`).

---

## Mocks default

| Sistema | Mock default | Activar real |
|---|---|---|
| Stripe `create-payment-intent` / `refund` | SQL UPDATE em `orders` | `E2E_STRIPE_LIVE=1` |
| MBWay | SQL UPDATE simulando webhook | nunca live em CI |
| FCM `notify-*` | `helpers.mocks.push_log` | — |
| Gemini `support-chatbot` | `helpers.mocks.RESPONSE_FIXTURES` | `E2E_GEMINI_LIVE=1` |
| dispatch-engine (pg_cron) | RPC `accept_dispatch_offer` directa | nunca live |

---

## Política de FAIL

- Falhas em 7E-B/C/D **não bloqueiam merge**.
- Cada FAIL legítimo abre BUG separado (referenciar test_id, ex: `T25 — fórmula tokens §32.4`).
- GAPS documentados em `TODO.md`.

---

## Limitações conhecidas

- Não testa UI Flutter — abrir TODO 7E-Flutter (separado).
- Não testa Stripe live (mock SQL total).
- Não testa GPS real (coords fixas).
- Não testa push real (`push_log` em memória).
- **Validação manual com pessoas reais ainda necessária antes de release.**

---

## Referências

- Audit completo: [`.claude/.ai/reports/07e_a_audit.md`](../../.claude/.ai/reports/07e_a_audit.md)
- Business rules §45: [`.claude/.ai/business_rules.md`](../../.claude/.ai/business_rules.md)
- Roadmap sub-sessões: [`TODO.md`](TODO.md)
