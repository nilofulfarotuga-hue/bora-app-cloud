# README — audit-protected-zones (read-only)

Meta-skill de segurança: confirma que as zonas protegidas não mudaram. Correr antes de build.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/audit.py --save-baseline   # grava baseline (hashes + estado)
python scripts/audit.py                    # compara vs baseline → relatório PT-BR
python scripts/audit.py --json
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `REPO_ROOT` |
| `audit.py` | sha256 de ficheiros-chave + triggers/Edge Fns + comparação vs baseline |

## Notas
- Baseline em `_baseline/protected_zones.json` (commitável; versiona o "estado bom conhecido").
- Edge Functions count (44) não é listável via REST → o relatório lembra de verificar via MCP.
- Read-only. Exit 1 se detetar drift (hash diferente / trigger/Edge Fn em falta).
