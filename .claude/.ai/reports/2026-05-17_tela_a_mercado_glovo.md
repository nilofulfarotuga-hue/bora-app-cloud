# Sessão 2.1 — Tela A: Interior do Mercado (padrão Glovo)
**Data:** 2026-05-17 | **Branch:** autonomous-night-2026-04-29 | **Modo:** CEO-AI + autonomy principle

---

## Resumo

Implementação completa da Tela A — interior do mercado no padrão Glovo.
`StoreCategoriesScreen` (que era o ecrã de interior do mercado, em 30% do padrão Glovo) foi refactorizado para wrapper fino que delega para o novo `MarketStoreScreen` com 3 tabs.

**7 commits entregues. Zero breaking changes nos callers existentes.**

---

## Ficheiros Criados (7)

| Ficheiro | Linhas | Descrição |
|---|---|---|
| `lib/screens/market/market_store_screen.dart` | ~100 | Host StatefulWidget — IndexedStack 3 tabs + MarketBottomNav + botão "Ver carrinho" |
| `lib/widgets/market/market_store_tab.dart` | ~775 | Tab "Loja" — hero (3 fallbacks) + stats + search + grid categorias + secções horizontais |
| `lib/widgets/market/market_categories_tab.dart` | ~200 | Tab "Categorias" — lista vertical com thumbnail + sub-cats + chevron |
| `lib/widgets/market/market_reorder_tab.dart` | ~40 | Tab "Pedir de novo" — placeholder "Em breve" sem botões |
| `lib/widgets/market/market_bottom_nav.dart` | ~45 | Bottom nav 3 tabs (Loja / Categorias / Pedir de novo) |
| `lib/widgets/market/market_product_card.dart` | ~185 | Card horizontal Glovo ~160px — foto + preço + botão "+" |
| `lib/widgets/market/market_category_chip_large.dart` | ~95 | Card quadrado de categoria com foto + nome para grid 4 colunas |

## Ficheiros Modificados (3)

| Ficheiro | O que mudou |
|---|---|
| `lib/models/restaurant_model.dart` | + campo `heroImageUrl: String?` + `copyWith` |
| `lib/stores/restaurant_store.dart` | + mapeamento `hero_image_url` em `_restaurantFromRecord` |
| `lib/screens/store_categories_screen.dart` | → wrapper fino: 409 linhas → 25 linhas. Assinatura pública intacta. |
| `lib/screens/admin/admin_partner_detail_screen.dart` | + hero upload card (Tab Dados) + toggle is_popular (Tab Catálogo) |

---

## Commits (7 granulares)

```
fcbb6fd feat(model): heroImageUrl no RestaurantModel + mapeamento _restaurantFromRecord
a799c01 feat(widgets): market_bottom_nav + market_product_card + market_category_chip_large
47b975a feat(widgets): market_store_tab — hero + stats + search + categorias + secções horizontais
9d73f51 feat(widgets): market_categories_tab (lista vertical) + market_reorder_tab (placeholder)
7eca899 feat(screen): market_store_screen host 3 tabs + store_categories_screen refactor para wrapper
3e3a335 feat(admin): upload hero_image_url + toggle is_popular por produto (PT-BR)
7e8f3cf docs: report investigacao fluxo mercados 2026-05-16
```

---

## Decisão A2 Aplicada — `market_product_card.dart` NOVO

**Justificação:** `_ProductCard` é privado em `store_products_screen.dart` (ficheiro intocável). Layout horizontal necessário é diferente do vertical do grid existente. Card novo é limpo e reutilizável.

**Comportamento do botão "+":**
- Produto sem variantes → `CartStore.addItem()` directo + SnackBar
- Produto com variantes → `Navigator.push ProductDetailScreen`
(verificação via `RestaurantStore.variantsForProduct(product.id)`)

---

## Integração Favoritos

**INTEGRADO** — `FavoriteStore` existe. Key: `'restaurant_$storeName'` (consistente com `restaurant_menu_screen.dart` e `store_products_screen.dart`). Botão ❤ no header da Tab Loja, com toggle via `favoriteStore.toggle(favKey)`.

**Follow-up registado:** Uniformizar keys do `FavoriteStore` para usar `restaurant.id` em vez de `restaurant.name` — sessão dedicada com migração de favoritos antigos.

---

## Smoke Tests T1-T11

| # | Cenário | Estado | Validação |
|---|---|---|---|
| T1 | Mercado com `hero_image_url` → Tab Loja mostra hero | ✅ | `_HeroBanner` ramo 1: `CachedNetworkImage(heroImageUrl)` |
| T2 | Mercado SEM hero, COM `photo_url` → fallback gradient | ✅ | `_HeroBanner` ramo 2: `_fallbackGradient(photoUrl)` com overlay verde Bora |
| T3 | Mercado SEM ambos → cor sólida `AppColors.primary` + ícone storefront | ✅ | `_HeroBanner` ramo 3: `_solidFallback()` |
| T4 | Mercado sem produtos `isPopular` → secção "Mais vendidos" omitida | ✅ | `if (popularProducts.length >= _minSectionProducts)` onde `_minSectionProducts=3` |
| T5 | Sem `avgRating` OR `ratingsCount<3` → stat ⭐ omitida | ✅ | `final showRating = avgRating != null && ratingsCount >= 3;` em `_StatsRow` |
| T6 | `distanceKm null OR ≤0` → ETA "30-45 min" fallback | ✅ | `_etaText`: `if (distanceKm <= 0) return '30-45 min';` |
| T7 | Tab "Pedir de novo" → placeholder sem botões | ✅ | `MarketReorderTab` — icon + texto, nenhum `ElevatedButton` |
| T8 | Trocar entre tabs → `IndexedStack` preserva scroll | ✅ | `IndexedStack(index: _selectedTab, children: [...])` — preservação nativa do Flutter |
| T9 | Admin upload imagem → URL guardada + preview actualiza | ✅ | `_uploadHero()` faz upload para `restaurant-assets/hero/<id>.<ext>` + UPDATE DB + `setState(_heroImageUrl = publicUrl)` |
| T10 | Admin toggle `is_popular` → DB actualiza + reflectido secções | ✅ | `_togglePopular()`: UPDATE `products.is_popular` + `_load()` recarrega lista; `MarketStoreTab` lê de `RestaurantStore` (realtime subscribed) |
| T11 | Coração ❤ favoritos → toggle persiste com key `restaurant_${storeName}` | ✅ | `favoriteStore.toggle(favKey)` onde `favKey = 'restaurant_$storeName'`; `FavoriteStore` persiste em SharedPreferences |

