# Sessão 7E-A — Framework E2E Tests — REPORT (entregue)

> **Data:** 2026-05-07
> **Branch:** `autonomous-night-2026-04-29`
> **Esforço:** ~4h (single session, autonomous-night)
> **Estado:** ✅ **MERGED** (3 commits granulares + push)

---

## TL;DR

Esqueleto do framework E2E em Python entregue. Zero testes funcionais (esses ficam para 7E-B/C/D em sub-sessões separadas, ~67 tests no agregado), mas:

- ✅ Boot do framework funcional
- ✅ 3/3 smokes em verde (3.20s)
- ✅ Seed 3+3+3 idempotente (9 entidades criadas)
- ✅ Cleanup soft com markers E2E (dry-run default)
- ✅ business_rules §45 documentado
- ✅ README PT-PT + TODO.md (roadmap 7E-B/C/D)

---

## Entregues

### Documentação
- `.claude/.ai/reports/07e_a_audit.md` (415 linhas) — audit Fase A
- `.obsidian-vault/sessoes/07e_a_audit.md` — sync condensado
- `.claude/.ai/business_rules.md §45` — 8 sub-secções (§45.1-§45.8)
- `scripts/e2e/README.md` — setup PT-PT
- `scripts/e2e/TODO.md` — roadmap 7E-B/C/D + GAPS

### Código (scripts/e2e/, 13 ficheiros)
- `.gitignore`, `.env.test.example`, `requirements.txt` (PINNED)
- `helpers/auth.py` — `load_env()`, `admin_client()`, `user_client(jwt)`, `is_stripe_live()`, `is_gemini_live()`
- `helpers/mocks.py` — `push_log` (FCM), `RESPONSE_FIXTURES` (Gemini), Stripe stub
- `helpers/orders.py` — stubs (implementação 7E-B)
- `seed.py` — 3+3+3 idempotente (UPSERT)
- `cleanup.py` — dry-run default; `--confirm` apaga real; escopo APENAS markers E2E
- `run_all.sh` — cross-platform runner
- `tests/conftest.py` — `admin_client` fixture
- `tests/test_smoke.py` — 3 smokes B9 independentes de seed

### Validação executada
| Comando | Resultado |
|---|---|
| `pytest tests/test_smoke.py -v` | 3/3 PASS em 3.20s |
| `python seed.py` (1ª vez) | 9 entidades criadas |
| `python seed.py` (re-run) | 9/9 ✓ existe (idempotente) |
| `python cleanup.py` (dry-run) | 4 orders + 3 restaurants + 6 users listados |

---

## Decisões arquitecturais aplicadas

1. **Service-role key reusada de `scripts/rag/.env`** via `load_dotenv("../rag/.env")`. Single source. Nunca duplicar.
2. **Pinned versions:** `pytest==8.3.4`, `supabase==2.10.0`, `httpx==0.27.2` (NB: 0.27.2 e não 0.28.1 — supabase 2.10.0 conflitua), `python-dotenv==1.0.1`.
3. **Mock Stripe default = SQL UPDATE.**
4. **Mock FCM default = `push_log` em memória.**
5. **Mock Gemini default = `RESPONSE_FIXTURES` hardcoded.**
6. **Mock dispatch default = RPC `accept_dispatch_offer` directa.**
7. **Cleanup escopo APENAS markers E2E.**
8. **Fixtures idempotentes via UPSERT.**
9. **Smoke B9 independente de seed** (3 testes triviais).

---

## Commits

```
3d6c451 feat(7e-a-framework): scripts/e2e/ setup + smoke OK
66a8d9c docs(7e-a): audit completo framework E2E tests
```

(commit 3 docs §45 + README + TODO + sync — push final)

---

## Próximos passos

- **7E-B** (4-6h, ~23 tests) — pricing + dispatch + wallet + cancellation
- **7E-C** (4-6h, ~30 tests) — stacking + tokens + ratings + store + reservations + refunds
- **7E-D** (3-5h, ~14 tests) — robot + suggestions + RLS + lifecycle

Total agregado: ~67 tests em 4 sub-sessões viáveis.

---

## Limitações & gaps a observar nas próximas sub-sessões

- §32.4 — fórmula tokens divergente entre docs e código (descoberta esperada em 7E-C T25-T29).
- §3 — Order stacking up to 3 não claro se implementado em prod; 7E-C Grupo 3 pode falhar.
- UI Flutter fora de scope (TODO 7E-Flutter separado).
- Stripe live, GPS real, push real, webhook signature — todos não cobertos. Validação manual com pessoas reais ainda necessária antes de release.
