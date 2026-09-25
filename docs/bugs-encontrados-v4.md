# TestSprite E2E v4 — Bugs Encontrados

> Suite: **Bora App - E2E Completo v4** · 2026-05-28 · backend Supabase cloud
> Resultado final: **10/10 testes passam** (cobrindo os 21 fluxos pedidos, A1–F3).
> Run inicial cloud: 8/10. As 2 falhas eram **bugs no teste** (corrigidos) — **0 bugs reais da app**.

---

## Resultado por bloco

| Bloco | Fluxos | Testes gerados | Estado |
|---|---|---|---|
| A — Autenticação | A1,A2,A3 | TC001 | ✅ |
| B — RLS / Isolamento | B1,B2,B3,B4 | TC002, TC004, TC010, TC009 | ✅ |
| C — Pedido E2E | C1,C2,C3,C4 | TC003, TC008 | ✅ |
| D — Wallet / Tokens | D1,D2,D3 | TC005, TC006 | ✅ |
| E — Edge Functions | E1,E2,E3,E4 | TC007, TC008 | ✅ |
| F — Segurança | F1,F2,F3 | TC004, TC009 | ✅ |

> O gerador TestSprite consolidou os 21 fluxos em 10 testes executáveis (vários
> fluxos cobertos pelo mesmo teste — ex. RLS SELECT+insert+isolamento).

---

## Pré-condição corrigida (fixtures, não app)

Os 3 utilizadores novos (`test-client2`, `test-partner`, `test-admin`) davam **500**
no login: tinham sido criados via SQL INSERT com colunas de token GoTrue a NULL
(`recovery_token`, `email_change`, etc.) em vez de `''`, e sem `provider` em
`raw_app_meta_data`. Corrigido com UPDATE em `auth.users` (mesmo padrão da sessão
anterior para client/driver) → os 5 utilizadores autenticam 200. Isto é dados de
fixture de teste, não código da app.

---

## Falhas da run inicial — ambas BUG NO TESTE (corrigidas)

### TC002 — `get_rest_v1_orders_authorized_access` (era ❌ → ✅)
- **Sintoma:** insert de pré-condição devolveu HTTP 400.
- **Causa-raiz (teste):** URL usava `?return=representation` como **query param**.
  O PostgREST interpreta `return` como filtro de coluna inexistente → 400.
- **Fix (teste):** removido o query param; adicionado header `Prefer: return=representation`.
- **Não é bug da app** — TC003 (insert correcto via header `Prefer`) sempre passou.

### TC007 — `notify_client_authenticated` (era ❌ → ✅)
- **Sintomas/causas (teste):** (1) `APIKEY` corrompida no ficheiro gerado
  (`...c2Z1c2ZlYWt6...` com `1c2Z` a mais) → anon key inválida → 401 no login;
  (2) email `test-client1@bora.app` (com "1") que não existe → 401;
  (3) body enviava `user_id` mas a Edge Function exige `clientId`.
- **Fix (teste):** anon key corrigida, email `test-client@bora.app`, body `clientId`.
- **Achado de contrato (não-bug):** `notify-client` valida `clientId` (não `user_id`)
  e devolve `{"ok":false,"error":"clientId is required"}` com 400 quando ausente —
  ou seja, a função **aceita o JWT** (requisito E1 "não-401" satisfeito) e faz
  validação de domínio correcta. Vale documentar no contrato da API.

---

## Bugs reais da app encontrados

**Nenhum.** Todas as validações de backend/segurança passaram:
- Auth real (5 utilizadores).
- RLS de `orders` (SELECT só dos próprios, insert com `user_id` alheio → 403, sem JWT → 401).
- RLS de `client_wallets` / `bora_tokens` (isolamento por utilizador).
- `ledger_entries` sem JWT → 401.
- PostgREST rejeita colunas desconhecidas (PGRST204) e query params inválidos (400).
- Edge Functions `notify-client` e `client-cancel-order` aceitam JWT e fazem validação
  controlada (sem 500).

---

## Limitações / não coberto (candidatos v5)

- **Stripe end-to-end:** `create-payment-intent` foi exercido só ao nível de auth/erro
  controlado; o cartão de teste `4242...` não foi usado num fluxo de pagamento completo.
- **notify-driver (E2):** coberto como "não-401"; entrega FCM real não verificada.
- **Fluxo de pedido completo com parceiro a aceitar + dispatch:** não testado (dispatch
  é zona protegida; só leitura RLS foi validada).
- **Cancelamento com cálculo de fee** (€1/€2.50/100%): só testado "não-500", não os valores.

---

## Zonas protegidas

Nada alterado. dispatch-engine, pricing_service, Stripe webhook, triggers financeiros
e RLS de orders/client_wallets/ledger_entries foram **apenas lidos/testados**, nunca
modificados. As 3 inserções de teste usaram `is_test_order=true`.
