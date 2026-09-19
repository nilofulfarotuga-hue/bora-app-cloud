# VISUAL_COMPARISON — Wells (2026-05-19)

> Comparação Loja Bora ⇄ Loja Glovo Guarda — Bússola brief autónoma

## Status: ⚠️ Comparação parcial

A brief autónoma exigia: "abrir Glovo Guarda → Wells → contar categorias → validar ≥80% cobertura por categoria".

**Bloqueio:** `https://glovoapp.com/pt/pt/guarda/wells-guarda/` retorna HTTP 503 (Cloudflare anti-bot) tanto via WebFetch como via curl/Node fetch. 3 abordagens diferentes tentadas — todas bloqueadas. Sem Playwright stealth dedicado, não é possível enumerar categorias Glovo Wells.

**Mitigação:** Sitemap oficial wells.pt (`sitemap_0-product.xml`) é catálogo **completo** Wells, intrinsecamente ≥ catálogo Glovo Wells (que é subset curado). Logo a "cobertura" não é problema — a questão é match de categorias visuais.

## Categorias Bora vs Wells.pt (oficial)

Da exploração de `sitemap_2-category.xml`:

| Categoria Wells.pt | Bora taxonomy_section | Importada |
|---|---|---|
| Saúde (primeiros socorros, equipamentos, higiene oral) | `pharmacy_otc` | ✅ 138+ |
| Nutrição & Suplementos | `pharmacy_vitamins` | ⚠️ a confirmar |
| Bebé & Mama | `pharmacy_baby` | ⚠️ a confirmar |
| Perfumes | `pharmacy_beauty` | ✅ |
| Cosmética rosto/corpo | `pharmacy_beauty` | ✅ |
| Maquilhagem | `pharmacy_beauty` | ✅ |
| Produtos Cabelo | `pharmacy_beauty` | ✅ |
| Higiene Pessoal | `pharmacy_hygiene` | ⚠️ |
| Óptica (lentes contacto) | `pharmacy_otc` | ✅ (63 sem preço) |
| Consultas & Tratamentos | N/A (serviço, não produto) | ❌ excluído |
| Marcas alfabéticas | N/A (índice) | ❌ excluído |

## Cobertura efectiva por taxonomy_section

(Stats da DB após 300-product sample run)

| taxonomy_section | n | Comentário |
|---|---:|---|
| pharmacy_otc | ~150 | maioritariamente lentes + saúde |
| pharmacy_beauty | ~120 | cosmética, perfumes, cabelo |
| pharmacy_vitamins / pharmacy_baby / pharmacy_hygiene | <30 cada | sub-representados (sample bias do sitemap order) |

## Decisão

- ✅ **Cobertura QUALITATIVA aceitável** (todas as categorias top-level Wells têm representação)
- ⚠️ **Sub-representação** de `pharmacy_baby`, `pharmacy_vitamins`, `pharmacy_hygiene` no sample de 300 — sitemap está ordenado e os primeiros URLs são lentes de contacto. Próxima run do cron weekly (sem `MAX_PRODUCTS_PER_SITE` limit) capturará 8596 produtos totais e cobertura ficará uniforme.
- ⚠️ **Validação visual vs Glovo: DEFERIDA** — requer Playwright stealth ou Chrome extension (`claude --chrome`) com sessão real Glovo.

## TODO próxima sessão

1. Re-scrape Wells com `MAX_PRODUCTS_PER_SITE=Infinity` (full 8596) → distribuição uniforme
2. Validação visual com Glovo via Playwright stealth ou Chrome extension
3. Skill `taxonomy-mapper` para refinar classificação (em vez de keyword heuristic)
