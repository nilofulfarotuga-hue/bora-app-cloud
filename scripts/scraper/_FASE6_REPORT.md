# Fase 6 — Relatório Final (3 mercados em falta)

**Data:** 2026-04-19
**Modo:** PROTECÇÃO TOTAL (CEO-AI orchestrator)
**Ordem executada:** Pingo Doce → Lidl → Intermarché

## Resultado final (DB)

| Mercado (restaurant_id) | Total | L1  | L2  | Badges | Fonte |
| --- | --- | --- | --- | --- | --- |
| pingodoce-guarda | 9.542 | **6.500** | 0 | 0 | `pingodoce_sfcc_bestsellers_2026-04-19` |
| lidl-guarda | 9.085 | 0 | **6.083** | 0 | `lidl_off_brands_2026-04-19` |
| intermarche-guarda | 6.504 | **3.500** | 0 | 0 | `intermarche_off_brands_2026-04-19` |

Todas as metas alcançadas. Zero /badges/ leaked. Zero failures nos INSERTs.

## Descobertas chave

### 1) Pingo Doce = SFCC (Salesforce Commerce Cloud)
Tal como Continente e Auchan. **Playwright não foi necessário.** Endpoint directo HTTP:
`https://www.pingodoce.pt/on/demandware.store/Sites-pingo-doce-Site/default/Search-UpdateGrid?srule=best-sellers&start={start}&sz=48&cgid=root`

- Scraper: [_pd_scrape.mjs](scripts/scraper/_pd_scrape.mjs)
- Parser: regex `data-gtm-info` + filtro `/Sites-pingo-doce-master/` (reject badges)
- Duração: ~140s, 130 páginas × 1s sleep
- Produtos únicos colhidos: 6.488 (L1 CDN próprio)

### 2) Lidl = API auth-gated → fallback OFF (L2)
Tentadas todas variantes `/q/api/search` e `/q/api/gridboxes` → 401/404. Playwright captura confirmou: todas chamadas dependem de token assinado. Per BR §27.2 actualizado e aprovação do utilizador, caiu para L2 OpenFoodFacts.

- Probe Playwright: [_lidl_spike.mjs](scripts/scraper/_lidl_spike.mjs), [_lidl_cat.mjs](scripts/scraper/_lidl_cat.mjs)
- Scraper final: [_lidl_off_v2.mjs](scripts/scraper/_lidl_off_v2.mjs) (search-a-licious, não world API — muito mais rápido)
- Query: `brands:lidl`, filtro `isLatinish` para excluir Cyrillic/CJK
- Duração: 132s, 6.083 produtos colhidos

### 3) Intermarché = sem loja online → OFF como L1 (excepção)
Per aprovação do utilizador: "Intermarché: contar como L1 (sem loja online, é melhor fonte disponível)". Target reduzido para 3.000.

- Scraper: [_intermarche_off.mjs](scripts/scraper/_intermarche_off.mjs)
- Queries combinadas (próprias-marcas Intermarché/Les Mousquetaires):
  - `brands:Intermarché` → 1.808 produtos
  - `brands:"Pâturages"` → 521
  - `brands:"Monique Ranou"` → 841
  - `brands:"Top Budget"` → 330
- Duração: 79s, 3.500 únicos (colheu-se acima para dedup seguro)

## Erros encontrados e mitigações

| Erro | Mitigação |
| --- | --- |
| `require is not defined` (ESM) | Renomear .js→.mjs (package.json `"type":"module"`) |
| OFF world API 503 após 380 produtos | Migrar para `search.openfoodfacts.org` (search-a-licious) |
| `p.brands.split is not a function` | `Array.isArray(p.brands) ? p.brands : String(p.brands\|\|'').split(',')` |
| Lidl 401/404 universal | Fallback OFF L2 (aprovado pelo utilizador) |
| Background `&` matava o processo Node | Foreground com `timeout: 540000` |

## Rollback SQL (atómico por fonte)

```sql
-- Reverter Pingo Doce Fase 6
DELETE FROM products WHERE source = 'pingodoce_sfcc_bestsellers_2026-04-19';

-- Reverter Lidl Fase 6
DELETE FROM products WHERE source = 'lidl_off_brands_2026-04-19';

-- Reverter Intermarché Fase 6
DELETE FROM products WHERE source = 'intermarche_off_brands_2026-04-19';
```

## BR §25.3 — Zonas protegidas

Nenhum ficheiro Flutter (`lib/**`), migration (`backend/supabase/migrations/**`) ou edge function (`backend/supabase/functions/**`) foi tocado. Toda a actividade ficou confinada a `scripts/scraper/**` + inserts via REST na tabela `products`.

## Ficheiros produzidos nesta fase

- [_pd_inspect.mjs](scripts/scraper/_pd_inspect.mjs) — probe SFCC Pingo Doce
- [_pd_scrape.mjs](scripts/scraper/_pd_scrape.mjs) — scraper Pingo Doce
- [_lidl_spike.mjs](scripts/scraper/_lidl_spike.mjs) — probe Playwright Lidl (homepage)
- [_lidl_cat.mjs](scripts/scraper/_lidl_cat.mjs) — probe Playwright Lidl (categoria)
- [_lidl_off.mjs](scripts/scraper/_lidl_off.mjs) — Lidl via OFF world API (descontinuado por 503)
- [_lidl_off_v2.mjs](scripts/scraper/_lidl_off_v2.mjs) — Lidl via OFF search-a-licious (final)
- [_intermarche_off.mjs](scripts/scraper/_intermarche_off.mjs) — Intermarché via OFF (multi-brand)
