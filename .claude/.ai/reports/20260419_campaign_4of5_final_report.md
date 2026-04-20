# Campanha 4/5 — Limpeza de Catálogo de Produtos

**Data:** 2026-04-19
**Owner:** Danilo
**Executor:** Claude (skill `market-data-cleaner`)
**Duração:** ~1 sessão (≈4 h) em 4 paragens (A=audit, B=plano, C=Mercadona, D=Auchan, E=Continente, F=Pingo Doce, G=Lidl/Intermarché)

## Resumo executivo

| Mercado      | Total  | Active após | Hidden | Encoding fixes | Estado |
|--------------|--------|-------------|--------|----------------|--------|
| Mercadona    |  5 011 |       5 009 |      2 |          1 555 | ✅ ES→PT + encoding |
| Auchan       |  6 333 |       4 272 |  2 061 |            747 | ✅ encoding + 29 electronics + 2 032 no_img+no_brand |
| Continente   |  6 334 |       5 147 |  1 187 |             35 | ✅ HTML entities + 1 187 no_img+no_brand (0 electronics genuínas) |
| Pingo Doce   |  9 542 |       7 476 |  2 066 |          3 366 | ✅ HTML entities + 7 appliances + 2 059 no_img+no_brand |
| Lidl         |  9 085 |       9 085 |      0 |              0 | ⚠️ **Wrong-country — re-scrape urgente (task criado)** |
| Intermarché  |  6 504 |       6 504 |      0 |              0 | ⚠️ **Wrong-country — re-scrape urgente (task criado)** |
| **Totais**   | **42 809** | **37 493** | **5 316** | **5 703** |  |

Circuit breakers aprovados em Paragem B:
- ❌ Nunca DELETE físico (só `is_available=false`).
- ❌ Zonas protegidas intactas (pricing_service, dispatch-engine, Stripe, triggers bora_tokens, driver_capacity_service, finalizePurchase, auth_store).
- ✅ `name_original` preserva o texto pré-fix em todas as 5 703 correcções.
- ✅ Backup `products_cleanup_backup_20260419` presente.

## Regras aplicadas (pré-aprovadas)

1. **Encoding fix**: mojibake Ã + HTML entities (&ordm;, &atilde;, ...) + broken title-case (MadagÁScar → Madagáscar) + double-UTF-8-encoded pairs.
2. **Soft-delete no_img+no_brand**: se `photo_url` NULL/vazio/inválido **E** nome não contém nenhuma marca da allowlist (602 marcas PT), esconder com `is_available=false`.
3. **Soft-delete electronics/appliances**: aspirador vertical, batedeira eléctrica, desumidificador (>15 €), airfryer, dispensador de água, aparador.
4. **ES→PT tradução** (Mercadona): dicionário manual com inferência contextual.

## Detalhes por mercado

### Mercadona (Paragem C — concluído na sessão anterior)
- 1 555 rows com mojibake ES fixadas via dicionário manual.
- 2 rows hidden (electronics residuais).
- Tradução ES→PT aplicada aos termos mais comuns do supermercado.

### Auchan (Paragem D)
- **747 rows** com encoding corrompido fixadas:
  - Mojibake ÃO/ÃE/ÃS/ã[A-Z]
  - HTML entities (&Agrave;, &Ecirc;, &Uacute;, &ccedil;, &Ordm;, &Nbsp;)
  - Double-UTF-8 pairs (Ã + U+0080-U+00BF)
  - Broken title-case (DÉLifrance, FrancÊS, MadagÁScar, TrÊS, DÚZia, GlÚTen)
  - Word overrides: francãs → francês
- **29 electronics genuínas** escondidas.
- **2 032 no_img+no_brand** escondidas após 3 passes da allowlist (270 → 498 → 610 brands).

### Continente (Paragem E)
- Sem mojibake real — apenas 41 rows com HTML entities (&ordm;, &Agrave;, &egrave;, &ccedil;, &atilde;, &ndash;).
- 0 electronics genuínas (5 matches iniciais eram todos falsos positivos: brinquedos "Super Tablet Mágico", "Consola Pop-It", etc).
- 1 187 no_img+no_brand escondidas.

### Pingo Doce (Paragem F)
- **3 366 rows** com HTML entities (&aacute;, &atilde;, &ccedil;, &eacute;, &iacute;, &uacute;, &oacute;, &ocirc;, &ecirc;, etc.) fixadas em lote único.
- **7 appliances** escondidos (Dispensador água €49.99, Desumidificador €109, Aparador King C, Aspirador Vertical/Sem Saco, Batedeira Hoffen, Airfryer 8L).
- **2 059 no_img+no_brand** escondidas.
- Danilo referiu TVs/electrónicos — confirmado que Pingo Doce NÃO tem TVs no catálogo actual; apenas appliances e lâmpadas LED (estas últimas ficam, são consumíveis).

### Lidl + Intermarché (Paragem G) — ACTIONITEM URGENTE
- **NÃO aplicada limpeza.** Catálogos têm dados de país errado:
  - Lidl: mistura DE/NL/EN/IT/FR ("Champignonsaus Stazak", "Notenkoekje", "Greek Plain Whole Milk Yogurt", "Le Moelleux À Partager", "Casereccio Salami")
  - Intermarché: ~90% francês ("Pain Complet", "Baguettes Constance", "Cassoulet Bio", "Saucisse Sèche Pur Porc")
- **Task criado** para re-scrape a partir de `lidl.pt` e `intermarche.pt`.
- Plano completo no prompt do task spawned: backup prévio → re-scrape → DELETE old rows → aplicar mesma pipeline de limpeza.

## Artefactos criados / actualizados

- `.claude/.ai/reports/_brand_allowlist.txt` — 602 marcas PT supermercado (iteradas em 3 passes).
- `.claude/.ai/reports/_brand_audit.py` — gera audit/apply/sample SQL parametrizado por mercado.
- `.claude/.ai/reports/_auchan_fix.py` — encoding fix script (dry/apply).
- `.claude/.ai/reports/auchan_encoding_fixes.json` — 747 pares {old,new}.
- `.claude/skills/market-data-cleaner/` — skill documentada.

## Próximos passos (pós-campanha)

1. **URGENTE** — Executar task de re-scrape Lidl.pt + Intermarche.pt.
2. Campanha 5/5 (pendente) — validação final do fluxo de pedido com dados limpos.
3. Launch readiness checklist — 3 items ainda pendentes (pagamento real Stripe, google-services.json Firebase, teste fim-a-fim).
