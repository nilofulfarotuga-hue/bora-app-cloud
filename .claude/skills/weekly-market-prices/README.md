# README — weekly-market-prices

Orquestra o update semanal de preços de mercado. **Só Continente** (método confirmado).
Preço **só** de fonte oficial; **nunca** de Uber/Glovo.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo semanal (segunda-feira)
```bash
python scripts/check_cron_health.py                       # pg_cron de preço OK?
python scripts/run_continente_update.py --limit 50        # dry-run amostra
python scripts/run_continente_update.py --commit          # aplica (3.5s/req)
python scripts/price_diff_report.py                        # relatório de diffs (usa _preview/)
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `MARKET_STORES` + `audit_log` + rate-limit |
| `check_cron_health.py` | tenta ler `cron.job`/view de saúde; senão informa como verificar via MCP |
| `run_continente_update.py` | resolve preço via Product-Show + JSON-LD (3.5s/req); dry-run/--commit |
| `price_diff_report.py` | compara `_preview/prices_before.csv` vs `prices_after.csv` |

## Bloqueios conhecidos (robots.txt)
- `auchan.pt`, `pingodoce.pt`: SFCC scraping **proibido** → não suportado aqui.
- Mercadona/Lidl/Intermarché: preço por fonte própria (fora desta skill por agora).

## Notas
- `run_continente_update` resolve `product-show` por SKU/URL embutido no produto; se o produto
  não tiver URL/sku resolvível, **salta** e lista para revisão (não inventa preço).
- Só grava `price` + `last_updated`. Rate limit obrigatório (default 3.5s).
- pg_cron de preços é gerido fora (DB); esta skill **verifica e corre manualmente**, não cria cron.
