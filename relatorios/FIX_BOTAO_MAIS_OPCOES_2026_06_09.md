# Fix botão "+" + opções no estafeta/parceiro · 2026-06-09
### MODO PROTECÇÃO TOTAL · UI only · Decisão pricing: **B (deixar como está)** → `product_detail_screen.dart` NÃO tocado

> `prompt-blindado-validator` ✅ PASS. `flutter analyze`: 0 erros, 0 novos warnings (6 issues pré-existentes, nenhum nas linhas tocadas).

---

## TAREFA 1 — Botão "+" abre detalhe se há opções obrigatórias ✅

**Causa:** o card delega o "+" a um callback `onAdd` (adiciona direto). Não havia gate por opções obrigatórias.

**Fix (data-driven, sem carregar os 10k items na listagem):**

1. **`lib/models/partner_product.dart`** — novo campo `final bool hasRequiredOptions` (default `false`) + copyWith.
2. **`lib/stores/restaurant_store.dart`** — em `loadProductsFromSupabase`, query leve (só `product_id`, paginada) a `product_option_groups WHERE is_required AND min_choices>=1` → `Set<String> _requiredOptionProductIds`; cada `PartnerProduct` recebe `hasRequiredOptions: set.contains(id)`. Preservado no realtime UPDATE.
3. **`lib/screens/restaurant_menu_screen.dart`** (`_SectionProductCard`, card principal do menu restaurante) — o "+":
   ```diff
   - onTap: onAdd,
   + onTap: product.hasRequiredOptions ? onTap : onAdd,
   ```
   (`onTap` abre `ProductDetailScreen`; `onAdd` adiciona direto.)
4. **`lib/widgets/bora/bora_product_card.dart`** (mercados/home — universal) — o "+":
   ```diff
   - onTap: hasPrice ? onAdd : null,
   + onTap: hasPrice ? (product.hasRequiredOptions ? onTap : onAdd) : null,
   ```

**Mercados intactos:** produtos de mercado têm `hasRequiredOptions=false` → "+" continua a adicionar direto. ✅ (242 produtos com opção obrigatória são só McD/BK/KFC/Açaí.)

---

## TAREFA 2 — Estafeta vê as opções escolhidas ✅ (estava em falta)

**Estado:** `driver_map_screen.dart` mostrava só `'${item.name} × ${item.quantity}'` — **não** mostrava as opções. Dados existiam (`order.items` é `List<CartItem>`, cada um com `selectedOptions`), só não eram renderizados.

**Fix:** `lib/screens/driver_map_screen.dart` (~2640) — o nome do item passou a `Column` com sub-texto:
```
McMenu Big Mac × 1
  Selecione o Tamanho: Médio (Medium)
  Selecione a sua bebida: Coca-Cola Média
  Selecione o seu acompanhamento: Batata
  Deseja adicionar um molho?: Ketchup
```
(uma linha por grupo: `grupo: items`).

---

## TAREFA 3 — Parceiro vê as opções escolhidas ✅ (estava em falta)

**Estado:** `partner_dashboard_screen.dart` mostrava só `'• qty × nome — €x'` — sem opções.

**Fix:** `lib/screens/partner_dashboard_screen.dart` (~1338) — cada item passou a `Column` com as opções por baixo:
```
• 1 × Copo Mega 500ml — €13.90
  Escolha os Acompanhamentos: Leite Condensado, Granola, Banana, Morango, Kiwi
  Deseja Extras?: Creme de Avelã, Paçoca
```

---

## 🚨 ACHADO CRÍTICO DE PRICING (precisa da tua decisão antes do commit)

Ao rotear os produtos fast-food para o **ecrã de detalhe**, descobri uma **inconsistência de preço pré-existente**:

| Caminho | Preço aplicado (não-parceiro) |
|---|---|
| "+" rápido (`addToCart`, `restaurant_menu_screen.dart:674`) | `product.price × 1,15` |
| Ecrã detalhe (`product_detail_screen.dart:147` `_addWithOptions`) | `product.price` **(SEM ×1,15)** |

O ecrã de detalhe **nunca** aplica o markup +15% non-partner (só usava açaí, que é parceiro → sem markup). Agora que o "+" do fast-food passa a abrir o detalhe, os McMenu/Whopper/Box **ficam 15% mais baratos** do que a tua intenção da Fase 2 (Glovo×0,8261 ×1,15 = Glovo×0,95).

**Exemplo:** McMenu Big Mac DB €5,65 → detalhe cobra €5,65 (devia ser €6,50). Idem para os extras (price_add ×0,8261 sem o ×1,15).

### Opções (decisão tua — toca pricing, por isso pergunto)
- **A (recomendada):** aplicar `×1,15` a (base + opções) no ecrã de detalhe quando a loja é non-partner — fica coerente com o "+" rápido e com a tua regra da Fase 2 (cliente paga Glovo×0,95). Toca `product_detail_screen.dart` (add + display), NÃO toca `pricing_service.dart`.
- **B:** deixar como está (fast-food fica 15% mais barato no detalhe) — não recomendado.
- **C:** outra abordagem (ex.: unificar o markup noutro sítio).

**→ DECISÃO Danilo (2026-06-09): B — deixar como está.** O `product_detail_screen.dart` NÃO foi tocado. Fast-food adicionado via detalhe fica a Glovo×0,8261 (base+opções coerentes entre si, mas ~15% abaixo da intenção da Fase 2). Pricing por resolver noutra altura (fora do âmbito deste fix).

---

## Ficheiros tocados (Tarefa 1/2/3 — UI)
- `lib/models/partner_product.dart`
- `lib/stores/restaurant_store.dart`
- `lib/screens/restaurant_menu_screen.dart`
- `lib/widgets/bora/bora_product_card.dart`
- `lib/screens/driver_map_screen.dart`
- `lib/screens/partner_dashboard_screen.dart`

## FIM
- Decisão pricing: **B** → `product_detail_screen.dart` NÃO tocado.
- Commit + push origin autonomous-night-2026-04-29 + bump versionCode.
- `/ctx doctor` + `/ctx stats`.

*Pricing NÃO tocado (decisão B). Só UI: 6 ficheiros.*
