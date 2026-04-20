# FASE 4 — HARVEST L1 POR MERCADO (RELATÓRIO FINAL 2026-04-18)

Executado: 2026-04-18
Orquestrador: `ceo-ai`
Status: ⚠️ **Parcialmente concluída — 2/4 mercados fechados, 3 deferidos**
Âmbito: replicar piloto Continente aos restantes 4 mercados

---

## 1. SUMÁRIO EXECUTIVO

| Mercado | Antes | +Batch | Depois | Meta ≥5k | Status Fase 4 |
|---|---:|---:|---:|:---:|---|
| mercadona-guarda | 5.011 | 0 | 5.011 | ✅ | Sem acção (já OK) |
| continente-guarda | 4.832 | +1.500 | **6.332** | ✅ | ✅ **Piloto validado** |
| auchan-guarda | 3.003 | +1.500 | **4.503** | ❌ (−497) | ✅ **L1 SFCC concluído** |
| pingodoce-guarda | 3.101 | 0 | 3.101 | ❌ (−1.899) | ⏸ Deferido (sem endpoint HTTP) |
| lidl-guarda | 3.002 | 0 | 3.002 | ❌ (−1.998) | ⏸ Deferido (SPA + auth 401) |
| intermarche-guarda | 3.004 | 0 | 3.004 | ❌ (−1.996) | ⏸ Deferido (sem loja online) |

Total produtos DB após Fase 4: **24.953** (antes: 21.953, delta: +3.000 L1 reais).
Produtos com `image_source = 'L1'`: **10.814** (Mercadona 5.011 + Continente 4.303 + Auchan 1.500).

---

## 2. CONTINENTE — PILOTO VALIDADO

Detalhes completos em [fase4_pilot_continente_2026-04-18.md](fase4_pilot_continente_2026-04-18.md).

| Métrica | Valor |
|---|---:|
| PIDs colhidos (90 páginas SFCC) | 3.148 |
| Usáveis (sem badge, com preço+imagem) | 1.794 |
| Após dedup vs. DB existente (4.832 rows) | 1.654 |
| Inseridos | 1.500 |
| Badges leaked | 0 |
| Chunks INSERT PostgREST | 8/8 OK |

Endpoint: `Search-UpdateGrid?srule=best-sellers&start={N}&sz=48&cgid=root` em `www.continente.pt`.

---

## 3. AUCHAN — PIPELINE REPLICADO

Descoberta: Auchan partilha plataforma Salesforce Commerce Cloud (SFCC) com Continente. Mesmo endpoint `Search-UpdateGrid`, só muda o site ID (`Sites-AuchanPT-Site`).

| Métrica | Valor |
|---|---:|
| Endpoint | `www.auchan.pt/on/demandware.store/Sites-AuchanPT-Site/pt/Search-UpdateGrid` |
| Parse field | `data-gtm` (vs `data-product-tile-impression` no Continente) |
| Páginas scraped | 50 (até timeout 300s) |
| PIDs colhidos | 2.400 |
| Usáveis | 2.392 |
| Após dedup vs. 3.003 existentes | 2.385 |
| Inseridos | 1.500 |
| Badges leaked | 0 |
| ID format | `auc-<pid>` (ex: `auc-3374864`) |

**Diferenças técnicas em relação ao Continente:**
- Auchan usa `data-gtm` JSON em vez de `data-product-tile-impression`
- 48 produtos por página (vs 35 Continente)
- Imagens em `/Sites-auchan-pt-master-catalog/` em `/hi-res/` (vs `-frente.{jpg|png}` Continente)
- Categorias em formato slug URL (`produtos-frescos/fruta/morangos-e-frutos-silvestres`) → limpas para `"Fruta / Morangos E Frutos Silvestres"`
- Nomes em MAIÚSCULAS (convenção Auchan) → convertidos para Title Case

**Rollback:** `DELETE FROM products WHERE source = 'auchan_sfcc_bestsellers_2026-04-18';`

---

## 4. PINGO DOCE — DEFERIDO

### Tentativas HTTP
| Endpoint | Resultado |
|---|---|
| `mercador.pingodoce.pt/*` | DNS ENOTFOUND |
| `compras.pingodoce.pt/*` | DNS ENOTFOUND |
| `mercadao.pt/pingo-doce` | 301 → pingodoce.pt (sem API) |
| `www.pingodoce.pt/produtos/` | 301 → /home/freshpage (SPA, sem JSON) |
| `www.pingodoce.pt/wp-json/*` | 301 → /not-found |
| `www.pingodoce.pt/sitemap_index.xml` | 200 mas 3 KB, só navegação |

**Conclusão:** Pingo Doce NÃO tem loja online pública HTTP no momento da auditoria. Scraper existente usa Playwright + intercepção de JSON (flaky).

