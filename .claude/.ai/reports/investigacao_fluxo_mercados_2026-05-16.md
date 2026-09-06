# Investigação: Fluxo Mercado → Checkout
**Data:** 2026-05-16 | **Autor:** CEO-AI | **Modo:** Leitura pura — zero alterações

---

## FASE 0 — Ficheiros Lidos

| Ficheiro | Estado |
|---|---|
| `business_rules.md` | ✅ Lido (via grep §partner/markup/storeShopping) |
| `lib/screens/stores_screen.dart` | ✅ Lido completo |
| `lib/screens/store_categories_screen.dart` | ✅ Lido completo |
| `lib/screens/store_products_screen.dart` | ✅ Lido completo (1629 linhas) |
| `lib/screens/product_detail_screen.dart` | ✅ Lido completo (553 linhas) |
| `lib/screens/cart_screen.dart` | ✅ Lido completo |
| `lib/stores/cart_store.dart` | ✅ Lido completo |
| `lib/stores/restaurant_store.dart` | ✅ Lido completo |
| `lib/screens/client_home_screen.dart` | ✅ Lido completo |
| `lib/screens/client_main_screen.dart` | ✅ Lido completo |
| `lib/models/restaurant_model.dart` | ✅ Lido (campos isPartner, BusinessCategory) |
| `pubspec.yaml` | ✅ Assets verificados |
| `assets/images/categories/` | ✅ Verificado — pasta inexistente/vazia |
| `.claude/.ai/knowledge/INDEX.md` | ✅ Lido |
| `markets_screen.dart` / `store_screen.dart` | ❌ Não existem — nomes divergentes. Ficheiros reais: `stores_screen.dart`, `store_categories_screen.dart`, `store_products_screen.dart` |

---

## FASE 1 — Mapeamento do Estado Actual

### A) ENTRADA — Lista de Mercados

**Ficheiro:** `lib/screens/stores_screen.dart`

**Classe:** `StoresScreen({BusinessCategory? initialCategory})`

**Fonte de dados:** `context.watch<RestaurantStore>()` → filtra `restaurants` onde `category == supermarket || store || pharmacy`. Nenhuma query Supabase directa — tudo já carregado no boot.

**Estrutura visual:**
- `BoraScreenAppBar` com título ("Supermercados" / "Lojas e Farmácias")
- Secções separadas: Supermercados | Lojas | Farmácias (se `initialCategory == null`)
- Cada mercado: `_StoreTile` (GestureDetector) com logo (CachedNetworkImage), nome, categoria, cor de banner baseada em `BusinessCategory`

**onTap (L164):** `_openStore(context, entry)`

```
_openStore():
  1. Verifica carrinho activo de outro vendor → AlertDialog ("Tens itens em X, novo pedido em Y?")
  2. cart.configureSession(
       serviceType: storeShopping,
       isPartnerStore: entry.business.isPartner,
       vendorName: entry.store.name,
       pickupLocation: entry.business.location ?? cart.deliveryLocation,
       pickupStreet: entry.business.address,
     )
  3. isLargeStore = category == supermarket || store
     → isLargeStore → StoreCategoriesScreen(restaurantId, storeName, isPartnerStore)
     → !isLargeStore (farmácia) → StoreProductsScreen(restaurantId, storeName, isPartnerStore)
```

**Ramificação partner/non-partner aqui:** `isPartnerStore: entry.business.isPartner` — passa o flag real. O CartStore aplica markup 15% no `addItem()` se `isPartner == false`.

---

### B) PÁGINA DO MERCADO (Interior)

**Ficheiro:** `lib/screens/store_categories_screen.dart`

**Classe:** `StoreCategoriesScreen({restaurantId, storeName, isPartnerStore})`

**Fonte de dados:**
- `restaurantStore.partnerProductsForRestaurant(restaurantId)` — lista de `PartnerProduct` já em memória (carregada no boot pelo RestaurantStore)
- **Nenhuma query Supabase directa** nesta tela
- Categorias derivadas dos campos `p.categoryRoot` (preferido) ou `p.category` dos produtos

