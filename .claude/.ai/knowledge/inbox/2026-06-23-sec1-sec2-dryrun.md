# SEC-1 / SEC-2 — Dry-Run (read-only)

> Data: 2026-06-23 · Projeto Supabase: `ojykpzwqrtusfeakzrna` (Postgres 17) · Modelo: Opus 4.8
> Agente: `seguranca-rls` (protocolo executado inline — agentes nativos não carregam quando
> a sessão arranca de `projetosflutter/` em vez de `bora_app/`).
> **Estado: ZERO alterações na DB.** Só `SELECT` + `get_advisors`. Nada aplicado.

## Método
- `get_advisors(security)` → 286 lints (processado em sandbox, não no contexto).
- `pg_class`/`pg_policy` → estado RLS + nº de políticas por tabela (metadata `pg_catalog`, não dados).
- `storage.buckets` → público/privado por bucket.
- **Tabelas protegidas NUNCA consultadas nos dados** (`orders`, `client_wallets`, `ledger_entries`,
  `bora_tokens`, `stripe_events`): só se leu o estado RLS via catálogo.

---

## SEC-1 — RLS

### 🔴 ERROR (1) — RLS desativado em `public`
| Tabela | RLS | Políticas | Natureza | Veredicto |
|---|---|---|---|---|
| `_backup_continente_precos_pre_oficial_2026_06_14` | ❌ **off** | 0 | Backup de preços (sem PII/financeiro) | **SEGURO APLICAR** |

Exposta via PostgREST sem RLS. É um backup temporário. Ação segura: `ENABLE ROW LEVEL SECURITY`
(fica trancada a service-role, sem políticas) **ou** dropar o backup. Sem impacto no app.

### 🟡 WARN — funções `SECURITY DEFINER` executáveis sem autorização suficiente
| Lint | Nº | Veredicto |
|---|---|---|
| `anon_security_definer_function_executable` | **14** | ⚠️ **REQUER APROVAÇÃO — prioridade ALTA** |
| `authenticated_security_definer_function_executable` | 223 | ⚠️ **REQUER APROVAÇÃO** |

**`anon` (público, sem login) pode executar 14 funções SECURITY DEFINER**, incluindo:
`admin_delete_business`, `admin_upsert_business`, `admin_set_business_visibility`,
`admin_continente_apply_prices`, `admin_continente_price_review`, `driver_convert_tokens`,
`errand_request_budget_increase`, `client_respond_budget_increase`, `fn_enqueue_errand_catalog`,
`search_businesses`, `admin_continente_price_list/summary`, `admin_list_businesses`,
`client_set_errand_request_photo`.
→ `driver_convert_tokens` toca **tokens (zona protegida)** e os `admin_*` deviam exigir papel admin.
Algumas (`search_businesses`, `admin_continente_price_list`) podem ser browsing público intencional.
**Não toquei** — rever caso-a-caso e `REVOKE EXECUTE ... FROM anon` nas que não devem ser públicas.

As 223 `authenticated_*` são, em larga medida, o padrão de RPCs do Bora (app chama RPC). O risco é
um `admin_*` que não valide o papel internamente. Auditoria grande → fora deste lote.

### 🔵 INFO (42) — RLS on, 0 políticas (tabelas trancadas)
Maioria são `_backup_*`, `_*_price_sources_*`, `continente_price_staging` (temporárias/staging) e
**`robot_audit_log` / `robot_runs` / `robot_suggestions` (INTOCÁVEIS)**. RLS on + 0 políticas = só
service-role acede → **seguro/intencional**. `guarda_businesses` é acedida via funções
SECURITY DEFINER (`search_businesses`/`admin_*_business`), por isso "sem política" é normal.
**Sem ação** (housekeeping: dropar backups antigos quando o Danilo quiser).

### ✅ Zonas protegidas — já seguras (sem ação)
`orders` (8 pol.), `client_wallets` (2), `ledger_entries` (2), `bora_tokens` (1),
`order_financials`/`order_financial_transactions` (1+1), `payouts`/`*_settlements` — **todas RLS on
com políticas**. ⚠️ Não existe tabela `stripe_events` no schema `public` (procurar noutro schema ou
nome diferente — confirmar com o Danilo; pode ser `mbway_debug_errors`/webhook noutro local).

---

## SEC-2 — Storage buckets

| Bucket | Público? | Listagem | Veredicto |
|---|---|---|---|
| `driver-documents` | 🔒 privado | — | ✅ correto (docs sensíveis) |
| `order-photos` | 🔒 privado | — | ✅ correto |
| `receipts` | 🔒 privado | — | ✅ correto (talões) |
| `restaurant-documents` | 🔒 privado | — | ✅ correto |
| `avatars` | 🌐 público | permite | ⚠️ listagem enumerável — **SEGURO RESTRINGIR** (manter leitura por path) |
| `product-images` | 🌐 público | permite | ✅ catálogo público (intencional) |
| `products` | 🌐 público | permite | ✅ catálogo público (intencional) |
| `restaurant-assets` | 🌐 público | permite | ✅ logos/heroes públicos (intencional) |

`public_bucket_allows_listing` (3): `avatars`, `product-images`, `restaurant-assets`. Só `avatars`
é uma fuga de privacidade real (enumerar nomes de ficheiros de avatar). Os outros são catálogo.

---

## Outros lints de segurança
| Lint | Alvo | Veredicto |
|---|---|---|
| `function_search_path_mutable` | `_errand_normalize`, `_haversine_km` | **SEGURO APLICAR** — `ALTER FUNCTION … SET search_path = ''` (helpers não-financeiros) |
| `auth_leaked_password_protection` | Auth | **SEGURO APLICAR** — ativar HaveIBeenPwned no signup (aditivo, sem risco) |

---

## 📋 Veredicto final (separado)

### ✅ SEGURO APLICAR AGORA (sem dados financeiros/sensíveis — ainda assim, aprovar antes de DDL)
1. `_backup_continente_precos_pre_oficial_2026_06_14` → `ENABLE RLS` ou dropar backup.
2. `function_search_path_mutable` → pinar `search_path` em `_errand_normalize` + `_haversine_km`.
3. `auth_leaked_password_protection` → ativar (toggle Auth / management API).
4. (Opcional, minor) `avatars` → desativar listagem pública mantendo leitura por path.

### ⚠️ REQUER APROVAÇÃO DANILO (zonas sensíveis/protegidas)
1. **`anon` executa 14 SECURITY DEFINER** (`admin_delete_business`, `admin_upsert_business`,
   `driver_convert_tokens`, …) → rever e `REVOKE EXECUTE FROM anon` onde aplicável.
   `driver_convert_tokens` = zona **tokens** → aprovação obrigatória.
2. 223 funções `authenticated_*` SECURITY DEFINER → confirmar verificação de papel interna.
3. Confirmar onde estão os eventos Stripe (não há `public.stripe_events`).
4. Tabelas `robot_*` com RLS-no-policy → **INTOCÁVEIS**, confirmar que devem ficar trancadas.

> Nada acima foi executado. Próximo passo só com "CONFIRMO" do Danilo, item a item.
> Para mutações: o agente `db-migrations` (dry-run + backup + rollback) ou `seguranca-rls`.