### Opções para sessão dedicada
1. **Playwright + intercept** (scraper existente) — lento, dependente do flow anti-bot
2. **Inspeccionar DevTools** para descobrir endpoint interno real (possível Magento ou custom)
3. **L2 partilhado:** mirror de produtos Mercadona/Continente que validem como mesmo (nome normalizado + marca + unidade) → apenas imagens partilhadas, preços colhidos de folheto

---

## 5. LIDL — DEFERIDO

### Tentativas HTTP
| Endpoint | Resultado |
|---|---|
| `/q/api/search` | 401 Unauthorized (auth token necessária) |
| `/p/api/products/search` | 404 |
| `/c/folhetos/s10008844` | 404 a bots, 200 em browser |
| `/h/nossa-gama/` | 404 a bots |
| `/h/ofertas-da-semana/` | 404 a bots |

**Conclusão:** Site SPA (Nuxt.js) com API Private protegida por token. Endpoint `/q/api/search` é conhecido mas requer:
- Anti-bot cookie (`DataDome` ou similar)
- Token JWT da sessão anónima
- Headers consentimento cookie

### Opções para sessão dedicada
1. **Playwright** — abrir página, capturar tokens, replicar requests
2. **Catálogo de folheto** — parse PDF semanal oficial de ofertas (fonte limitada: ~200 produtos/semana)
3. **L2 partilhado** com Continente + Mercadona (preços precisam ser ajustados para Lidl — BR §27.2 proíbe partilhar preços)

**Não existe scraper `lidl.js` em `scripts/scraper/scrapers/`.**

---

## 6. INTERMARCHÉ — DEFERIDO

### Tentativas HTTP
| Endpoint | Resultado |
|---|---|
| `intermarche.pt/produtos` | 404 |
| `intermarche.pt/folhetos` | 404 (página existe, só em browser) |
| `intermarche.pt/api/products` | 404 |
| `intermarche.pt/_next/data/*` | 404 |

**Conclusão:** `intermarche.pt` é um site institucional sem catálogo online. Scraper existente (`scripts/scraper/scrapers/intermarche.js`) usa **Open Food Facts** (base de dados comunitária pública de produtos PT) porque é a única fonte disponível.

### Opções para sessão dedicada
1. **Open Food Facts** (scraper existente) — não é L1 estrito (foto vem do CDN OFF, não do Intermarché), mas marca produtos correctamente com `source: 'intermarche-guarda'`
2. **Folheto PDF** semanal — fontes limitadas, <200 produtos/semana
3. **L2 partilhado** com Continente

---

## 7. ZONAS PROTEGIDAS BR §25.3 — INTACTAS

- `lib/services/pricing_service.dart` — não tocado
- `lib/dispatch/driver_capacity_service.dart` — não tocado
- `lib/stores/order_store.dart::finalizePurchase` — não tocado
- Triggers `bora_tokens`, `trg_award_tokens_on_delivery` — não tocados
- Stripe, Edge Functions — não tocados
- Backup `products_backup_2026_04_18` (22.264 rows) — preservado

Apenas `public.products` mutada: **+3.000 INSERTs** (0 UPDATE, 0 DELETE).

---

## 8. ROLLBACK COMPLETO FASE 4

```sql
DELETE FROM products WHERE source = 'continente_sfcc_bestsellers_2026-04-18';
DELETE FROM products WHERE source = 'auchan_sfcc_bestsellers_2026-04-18';
```

Alternativa total (reverter Fase 3+4):
```sql
BEGIN;
TRUNCATE products;
INSERT INTO products SELECT * FROM products_backup_2026_04_18;
ALTER TABLE products DROP COLUMN IF EXISTS image_source;
ALTER TABLE products DROP COLUMN IF EXISTS needs_photo;
COMMIT;
```

---

## 9. RECOMENDAÇÕES PARA SESSÕES SEGUINTES

### Opção A — Sessão L1 Playwright (1–2h)
Criar scrapers reais com Playwright para Pingo Doce + Lidl + Auchan-complementar. Respeitar rate-limit 1 req/s (BR §27.5). Estimado: 1.500–2.000 produtos por mercado, 2–3h total.

### Opção B — Sessão market-harvester L2→L4 (1–2h)
Focar em cobrir imagens dos 14.064 `needs_photo=true` via cascata L2 (match Mercadona/Continente) → L3 (CDN marca) → L4 (Bing/Google). Não adiciona produtos, mas melhora cobertura visual.

### Opção C — Sessão Fase 5 (2h)
Edge function `update-products` + `pg_cron` semanal. Permite que mercados sem Fase 4 se actualizem automaticamente via folhetos semanais (Pingo Doce, Lidl, Intermarché).

**Ordem recomendada: C → A → B** (automação primeiro garante que o sistema se auto-atualiza mesmo sem a Fase 4 completa).

---

*Gerado automaticamente pelo `ceo-ai`. Pipeline SFCC validado em 2 mercados. 3 mercados deferidos com rationale técnico documentado.*
