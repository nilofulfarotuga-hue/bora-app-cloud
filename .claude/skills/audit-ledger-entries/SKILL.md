---
name: audit-ledger-entries
description: Forensics financeiras read-only sobre ledger_entries — deteta entries órfãs (sem order), duplicados, sinais inesperados (earning negativo, commission positiva), e pedidos sem trio driver/platform. Só reporta, NUNCA corrige. Relatório PT-BR.
metadata:
  type: financeiro
  category: audit
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Audit Ledger Entries (read-only)

Auditoria forense do ledger. **Só deteta e reporta** — correção é decisão humana (nunca automática).

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/07-database-key-tables.md` (`ledger_entries`)
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/audit.py                 # todo o ledger
python scripts/audit.py --days 30       # só últimos 30 dias
python scripts/audit.py --json
```

## Verificações (heurísticas; só sinalizam)
- **Órfãs**: entries sem `order_id` (exceto `cash_adjustment`, que pode ser legítimo).
- **Duplicados**: mesma `(user_id, order_id, type, amount)` repetida.
- **Sinais inesperados**: `earning` < 0, `commission` > 0 (esperado ≤0 p/ a Bora cobrar), `payout` > 0.
- **Pedido incompleto**: `order_id` com lançamentos mas sem `user_type='driver'` nem `platform`.
- **Amount nulo/zero** em tipos que deviam ter valor.

## Salvaguardas
- **READ-ONLY absoluto**: só `SELECT`. Nunca `UPDATE`/`DELETE`/correção.
- Heurístico: cada achado lista `id`/`order_id` para investigação humana (pode haver exceções legítimas).
- Exit 1 se houver achados críticos (órfãs/duplicados/sinais), 0 se limpo.
