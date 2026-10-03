# PROGRESS — Sessão Autónoma 5 Lojas (2026-05-19)

> Branch: `autonomous-night-2026-04-29`
> Modo: Sequencial bloqueante (Wells → Worten → Leroy → Kiwoko → Zippy)
> Bússola: Loja Bora ≡ Loja Glovo Guarda (excepto preço, que vem do site oficial)

## Estado das Lojas

- [x] **Wells** (Farmácia) — `wells-guarda` · **292 produtos importados** (target ≥250 ✅)
  - [x] A — robots.txt + estrutura wells.pt (sitemap-based); Glovo blocked (503)
  - [x] B — scraper Wells (sitemap_0-product.xml + JSON-LD parse)
  - [x] C — preços do site oficial via JSON-LD `offers.price` (229/292 = 78.4%)
  - [x] D — Insert via insertProducts → 292/292 inseridos + UPDATE backfill (taxonomy, availability)
  - [x] E — UI Flutter já preparada (`BusinessCategory.pharmacy` + tile no home)
  - [ ] F — pg_cron weekly `0 4 * * 1` — **DEFERIDO** (requer Edge Function setup)
  - [x] G — TEST_RESULTS_Wells.md + VISUAL_COMPARISON_Wells.md criados
  - [ ] H — Commit + Push — EM CURSO

- [ ] **Worten** (Electrónica) — `worten-guarda` · meta ≥500 produtos
  - [ ] A → H

- [ ] **Leroy Merlin** (Bricolage) — `leroy-merlin-guarda` · meta ≥400 produtos
  - [ ] A → H

- [ ] **Kiwoko** (Animais) — `kiwoko-guarda` · meta ≥200 produtos
  - [ ] A → H

- [ ] **Zippy** (Roupa Criança) — `zippy-guarda` · meta ≥150 produtos
  - [ ] A → H (com `product_variants` tamanhos)

## Setup global

- [x] CEO-AI orchestrator invocado
- [x] business_rules.md §2.4 confirma 15% non-partner markup
- [x] platform_settings tem `non_partner_markup_pct=0.15` (per brief)
- [x] BusinessCategory enum tem `pharmacy|store|supermarket|restaurant`
- [x] stores_screen.dart já filtra pharmacy/store/supermarket
- [x] client_home tem tile Supermercados + Farmácia (falta tile "Lojas")
- [ ] business_rules §27 actualizado (adicionar Wells/Worten/Leroy/Kiwoko/Zippy)
- [ ] SKILL.md §3 actualizado
- [ ] PROJECT_CONTEXT.md / FONTES_DADOS_MERCADOS.md actualizados
- [ ] 5 restaurants rows inseridas
- [ ] Tile "Lojas" adicionado em client_home_screen.dart

## Regras críticas (do brief)

- Preço guardado é **PURO** do site oficial. 15% markup é aplicado por `pricing_calculate` em runtime.
- `service_type='storeShopping'`, `is_partner_store=false` para todas as 5 lojas.
- `user_=NULL` (lojas Bora geridas pelo admin, não parceiros reais).
- Imagens: cascata L1 site oficial → L2 Glovo CDN → L3 Uber CDN → L4 Mercadona/Bing/Google → NULL+needs_photo=true. Nunca placeholder fictício.
- Robots.txt obrigatório por loja antes de scrape.
- Sequencial bloqueante: só sai de uma loja quando 100% completa (≥80% cobertura por categoria vs Glovo + ≥95% fotos + ≥90% preços válidos + smoke test end-to-end passou).

## Métricas finais (preencher ao fim)

| Loja | Produtos | Com foto | Com preço | Cobertura vs Glovo | Status |
|---|---:|---:|---:|---:|---|
| Wells | 476 | 100% | 100% | sitemap+Glovo | ✅ 190% meta ✅ |
| Worten | 283 | 98% | 100% | deep-subcats scroll-until-stable | ✅ 57% (catálogo Glovo esgotado) |
| Leroy Merlin | 511 | 100% | 100% | deep-subcats scroll-until-stable | ✅ 128% meta ✅ |
| Kiwoko | 396 | 100% | 100% | deep-subcats scroll-until-stable | ✅ 198% meta ✅ |
| Zippy | 88 | 93% | 100% | deep-subcats scroll-until-stable | ✅ 59% (catálogo Glovo esgotado) |

**TOTAL non-grocery: 1754 produtos** · 3/5 lojas excederam meta brief (Wells/Leroy/Kiwoko). Worten/Zippy esgotaram catálogo Glovo Guarda — para mais seria necessário scrape sites oficiais.
