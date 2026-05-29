---
name: audit-protected-zones
description: Meta-skill de segurança read-only — verifica que as zonas protegidas continuam intactas (pricing_service, dispatch, bora_tokens triggers, Stripe, ficheiros-chave) comparando com um baseline de hashes/contagens. Relatório PT-BR ✅/⚠️/❌. Correr ANTES de cada build.
metadata:
  type: qa
  category: readiness
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Audit Protected Zones (read-only)

Confirma que nada nas zonas protegidas mudou sem querer. **Read-only.** Corre antes de build.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/10-protected-zones.md` (a fonte da verdade do que proteger)

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (para checks de DB).

## Uso
```bash
python scripts/audit.py --save-baseline      # 1ª vez: grava baseline (hashes/contagens atuais)
python scripts/audit.py                       # compara estado vs baseline → relatório
python scripts/audit.py --json
```

## O que verifica
| Zona | Check |
|------|-------|
| Ficheiros-chave Flutter | sha256 de `lib/services/pricing_service.dart`, `lib/config/app_theme.dart`, `app_colors.dart`, `lib/dispatch/driver_capacity_service.dart`, `main.dart` vs baseline |
| bora_tokens trigger | `trg_award_tokens_on_delivery` presente (`information_schema.triggers`) |
| orders_financial_lock | trigger de imutabilidade financeira presente |
| Stripe/pagamentos | Edge Fns `create-payment-intent`/`stripe-webhook`/`refund` vivas (OPTIONS) |
| Edge Functions count | baseline 44 — **verificar via MCP** `list_edge_functions` (REST não lista) |

## Baseline
`_baseline/protected_zones.json` (commitável). `--save-baseline` (re)grava. Sem baseline,
o 1º run só fotografa e avisa. Mudança de hash de ficheiro protegido → **❌** (rever se intencional).

## Salvaguardas
- **Read-only total**: só lê ficheiros + catálogo de sistema da DB + OPTIONS.
- Não corrige nada — apenas alerta. Exit 1 se houver ❌ (drift detetado).
