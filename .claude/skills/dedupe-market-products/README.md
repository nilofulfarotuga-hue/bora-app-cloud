# README — dedupe-market-products

Limpa duplicados de mercado (mesma loja + `search_normalized`). **Soft-delete só.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo
```bash
python scripts/find_duplicates.py  --store continente-guarda          # → _preview/duplicates.csv
python scripts/merge_duplicates.py --store continente-guarda          # dry-run + backup
python scripts/merge_duplicates.py --store continente-guarda --commit # soft-delete perdedores
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `MARKET_STORES` + `audit_log` + paginação |
| `find_duplicates.py` | agrupa por `search_normalized`, lista grupos com >1 → CSV |
| `merge_duplicates.py` | escolhe vencedor (completude), backup CSV, dry-run/`--commit` soft-delete |

## Regras
- **Soft-delete = `is_available=false` + `needs_review=true`** (não há `is_deleted/deleted_at` — pendência).
- Vencedor por pontuação de completude (preço/foto/review/descrição). Empate → id mais antigo.
- Só lojas de mercado (allowlist). Parceiros/fast-food/uuid recusados.
- Backup `_preview/backup_<store>.csv` antes de mutar. Nunca hard delete. Nunca toca preço do vencedor.
