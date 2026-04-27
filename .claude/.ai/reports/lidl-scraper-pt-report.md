# Lidl PT — Scraper Report

**Campanha:** `lidl-scraper-pt`
**Data de execução:** 2026-04-20
**Source tag:** `lidl.pt_2026-04-20`
**Restaurant / mercado:** `lidl-guarda` (category=`supermarket`)
**Operador:** Claude Code + MCP Supabase (projeto `ojykpzwqrtusfeakzrna`, EU-West-1)

---

## 1. Resultado final

| Métrica | Valor |
|---|---|
| **Produtos inseridos em `products`** | **62** ✅ |
| Com preço real (`oldPrice` lidl.pt) | 62 (100%) |
| Com imagem (CDN oficial Lidl) | 62 (100%) |
| `needs_review=true` (vinho, age-restricted) | 1 |
| `brand_low='Lidl'` (marca própria sem `brand.name`) | 18 |
| Marcas distintas | 26 |
| Preço min / max / avg | €0.75 / €21.63 / €4.12 |

**Pré-count BD Lidl:** 0 · **Pós-count BD Lidl:** 62 · **Duplicados internos:** 0 · **Erros:** 0.

---

## 2. Método

### Endpoints utilizados
- **Descoberta:** `https://www.lidl.pt/static/sitemap.xml` → apontava para `product_sitemap.xml.gz` (635 URLs) e `pages_pt-PT_pt.xml.gz` (507 URLs)
- **Scrape principal:** `https://www.lidl.pt/q/api/search?assortment=PT&locale=pt_PT&version=v2.0.0&fetchsize=108&offset=N`
- **Paginação observada:** `numFound=238`, `fetchsize` cap server-side a 108, offsets `0 → 108 → 216`

### Dados extraídos por produto (JSON `gridbox.data`)
- `title`, `fullTitle` → nome
- `lidlPlus[0].price.oldPrice` → preço loja (sem app) — **campo fonte do `price` na BD**
- `lidlPlus[0].price.price` → preço Lidl Plus (guardado em memória, não usado)
- `lidlPlus[0].price.packaging.text` → `unit`
- `lidlPlus[0].price.basePrice.text` → `description` (ex: "1 kg = 1.73")
- `image_V1.image` → `photo_url`
- `brand.name` ou "Lidl" se `showBrand=false` → `brand_low`
- `keyfacts.wonCategoryPrimary` → `category_root` (input para `taxonomy-mapper` posterior)

### Configuração anti-bloqueio
- User-Agent real de Chrome 131 desktop Windows
- Cookie `i18n_redirected` semeado via GET homepage antes das chamadas API
- Rate limit: **3-3.5s** entre requests
- Nenhum bloqueio, 403, 429 ou CAPTCHA observado

### Regras de inserção aplicadas
- ❌ Rejeitado se `oldPrice` e `price` ambos NULL
- ❌ Rejeitado se sem imagem (`image_V1` NULL)
- ❌ Rejeitado se nome em DE/FR/IT/EN (0 detecções — catálogo 100% PT)
- ✅ Dedupe por `productId` (Fase 1) e por `name` case-insensitive (Fase 2) — 0 dupes encontrados
- ✅ `needs_review=true` se categoria começa com "Vinho"
- ✅ `id` determinístico `lidl-<productId>` — permite re-runs idempotentes

---

## 3. Gap analysis

### Sitemap 635 vs Search API 238 (gap: 397)

A sitemap `product_sitemap.xml.gz` lista 635 URLs `/p/...`, mas a API interna `/q/api/search?assortment=PT` só devolve 238 (`numFound=238` consistente em todas as páginas).

**Interpretação:** os 397 produtos não acessíveis via API são:
- SKUs descontinuados mas com PDP ainda indexada
- Produtos de semanas anteriores (Lidl rota surtido semanalmente)
- SKUs que a sitemap expõe por SEO mas que o catálogo "assortment=PT" já não inclui

**Decisão:** descartar os 397 — não são catálogo activo. Validado com Danilo.

### 238 → 62 inseríveis (rejeitados: 176)

Dos 238 produtos activos, 176 (74%) **sem preço** — são produtos **online-only** (`store=false`, `lidlPlus=[]`) fora do catálogo de loja física. Categorias dominantes dos rejeitados:

| Categoria (root) | Total | Sem preço | Motivo |
|---|---|---|---|
| Moda feminina | 12 | 12 | Online-only |
| Moda homem | 8 | 8 | Online-only |
| Bicicleta | 15 | 15 | Online-only |
| Brinquedos | 7 | 7 | Online-only |
| Beleza e cuidados corporais | 10 | 10 | Online-only |
| Casa de banho / Decoração / Jardim / Ferragens | 14 | 14 | Online-only |
| Roupa de bebé / criança 2-8 anos | 9 | 9 | Online-only |
| Fitness | 3 | 3 | Online-only |
| Flores e plantas | 6 | 6 | Online-only |
| Alimentos sem preço (produtos raros) | 92 | 92 | Rotação semanal |

Estes 176 não existem na loja física da Guarda → correctamente descartados.

