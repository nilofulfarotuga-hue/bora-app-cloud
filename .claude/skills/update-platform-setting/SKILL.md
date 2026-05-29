---
name: update-platform-setting
description: Altera UMA chave de platform_settings com segurança — dry-run gera SQL + impacto + chaves dependentes; --commit aplica + admin_audit_log + cria nota ADR em decisions/. Chaves blindadas (stripe_/dispatch_/pricing_/commission_/fee_) exigem --i-know-what-im-doing.
metadata:
  type: operator
  category: config
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Update Platform Setting

Altera **uma** chave runtime de `platform_settings` (= regra de negócio). Dry-run por
defeito. Confirmar SEMPRE com Danilo antes de `--commit` (impacto em pricing/fees/dispatch).

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/09-platform-settings.md`
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`,
`BORA_ADMIN_EMAIL` (opcional).

## Uso
```bash
python scripts/show_setting.py --key reservation_prepayment_cents
python scripts/update_setting.py --key reservation_prepayment_cents --value 400 --reason "Subida do prépagamento"          # dry-run
python scripts/update_setting.py --key reservation_prepayment_cents --value 400 --reason "..." --commit
# chave blindada (contém 'fee_'):
python scripts/update_setting.py --key delivery_base_fee_cents --value 300 --reason "..." --i-know-what-im-doing --commit
```

## 🔒 Chaves blindadas (proteção de fórmulas sagradas)
Qualquer chave que contenha `stripe_`, `dispatch_`, `pricing_`, `commission_` ou `fee_`
**exige `--i-know-what-im-doing`** (mesmo em dry-run avisa; em `--commit` bloqueia sem a flag).
Ex.: `delivery_base_fee_cents`, `bag_fee_restaurant_cents`, `partner_visible_commission_pct`, `dispatch_offer_timeout_seconds`.
> Nota: a regra é por **substring**. Chaves como `delivery_per_km_cents` NÃO contêm nenhum
> dos substrings e por isso **não** são blindadas (embora sejam pricing) — rever caso a caso.

## Modos
- **DEFAULT (dry-run)**: lê valor atual, mostra `old → new`, gera o **SQL**, lista **chaves
  dependentes** (mesmo prefixo/categoria). NÃO escreve.
- **`--commit`**: `UPDATE platform_settings SET value=:json::jsonb, updated_at=now(),
  updated_by=:admin WHERE key=:key` (1 linha) + `admin_audit_log` + cria
  `decisions/{data}-update-setting-{key}.md` (porquê).

## Salvaguardas
- `--value` tem de ser **JSON válido** (número/bool/string/objeto) — a coluna é `jsonb`.
- `--reason` é **obrigatório** em `--commit` (vai para a nota ADR + auditoria).
- Atua só na chave indicada (nunca em massa). Idempotente (valor já igual → exit 0).
