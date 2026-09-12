# Relatório — McDonald's Guarda (apagar tudo e refazer)

> Data: 2026-06-08 · `restaurant_id='mcdonalds-guarda'` · MODO PROTECÇÃO TOTAL
> Branch: `autonomous-night-2026-04-29` · Supabase project `ojykpzwqrtusfeakzrna`

## Resumo executivo

- DB antes: **131 produtos** (preços Glovo inflacionados, categorias confusas: "Items Individuais", "Sanduiche individual", "Saco de Transporte").
- DB depois: **138 produtos**, **0 sem foto**, **0 sem preço**, **9 categorias**, `sort_order` em todos.
- Preços: **Fonte A (foto do quiosque) = preço EXACTO de loja** para 50 itens âncora; restantes **= preço_Glovo × 0,8261** (decisão Danilo 2026-06-08). **Nenhum ÷1,15 aplicado.**
- Backup: `_backup_mcdonalds_2026_06_08` (131 linhas) criado e verificado antes do DELETE.
- Zonas protegidas intactas: só `products WHERE restaurant_id='mcdonalds-guarda'` foi tocado. pricing_service / dispatch / triggers / tokens / Stripe NÃO tocados. KFC/BK/Pizza Hut NÃO tocados.

---

## 1. Como se vasculhou a Glovo (o caminho)

Loja: McDonald's Guarda, store `215649`, addr `346436`. API `https://api.glovoapp.com` (server-side, só headers `glovo-api-version:14` + `glovo-location-city-code:GRD` — sem auth/cookie).

Crawler novo `.ai_mcd_deep_crawler.js` (combina os 2 padrões do prompt):
- **Modelo restaurante** (`.ai_rest_harvest_v2`): `LIST` (secções do menu) → `PRODUCT_ROW` (inline no `content` + segue `action.data.path` de cada secção) + **expansão de TAMANHOS** (`attributeGroups` "Selecione o Tamanho" com `priceImpact` → 1 variante por tamanho ≠ 0: Média/Grande).
- **Recursão de mercearia** (`glovo_grocery_crawler`): segue `COLLECTION_TILE.action.data.path` + `CONTENT_PLACEHOLDER.contentUri` + actualiza categoria em `GRID`/`CAROUSEL`, com dedup de caminhos.

`GET /v3/stores/215649/addresses/346436/content` devolveu **12 secções no home**: `Mais vendidos | Novidades | Sanduíches e McMenu | Happy Meal | Saco de Transporte | Sobremesas | Saladas, Veggies & outros mais | Europoupança | Acompanhamentos e molhos | Bebidas | Sanduiche individual | Items Individuais`. Todos os `PRODUCT_ROW` estão inline no home (seguir os paths das secções não acrescentou nada — confirmado).

**Correcção-chave vs captura anterior:** o crawler antigo excluía a secção **Europoupança** (a regex `poupanc`), perdendo os itens de valor (Hamburguer, Cheeseburger, Chicken Bacon, Snack McWraps, Wings 3…). O novo crawler **mantém Europoupança** e só de-prioriza carrosséis promo (Mais vendidos/Novidades) como *fonte de categoria* (os produtos continuam capturados, dedup por `storeProductId`, categoria real ganha sobre promo).

Excluídos conforme prompt: Pontos & Ofertas, Alergénios, banners "35 Anos"/promo (não são `PRODUCT_ROW`). "Novidade" tratada como tag, não categoria.

## 2. Total capturado por fonte