**Estrutura actual:**
- `AppBar` simples com `storeName` + `_CartBadge` (ícone carrinho com contador)
- `_AllProductsTile` — tile de "Todos X produtos" (onTap → StoreProductsScreen sem filtro)
- `GridView.builder` — grid de `_CategoryCard` (ícone + nome + contagem de produtos)
- Ícones e cores das categorias: **hardcoded** em `_categoryIcons` e `_categoryColors` (Map<String, IconData/Color>) — sem imagens reais
- Botão flutuante "Ver carrinho · €X,XX" (só aparece quando `cartStore.items.isNotEmpty`)

**onTap categoria (L166):** `_openProducts(context, cat)` → `Navigator.push → StoreProductsScreen(restaurantId, storeName, initialCategory: cat, isPartnerStore)`

**O que NÃO existe:**
- ❌ Barra de busca
- ❌ Banners/promoções (carrossel)
- ❌ Secção "Mais vendidos" (scroll horizontal)
- ❌ Fotos reais nas categorias (só ícones Material)
- ❌ Header colapsável com logo do mercado
- ❌ Bottom navigation (Loja | Categorias | Pedir de novo)

---

### C) CATEGORIA DE PRODUTOS

**Ficheiro:** `lib/screens/store_products_screen.dart` (1629 linhas)

**Classe:** `StoreProductsScreen({restaurantId, storeName, initialCategory, isPartnerStore})`

**Fonte de dados:**
- `restaurantStore.partnerProductsForRestaurant(restaurantId, onlyAvailable: true)` — dados em memória
- Busca textual: RPC Supabase `search_products(query_text, p_restaurant_id, max_results: 50)` — só activada com ≥2 caracteres após debounce 350ms

**Estrutura actual:**
- `AppBar` com `storeName` + `_CartBadge`
- `TextField` de busca (com limpar e sugestões via `_SuggestionsPanel`)
- **Chips horizontais** (`ChoiceChip`) derivados das categorias dos produtos — scroll horizontal, inclui "Todos"
- Quando "Todos" seleccionado: `_SectionedView` (produtos agrupados por categoria, com `_SectionHeader`)
- Quando categoria específica: `_FlatGridView` (grid plano)
- Cada produto: `_BoraProductCardTile` ou `_ProductCard` com foto, nome, preço, botão "+"
- Botão "+" inline em cada card → `CartStore.addItem()`
- Toca no produto → `Navigator.push → ProductDetailScreen(product)`
- Botão flutuante "Ver carrinho · €X,XX" quando carrinho não vazio

**Modos de layout:**
- `_SectionedView` (L575): lista de secções por categoria, cada uma com `SliverChildBuilderDelegate`
- `_FlatGridView` (L692): grid 2 colunas
- `_SkeletonLoader` (L440): loading state

**O que NÃO existe:**
- ❌ Banners de promoção no topo da lista
- ❌ Secção "Em promoção" ou "Mais vendidos" horizontal
- ❌ Imagens nos chips de categoria (só texto)

---

### D) DETALHE DO PRODUTO

**Ficheiro:** `lib/screens/product_detail_screen.dart` (553 linhas)

**Classe:** `ProductDetailScreen({required PartnerProduct product})`

**Estrutura actual:**
- `Scaffold` → `Column` → `CustomScrollView`
- `SliverAppBar` expansível com `_ProductHeroImage` (foto grande via `Image.network`)
- Back button com `Navigator.pop()`
- Abaixo: nome, descrição, preço
- Se tem variantes: lista de `_VariantCard` (cada variante = marca diferente, com foto e preço)
- Seletor de quantidade (`_quantity`, botões +/−)
- `ElevatedButton` "Adicionar ao carrinho · €X,XX"
- `_CartBadge` no AppBar → `Navigator.push → CartScreen`

