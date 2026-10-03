# Sessão RESERVAS-PRO-F1-SCHEMA — Overview

**Data:** 2026-05-08
**Modo:** Opção A (MCP directo via Claude.ai antes; sync repo agora)
**Branch:** `autonomous-night-2026-04-29`

## Resultado

8 tabelas novas + 10 colunas em `reservations` + 13 settings + 14 RLS
policies + 9 índices + 4 triggers + 1 função helper.

## Migrations aplicadas em prod (validadas via MCP)

| Version | Name |
|---|---|
| `20260508231040` | `reservas_pro_f1_01_restaurant_config_tables` |
| `20260508231127` | `reservas_pro_f1_02_reservation_runtime_tables` |
| `20260508231156` | `reservas_pro_f1_03_alter_reservations_and_settings` |

## Migration files locais (sync via esta sessão)

Timestamps batem 100% com `supabase_migrations.schema_migrations`
em prod (zero drift, zero risco de re-aplicação acidental):

- `supabase/migrations/20260508231040_reservas_pro_f1_01_restaurant_config_tables.sql`
- `supabase/migrations/20260508231127_reservas_pro_f1_02_reservation_runtime_tables.sql`
- `supabase/migrations/20260508231156_reservas_pro_f1_03_alter_reservations_and_settings.sql`

## Validação A0 (read-only, pré-sync)

| Check | Esperado | Real | Status |
|---|---|---|---|
| Migrations applied | 3 | 3 | ✓ |
| Tabelas criadas | 8 | 8 | ✓ |
| Cols `reservations` | 10 | 10 | ✓ |
| Settings `reservation_*` | 19 (6 antigas + 13 novas) | 19 | ✓ |
| RLS policies | 14 | 14 | ✓ |
| Numeração próxima §X | §50 (após §49) | §50 | ✓ |
| PROJECT_CONTEXT.md root | existe | existe | ✓ |
| PROJECT_CONTEXT.md ceo-ai | existe | existe | ✓ |

## Roadmap

- **F1 SCHEMA:** APLICADA (esta sessão sincroniza repo)
- **F2 BACKEND CORE** (~4-6h): PENDENTE
- **F3 UI CLIENTE** (~3-5h): PENDENTE
- **F4 UI PARCEIRO + ADMIN** (~5-10h): PENDENTE

## TODOs

- [ ] **TODO 7-α (global):** `supabase db pull` quando viável para
  sincronizar TODAS as migrations aplicadas via MCP que não estão
  em ficheiros locais (não só estas 3). Débito histórico em §48.2.
- [ ] F2 BACKEND CORE — Edge Functions + RPCs + CRON reminders.

Zero touches em código de produção (Flutter/Edge Functions).
