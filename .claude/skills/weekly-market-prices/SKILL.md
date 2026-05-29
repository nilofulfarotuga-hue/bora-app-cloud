---
name: weekly-market-prices
description: Orquestra o update semanal de preços de mercado. Verifica saúde dos pg_cron de preços, corre o update do Continente (Product-Show + JSON-LD, 3.5s/req) e gera relatório de diferenças. SÓ Continente (método confirmado). NUNCA preços de Uber/Glovo. Dry-run default.
metadata:
  type: data
  category: market
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Weekly Market Prices

Gere o ciclo semanal de **preços** de mercado. Não inventa scraping novo — orquestra o
método **confirmado** para o Continente e reporta. **Preço só de fonte oficial da loja.**

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md` (preço puro, markup runtime)
2. `bora-knowledge/knowledge/07-database-key-tables.md`
3. `bora-knowledge/knowledge/10-protected-zones.md` (preço/pricing intocáveis)

## Regras de preço (críticas)
- **SÓ Continente** tem método confirmado (Product-Show + JSON-LD, segunda-feira, **3.5s/req**).
- `auchan.pt` e `pingodoce.pt`: `robots.txt` **proíbe** scraping SFCC → **bloqueados** (anotado).
- Mercadona/Lidl/Intermarché: preço por fonte própria (fora desta skill por agora).
- **NUNCA** usar preço de Uber Eats / Glovo. Glovo÷1.15 é só fallback de *importação* inicial, não update.

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/check_cron_health.py                                  # estado dos pg_cron de preço
python scripts/run_continente_update.py --limit 50                   # dry-run (Product-Show, 3.5s/req)
python scripts/run_continente_update.py --commit                     # grava preços (só Continente)
python scripts/price_diff_report.py --snapshot-before before.csv     # compara antes/depois
```

## Modos
- **DEFAULT (dry-run)**: resolve preços do site oficial, mostra `antigo → novo`, NÃO grava.
- **`--commit`**: `UPDATE products SET price=:p, last_updated=:ts WHERE id=:id` (só Continente)
  + `admin_audit_log`. Rate limit obrigatório (`--rate`, default 3.5s).

## Salvaguardas
- Só `restaurant_id='continente-guarda'`. Outros mercados → recusa + nota de bloqueio.
- Só toca `price` (e `last_updated`); nunca markup, nunca comissões.
- Rate limit cortês obrigatório. `price_diff_report` para auditar antes de aplicar em massa.