**Lógica de adicionar:**
- Com variante seleccionada: `CartStore.addItem(CartItem(productId: variant.id, name: '${product.name} (${v.brandName})', price: v.price, quantity: _quantity))`
- Sem variante (produto simples): `CartStore.addItem(CartItem(productId: product.id, name: product.name, price: product.price, quantity: _quantity))`
- Markup 15% aplicado no `CartStore.addItem()` se `_isPartnerStore == false`

**O que NÃO existe:**
- ❌ Zoom na foto
- ❌ Marca/origem destacada fora das variantes

---

### E) CARRINHO

**Ficheiro:** `lib/screens/cart_screen.dart`

**Classe:** `CartScreen` (StatelessWidget)

**Estrutura actual:**
- `AppBar` com "Carrinho"
- `ListView.builder` de `_CartItemTile` (nome + quantidade +/− + preço + remover)
- `_CheckoutPanel` (sticky no fundo): subtotal, taxa de entrega, taxa de serviço, total, gorjeta
- `ElevatedButton` "Ir para pagamento" / "Finalizar pedido" → `Navigator.push → PaymentMethodScreen` ✅

**O que NÃO existe:**
- ❌ Foto dos produtos nos items do carrinho (só nome)
- ❌ Layout estilo Glovo (mais visual)

---

### F) STATE MANAGEMENT

**CartStore** (`lib/stores/cart_store.dart`):
- `configureSession(serviceType, isPartnerStore, vendorName, pickupLocation, pickupStreet, ...)` — configura contexto da sessão; se `_items.isNotEmpty && !isSameContext` → clear automático
- `addItem(CartItem)` → aplica `PricingService.applyMarkup(item.price, _isPartnerStore)` — markup 15% embutido no preço ao adicionar
- `increaseQuantity / decreaseQuantity / removeItem`
- `clearCart()`
- Persiste em SharedPreferences (`bora_cart_v1`)
- `quoteOrderPricing()` → RPC `quote_order_pricing` para preview de preço no checkout

**RestaurantStore** (`lib/stores/restaurant_store.dart`):
- `loadProductsFromSupabase()` — paginação 1000/página, projection explícita:
  `id, restaurant_id, name, description, price, price_low, photo_url, is_available, category, category_root, is_popular, is_on_sale, discount_price`
- `partnerProductsForRestaurant(restaurantId, {onlyAvailable: true})` — retorna lista em memória
- `loadVariantsFromSupabase()` — carrega `ProductVariant` separadamente
- Realtime: subscrito a mudanças em `products` table

**Não existe:** MarketStore, CategoryStore, PromoStore dedicados.

**Colunas DB existentes e carregadas (relevantes para Glovo-style):**
- `is_popular: bool` ✅ (carregado, mapeado para `PartnerProduct.isPopular`)
- `is_on_sale: bool` ✅ (carregado, mapeado para `PartnerProduct.isOnSale`)
- `discount_price: double?` ✅ (carregado, mapeado para `PartnerProduct.discountPrice`)
- `sales_count` — **NÃO existe** na projection nem mapeado (coluna pode não existir no DB)

---

### G) NAVEGAÇÃO — Fluxo Actual

```
ClientMainScreen (tabs: Início | Pedidos | Reservas | Perfil)
  │
  └─ ClientHomeScreen
       │  (botão "Supermercados" / "Lojas" na home)
       │  Navigator.push → StoresScreen(initialCategory: supermarket)
       │
       StoresScreen  [stores_screen.dart]
         │  GestureDetector onTap → _openStore(context, entry)
         │  → cart.configureSession(storeShopping, isPartner, vendorName, ...)
         │
         ├─ isLargeStore (supermarket/store):
         │    Navigator.push → StoreCategoriesScreen  [store_categories_screen.dart]
         │      │  GestureDetector onTap(category) → _openProducts()
         │      │  Navigator.push → StoreProductsScreen(initialCategory: cat)
         │      │
         │      StoreProductsScreen  [store_products_screen.dart]  ◄─┐
         │        │  onTap(produto) → Navigator.push → ProductDetailScreen     │
         │        │  "+" inline → CartStore.addItem()                          │
         │        │  "Ver carrinho" badge → Navigator.push → CartScreen        │
         │        │                                                             │
         │        ProductDetailScreen  [product_detail_screen.dart]            │
         │          │  "Adicionar ao carrinho" → CartStore.addItem()           │
         │          │  _CartBadge → Navigator.push → CartScreen                │
         │                                                                     │
         └─ !isLargeStore (farmácia):                                          │
              Navigator.push → StoreProductsScreen ──────────────────────────┘
                (sem passar por StoreCategoriesScreen)

CartScreen  [cart_screen.dart]
  │  "Ir para pagamento" → Navigator.push → PaymentMethodScreen ✅
  │
PaymentMethodScreen → Checkout ✅ (JÁ FUNCIONA — não tocar)
```

