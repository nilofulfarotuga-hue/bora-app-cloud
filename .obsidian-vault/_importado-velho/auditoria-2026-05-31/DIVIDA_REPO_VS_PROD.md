# 🔴 DÍVIDA: Repo vs Produção (DB) — 2026-05-31
> Mudanças que estão **LIVE na DB de produção** mas **NÃO existem como migration no repo**.
> Risco: um futuro `db reset` / re-deploy do repo **reverte-as** (reintroduz os bugs/buracos).

## ✅ RESOLVIDO 2026-05-31 (migrations criadas no repo)
| # | Mudança (live na DB) | Migration no repo | Estado |
|---|---|---|---|
| 1 | **`receipts` bucket privado** (`public=false`) | `20260531070000_make_receipts_bucket_private.sql` | ✅ alinhado |
| 2 | **Cron `bora_dispatch_maintenance`** usa `net.http_post` | `20260531064411_fix_dispatch_maintenance_net_http_post.sql` (corpo EXATO de prod) | ✅ alinhado |
| 3 | **`admin_list_orphans` guarded** (authenticated+service_role, anon revogado) | `20260531060919_admin_list_orphans_guard.sql` (reflete estado VIVO) | ✅ alinhado |

> Ficheiros criados a refletir o **estado vivo** (verificado por `pg_get_functiondef` + grants). **Nada re-aplicado** contra prod (já vivo). `business_rules.md:3715` já documenta o bucket `receipts` como privado.

## ⚠️ Notas para o deploy
- As migrations cloud `20260531060919` (orphans) e `20260531064411` (cron) **já estão no histórico da nuvem**. Os ficheiros locais agora existem para **fidelidade num deploy fresco**. Contra a nuvem EXISTENTE, **não correr `supabase db push`** sem confirmar — se houver mismatch de checksum (a migration cloud de orphans gravou a variante que revogava `authenticated`; o ficheiro local reflete o estado corrigido com `authenticated` concedido), usar `supabase migration repair --status applied <versão>` para marcar como aplicada **sem re-correr** (NÃO executar contra prod sem aprovação do Danilo).
- A migration `20260531070000` (bucket privado) é **idempotente** — segura mesmo que corra de novo.

## Recomendações futuras
- **Regra:** toda mudança direta na DB de produção deve ganhar migration no repo (senão drift silencioso).
- Auditoria periódica: `list_migrations` (cloud) vs `supabase/migrations/` (repo) vs estado real (`pg_get_functiondef`).

> Verificado por MCP em 2026-05-31: `receipts public=false` ✅, `bora_dispatch_maintenance` usa `net.http_post` ✅, `admin_list_orphans` grants = authenticated/service_role (anon revogado) ✅.
