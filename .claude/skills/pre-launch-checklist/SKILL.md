---
name: pre-launch-checklist
description: Auditoria read-only de prontidão para lançamento — agrega contagens dos pontos críticos (drivers/restaurants pending, produtos sem preço/imagem, settings críticos, admin_audit_log recente) e devolve relatório PT-BR com ✅/⚠️/❌ por categoria. Não escreve nada.
metadata:
  type: auditor
  category: readiness
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Pre-Launch Checklist (read-only)

Tira uma "fotografia" de prontidão para lançamento. **Não escreve nada** — só lê e agrega.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/07-database-key-tables.md`
2. `bora-knowledge/knowledge/09-platform-settings.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/checklist.py                       # imprime + escreve _preview/checklist.md
python scripts/checklist.py --json                # saída JSON (para pipelines)
```

## O que verifica
| Categoria | Métrica | Critério |
|-----------|---------|----------|
| Estafetas | `drivers.approval_status='pending'` | ⚠️ se >0 (há candidaturas por rever) |
| Parceiros | `restaurants.approval_status='pending'` | ⚠️ se >0 |
| Catálogo | produtos sem preço (`price` null/0) | ❌ se >0 |
| Catálogo | produtos sem imagem (`photo_url` null/'') | ⚠️ se >0 |
| Config | settings críticos presentes e não-nulos | ❌ se faltar algum |
| Auditoria | `admin_audit_log` últimos 7 dias | info (atividade admin) |
| Edge Fns | baseline 44 (S2) | info — **verificar via MCP** `list_edge_functions` (REST não lista) |

Settings críticos verificados: `delivery_base_fee_cents`, `driver_base_fee_cents`,
`max_cash_amount_cents`, `dispatch_offer_timeout_seconds`, `partner_visible_commission_pct`,
`token_value_cents_x100`, `non_partner_markup_pct`.

## Salvaguardas
- **Read-only total** — zero escrita, zero Edge Fns, nenhum efeito colateral.
- Contagens via `Prefer: count=exact` (não traz linhas — eficiente em catálogos grandes).
