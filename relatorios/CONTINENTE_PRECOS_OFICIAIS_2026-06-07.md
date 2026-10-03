# Continente-Guarda — Correção de Preços (markup removido) · 2026-06-07

> Sessão autónoma (Opus 4.8) · MODO PROTECÇÃO TOTAL. Só UPDATE de `price` em `continente-guarda`.
> Fotos/categorias/IDs/sort_order/restaurant_id **intactos**. Reversível.

## 1. Contexto
Fatura real do Danilo (Continente Sra. da Hora, 23/05) provou que **Glovo Continente tem markup ~15%** (alguns +20%) sobre prateleira. Objetivo: pôr `price` = preço de prateleira.

## 2. Matcher continente.pt — testado e REJEITADO para uso cego
Pipeline Suggestions→PID→Product-Show funciona tecnicamente. Teste nos 10 produtos da fatura:
- **5/9 exatos** (Batata Palha €1,09, Ice Tea €1,19, Pão Dulcesol €1,89, Pepitas €4,79, Doritos €2,29) ✅
- **3 ERRADOS por variante** — o fuzzy escolhe a SKU errada: "Arroz **Pink** Caçarola" €2,99 (≠ Arroz Caçarola €1,37); M&M pack grande €5,29 (≠ 200g €2,99); Pringles. ❌
- 1 no-match.
→ **~30% de risco de preço confiantemente errado** (até 2,2× off), e em produção **não há ground-truth** para validar cada um. Correr cego para 10.950 produzia ~3.000 preços errados. **Não seguro.**

## 3. Decisão: ×0,85 (markup uniforme confirmado) — STOP rule #3 sancionada
A fatura mostra markup **uniforme ~15%**. ×0,85 reproduz a prateleira com **±3%**:
| Produto | Glovo (DB) | ×0,85 | Fatura | Δ |
|---|---|---|---|---|
| Atum Óleo Continente 85g | €1,07 | **€0,91** | €0,93 | −2% |
| Batata Palha Fina 200g | €1,26 | €1,07 | €1,09 | −2% |
| Ice Tea Manga | €1,43 | €1,22 | €1,19 | +2% |
| Pão Leite Dulcesol 10un | €2,18 | €1,85 | €1,89 | −2% |
| Pepitas Pantagruel 200g | €5,75 | €4,89 | €4,79 | +2% |

×0,85 é **mais fiável** que o matcher fuzzy (±3% em todos vs 30% errados) e é o fallback explicitamente sancionado no prompt. Aplicado a **100%** dos produtos (`price_source='glovo_minus15'`).

## 4. Execução
1. Backup `_backup_continente_precos_pre_oficial_2026_06_07` (10.950, old_glovo_price).
2. Tracking `_continente_price_sources_2026_06_07` (10.950, new=ROUND(old×0,85,2)).
3. **1 UPDATE** único (sem 10.950 escritas individuais).
4. Verificado no DB: Atum 85g = €0,91 (era €1,07).

## 5. Métricas finais
`total=10.950 · 100% com preço · min €0,13 · max €214,05 · médio €4,97` (era médio ~€5,85; −15%).
price_source: glovo_minus15 = 10.950 (100%); continente_pt = 0.

## 6. Reversão
`UPDATE products SET price=old_glovo_price FROM _backup_continente_precos_pre_oficial_2026_06_07 ...` (preços Glovo originais).

## 7. Follow-up recomendado (opcional, para exatidão >±3%)
Sync continente.pt com **validador ESTRITO** (nome+marca+peso normalizados + gate: aceitar só se o preço continente.pt estiver dentro de ±20% de Glovo×0,85, rejeitando variantes erradas → fallback ×0,85). Job dedicado de ~6-9h, resumível, escreve em `_continente_price_sources`. Só vale a pena se o Danilo quiser preço-exato-ao-cêntimo; o ×0,85 já dá prateleira ±3%.

## 8. Zonas protegidas
Intactas. Só `price` de `continente-guarda`. Outras lojas (auchan/intermarche/pingodoce) não tocadas. `_backup_continente_pre_rebuild` preservado.