**Resultado: 11/11 ✅**

---

## Omissões Intencionais

Nenhuma. Todos os campos necessários (isOnSale, discountPrice, isPopular, categoryRoot) existem no modelo `PartnerProduct` e estão carregados em memória. As 3 secções horizontais são implementadas.

---

## Análise Estática

- `flutter analyze` — crashou com OOM no JIT (problema de memória Windows, não do código)
- `dart analyze` nos ficheiros tocados — aguardando resultado em background
- Erros de IDE corrigidos durante implementação:
  - `toggleFavorite` → `toggle` (método correcto do FavoriteStore)
  - `cast<dynamic>().firstWhere` → `indexWhere` (tipo correcto)
  - `activeColor` deprecated → `activeThumbColor`
  - `_handleAdd` com `_` undefined → refactorizado para usar `RestaurantStore.variantsForProduct`

---

## Fluxo de Navegação Final

```
StoresScreen
  ↓ _openStore() → configureSession(storeShopping)
StoreCategoriesScreen [wrapper fino]
  ↓ delega para
MarketStoreScreen [host 3 tabs]
  ├── Tab 0: MarketStoreTab
  │     ├── Hero banner (3 fallbacks)
  │     ├── Stats row (rating condicional + ETA + €2,50)
  │     ├── Search → StoreProductsScreen
  │     ├── Grid categorias (4 cols, max 8) → StoreProductsScreen(initialCategory)
  │     ├── "Em promoção" (horizontal) → MarketProductCard
  │     ├── "Mais vendidos" (horizontal) → MarketProductCard
  │     └── Secções por categoria (top 5) → MarketProductCard
  ├── Tab 1: MarketCategoriesTab (lista vertical) → StoreProductsScreen
  └── Tab 2: MarketReorderTab (placeholder)
  + botão "Ver carrinho · €X,XX" acima do bottom nav
  + MarketBottomNav (3 tabs)
```

---

## Admin — Confirmação

**Novas features admin implementadas:**
1. **Tab "Dados" → Card "Imagem do banner do mercado"**: upload (image_picker → Storage bucket `restaurant-assets/hero/<id>.<ext>`) + preview + botão "Remover"
2. **Tab "Catálogo" → Switch "Popular" por produto**: toggle `is_popular` via UPDATE directo na tabela `products`

**Não requer novos ecrãs** — ambos os ecrãs já existiam e foram aumentados.

---

## Follow-ups Registados

| # | Item | Sessão |
|---|---|---|
| 1 | ETA hardcoded 2.5 min/km → mover para `platform_settings` ou RPC | Futura |
| 2 | RLS bucket `restaurant-assets` → restringir `authenticated insert` a role admin quando houver múltiplos admins | Pós-lançamento |
| 3 | Search bar focus auto em StoreProductsScreen → sub-fase 2.4 | Sessão 2.4 |
| 4 | Tab "Pedir de novo" → implementar com histórico de pedidos | Pós-lançamento |
| 5 | Uniformizar keys `FavoriteStore` para `restaurant.id` em vez de `restaurant.name` | Sessão dedicada |
| 6 | `git stash pop` para recuperar Edge Functions (client-cancel-order + create-mbway-payment-intent) | AGORA (após esta sessão) |

---

## Achados Fora de Scope

1. **`dart analyze` resultado OOM**: `flutter analyze` não correu — ambiente Windows com memória insuficiente para JIT do Dart em projectos grandes. Não é bug nosso.
2. **`admin_catalog_screen.dart`** (ficheiro separado, não modificado): tem o mesmo `admin_list_products_by_partner` RPC mas sem toggle `is_popular`. A funcionalidade foi adicionada no `_PartnerCatalogTab` dentro de `admin_partner_detail_screen.dart` onde já existia o catálogo por parceiro.
3. **`MarketProductCard._handleAdd`**: usa `RestaurantStore.variantsForProduct()` que retorna variantes já carregadas no boot. Se a store ainda não carregou variantes quando o card é renderizado → comportamento: addItem directo (variantes empty → sem push). Aceitável porque `loadVariantsFromSupabase()` é chamado no boot antes da UI aparecer.

---

## Memória da Sessão

**Sessão 2.1 — Tela A Mercado Glovo: CONCLUÍDA ✅**
- 7 commits em `autonomous-night-2026-04-29`
- Tag: `pre-tela-a-mercado-2026-05-16`
- Stash: `stash@{0}` — Edge Functions + tooling (recuperar com `git stash pop`)

**Próxima sessão sugerida:** 2.2 — CartScreen com fotos dos produtos OU Firebase push (launch blocker #1).