---

## 4. Breakdown por categoria (inseridos)

Mapeado a partir de `keyfacts.wonCategoryPrimary`:

| `category_root` (simplificado) | Inseridos |
|---|---|
| Salsicha e carne | 14 |
| Peixe e marisco | 7 |
| Farmácia - higiene, alimentos para bebés, cosméticos, produtos de limpeza | 7 |
| Alimentos congelados | 5 |
| Queijo e produtos lácteos | 4 |
| Ovos e alimentos básicos (massas, farinha, leguminosas) | 4 |
| Snacks e produtos de confeitaria | 4 |
| Bebidas | 4 |
| Gorduras, óleos, vinagre e conservas | 3 |
| Pão e produtos de pastelaria | 3 |
| Refeições prontas | 2 |
| Café, chá e cacau | 2 |
| Frutas e legumes | 2 |
| Vinho / Vinho branco | 1 *(needs_review=true)* |
| **Total** | **62** |

---

## 5. Lista completa dos 62 produtos inseridos

Formato: `productId · nome · €preço · marca · unit · categoria`

### Salsicha e carne (14)
- 10043296 · Pato Inteiro com Miúdos · €4.49 · Lidl · Vendido ao kg
- 10044937 · Preparado de Carne de Bovino XXL · €11.69 · Lidl · Emb. 1 kg
- 10044965 · Tira de Entrecosto de Porco · €6.99 · Lidl · Vendido ao kg
- 10044967 · Espetada de Peru · €7.59 · Lidl · Vendido ao kg
- 10044969 · Hambúrguer de Frango com Bacon e Queijo · €2.49 · Lidl · Emb. 2x120 g
- 10044979 · Chouriço Receita do Fundão · €2.49 · Fumeiro da Gardunha · Emb. 200 g
- 10044981 · Salame Extra Fatiado · €1.49 · DULANO · Emb. 150 g
- 10044983 · Bacon Fatiado Formato Familiar · €2.79 · FUMADINHO · Emb. 300 g
- 10044985 · Fiambre da Pá Finíssimo · €1.25 · FUMADINHO · Emb. 150 g
- 10044999 · Kebab/ Gyros de Frango · €7.99 · MONISSA · Cada emb. 750 g
- 10045189 · Bife Frango Marinado Alho e Salsa · €8.49 · Lidl · Vendido ao kg
- 10045191 · Costeletas do Cachaço de Porco · €5.69 · Lidl · Vendido ao kg
- 10045193 · Hambúrguer de Bovino Angus · €4.69 · Lidl · Emb. 300 g
- 10045209 · Peito de Frango Forno a Lenha · €1.89 · FUMADINHO · Emb. 150 g

### Peixe e marisco (7)
- 10044971 · Salmão Selvagem à Posta · €10.99 · OCEAN SEA · Vendido ao kg
- 10044973 · Postas de Bacalhau XXL · €12.29 · OCEAN SEA · Emb. 1,2 kg
- 10044975 · Filetes de Pescada do Cabo · €5.39 · OCEAN SEA · Emb. 580 g
- 10045197 · Lombos de Salmão · €21.63 · Lidl · Vendido ao kg
- 10045199 · Red Fish · €5.29 · Lidl · Vendido ao kg
- 10045201 · Redondos de Pescada do Cabo · €4.25 · OCEAN SEA · Emb. 475 g
- 10045203 · Lombos de Bacalhau · €18.99 · OCEAN SEA · Emb. 800 g

### Farmácia / Higiene / Limpeza (7)
- 10045083 · Hydra Intense Creme/ Sérum Facial · €4.49 · CIEN · Cada emb. 30 ml/ 50 ml
- 10045087 · Gel de Banho de Argão · €1.59 · CIEN · Emb. 1 L
- 10045091 · Condicionador Hairvital · €2.39 · CIEN · Cada emb. 330 ml
- 10045095 · Champô Hairvital · €1.99 · CIEN · Cada emb. 400 ml
- 10045251 · Detergente em Pó Frescura Azul · €14.49 · FORMIL · Emb. 6,5 kg
- 10045253 · Fio Dentário · €1.65 · DENTALUX · Cada emb.
- 10045255 · Men Deospray · €1.29 · CIEN MEN · Cada emb. 200 ml

### Alimentos congelados (5)
- 10044939 · Miolo de Camarão 80/100 · €3.65 · OCEAN SEA · Emb. 250 g
- 10044957 · Pastel de Nata · €2.10 · Lidl · Cada unid. 58 g
- 10044995 · Cordon Bleu de Frango · €4.49 · CHEF SELECT/MONISSA · Cada emb. 500 g
- 10044997 · Batatas Rústicas · €1.49 · HARVEST BASKET · Emb. 750 g
- 10045205 · Pizza Bacon, Cogumelos e Azeitonas · €2.89 · CHEF SELECT · Emb. 450 g