**Onde diverge do padrão Glovo:**
- `StoreCategoriesScreen` não tem busca, banners, "mais vendidos", fotos reais
- `StoreProductsScreen` não tem banners/promoções inline
- `CartScreen` não tem fotos dos produtos nos items

---

## FASE 2 — Partner vs Non-Partner

### Distinção implementada

| Mercado | isPartner | Comportamento |
|---|---|---|
| **Auchan Guarda** | `true` | Sem markup, service fee 5%, driver sem bónus extra de compra |
| **Continente** | `false` | Markup 15% embutido nos preços ao adicionar ao carrinho |
| **Lidl** | `false` | Idem |
| **Pingo Doce** | `false` | Idem |
| **Mercadona** | `false` | Idem |
| **Intermarché** | `false` (pós-lançamento) | Idem |

### Como funciona tecnicamente

1. `RestaurantModel.isPartner: bool` — vem da coluna `is_partner` na tabela `restaurants`
2. `StoresScreen._openStore()` → `cart.configureSession(isPartnerStore: entry.business.isPartner)`
3. `CartStore._isPartnerStore` guarda o valor para a sessão inteira
4. `CartStore.addItem()` → `PricingService.applyMarkup(item.price, _isPartnerStore)`:
   - `isPartner == true` → preço sem markup
   - `isPartner == false` → preço × 1.15 (+15%)
5. O `isPartnerStore` passa por toda a cadeia: `StoreCategoriesScreen` → `StoreProductsScreen` → mas **não é usado visualmente nestes ecrãs** (não há badge "preços de loja", aviso de markup, etc.)

### Ramificações visuais baseadas em isPartner

**Actualmente: NENHUMA.** O UI é idêntico para parceiro e não-parceiro. A diferença é apenas no pricing (CartStore + PricingService). Não há:
- Badge/aviso "preços com markup de mercado"
- Diferença de layout na `StoreCategoriesScreen` ou `StoreProductsScreen`
- Indicação visual de "preço do site" vs "preço Bora"

### Regra de negócio (BR §7 — confirmada)

```
Parceiro storeShopping (is_partner_store=true):
  - Service fee: 5% do subtotal
  - Markup: 0% (preço de parceiro)
  - Driver: €3.80 + €0.20/km + €0.80 bónus storeShopping
  - Saco: €0 (parceiro absorve)

Não-parceiro storeShopping (is_partner_store=false):
  - Service fee: €2.50 FIXO (não percentagem)
  - Markup: 15% embutido no preço do produto (ponto de adição ao carrinho)
  - Driver: €3.80 + €0.80 + €0.20/km + 30% boraNet profit share
  - Saco: €0.10/saco × sacos reais (cap 5 sacos = €0.50 máx)
  - Cobrança pós-entrega via RPC finalize_storeshopping_purchase + charge automático

⚠️ CRÍTICO (BR §7): Confundir partner com non-partner = erro grave.
   Verificar SEMPRE is_partner_store antes de qualquer lógica de pricing.
```

---

## FASE 3 — Referência Glovo (Padrão Alvo)

