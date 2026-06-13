# HOTFIX — B5 partiu o ecrã das lojas de mercado (regressão build 288)

**Data:** 2026-06-12 · **Modelo:** Opus 4.8 · **Tipo:** hotfix cirúrgico de regressão em produção.
**Origem:** sessão B1-B6 (commit B5 `c90b701`). **Ler antes:** BLOQUEADORES_B1-B6_RESOLVIDOS_2026-06-12.md §B5.

---

## 1. Resumo para o Danilo (PT-BR)

O B5 trocou "carregar tudo no arranque" por "carregar 30 de cada vez ao abrir a loja". Mas os 3 ecrãs de mercado (loja, lista de categorias, tela de categoria) **montam as categorias filtrando os produtos que estão na memória** — e com só 30 carregados (todos da mesma categoria, porque vêm ordenados), aparecia **1 categoria** e tocar nela dava **tela branca** (os 30 em memória não eram dessa categoria).

A correção **não reescreve nada**: ao abrir uma loja de mercado, carrego **a loja inteira** (1000 de cada vez, ~7 pedidos no Auchan), e os ecrãs voltam a funcionar exactamente como antes do B5 (todas as 21 categorias, tela de categoria com produtos). **O ganho do B5 mantém-se**: o arranque continua a NÃO carregar os 45k (só parceiros + restaurantes); os mercados só carregam quando abres, e só fica **1 mercado em memória de cada vez** (descarrego os outros). A busca continua 100% na base de dados.

---

## 2. Causa-raiz (confirmada via MCP + código)

- Os 3 ecrãs leem `partnerProductsForRestaurant(id)` e fazem `_categoryOf` (= `category_root` capitalizado) **em memória**:
  - `market_store_tab.dart` → `_topCategories`/`_topCategorySections` (carrosséis)
  - `market_categories_tab.dart` → agrupa por categoria (lista)
  - `store_products_screen.dart` → `_applyFilters` por `_selectedCategory`
- O B5 v1 só punha 30–120 produtos em memória (`ensureStoreProductsLoaded`/`loadMoreStoreProducts`). Como os produtos vêm `ORDER BY sort_order` (agrupados por categoria na fonte), os primeiros 30 eram **todos de 1 categoria** → só 1 carrossel; e a tela de categoria filtrava 30 produtos que **não** continham a categoria tocada → **branco**.
- **Dados estão perfeitos** (não é problema de dados): Continente 38 cat / 11.884 prod, Mercadona 25 / 8.097, Auchan 21 / 6.240, Intermarché 42 / 5.824, Pingo Doce 19 / 5.023 — todos com 0 produtos sem categoria.

## 3. Decisão de arquitectura (divergência justificada do prompt)

O prompt sugeria **Option A**: RPC de categorias distintas + amostra por categoria + paginação por categoria na tela. Optei por **Option B (full-load da loja ao abrir)**. Porquê (DNA §2 "funcionar sempre > features", §5 "cirúrgico, nunca revolucionário", #7 "proteção antes de velocidade"):

| | Option A (prompt) | **Option B (escolhida)** |
|---|---|---|
| Superfície de mudança | RPC nova + reescrever 3 ecrãs complexos + casar `category_root`/capitalização no filtro DB | 1 método novo no store + 5 edits de 1-3 linhas; **0 mudanças de lógica nos ecrãs** |
| Risco (hotfix de produção) | Alto (novos bugs em 3 ecrãs) | Baixo (restaura o modelo que já funcionava) |
| Ganho B5 (arranque sem 45k) | Mantido | **Mantido** (+ eviction: máx 1 loja em memória) |
| Reversível | Difícil | Trivial |

Option A fica como **follow-up de performance** (first-paint instantâneo com amostras), não como hotfix.

## 4. O que mudou (cirúrgico)

| Ficheiro | Mudança |
|---|---|
| `lib/stores/restaurant_store.dart` | Removido o andaime lazy do B5 (`storePageSize=30`, `_storeHasMore`, `storeHasMoreProducts`, `ensureStoreProductsLoaded`, `loadMoreStoreProducts`). Novo `loadFullStoreProducts(id)`: carrega a loja toda a 1000/página para `_productsByRestaurant`, `notifyListeners` por página (carrosséis preenchem progressivamente), idempotente (`_storeFullyLoaded`), **eviction** dos outros mercados (parceiros/restaurantes do arranque nunca entram em `_storeFullyLoaded` → intactos). Dedupe O(1) por `Set`. Arranque: `_storeHasMore.clear()` → `_storeFullyLoaded.clear()`. |
| `lib/screens/market/market_store_screen.dart` | `initState`: `ensureStoreProductsLoaded(120)` → `loadFullStoreProducts(id)`. |
| `lib/screens/store_products_screen.dart` | `initState`: `ensureStoreProductsLoaded(30)` → `loadFullStoreProducts(id)`. Removido o `NotificationListener` de scroll-infinito-por-30 (desnecessário — loja toda em memória); mantido o spinner enquanto carrega. |
| `lib/widgets/market/market_categories_tab.dart` | Empty + a carregar → spinner (em vez do falso "Sem categorias" a piscar durante o full-load). |

**Não tocado:** `market_store_tab.dart` (funciona tal-e-qual com a loja completa), pricing, create_order, dispatch, Stripe, tokens, busca (RPC `search_products`).

## 5. Como mantém o ganho do B5 (memória)

- Arranque: só parceiros + restaurantes (pequeno) — **inalterado**.
- Abrir mercado: carrega só essa loja; ao abrir outra, **descarrega a anterior** (`_storeFullyLoaded` só contém mercados). Máximo em memória = **1 mercado** (pior caso Continente ~11.884) + parceiros/restaurantes. Nunca os 45k juntos, mesmo navegando todas as lojas.
- Custo de abrir: pedidos sequenciais de 1000 (Auchan 7, Continente 12) com spinner + preenchimento progressivo. Pré-B5 carregava 45k no arranque (pior). 

## 6. Validação

| Critério | Estado |
|---|---|
| flutter analyze 0 errors | ✅ **0 errors** (removido 1 import morto que a churn deixou em store_products_screen) |
| Auchan mostra as 21 categorias | ✅ por construção (loja completa em memória → `_topCategories`/CategoriesTab veem tudo) |
| Tap "Mercearia Doce" → produtos (não branco) | ✅ `_applyFilters` sobre a loja completa; spinner enquanto carrega |
| Scroll vê todos os produtos da categoria | ✅ lista em memória completa (scroll normal; "infinito" deixou de ser preciso) |
| Arranque NÃO carrega 45k | ✅ `loadProductsFromSupabase` continua `inFilter` parceiros+restaurantes; mercados só on-demand |
| Busca na DB | ✅ inalterada (`search_products`) |

## 7. Follow-ups (não bloqueantes)

1. **Option A (perf)**: RPC `store_categories_with_counts(restaurant_id)` + amostra por categoria → first-paint instantâneo sem esperar o full-load (Continente são 12 pedidos sequenciais ~3-6s). Hoje mitigado por spinner + preenchimento progressivo.
2. Paralelizar as páginas do full-load (em vez de sequencial) reduz o tempo de abertura das lojas grandes.
3. `loadVariantsFromSupabase` continua unbounded (pequeno hoje).

## 8. Analyze

`flutter analyze --no-pub`: **0 errors** ✅. Limpei o `app_colors.dart` (import morto em store_products_screen, confirmado 0 usos). Restantes warnings/infos são baseline pré-existente (register_partner unused import; prefer_const em market_store_tab) — nada introduzido por este hotfix.