### Queijo e produtos lácteos (4)
- 10044987 · Iogurte Líquido Magro de Frutos Vermelhos · €1.35 · MILBONA · Pack 4x170 g
- 10045211 · Queijo Manchego DOP · €5.29 · MILBONA · Emb. 250 g
- 10045215 · Pudim com Proteína Chocolate/Caramelo/Avelã · €0.89 · MILBONA · Cada emb. 200 g
- 10045217 · Iogurte Natural Açucarado · €1.59 · MILBONA · Pack 8x125 g

### Ovos e alimentos básicos (4)
- 10045013 · Puré de Batata · €1.85 · HARVEST BASKET · Emb. 500 g
- 10045015 · Arroz Carolino · €1.15 · CAMPO LARGO · Emb. 1 kg
- 10045031 · Muesli de Frutos e Sementes · €3.69 · CROWNFIELD · Emb. 750 g
- 10045227 · Grão de Bico Cozido · €0.85 · CAMPO LARGO · Emb. 400 g

### Snacks e confeitaria (4)
- 10045045 · Madalenas de Chocolate · €2.29 · Lidl · Emb. 500 g
- 10045047 · Chocolate Recheado King Size · €3.99 · FIN CARRÉ · Cada emb. 295 g/ 300 g
- 10045049 · Chocolate Branco · €1.09 · MORENAZOS · Emb. 150 g
- 10045229 · Bolachas Tostadas · €1.69 · SONDEY · Pack 4x200 g

### Bebidas (4)
- 10045051 · Sumo de Maçã · €1.49 · SOLEVITA · Pack 6x200 ml
- 10045239 · Sangria · €1.69 · CONDE NOBLE · Emb. 1,5 L
- 10045241 · Cerveja Perlenbacher · €4.79 · PERLENBACHER · Pack 6x0,50 L
- 10045243 · Panaché · €3.49 · ARGUS · Pack 10x0,25 L

### Gorduras, óleos, vinagre e conservas (3)
- 10044941 · Atum em Óleo Vegetal · €1.99 · RAMIREZ · Emb. 120 g
- 10045011 · Salsichas de Aves · €1.09 · FUMADINHO · Emb. 200 g
- 10045017 · Feijão Encarnado Cozido · €0.85 · CAMPO LARGO · Emb. 400 g

### Pão e produtos de pastelaria (3)
- 10044959 · Broa de Milho Doce · €1.09 · Lidl · Cada unid. 550 g
- 10045185 · Pão de Mistura da Baviera · €0.75 · Lidl · Unid. 400 g
- 10045187 · Meia Baguete · €0.92 · Lidl · Cada unid. 110 g

### Refeições prontas (2)
- 10044961 · Empanadilha de Atum · €0.99 · Lidl · Cada unid. 120 g
- 10045207 · Esparguete Bolonhesa · €2.75 · CHEF SELECT · Emb. 350 g

### Café, chá e cacau (2)
- 10045039 · Cápsulas de Café Espresso Ouro · €3.85 · BELLAROM · Emb. 16 unid.
- 10045041 · Cápsulas de Café Viola · €3.75 · BELLAROM · Emb. 20 unid.

### Frutas e legumes (2)
- 10044943 · Melão Verde · €2.15 · Lidl · Vendido ao kg
- 10045181 · Maçã Granny Smith Nacional · €1.99 · Lidl · Vendido ao kg

### Vinho (1, needs_review=true)
- 10045065 · Vinho Branco Regional · €4.99 · JOÃO PIRES · Emb. 750 ml

---

## 6. Próximos passos recomendados

1. **`taxonomy-mapper`** — correr a skill contra `category_root` para popular `taxonomy_section` nas 18 secções canónicas Bora (carne → Talho, peixe → Peixaria, padaria → Padaria, higiene/limpeza → Higiene Pessoal/Higiene do Lar, vinho → Bebidas, etc.)
2. **Monitorização semanal** — Lidl roda surtido. Criar cron para re-scrape semanal (Segunda 07:00) e UPSERT por `id='lidl-<productId>'` (é determinístico → dá para `ON CONFLICT (id) DO UPDATE`).
3. **Recuperar descrições** — actualmente `description` guarda só o preço por kg. Se quisermos descrição real, scraping adicional das PDPs via Playwright (não prioritário).
4. **Validar preços em loja física** (spot-check) — confirmar que `oldPrice` (sem app) é de facto o PVP na Guarda.

---

## 7. Artefactos

- Fonte JSON bruto: `.claude/.ai/tmp/lidl_all_products.json` (238 produtos normalizados)
- Summary Fase 1: `.claude/.ai/tmp/lidl_fase1_summary.json`
- SQL gerado Fase 2: `.claude/.ai/tmp/lidl_fase2_insert.sql`
- Preview pré-insert: `.claude/.ai/tmp/lidl_fase2_preview.json`
- Log do scraper: `.claude/.ai/tmp/lidl_fase1_log.txt`
- Sitemap capturado: `.claude/.ai/tmp/lidl_sitemap_products.xml`, `lidl_sitemap_pages.xml`
- Scripts: `.claude/.ai/scripts/scrape_lidl_fase1.py`, `build_lidl_insert_sql.py`

---

*Relatório gerado por Claude Code — Modo Protecção Total (aprovação por fase).*
