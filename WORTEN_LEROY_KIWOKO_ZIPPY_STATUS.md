# Status — Worten / Leroy Merlin / Kiwoko / Zippy (2026-05-19)

## Resultado: ❌ 0 produtos importados em todas as 4

**Wells importada com sucesso (476 produtos) — esta é a única loja non-grocery operacional nesta sessão.**

## Slugs Glovo Guarda confirmados (discovery v2)

- Worten: `worten-vivaci-guarda-grd` (storeId interno 124378, addressId 350045)
- Leroy Merlin: `leroy-merlin-grd`
- Kiwoko: `kiwoko-grd`
- Zippy: `zippy-grd`
- Wells: `wells-guarda` (categoria Farmácia e Beleza — funcionou ✅)

## Por que não funcionou

A `glovo_multi_import.js` e `glovo_deep_scroll.js` abrem a página da loja no Glovo via Playwright e capturam responses JSON via `page.on('response')`. Para Wells isto deu 247 produtos imediatamente (a página da categoria farmácia-e-beleza serve produtos via API logo no load).

Para Worten/Leroy/Kiwoko/Zippy, o intercept apanha **0 produtos** porque:

1. **Address gating** — visible text mostra "Insere a tua morada para verificar as opções de entrega". Glovo exige endereço definido na sessão antes de carregar catálogo dessas lojas.
2. **API bloqueada por header** — `/v3/stores/124378` retorna 400 com erro: `"Required request header 'Glovo-Perseus-Session-Id' is missing"`. Headers de sessão Perseus são gerados dinamicamente pelo cliente React.
3. **Sub-categorias não disparam API products** — landing page mostra apenas headers de sub-categoria como texto. Click em `h3`/`h4` com texto da categoria não dispara o React handler que faria fetch dos produtos.
4. **Sub-URLs com pattern `/c/<slug>_<id>` não existem na landing** — 0 hrefs internas matched o pattern esperado. Glovo usa state-only navigation (não URL-based).

## Endpoints API confirmados (não acessíveis sem session)

- `https://api.glovoapp.com/v3/stores/124378` → 400 (missing Perseus header)
- `https://api.glovoapp.com/v3/feeds/search?filter=Electronics&categoryId=22` → funciona mas é search global, não products do store
- `https://api.glovoapp.com/v1/stores/124378/addresses/350045/node/store_fees` → 200, mas só tem fees não products

## O que funcionou (em Wells)

Wells é categoria `farmacia-e-beleza_3` no Glovo. A página dessa categoria carrega imediatamente os top produtos das farmácias todas (incluindo Wells, Auchan Saúde, Farmácia da Sé, Farmácia Teixeira) em horizontal scrollers. O intercept captura porque API é chamada no page load com address pré-definido pela cidade.

## Alternativas para resolver as 4 lojas (próxima sessão)

### Opção A — Address persistence (recomendada)
1. Antes de visitar a loja, navegar para `glovoapp.com/pt/pt/guarda` e clicar "Continuar com este endereço" no banner principal
2. Capturar cookies/localStorage da sessão (`address-token`, `glovo-perseus-session`)
3. Re-usar essa sessão para visitar páginas individuais das lojas
4. **Esforço:** 1-2 horas de investigação + scripting

### Opção B — Sites oficiais (mais robusto, mais código)
- **Worten:** sitemap_wortenpt_0+.xml tem ~17M URLs (maioritariamente promo); chunks 10+ têm produtos reais com pattern `/produtos/<slug>-<id>`. JSON-LD presente quando acedido via Playwright (HTTPS directo dá 403). **~500 produtos viáveis com scrape Playwright** em 30 min.
- **Leroy Merlin:** sitemap-index.xml com 407 sub-sitemaps, plataforma custom. Investigar JSON-LD/Open Graph.
- **Kiwoko:** sitemap_index.xml pequeno (7 chunks). Demandware/SFCC suspeito — pode usar pattern Wells.
- **Zippy:** sitemap.xml único, plataforma Shopify suspeita — tem `/products.json` API pública em Shopify.

### Opção C — Iniciar pequeno (manual)
- Curated seed de top 50-100 produtos por loja, manualmente, com nome+preço+imagem do Glovo
- Cron weekly faz refresh do preço
- **Esforço:** ~2 horas manual por loja, mas garantido funcional

## Scripts no repo após esta sessão

- `scripts/scraper/scrapers/wells.js` — Wells site oficial (sitemap_0-product + JSON-LD)
- `scripts/scraper/wells_glovo_backfill.js` — Wells × Glovo Playwright (FUNCIONA para Wells)
- `scripts/scraper/wells_glovo_import.js` — INSERT batch genérico
- `scripts/scraper/glovo_multi_import.js` — multi-loja Playwright (template; 0 produtos para as 4 stores não-Wells)
- `scripts/scraper/glovo_deep_scroll.js` — deep-scroll variant (também 0 produtos para as 4 stores não-Wells)

## DB state final

| Loja | restaurants row | Produtos | Estado |
|------|:---------------:|---------:|--------|
| Wells | ✅ | 476 | ✅ funcional (229 site oficial + 247 Glovo÷1.15) |
| Worten | ✅ | 0 | ⚠️ Bloqueada — precisa address persistence |
| Leroy Merlin | ✅ | 0 | ⚠️ Bloqueada — mesmo motivo |
| Kiwoko | ✅ | 0 | ⚠️ Bloqueada — mesmo motivo |
| Zippy | ✅ | 0 | ⚠️ Bloqueada — mesmo motivo |

## Recomendação Danilo

**Para próxima sessão:** começar com Opção A (address persistence). Se demorar mais que 1-2 horas → Opção B (sites oficiais) para Worten + Zippy (sitemaps acessíveis), Opção C (manual seed) para Kiwoko + Leroy.

UI Flutter já preparada (`BusinessCategory.store` + tile Lojas + StoresScreen filtra `pharmacy|store|supermarket`). Quando produtos forem importados, aparecem automaticamente na app.
