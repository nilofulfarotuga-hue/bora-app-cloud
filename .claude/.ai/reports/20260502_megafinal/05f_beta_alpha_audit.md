# 5F-β-α — FASE A AUDIT REPORT

**Data:** 2026-05-07
**Sessão:** 5F-β-α/7 — Activação pg_net via Supabase Vault
**Branch:** autonomous-night-2026-04-29
**Modo:** PROTECÇÃO TOTAL — read-only audit
**Status:** ⛔ STOP após A5. Aguardar luz verde Danilo antes de FASE B.

---

## A0 — Vault Status + Skills + Settings

### Vault
| Métrica | Valor |
|---|---|
| Extension | `supabase_vault` v**0.3.1** ✅ |
| Schema `vault` presente | ✅ (1) |
| `vault.create_secret` function | ✅ existe |

### vault.secrets existentes (1 entrada — sem conflito)

| name | description | created_at |
|---|---|---|
| `dispatch_anon_jwt` | Anon JWT used by pg_cron dispatch jobs (S2 vault cutover, 2026-04-30) | 2026-04-30 |

⚠️ **Nenhum conflito.** Não existe `project_url` nem `service_role_key`. Inserir 2 novas entradas em B1 sem colisão.

### Skills (validação BR §40)
- **Total active: 21** ✅ (matches expected)
- read_only: 11
- escalate: 3
- write_shadow: 7

### pg_net / pg_cron / current_setting

| Métrica | Valor |
|---|---|
| `pg_net` instalado | ✅ |
| `pg_cron` instalado | ✅ |
| `app.supabase_url` | **NULL** ❌ (confirma 5F-β audit) |
| `app.service_role_key` | **MISSING** ❌ |

### business_rules.md numeração
- Última secção: **§41** (5F-β Push Admin Urgente)
- Próxima a adicionar: **§42** (5F-β-α Activação pg_net via Vault)

---

## A1 — Localização SUPABASE_SERVICE_ROLE_KEY

| Ficheiro | Existe | Tem Key? | Prefixo | Length |
|---|---|---|---|---|
| `bora_app/.env` | ❌ MISSING | — | — | — |
| `bora_app/scripts/rag/.env` | ✅ | ✅ | `eyJhbGci` (JWT válido) | 219 chars ≥ 200 ✅ |
| `bora_app/scripts/crosstalk/.env` | ❌ MISSING | — | — | — |

✅ **Gate A1 PASS** — chave válida disponível em `scripts/rag/.env`. Valor NÃO exposto neste relatório.

---

## A2 — Funções a Refactorizar (3 funções)

| Função | URL | KEY | Security | Sessão Origem |
|---|---|---|---|---|
| `public._notify_admin_urgent_trigger` | YES | YES | DEFINER | 5F-β |
| `public.admin_approve_action` | YES | YES | DEFINER | 5B-β1 |
| `public.fn_notify_admin_pending_action` | YES | YES | DEFINER | 5B-β1 |

✅ **Gate A2 PASS** — 3 funções, todas SECURITY DEFINER, todas usam ambas as settings. Refactor B2 (5F-β) + B3 (5B-β1 × 2).

---

## A3 — Cron Jobs (17 total)

### Jobs a refactorizar com vault (escopo 5F-β-α)

| jobid | jobname | schedule | settings usadas |
|---|---|---|---|
| 28 | `analyze-conversations-weekly` | `0 4 * * 1` | `app.supabase_url` + `app.service_role_key` (formato 5D) |

### Jobs `update-*` com formato ANTIGO (`app.settings.service_role_key`) — FORA DE ESCOPO

| jobid | jobname | schedule |
|---|---|---|
| 3 | update-mercadona | `0 3 * * 1` |
| 4 | update-continente | `0 3 * * 2` |
| 5 | update-pingodoce | `0 3 * * 3` |
| 6 | update-lidl | `0 3 * * 4` |
| 7 | update-auchan | `0 3 * * 5` |
| 8 | update-intermarche | `0 3 * * 6` |
| 9 | update-restaurants | `0 3 1 * *` |

⚠️ **DESCOBERTA**: 7 jobs `update-*` usam `current_setting('app.settings.service_role_key', true)` (formato com `.settings.`) — diferente de `app.service_role_key`. Provavelmente JÁ ESTÃO QUEBRADOS porque ALTER DATABASE também não consegue setar `app.settings.*` em Supabase managed. URLs estão hardcoded.

**Recomendação**: tratar em sessão separada (não 5F-β-α). Audit pre-vault: confirmar via `cron.job_run_details` se estão a falhar há tempo.

✅ **Gate A3 PASS** — 1 cron job em escopo (analyze-conversations-weekly).

---

## A4 — Análise de Impacto

### Migrations FASE B planeadas

| Migration | Conteúdo | Risco |
|---|---|---|
| **B1** `5f_beta_alpha_b1_vault_secrets` | INSERT 2 secrets via `vault.create_secret` (idempotente) | ⚠️ Contém service_role_key em plain text |
| **B2** `5f_beta_alpha_b2_trigger_refactor` | CREATE OR REPLACE `_notify_admin_urgent_trigger` | Baixo — apenas fonte settings muda |
| **B3** `5f_beta_alpha_b3_other_functions_refactor` | REPLACE `admin_approve_action` + `fn_notify_admin_pending_action` | Baixo — mesma lógica |
| **B4** `5f_beta_alpha_b4_cron_refactor` | `cron.alter_job(28, ...)` para `analyze-conversations-weekly` | Baixo — preserva schedule |

### Riscos identificados
1. **B1 contém secret em git history** → ⚠️ DECISÃO DANILO necessária (Opção A/B/C):
   - **A**: gitignore migration B1
   - **B**: aplicar via apply_migration sem committar `.sql` ⭐ **RECOMENDADA**
   - **C**: aceitar key + rotar imediatamente
2. **Logs Claude Code expostos** → mitigado: interpolação directa `apply_migration`, sem echo
3. **Múltiplas funções** → mitigado: B3 usa template + diff por função

### Plano rollback
- `DELETE FROM vault.secrets WHERE name IN ('project_url','service_role_key')`
- CREATE OR REPLACE com versão anterior (current_setting)
- `cron.alter_job(28, command_old)`

### Features que activam após FASE B
- ✅ 5D cron auto-suggest skills (analyze-conversations weekly)
- ✅ 5B-β1 push admin pending actions
- ✅ 5F-β push admin urgência crítica
- ✅ PASSWORD_RESET real (se 5B-β1 dispatch via pg_net)

---

## A5 — Skill Identification

**Skill aplicável**: nenhuma das 21 skills crosstalk corresponde directamente a infrastructure migration. Esta sessão é manual (Claude Code direct execution).

---

## DECISÕES PENDENTES (luz verde Danilo)

1. **Confirmar Opção B1** (recomendada): aplicar migration B1 via `apply_migration` SEM committar o `.sql` ao git. Histórico migration apenas em Supabase.
2. **Confirmar escopo B3**: refactorizar `admin_approve_action` + `fn_notify_admin_pending_action` (5B-β1)? Ou apenas a primeira?
3. **Confirmar escopo B4**: refactorizar apenas `analyze-conversations-weekly` (jobid 28). Os 7 jobs `update-*` ficam para sessão separada.
4. **Próximo passo**: avançar FASE B com 4 migrations + smokes S1–S17 + commit + push?

---

## ⛔ STOP — Aguardar aprovação Danilo

Nenhuma mutação foi feita. Apenas SELECTs read-only + leitura `.env` local (sem expor valor).