### TELA A — Mercado Interior (Glovo style)
- Header colapsável com **logo do mercado em destaque** (grande, no topo)
- **Sticky search bar** (aparece ao fazer scroll, cola no topo)
- **Banners de promoções** — carrossel horizontal (campanha, desconto, produto em destaque)
- **"Categorias populares"** — grid 4 colunas com **fotos reais** (ex: foto de maçã para Frutas)
- **"Todas as categorias"** — link para ver lista completa das 18-22 categorias
- **"Mais vendidos"** — scroll horizontal de produtos com foto, preço, botão "+"
- **Bottom nav:** Loja | Categorias | Pedir de novo

### TELA B — Categoria de Produtos (Glovo style)
- **Search fixa** no topo
- **Chips horizontais** de sub-categorias (texto ou ícone)
- **Grid 2 colunas fixo** — foto, nome, preço, botão "+"
- Contador flutuante "Ver carrinho (€X,XX)"

### TELA C — Detalhe do Produto (Glovo style)
- Foto grande, **zoomável**
- Nome, marca, descrição
- Seletor de quantidade
- Botão "Adicionar ao carrinho · €X,XX" (fixo no fundo)

### TELA D — Carrinho (Glovo style)
- Lista de itens com **foto pequena** + qty + preço
- Subtotal, taxa entrega, taxa serviço, total
- Botão "Finalizar pedido" (laranja)

### TELA E — Checkout
✅ Já funciona — não tocar.

---

## FASE 4 — Gap Analysis

| Tela | O que existe hoje | Padrão Glovo | Gap — O que falta |
|---|---|---|---|
| **A. Interior mercado** (`StoreCategoriesScreen`) | AppBar básico + GridView de categorias com ícones hardcoded + badge carrinho | Header com logo + sticky search + banners + fotos reais nas categorias + "Mais vendidos" + bottom nav | ❌ Logo mercado em destaque ❌ Search bar ❌ Banners/carrossel promoções ❌ Fotos reais nas categorias ❌ Secção "Mais vendidos" ❌ Bottom nav |
| **B. Categoria produtos** (`StoreProductsScreen`) | Search TextField + chips horizontais (texto) + grid produtos + "+" inline + badge carrinho | Search fixa + chips + grid 2 colunas fixo + badge | ✅ Search existe ✅ Chips existem ✅ Grid existe ✅ Botão "+" inline ✅ Badge carrinho ❌ Chips sem fotos ❌ Banners/promoções inline |
| **C. Detalhe produto** (`ProductDetailScreen`) | SliverAppBar + foto grande + nome + preço + qty selector + botão adicionar + variantes | Foto zoomável + nome + marca + descrição + qty + botão | ✅ Foto grande ✅ Nome + preço ✅ Qty selector ✅ Botão adicionar ❌ Zoom na foto ❌ Marca destacada separada das variantes |
| **D. Carrinho** (`CartScreen`) | Lista items (nome + qty + preço) + fees breakdown + botão finalizar | Items com foto pequena + fees + botão | ✅ Lista items ✅ Fees breakdown ✅ Botão finalizar ❌ Foto pequena dos produtos |
| **E. Checkout** (`PaymentMethodScreen`) | ✅ Funciona | ✅ Padrão | ✅ Não tocar |

---

## FASE 5 — Impacto e Dependências

### Gap 1 — Logo do mercado em destaque (StoreCategoriesScreen header)
- **Ficheiros tocados:** `store_categories_screen.dart`
- **Stores:** `RestaurantStore` (já tem `restaurant.photoUrl` ou `logoUrl`)
- **Supabase:** `restaurants.photo_url` — verificar se existe e tem valor para mercados
- **Assets:** Nenhum novo (usa URL remoto)
- **Risco:** Baixo — cosmético
- **Admin:** Não precisa novo ecrã (gestão de logo já existe em `partner_dashboard_screen`)

### Gap 2 — Sticky search bar na StoreCategoriesScreen
- **Ficheiros tocados:** `store_categories_screen.dart` (adicionar TextField + SliverPersistentHeader ou SliverAppBar pinned)
- **Stores:** Nenhuma nova
- **Supabase:** Pode reusar RPC `search_products` já existente em `StoreProductsScreen`
- **Risco:** Baixo-Médio — precisa converter para `CustomScrollView` + Slivers

