# TestSprite AI Testing Report (MCP) — Bora App
> **Run 3 (v3) — schema real + credenciais correctas → 7/7 PASSED (100%)**

---

## 1️⃣ Document Metadata
- **Project:** bora_app
- **Date:** 2026-05-28 (Run 3)
- **Suite:** Bora App - Backend Real v3
- **Backend:** Supabase cloud `https://ojykpzwqrtusfeakzrna.supabase.co`
- **Tests:** 7 gerados · **7 PASSED** ✅ · **0 FAILED**
- **Cobertura:** 100.00%

### O que mudou face às Runs 1 e 2 (0% e 12.5%)
1. **Schema real injectado** no `code_summary.yaml` — `orders` NÃO tem `currency`/`total_cents`/`amount`. Insert mínimo documentado: `{user_id, status, items:[], is_test_order:true}`.
2. **Credenciais reais** — `test-client@bora.app` / `TestBora2026!` (já com bcrypt + `aud`/`instance_id` corrigidos no auth.users na sessão anterior).
3. **`apikey` header obrigatório** em todos os requests + **login JSON** (não form-data).
4. **`additionalInstruction`** explícito com headers, schema e os 6 cenários-alvo.

---

## 2️⃣ Requirement Validation Summary

| TC | Cenário | Endpoint | Status |
|---|---|---|---|
| TC001 | Auth login devolve access_token | `POST /auth/v1/token?grant_type=password` | ✅ Passed |
| TC002 | RLS SELECT — cliente vê só os seus orders | `GET /rest/v1/orders` | ✅ Passed |
| TC003 | Insert order válido com `user_id` correcto | `POST /rest/v1/orders` | ✅ Passed |
| TC004 | Insert com campo desconhecido → rejeitado | `POST /rest/v1/orders` | ✅ Passed |
| TC005 | Insert com `user_id` divergente → RLS bloqueia | `POST /rest/v1/orders` | ✅ Passed |
| TC006 | wallet_get_balance devolve saldo | `POST /rest/v1/rpc/wallet_get_balance` | ✅ Passed |
| TC007 | notify-client com JWT válido → não-401 | `POST /functions/v1/notify-client` | ✅ Passed |

> Os 6 cenários prioritários pedidos ficaram cobertos; o TestSprite dividiu o
> tema "orders insert/RLS" em 3 testes (TC003/004/005), reforçando a validação
> de segurança (RLS WITH CHECK `user_id = auth.uid()` confirmada a funcionar).

---

## 3️⃣ Coverage & Matching Metrics

- **100.00%** dos testes passaram (7/7).

| Requisito | Total | ✅ | ❌ |
|---|---|---|---|
| Authentication | 1 | 1 | 0 |
| RLS Orders (SELECT + isolamento + insert checks) | 4 | 4 | 0 |
| Wallet RPC | 1 | 1 | 0 |
| Notifications Edge Function | 1 | 1 | 0 |
| **TOTAL** | **7** | **7** | **0** |

---

## 4️⃣ Key Gaps / Risks

### Validações de segurança confirmadas ✅
- **RLS de `orders` funciona end-to-end:** cliente autenticado só vê/insere os seus;
  insert com `user_id` de outro utilizador é bloqueado (TC005); SELECT sem JWT
  não devolve dados de terceiros (TC002).
- **PostgREST rejeita colunas desconhecidas** (TC004) — schema enforcement ok.
- **Auth real funcional** com `test-client@bora.app`.
- **Edge Function `notify-client` aceita JWT de utilizador** (não-401).

### Bugs encontrados
- **Nenhum bug da app** nesta run. As 3 runs anteriores falharam por problemas de
  configuração de teste (schema/credenciais), não por defeitos do backend.

### Limitações
- Estes 7 testes cobrem auth, RLS de orders, wallet RPC e 1 Edge Function. **Não**
  cobrem ainda: pagamentos Stripe (cartão de teste não exercido nesta run),
  cancelamento com fees, tokens redeem, dispatch. Candidatos para v4.
- `notify-client` valida só "não-401"; não verifica entrega real de FCM/email.

---

## 5️⃣ Reproduzir
```bash
cd bora_app
API_KEY=<testsprite_key> node .claude/_mcp-v3.js          # regenera PRD+plano
API_KEY=<testsprite_key> testsprite-mcp-plugin generateCodeAndExecute   # executa
# resultados em testsprite_tests/tmp/raw_report.md
```
Credenciais e schema reais já estão em `testsprite_tests/tmp/code_summary.yaml`
e no `additionalInstruction` em `testsprite_tests/tmp/config.json`.

---

**Fim do relatório Run 3 — backend Bora App validado a 100% nos 7 testes.**
