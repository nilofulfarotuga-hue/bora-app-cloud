---
name: manage-promo-codes
description: Cria/lista/desativa códigos promocionais via RPCs admin existentes (admin_create_promo_code / admin_list_promo_codes / admin_deactivate_promo_code). Dry-run default; --commit chama a RPC com JWT de admin. Avisa impacto na margem. NÃO toca pricing_service.
metadata:
  type: operacoes
  category: promo
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# Manage Promo Codes

Gere códigos promocionais usando as **RPCs admin existentes** (tabela `promo_codes` +
`promo_code_uses`). Não reimplementa lógica de desconto nem toca `pricing_service`.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md` (margem/comissão)
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, e **JWT de admin**
(`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`) — as RPCs `admin_*` exigem `is_admin()`.

## RPCs usadas (assinaturas confirmadas via MCP)
- `admin_create_promo_code(p_code, p_type, p_value_cents, p_value_pct, p_max_uses,
  p_max_uses_per_user, p_min_order_cents, p_valid_until, p_partner_ids)`
- `admin_list_promo_codes(p_active_only, p_search, p_limit, p_offset)`
- `admin_deactivate_promo_code(p_code, p_reason)`

## Uso
```bash
python scripts/list_promos.py --active-only
python scripts/create_promo.py --code BORA10 --type pct --value 10 --max-uses 100 --expires 2026-12-31   # dry-run
python scripts/create_promo.py --code BORA10 --type pct --value 10 --max-uses 100 --expires 2026-12-31 --commit
```

## Mapeamento --type
- `pct` → `p_value_pct` (ex.: 10 = 10%). `fixed` → `p_value_cents` (ex.: 500 = €5.00).

## Salvaguardas
- Dry-run default; `--commit` chama a RPC (admin). Idempotência delegada à RPC (código único).
- **Aviso de margem**: desconto reduz receita Bora — o relatório alerta (especialmente em
  códigos pct elevados ou sem `min_order`). NÃO altera comissões nem `pricing_service`.
- **Admin UI**: gestão de promos devia ter ecrã admin — **pendência** anotada.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
