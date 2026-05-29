---
name: run-weekly-payouts
description: Gera o relatório de payouts semanais (estafetas + parceiros) somando ledger_entries do período — net a pagar por entidade + CSV. SEMPRE dry-run; NUNCA executa transferências nem toca bora_tokens/Stripe. Execução real = humano/Stripe Connect.
metadata:
  type: financeiro
  category: report
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Run Weekly Payouts (relatório, read-only)

Calcula quanto há a pagar a cada estafeta e parceiro no período, **somando `ledger_entries`**
(fonte de verdade — não recalcula fórmulas). **Não executa transferências.**

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md` (fórmulas — referência, não recálculo)
2. `bora-knowledge/knowledge/07-database-key-tables.md` (`ledger_entries`)
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Modelo (confirmado via MCP)
`ledger_entries`: `user_id`(TEXT), `user_type`{driver,platform,restaurant}, `order_id`,
`amount`(numeric, sinalizado), `type`{earning,commission,payout,cash_adjustment}, `created_at`.

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/payouts.py                       # últimos 7 dias
python scripts/payouts.py --days 14
python scripts/payouts.py --since 2026-05-01T00:00:00Z --until 2026-05-08T00:00:00Z
```

## O que faz
1. Lê `ledger_entries` do período (paginado).
2. Agrupa por `(user_type, user_id)`: totais por `type` + **net** (soma sinalizada).
3. Relatório PT-BR (estafetas e parceiros) + `_preview/payouts_{periodo}.csv`.
4. **Dry-run sempre** — não há `--commit`. A transferência real é decisão humana (Stripe Connect).

## Salvaguardas
- **READ-ONLY**: só `SELECT ledger_entries`. NUNCA mexe em `bora_tokens`, `orders`, Stripe.
- Não recalcula comissões (usa os valores já lançados no ledger; fórmulas só p/ referência humana).
- `platform` é mostrado como informação (margem Bora), não como payout.
