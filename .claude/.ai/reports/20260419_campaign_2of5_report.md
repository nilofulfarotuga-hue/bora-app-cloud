# Campanha 2/5 — Relatório Final

Data: 2026-04-19
Modo: PROTECÇÃO TOTAL
Orquestrador: CEO-AI
Zonas protegidas: ✅ INTACTAS (incluindo `auth_store.dart`)

---

## Objectivo

"Ver todos os produtos" — cards com imagem grande preenchendo o card todo, em grelha 2 colunas consistente (tipo Uber Eats / Glovo).

## Decisão

- **Opção A** (segura) — produtos com variants ficam intactos no card antigo
- **Grid 2 colunas** em ambos os modos (sub-opção 3b — secções com grid interno)
- **Placeholder**: ícone Flutter `shopping_cart_outlined` neutro
- **Aspect ratio 3:4**

---

## Diagnóstico SQL (distribuição de 43 501 produtos)

| Métrica | Valor | % |
|---------|-------|---|
| Total produtos | 43 501 | 100% |
| Com foto | 29 223 | **67.2%** |
| Sem foto | 14 278 | **32.8%** |
| Com variants | 190 | **0.44%** |
| Sem variants | 42 931 | **98.7%** |

→ 98.7% dos produtos recebem o card novo. Placeholder cobre ~1/3 dos casos, pelo que não é edge case.

---

## Implementação

### Widget novo — `BoraProductCard`

Ficheiro: `lib/widgets/bora/bora_product_card.dart`

- Stateless, recebe `PartnerProduct`, `onAdd`, `onTap`, `onFavoriteToggle?`, `isFavorite`
- Foto: 62% altura, `ClipRRect` top-only, `BoxFit.cover`, `errorBuilder` → `_Placeholder`
- Placeholder: `Color(0xFFF2F2F2)` + `Icon(Icons.shopping_cart_outlined, size:48)`
- Badges "Top" / "Promo" sobre foto (`Positioned(top:8,left:8)`)
- Favorito sobre foto (`Positioned(top:6,right:6)` com círculo branco)
- Nome: 2 linhas ellipsis, fontSize 13, weight 700
- Preço: fontSize 15, weight 800, `AppColors.primary` (verde). Se sem preço → "Indisponível" cinza
- Botão "+": 34×34, `AppColors.primary`, radius 10 — desativado (cinza) se `price <= 0`

Exportado em `lib/widgets/bora/bora.dart`.

### Ecrã — `store_products_screen.dart`

Removido:
- `ListView.builder` vertical simples (modo categoria seleccionada)
- `ListView.builder` horizontal por secção (modo "Ver todos")
- `_SectionedView._cardHeightFor` (dead code)

Adicionado:
- `_FlatGridView` — `CustomScrollView` com `SliverGrid` 2 colunas aspect 3/4 (modo categoria seleccionada)
- `_SectionedView` reescrita para `CustomScrollView` com alternância `SliverToBoxAdapter(header) → SliverGrid(sem variants) → SliverList(com variants) → Divider`
- `_SectionHeader` — widget dedicado para o cabeçalho colorido da secção (era inline)
- `_BoraProductCardTile` — wrapper que liga `BoraProductCard` ao `CartStore` + `FavoriteStore`

Intactos:
- `_ProductCard`, `_VariantMiniCard`, `_ProductThumbnail`, `_Badge`, `_PlaceholderImage`, `_QtyButton`, `_categoryStyle`, `_SkeletonLoader`, `_EmptyState`, `_CartBadge`, `_SuggestionsPanel` — reutilizados pelos 190 produtos com variants
- `PartnerProduct`, `ProductVariant` models
- Queries `RestaurantStore.partnerProductsForRestaurant` / `variantsForProduct`
- `CartStore.addItem()` — chamado exactamente como antes
- Pricing, DispatchEngine, Stripe, `auth_store.dart`, triggers `bora_tokens`
- Todas as fotos reais (`photo_url`)

### Ficheiros modificados

```
lib/widgets/bora/bora_product_card.dart     (NOVO)
lib/widgets/bora/bora.dart                  (export)
lib/screens/store_products_screen.dart      (grid + slivers)
```

---

## `flutter analyze`

```
Analyzing bora_app...
info - dart:js deprecation — place_autocomplete_service_web.dart:5:1
info - dart:html deprecation — place_autocomplete_service_web.dart:4:1
info - dart:js deprecation — directions_service_web.dart:4:1

3 issues found. (ran in 36.7s)
— 0 errors
— 0 warnings
— 3 infos pré-existentes (web deprecations, fora de scope)
```

---

## Instruções de teste (Danilo)

### Fluxo completo
1. `flutter clean && flutter pub get && flutter run`
2. Entra como cliente → escolhe um supermercado com muitos produtos
3. Toca "Ver todos os produtos"
4. **Verifica:** grelha 2 colunas, foto preenche 62% do card, nome 2 linhas, preço verde, botão "+" laranja verde-Bora
5. Scroll: headers coloridos de secção (Bebidas, Mercearia, etc.) intercalam com grids
6. Toca "+": snackbar "adicionado ao carrinho" aparece — preço/markup inalterados

### Edge cases
- **Produto sem imagem:** card mostra fundo cinza claro + ícone `shopping_cart_outlined`
- **Produto com nome longo:** trunca em 2 linhas com "…"
- **Produto com preço 0:** mostra "Indisponível", botão "+" desactivado (cinza)
- **Produto com variants (raro — <0.5%):** renderiza em **lista abaixo** do grid da secção, layout antigo (imagem pequena + variants lado a lado) — comportamento do "+" idêntico ao antes

### Regressão a validar (zonas protegidas)
- ✅ Preços no checkout idênticos
- ✅ DispatchEngine atribui drivers normalmente
- ✅ Stripe payment intent funciona
- ✅ Auth / sessão cliente inalterados (bug sistémico auth continua pendente — ver campanha 6)

---

## 🔔 Lembretes

- **Campanha 6 (auth sistémica — Opção A)** continua pendente. ~93% orders ainda vão para `guest@bora.com`. **Bloqueador de lançamento.**
- **Campanha 3** próxima: criação da skill `taxonomy-mapper` para agrupar produtos nas 18 secções canónicas.
- Bugs visuais fora de scope encontrados: **nenhum** novo nesta campanha.

---

## Classificação CEO-AI

- RECEITA: inalterada (preços/addItem idênticos)
- UX: 🟢 grande melhoria — cards tipo Uber Eats/Glovo em vez do layout horizontal com thumbnail pequeno
- ESTABILIDADE: 🟢 0 errors, 0 warnings, zonas protegidas intactas
- VELOCIDADE DE LANÇAMENTO: 🟢 1 campanha concluída do roadmap de 5

Próxima acção recomendada: validar no dispositivo + avançar para campanha 3/5 (taxonomy-mapper).