| Fonte | Produtos | Notas |
|---|---|---|
| **Glovo (deep crawl)** | **139** (106 base + 33 variantes de tamanho) | Catálogo completo + fotos. Cobre 43/50 itens Fonte A. |
| **Uber Eats** (`b4866ee3-…`, McDonald's® (Guarda), isOpen=true) | 82 | **Preços byte-a-byte iguais aos da Glovo**; subconjunto da Glovo; **0 produtos novos**. Menu = 1 secção "McMenu" com 11 subsecções. |
| **mcdonalds.pt** | 0 preços | Site **não publica preços** (0 price-hits, sem `__NEXT_DATA__`/JSON-LD). Inútil para preço. |

**Conclusão:** Glovo = fonte única do catálogo+fotos. Uber não acrescenta nada (mesmos preços, menos itens). Por isso o método Fonte B (comparar 3 fontes / site como autoridade) é impraticável → Danilo definiu `× 0,8261` para os não-âncora.

## 3. Tabela Fonte A (quiosque) — quiosque vs Glovo vs Uber vs site vs DB final

Site = sem preço em todas as linhas. DB final = **preço exacto do quiosque** (lei). Coluna Glovo/Uber só para medir inflação das plataformas.

| Produto | Quiosque (DB) | Glovo | Uber | Site | Inflação Glovo |
|---|---|---|---|---|---|
| Hamburguer | 1,80 | 2,60 | 2,60 | — | +44% |
| Cheeseburger | 1,90 | 3,00 | 3,00 | — | +58% |
| Veggie Burguer | 2,40 | *ausente* | *ausente* | — | criado |
| Chicken Bacon | 2,40 | 3,70 | 3,70 | — | +54% |
| Snack McWrap Chicken Mayo | 2,40 | 3,70 | 3,70 | — | +54% |
| Snack McWrap Chicken Cheese | 2,40 | 3,70 | 3,70 | — | +54% |
| McChicken® | 5,25 | 6,40 | 6,40 | — | +22% |
| Double Cheeseburger | 5,50 | 6,30 | 6,40 | — | +15% |
| McPrego | 5,40 | 6,35 | 6,35 | — | +18% |
| McPrego com Ovo | 6,20 | 7,30 | 7,30 | — | +18% |
| McBifana à Cervejeira | 5,20 | 6,30 | 6,30 | — | +21% |
| Big Mac® | 5,65 | 6,50 | 6,50 | — | +15% |
| McRoyal® Bacon | 6,00 | 8,10 | 8,10 | — | +35% |
| McRoyal® Cheese | 6,00 | 8,10 | 8,10 | — | +35% |
| McRoyal® Deluxe | 6,00 | 8,30 | 8,30 | — | +38% |
| CBO® | 7,10 | 8,60 | 8,60 | — | +21% |
| McCrispy Original | 7,10 | 8,60 | 8,60 | — | +21% |
| McCrispy BBQ & Bacon | 7,70 | 8,80 | 8,80 | — | +14% |
| McCrispy Spicy Cajun | 7,70 | 8,80 | 8,80 | — | +14% |
| Big Tasty® Single | 7,20 | 8,60 | 8,60 | — | +19% |
| Big Tasty® Double | 10,00 | 12,50 | 12,50 | — | +25% |
| Big Arch | 9,90 | 12,50 | 12,50 | — | +26% |
| Menu Almoço | 6,00 | *ausente* | *ausente* | — | criado |
| McMenu® 2 Snack Wraps | 6,60 | 8,25 | 8,25 | — | +25% |
| Happy Meal (todos, ×5) | 5,00 | 6,10 | 6,10 | — | +22% |
| 10 Chicken McNuggets® | 4,20 | 6,00 | 6,00 | — | +43% |
| 20 Chicken McNuggets® | 7,20 | 10,30 | 10,30 | — | +43% |
| Chicken Wings 3 | 2,70 | 3,10 | 3,10 | — | +15% |
| Chicken Wings 6 | 4,40 | 5,90 | 5,90 | — | +34% |
| Chicken Delights | 2,40 | 3,60 | 3,60 | — | +50% |
| Chicken Share Box (ambos) | 7,95 | 9,90 | 9,90 | — | +25% |
| Batata Pequena | 2,20 | 2,60 | 2,60 | — | +18% |
| Cenouras Baby | 2,00 | 2,30 | 2,30 | — | +15% |
| Sopa Caldo Verde | 3,20 | 3,65 | 3,65 | — | +14% |
| Sopa Feijão Verde | 3,20 | *ausente* | *ausente* | — | criado |
| Creme Cenoura | 3,20 | *ausente* | *ausente* | — | criado |
| Creme Espinafres | 3,20 | 3,65 | 3,65 | — | +14% |
| Ketchup | 0,05 | 0,10 | 0,10 | — | +100% |
| Molhos (todos os outros) | 0,90 | 1,15 | 1,15 | — | +28% |
| Mini McFlurry KitKat | 1,90 | *ausente* | *ausente* | — | criado |
| Sundae Chocolate/Caramelo/Morango/Natura | 1,90 | 3,00 | 3,00 | — | +58% |
| Sundae Ananás | 2,30 | 3,10 | 3,10 | — | +35% |
| Tarte de Maçã | 1,60 | 1,80 | 1,80 | — | +13% |
| Abacaxi | 1,70 | *ausente* | *ausente* | — | criado |
| Fatias Maçã | 1,70 | 2,30 | 2,30 | — | +35% |
| Polpa Fruta | 1,70 | 2,30 | 2,30 | — | +35% |
| Panquecas | 2,70 | *ausente* | *ausente* | — | criado |

**Inflação Glovo/Uber sobre o balcão: +13% a +100%, sem factor consistente** (por isso "esquece divisão" estava certo — não há divisor único). Verificação SQL final: **45/45 nomes da query de confirmação batem o preço do quiosque** (Fonte A = lei cumprida).

## 4. Produtos novos (não existiam na DB antiga) — 16

Itens de valor Europoupança (estavam a ser excluídos) + 7 criados via Fonte A:
`Hamburguer · Cheeseburger · Chicken Bacon · Snack McWrap Chicken Mayo · Snack McWrap Chicken Cheese · Chicken Wings 3 · Chicken McNuggets® 4` (Europoupança, recuperados) ·
`Veggie Burguer · Menu Almoço · Sopa Feijão Verde · Creme Cenoura · Mini McFlurry KitKat · Abacaxi · Panquecas` (criados, sem origem Glovo/Uber/site) ·
2 renomeados (trailing-space corrigido nas Chicken Share Box).

**7 itens criados** (ausentes em TODAS as fontes) com preço do quiosque + foto reutilizada de produto similar da Glovo:
| Criado | Preço | Foto reutilizada de |
|---|---|---|
| Veggie Burguer | 2,40 | McVeggie |
| Menu Almoço | 6,00 | McMenu (genérico) |
| Sopa Feijão Verde | 3,20 | Sopa Caldo Verde |
| Creme Cenoura | 3,20 | Creme Espinafres |
| Mini McFlurry KitKat | 1,90 | McFlurry KitKat |
| Abacaxi | 1,70 | Fatias Maçã |
| Panquecas | 2,70 | Tarte de Maçã |

## 5. Categorias finais (9) e contagens

| category_root | n | min € | max € |
|---|---:|---:|---:|
| Sanduíches e McMenus | 50 | 5,20 | 12,31 |
| Bebidas | 24 | 1,32 | 1,90 |
| Acompanhamentos e Molhos | 21 | 0,05 | 12,56 |
| Sobremesas | 16 | 1,60 | 3,22 |
| Saladas, Veggies & outros mais | 11 | 2,00 | 7,93 |
| Europoupança | 9 | 1,80 | 2,70 |
| Happy Meal | 5 | 5,00 | 5,00 |
| McCafé | 1 | 2,70 | 2,70 |
| Menu Almoço | 1 | 6,00 | 6,00 |

(Os McMenus foram agrupados em "Sanduíches e McMenus". McCafé/Bebidas Quentes/Chicken como Nunca/Europoupança DUO não aparecem na Glovo/Uber desta loja — só Panquecas representa o pequeno-almoço/McCafé.)

## 6. Diff vs backup

- **+16 novos** (secção 4).
- **−3 removidos**: `Saco de Transporte` (intencional — a taxa de saco é aplicada pelo `pricing_service`; tê-la como produto duplicaria a cobrança) + 2 entradas com espaço final corrigido (Chicken Share Box McNuggets & Wings; Menu para 2 …).
- Restantes: mesmos produtos, **preços corrigidos** (Glovo→quiosque/×0,8261) e **categorias limpas** (de 9 confusas → 9 canónicas).

## Notas sobre o alvo "≥150"

Catálogo limpo e deduplicado = **138** (>130, regra dura cumprida). Os 150-200 esperados pressupunham carrosséis escondidos com muitos produtos; na realidade o McDonald's Guarda expõe ~110 produtos únicos + 33 variantes de tamanho nas plataformas de entrega, e **não** lista McCafé/Bebidas Quentes/pequeno-almoço completo na Glovo/Uber. Padding artificial (manter duplicados CBO×2 etc.) foi rejeitado por ser mau UX. 138 é o catálogo real e limpo.

## Critérios de validação (SQL)

```
total=138 · sem_foto=0 · sem_preco=0 · categorias=9 · com_sort=138 · min=0.05 · max=12.56
Fonte A: 45/45 nomes confirmam preço do quiosque
```
✅ 0 sem foto · ✅ 0 sem preço · ✅ ≥8 categorias · ✅ Fonte A 100% · ⚠️ total 138 (<150 esperado, >130 regra dura — catálogo real).

## Artefactos

- `.ai_mcd_deep_crawler.js` — deep crawler Glovo (novo).
- `.ai_mcd_uber_crawler.js` — crawler Uber (cross-ref).
- `.ai_mcd_build_apply.js` — builder + DELETE/INSERT (Fonte A + ×0,8261).
- `.ai_mcd_deep.json` (139) · `.ai_mcd_uber.json` (82) · `.ai_mcd_insert.json` (138).