### Gap 3 — Banners/carrossel de promoções (TELA A e B)
- **Ficheiros tocados:** `store_categories_screen.dart`, `store_products_screen.dart`
- **Stores:** Nenhuma nova — dados já disponíveis (`is_on_sale`, `discount_price` carregados)
- **Supabase:** Query nova possível para banners curados, OU usar `is_on_sale == true` como proxy para "promoções" (já existe)
- **Admin:** ⚠️ Precisa ecrã admin para gerir banners por mercado (imagem, título, produto destaque) — **não existe actualmente**
- **Risco:** Médio — depende de decisão: banners automáticos (is_on_sale) vs curados (admin)

### Gap 4 — "Mais vendidos" / "Populares" (TELA A)
- **Ficheiros tocados:** `store_categories_screen.dart` (nova secção scroll horizontal)
- **Stores:** Nenhuma nova
- **Supabase:** `is_popular == true` já existe na DB e é carregado! `partnerProductsForRestaurant().where((p) => p.isPopular)` — zero queries adicionais
- **Assets:** Fotos dos produtos já vêm do `photo_url`
- **Risco:** Baixo — dados já existem. Só falta o widget UI
- **Nota:** `sales_count` **não existe** na projection/DB. Usar `is_popular` como proxy. Para gestão manual de "populares" → admin panel precisa toggle `is_popular` por produto

### Gap 5 — Fotos reais nas categorias (TELA A)
- **Ficheiros tocados:** `store_categories_screen.dart`, `pubspec.yaml`
- **Assets:** `assets/images/categories/` — **pasta não existe**, não há imagens registadas no pubspec
- **Opções:**
  - a) Usar foto do primeiro produto de cada categoria (URL remoto — zero assets)
  - b) Criar imagens estáticas por categoria e adicionar ao pubspec
  - c) Manter ícones actuais (aceitável para MVP)
- **Risco:** Baixo-Médio (opção a é a mais rápida)

### Gap 6 — Foto pequena dos produtos no CartScreen
- **Ficheiros tocados:** `cart_screen.dart` — `_CartItemTile` (adicionar `CachedNetworkImage`)
- **Stores:** `CartItem` precisa de campo `photoUrl` (actualmente não tem)
- **Modelos:** `cart_item.dart` — adicionar `String? photoUrl`
- **Propagação:** `store_products_screen.dart` e `product_detail_screen.dart` — passar `photoUrl` ao criar `CartItem`
- **Supabase:** Dados já carregados (`photo_url` no produto)
- **Risco:** Médio — toca em `CartItem` (modelo serializado em SharedPreferences → migration do formato de persistência pode ser necessária)
- **Atenção:** `SharedPreferences` guarda o cart serializado. Mudar `CartItem` pode apagar carrinhos activos. Verificar `_kPrefsKey = 'bora_cart_v1'` e versionar se necessário.

### Gap 7 — Bottom nav na StoreCategoriesScreen
- **Ficheiros tocados:** `store_categories_screen.dart`
- **Stores:** Nenhuma
- **Risco:** Baixo-Médio — design decision. "Pedir de novo" requer histórico de produtos do mercado por cliente (não existe actualmente)
- **Decisão necessária:** Implementar só "Loja | Categorias" e deixar "Pedir de novo" para pós-lançamento

### Gap 8 — Zoom na foto do produto (ProductDetailScreen)
- **Ficheiros tocados:** `product_detail_screen.dart`
- **Dependência:** Pacote `photo_view` ou `interactive_viewer` (built-in Flutter)
- **Risco:** Baixo — `InteractiveViewer` não precisa pacote novo
- **Admin:** Nenhum

---

## FASE 6 — Achados Fora de Scope

