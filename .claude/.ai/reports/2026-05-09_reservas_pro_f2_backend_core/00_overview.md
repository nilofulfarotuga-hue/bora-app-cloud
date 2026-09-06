# Sessão RESERVAS-PRO-F2-BACKEND-CORE — Overview

**Data:** 2026-05-09
**Modo:** Opção A (MCP directo via Claude.ai antes; sync repo agora)
**Branch:** `autonomous-night-2026-04-29`
**HEAD anterior:** `39fd6e9` (F1 SCHEMA)

## Resultado

10 RPCs (4 cliente + 6 parceiro) + 5 triggers + 5 CRON jobs +
6 helper functions + auto-logic VIP/block + 9 push parceiro + 7 push cliente.

## Migrations aplicadas em prod (validadas via MCP)

| Version | Name |
|---|---|
| `20260509000041` | `reservas_pro_f2a_triggers_and_helpers` |
| `20260509000306` | `reservas_pro_f2b_client_rpcs` |
| `20260509000407` | `reservas_pro_f2c_partner_rpcs` |
| `20260509000453` | `reservas_pro_f2d_cron_jobs` |

## Migration files locais (sync via esta sessão)

Timestamps batem 100% com `supabase_migrations.schema_migrations`:

- `supabase/migrations/20260509000041_reservas_pro_f2a_triggers_and_helpers.sql`
- `supabase/migrations/20260509000306_reservas_pro_f2b_client_rpcs.sql`
- `supabase/migrations/20260509000407_reservas_pro_f2c_partner_rpcs.sql`
- `supabase/migrations/20260509000453_reservas_pro_f2d_cron_jobs.sql`

## Validação A0 (read-only, pré-sync)

| Check | Esperado | Real | Status |
|---|---|---|---|
| Migrations applied | 4 | 4 | ✓ |
| RPCs cliente | 4 | 4 | ✓ |
| RPCs parceiro | 6 | 6 | ✓ |
| Triggers (reservations + waitlist) | 5 | 5 | ✓ |
| CRON jobs (`reservas_pro_*`) | 5 | 5 | ✓ |
| Numeração próxima §X | §51 (após §50) | §51 | ✓ |
| Timestamps locais livres | nenhum `20260509000*` | nenhum | ✓ |

## Nota sobre fidelidade dos ficheiros locais

Char counts diferem ligeiramente do prod (deltas: -25 a -136 ASCII chars
em 4 ficheiros). Origem: trailing whitespace em linhas brancas dentro
de funções PL/pgSQL (Postgres ao guardar via `apply_migration` preserva
indentação visual em blank lines com 2 espaços) + `-- ` (comment com
trailing space) em separadores de header.

**Multi-byte UTF-8 chars (`═`, `─`, `•`, acentos `Ç/ã/ê`) batem 100%
em todos os ficheiros** — overhead UTF-8 em bytes é exactamente igual
ao prod (526/494/614/626 bytes overhead respectivamente).

**Funcionalmente idêntico ao prod**: trailing whitespace pré-newline
não afecta parsing PL/pgSQL nem schema_migrations tracking. Migrations
estão aplicadas — ficheiros locais servem documentação/source-of-truth
mirror, não re-aplicação.

## 6 Helper Functions

- `_reservas_pro_get_partner_user_id(restaurant_id)` — devolve dono
- `_reservas_pro_get_turn_time(restaurant_id, party, dow?)` — minutos turn time
- `_reservas_pro_notify_partner_push(uid, kind, title, body, related_id)` — wrapper in-app + FCM (FCM comentado)
- `_reservas_pro_match_notify_list(restaurant_id, slot_time, people)` — auto-OpenTable (max 5 FIFO)
- `_reservas_pro_update_client_profile(client_id, restaurant_id, action)` — visit/no_show/late_cancel + auto-VIP/block
- `_reservas_pro_assert_partner(restaurant_id)` — guard SECURITY DEFINER

## Roadmap

- **F1 SCHEMA:** APLICADA (commit `39fd6e9`)
- **F2 BACKEND CORE:** APLICADA (esta sessão — sync repo)
- **F3 UI CLIENTE** (~3-5h): PENDENTE
  - Floor plan visualizer, table selection, waitlist UI, notify UI
  - Calls aos 4 RPCs cliente
- **F4 UI PARCEIRO + ADMIN** (~5-10h): PENDENTE
  - Configurador floor plans, pacing rules, turn times
  - Walk-in flow, VIP management, blocked clients
  - Push #8 (VIP) e #9 (blocked client tentou) ainda por implementar

## TODOs

- [ ] **TODO 7-α (global):** débito histórico de `supabase db pull` continua aberto.
- [ ] **F2 FCM real:** activar `net.http_post` em `_reservas_pro_notify_partner_push` quando Firebase Service Account configurado em production secrets.
- [ ] F3 UI CLIENTE — implementar fluxos cliente (search → reserve → arrived).

## Ficheiros tocados nesta sessão

| Tipo | Caminho |
|---|---|
| Migration | `supabase/migrations/20260509000041_*.sql` |
| Migration | `supabase/migrations/20260509000306_*.sql` |
| Migration | `supabase/migrations/20260509000407_*.sql` |
| Migration | `supabase/migrations/20260509000453_*.sql` |
| Doc rules | `.claude/.ai/business_rules.md` (§51 + footer) |
| Doc context | `PROJECT_CONTEXT.md` (§13 expandido com F2) |
| Doc context | `.claude/skills/ceo-ai/references/PROJECT_CONTEXT.md` (§13 espelho) |
| Relatório | `.claude/.ai/reports/2026-05-09_reservas_pro_f2_backend_core/00_overview.md` |
| Relatório | `.claude/.ai/reports/2026-05-09_reservas_pro_f2_backend_core/01_notification_flows.md` |
| Obsidian | `.obsidian-vault/sessoes/2026-05-09_reservas_pro_f2_backend_core/00_overview.md` |
| Obsidian | `.obsidian-vault/sessoes/2026-05-09_reservas_pro_f2_backend_core/01_notification_flows.md` |

Zero touches em código de produção (Flutter/Edge Functions).
