# REVOKE anon — Funções SECURITY DEFINER (HIGH + MEDIUM)
**Data:** 2026-06-23  
**Aprovação Danilo:** 2026-06-23  
**Resultado:** 9/9 funções revogadas ✅

---

## Funções Revogadas

### HIGH (3 funções)

| Função | Técnica | anon_can_execute |
|--------|---------|-----------------|
| `admin_delete_business(p_id uuid)` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `admin_upsert_business(...)` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `driver_convert_tokens(p_amount integer)` | `REVOKE FROM anon` (sem PUBLIC grant) | ❌ FALSE ✅ |

### MEDIUM (6 funções)

| Função | Técnica | anon_can_execute |
|--------|---------|-----------------|
| `admin_set_business_visibility(p_id uuid, p_visible boolean)` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `admin_list_businesses(p_search text, p_limit integer, p_offset integer)` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `admin_continente_apply_prices()` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `admin_continente_price_list(p_filter text, p_limit integer, p_offset integer)` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `admin_continente_price_review(p_ids uuid[], p_action text)` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |
| `admin_continente_price_summary()` | `REVOKE FROM anon` + `REVOKE FROM PUBLIC` | ❌ FALSE ✅ |

---

## Funções LOW — NÃO TOCADAS (por decisão de Danilo)

- `client_respond_budget_increase` — possível fluxo público errand
- `client_set_errand_request_photo` — possível fluxo público errand
- `errand_request_budget_increase` — possível fluxo público errand
- `fn_enqueue_errand_catalog` — catálogo errand
- `search_businesses` — pode ser intencional para landing page pública
- `haversine` — função matemática de distância, sem dados sensíveis

---

## Nota Técnica

**Causa-raiz descoberta:** 8 das 9 funções tinham grant `=X/postgres` (PUBLIC) no ACL.
`REVOKE FROM anon` sozinho não era suficiente porque `anon` herda de PUBLIC.
Foi necessário `REVOKE FROM PUBLIC` para remover a herança.
`driver_convert_tokens` tinha grant explícito para `anon` (não PUBLIC), por isso
`REVOKE FROM anon` foi suficiente.

**Grants preservados (authenticated + service_role intactos):**
- `authenticated=X/postgres` — mantido em todas as 8 funções admin
- `service_role=X/postgres` — mantido em todas as 8 funções admin

---

## Migration criada

Ficheiro: `supabase/migrations/20260623120000_revoke_anon_admin_functions.sql`