### 1. `client_main_screen.dart` — Inconsistência de tabs
Encontradas **duas versões** do ficheiro em memória (uma com `ClientReservationsScreen` no tab list, outra sem). A versão mais recente parece ter 4 tabs (`ClientHomeScreen`, `OrdersScreen`, `ClientReservationsScreen`, `ProfileScreen`). Verificar qual versão está efectivamente em uso.

### 2. `StoreProductsScreen` — Ficheiro muito grande (1629 linhas)
Concentra: fetch de produtos, filtros, busca RPC, múltiplos widgets (_SectionedView, _FlatGridView, _SkeletonLoader, _ProductCard, _BoraProductCardTile, _VariantMiniCard, _SuggestionsPanel...). Bom candidato a split de ficheiro no futuro, mas fora do scope actual.

### 3. `CartStore.addItem()` — Markup aplicado no preço do CartItem
O preço no `CartItem` já vem com markup embutido. Isso significa que no `CartScreen`, o preço exibido **já é o preço com markup**. Verificar se o cliente vê alguma indicação de que o preço inclui taxa de serviço Bora (exigência legal possível). Sem correção recomendada aqui — só registo.

### 4. `is_popular` na DB — Gestão manual
A coluna `is_popular` existe mas não há ecrã admin para toggle por produto. A secção "Mais vendidos" que queremos adicionar dependeria desta coluna. O admin panel precisaria de um toggle por produto. Actualmente só se pode gerir via Supabase dashboard directamente.

### 5. `discount_price` carregado mas não exibido
`PartnerProduct.discountPrice` está mapeado no `RestaurantStore` mas nenhum widget em `StoreProductsScreen` ou `ProductDetailScreen` exibe um preço riscado + preço de promoção. A infra-estrutura existe; só falta o widget.

### 6. `assets/` — Apenas 1 asset registado
`pubspec.yaml` regista apenas `assets/sounds/bora_alert.wav`. Não há imagens de categorias, logos, ou placeholders. Se se optarem por imagens locais de categorias, o `pubspec.yaml` terá que ser actualizado.

### 7. `StoresScreen` — Farmácias vão directo para `StoreProductsScreen`
Farmácias (`BusinessCategory.pharmacy`) saltam `StoreCategoriesScreen` e vão directamente para `StoreProductsScreen` (sem filtro de categoria). Este comportamento é intencional (farmácias têm menos produtos, não precisam de ecrã intermédio de categorias). Mas se a Wells tiver muitos produtos, reconsiderar.

### 8. `pickupCity` e `pickupPostalCode` não preenchidos para mercados
Em `_openStore()` (L237-238): `pickupCity: null, pickupPostalCode: null`. Estes campos ficam nulos para todos os mercados. Pode afectar funcionalidades futuras que dependam do postal code do pickup.

---

## Sumário Executivo

### Fluxo actual (resumo):
```
StoresScreen → [configureSession(storeShopping)] → StoreCategoriesScreen → StoreProductsScreen → ProductDetailScreen → CartScreen → PaymentMethodScreen ✅
```

### Estado vs Glovo:
- **TELA B (categoria) e C (detalhe) e D (carrinho):** 70-85% completos — pequenos ajustes
- **TELA A (interior mercado):** 30% completo — é o maior gap. Falta search, banners, "mais vendidos", fotos reais
- **TELA E (checkout):** 100% ✅ — não tocar

### Quick wins (sem novas queries Supabase):
1. Secção "Mais vendidos" em `StoreCategoriesScreen` → dados já em memória (`is_popular`)
2. Fotos nos items do carrinho → foto do primeiro produto em memória
3. Zoom na foto do produto → `InteractiveViewer` (built-in Flutter)
4. Preços em promoção (`discount_price`) já carregados → só falta widget

### Requer decisão do Danilo antes de implementar:
- Banners de promoção: automáticos (is_on_sale) vs curados (admin panel novo)?
- Fotos nas categorias: foto do 1º produto (mais rápido) vs imagens estáticas vs manter ícones?
- Bottom nav na StoreCategoriesScreen: implementar agora ou pós-lançamento?
- CartItem + photoUrl: versionar SharedPreferences ou aceitar perda de carts activos?
