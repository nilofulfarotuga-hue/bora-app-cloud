# README — audit-orange-rule (read-only)

Audita "1 elemento laranja por ecrã" em `lib/screens/`. Não altera nada.

## Uso
```bash
python scripts/audit.py                 # todos os ecrãs
python scripts/audit.py --screen client_home_screen
python scripts/audit.py --json
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | `REPO_ROOT` + `log` resiliente (reusa motor S1) |
| `audit.py` | conta laranja dominante vs semântico por ecrã; [OK]/[!]/[X]; `_preview/orange_audit.md` |

## Notas
- Heurística: lista ficheiro:linha para revisão humana (gradients de tiles na home são OK legítimos).
- Exit 1 se algum ecrã [X] (3+ laranja dominante).
