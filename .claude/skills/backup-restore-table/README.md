# README — backup-restore-table

Backup (read-only) e restore (UPSERT) de tabelas para JSON. Financeiras protegidas no restore.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo
```bash
python scripts/backup.py --table platform_settings
python scripts/restore.py --file .claude/.ai/backups/2026-05-29-platform_settings.json \
  --table platform_settings            # dry-run
python scripts/restore.py --file ... --table platform_settings --commit
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + `FINANCIAL_TABLES` + `REPO_ROOT` |
| `backup.py` | SELECT * paginado → `.claude/.ai/backups/{data}-{table}.json` (+gz se grande) |
| `restore.py` | dry-run/`--commit` UPSERT (merge-duplicates); gate financeiras |

## Notas
- Backup sempre seguro. Restore = UPSERT (não apaga ausentes).
- Financeiras (`bora_tokens`/`orders`/`ledger_entries`/`payments`/`wallet_transactions`) →
  `--i-know-what-im-doing` + `--reason`.
- Backups em `bora_app/.claude/.ai/backups/`. Gzip automático para ficheiros grandes.
