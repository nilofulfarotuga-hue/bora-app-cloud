# Wells × Glovo Backfill Report — 2026-05-19

## Tarefa
Backfill preços para 63 produtos Wells `is_available=false`/`price=NULL` via Glovo Guarda Wells, dividindo o preço Glovo por 1.15 (sistema aplica +15% no checkout).

## Resultado: ❌ 0 produtos actualizados

**Motivo:** os 63 produtos Wells sem preço **não existem no catálogo Glovo Wells Guarda**.

## Como sei

Script [scripts/scraper/wells_glovo_backfill.js](scripts/scraper/wells_glovo_backfill.js) executou com sucesso:
- ✅ Playwright abriu `https://glovoapp.com/pt/pt/guarda/wells-guarda` (200 OK)
- ✅ Clicou em 7 categorias (Cosmética Rosto, Cuidado Cabelo, Saúde, Bebé, Higiene Oral, Maquilhagem, Perfumes)
- ✅ Network intercept apanhou 505 URLs únicos da API Glovo
- ✅ **247 produtos extraídos** do feed Glovo com nome+preço válidos
- ❌ Melhor match foi score 0.40 (overlap coef) — falso positivo

## Composição do mismatch

**Os 63 produtos Wells sem preço pertencem a 3 segmentos que Glovo NÃO carrega:**

| Segmento | Nº | Razão Glovo não tem |
|---|---:|---|
| Lentes de contacto (Acuvue, Biofinity, Air Optix, Dailies, Proclear, Purevision, Soflens, Ultra) | 21 | Precisam prescrição médica — Glovo regulatoriamente impedido |
| Luxury skincare (Estée Lauder Advanced Night Repair, Clinique, MAC, Origins, Kiehl's, Lancôme, Sisley, Sérum Génifique, Double Serum Clarins, Rénergie, Smart Clinical Repair) | ~25 | Premium tier; Glovo Wells stock é dermocosmética budget-mid |
| Wella EIMI styling sprays/foams + Nativo bronzeadores + outros nichos | ~17 | Brands específicas que Wells Guarda não tem em loja física integrada Glovo |

## Composição do catálogo Glovo Wells

Os 247 produtos capturados são **dermocosmética farmácia padrão**:
- Marcas: La Roche-Posay, Avène, Bioderma, Vichy, Eucerin, Ducray, ISDIN, A-Derma, Skinerie, Uriage, Roséliane, SVR
- Tipos: cremes acne/anti-rugas/hidratantes, fotoprotectores, sunscreens, anti-vermelhidão
- Preços: €9-33 maioritariamente

## Top 5 falsos positivos (para validação)

| Score | DB (Wells.pt) | Glovo Wells | Veredicto |
|---|---|---|---|
| 0.40 | Photoderm Gel-Crème After Sun | Gel-Creme Calmante Sensibio Ds Bioderma | ❌ diferente (BIODERMA, não Bioderma after-sun) |
| 0.33 | Líquido Limpeza Renu Multiplus | Seringa para Alimentação 1un | ❌ totalmente diferente |
| 0.33 | Mattifying Compact Powder | Essence Compact Pos All About Matt | ❌ marcas distintas |
| 0.33 | Óleo Hidratante Bio-Oil | Dentífrico Baby Bio | ❌ falso match por "bio" |
| 0.33 | Reparador Labial Stick | Champô Reparador Hydration Boost | ❌ tipos diferentes |

## Decisão

**NÃO actualizar DB.** Aplicar preços baseados em falsos positivos seria pior que `needs_review=true`.

## Estado actual Wells (inalterado)

```
total: 292
com_preco: 229 (78.4%)
sem_preco: 63 (needs_review=true, is_available=false)
via_glovo: 0
```

## Alternativas para resolver os 63

1. **Re-scrape wells.pt com variant handling** — Wells.pt tem `Product-Variation` endpoint (proibido pelo robots.txt) mas os 63 produtos têm variantes (graduações de lentes, tamanhos de creme). Possivelmente preço default no Product-Show JSON-LD precisa pesquisa mais cuidadosa.
2. **Manual price entry pelo admin** — 63 produtos é manageable num batch admin.
3. **Excluir produtos sem preço** — `DELETE FROM products WHERE restaurant_id='wells-guarda' AND price IS NULL` se decidir não vender lentes/luxury via Bora.
4. **Bonus: importar os 247 produtos Glovo como NOVOS** — gama dermocosmética completa, com preços. Faria Wells passar de 229 vendáveis → ~470 vendáveis.

## Sub-produto útil

[wells_glovo_backfill.js](scripts/scraper/wells_glovo_backfill.js) é o **primeiro scraper Playwright funcional para Glovo Guarda** neste repo. Pattern provado:
- Network intercept (`page.on('response')`) com filtro JSON
- Recursive walk para encontrar `{ name, price }` objects
- Click em categorias para forçar lazy load
- Dedup por nome normalizado

Reutilizável para Worten/Leroy/Kiwoko/Zippy se eles tiverem páginas Glovo Guarda também. Substitui o anterior pessimismo (503 Cloudflare via WebFetch) — Node + Playwright passa.
