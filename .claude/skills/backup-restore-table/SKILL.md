---
name: backup-restore-table
description: Backup (read-only, sempre seguro) e restore (UPSERT) de tabelas-chave para JSON em .claude/.ai/backups/. Restore em tabelas financeiras (bora_tokens/orders/ledger_entries/payments) exige --i-know-what-im-doing + --reason. Restore dry-run default.
metadata:
  type: devops
  category: data
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Backup / Restore Table

Exporta e restaura tabelas. **Backup é sempre seguro (read-only).** Restore é controlado.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/07-database-key-tables.md`
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/backup.py --table platform_settings              # → .claude/.ai/backups/{data}-{table}.json
python scripts/restore.py --file <backup.json> --table platform_settings        # dry-run (mostra linhas)
python scripts/restore.py --file <backup.json> --table platform_settings --commit
# tabela financeira:
python scripts/restore.py --file b.json --table bora_tokens --i-know-what-im-doing --reason "..." --commit
```

## 🔒 Tabelas financeiras (restore exige flag + reason)
`bora_tokens`, `orders`, `ledger_entries`, `payments`, `wallet_transactions` →
restore **bloqueado** sem `--i-know-what-im-doing` + `--reason`. (Backup é sempre permitido.)

## Modos
- **backup.py**: read-only — `SELECT *` paginado → `.claude/.ai/backups/{YYYY-MM-DD}-{table}.json`
  (+ `.json.gz` se grande). Nunca escreve na DB.
- **restore.py DEFAULT (dry-run)**: lê ficheiro, mostra nº de linhas + amostra. NÃO escreve.
- **restore.py `--commit`**: UPSERT (PostgREST `Prefer: resolution=merge-duplicates`) + `admin_audit_log`.

## Salvaguardas
- Backup nunca é destrutivo. Restore faz **UPSERT** (não apaga o que não está no ficheiro).
- Tabelas financeiras protegidas (acima). `--reason` vai para auditoria.
- Backups versionados em `bora_app/.claude/.ai/backups/` (path relativo a REPO_ROOT).
- Pendência: backups grandes (orders/products ~44k) — usar `--limit`/filtro; gzip automático.
