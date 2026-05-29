---
name: dedupe-market-products
description: Identifica e limpa produtos de mercado duplicados (mesmo search_normalized + mesma loja) com merge inteligente — mantém o mais completo, soft-delete dos restantes via is_available=false (NUNCA hard delete). Backup CSV antes. Não toca parceiros. Dry-run default.
metadata:
  type: data
  category: market
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Dedupe Market Products

Remove duplicados dentro da **mesma loja de mercado** (agrupados por `search_normalized`).
**Soft-delete apenas** (`is_available=false`) — nunca `DELETE` físico. Mantém o registo
mais completo. Não toca produtos de restaurantes parceiros.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/07-database-key-tables.md`
2. `bora-knowledge/knowledge/10-protected-zones.md` (hard delete proibido)

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/find_duplicates.py --store continente-guarda          # grupos com >1 → CSV
python scripts/merge_duplicates.py --store continente-guarda         # dry-run (plano de merge)
python scripts/merge_duplicates.py --store continente-guarda --commit
```

## Como escolhe o "vencedor" (registo a manter)
Pontuação por completude: tem preço>0 (+3), tem foto / needs_photo=false (+2),
needs_review=false (+2), description não-vazia (+1), is_available=true (+1).
Empate → mantém o `id` mais antigo (lexicográfico estável). Os outros do grupo ficam
**soft-deleted** (`is_available=false`, `needs_review=true`).

## Modos
- **DEFAULT (dry-run)**: agрupa, escolhe vencedor, escreve `_preview/dedupe_plan.csv` +
  backup `_preview/backup_<store>.csv` (grupos completos). NÃO escreve na DB.
- **`--commit`**: aplica soft-delete dos perdedores + `admin_audit_log`.

## Salvaguardas
- **SOFT delete só** (`is_available=false`) — não há `is_deleted/deleted_at` (pendência);
  marca também `needs_review=true` para rastreio. NUNCA `DELETE`.
- Só lojas de **mercado** (allowlist). Recusa partner/fast-food/uuid.
- Backup CSV de cada grupo antes de qualquer mutação.
- Nunca toca preço dos vencedores nem de parceiros.
