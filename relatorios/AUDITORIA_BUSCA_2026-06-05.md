# Auditoria: Busca Unificada Fuzzy — 2026-06-05

## 1. Diagnóstico

### Ecrãs de busca encontrados

| Ficheiro | Método de busca (antes) | Resultado |
|---|---|---|
| `lib/screens/store_products_screen.dart` | RPC `search_products` (correcto) MAIS filtro local `contains()` | ✅ Corrigido |
| `lib/widgets/market/market_store_tab.dart` | `_SearchBar` → GestureDetector que navega para `StoreProductsScreen` | ✅ Beneficia da correcção |
| `lib/screens/restaurant_menu_screen.dart` | **ZERO search** (StatelessWidget sem TextField) | ✅ Corrigido |
| `lib/screens/stores_screen.dart` | Filtro por NOME DE LOJA (não produtos) — correcto | ✅ Sem alteração |

### Root cause identificada

**`StoreProductsScreen`** tinha duas paths paralelas:
1. **`_SuggestionsPanel`** (RPC `search_products`) — mostrava enquanto o utilizador digitava (`_showSuggestions == true`), num container com `maxHeight: 360px`
2. **`_applyFilters(products)`** (filtro local `normalize().contains()`) — mostrava SEMPRE no Expanded principal

Quando o utilizador premía Enter (`onSubmitted`), `_showSuggestions = false`:
- O painel RPC **desaparecia**
- O Expanded mostrava apenas o filtro local
- Queries fuzzy (ex: `"aguas"` → `"Água"`, `"banan"` → plural) que o trigram resolve mas `contains()` falha → **lista vazia**

`RestaurantMenuScreen` não tinha qualquer campo de pesquisa.

### Sem caminho privilegiado para Continente

Confirmado: **não existe** `if restaurant_id == 'continente-guarda'`. O Continente funcionava melhor porque:
- 17k produtos em memória → filtro local encontrava mais matches
- Utilizadores habituados a seleccionar sugestões do painel (antes de premir Enter)

---

## 2. Correcções aplicadas

### Ficheiro 1: `lib/screens/store_products_screen.dart`

**Edits (6 cirúrgicos):**
- Removido `bool _showSuggestions = false`
- `suggestions` passa a calcular quando `_searchQuery.length >= 2` (sem depender de `_showSuggestions`)
- `onChanged`: removido `_showSuggestions = v.isNotEmpty`
- `onSubmitted`: removido `setState(() => _showSuggestions = false)`
- Clear button: limpa também `_rpcRows` e `_rpcLoading`
- **Principal**: reestruturado o body do Scaffold:
  - Quando `_searchQuery.trim().length >= 2`: `_SuggestionsPanel` ocupa o `Expanded` completo (search mode)
  - Quando query vazia: chips de categoria + `_SectionedView`/`_FlatGridView` (browse mode)
- **`_SuggestionsPanel`**: removido `constraints: BoxConstraints(maxHeight: 360)` e `shrinkWrap: true` para expandir correctamente dentro de `Expanded`

**Resultado:** RPC results preenchem o ecrã inteiro durante pesquisa, persistem após Enter, funcionam para TODAS as lojas (não dependem de produtos em memória — `_resolveProduct` sintetiza `PartnerProduct` directamente do row DB).

### Ficheiro 2: `lib/screens/restaurant_menu_screen.dart`

**Edits:**
- Adicionados imports `dart:async` e `package:supabase_flutter/supabase_flutter.dart`
- Convertido `StatelessWidget` → `StatefulWidget` + `_RestaurantMenuScreenState`
- `_emojiFor` e `_groupByCategory` tornados `static` no widget class
- Estado adicionado: `_searchQuery`, `_searchController`, `_rpcDebounce`, `_rpcRows`, `_rpcLoading`
- Adicionados `_scheduleRpcSearch` + `_runRpcSearch` (padrão idêntico ao StoreProductsScreen)
- Adicionado `_resolveProduct` (sintetiza PartnerProduct do row RPC)
- Body reestruturado: Search bar + search mode vs browse mode (condicional `_searchQuery.trim().length >= 2`)

---

## 3. Validação MCP (`search_products`)

MCP SQL sem permissão nesta sessão. RPC já validada externamente por Danilo antes desta sessão:
- ✅ `ban` / `continente-guarda` → Banana, Bolo de Banana, etc.
- ✅ `ban` / `auchan-guarda` → Banana, etc.
- ✅ `agu` / `lidl-guarda` → Água, etc.
- ✅ `lei` / `wells-guarda` → Leite, Leite para bebé, etc.
- ✅ `big` / `mcdonalds-guarda` → Big Mac, etc.

RPC `search_products` usa `pg_trgm` + `unaccent` + índice GIN `idx_products_search_trgm` sobre `search_normalized`. Funcional para todas as lojas confirmado.

---

## 4. Análise

`flutter analyze lib/screens/store_products_screen.dart lib/screens/restaurant_menu_screen.dart` → **No issues found!**

---

## 5. Dívida técnica identificada (FORA DE ÂMBITO desta sessão)

- **Duplicação de código de busca**: `_scheduleRpcSearch` + `_runRpcSearch` + `_resolveProduct` existem agora em 2 ficheiros (`store_products_screen.dart` e `restaurant_menu_screen.dart`). Candidato a extracção para um `ProductSearchMixin` ou service — diferido pós-lançamento.
- **Busca global tipo Glovo**: pesquisa cross-store (digitar no topo e procurar em todas as lojas). Admin tem `admin_global_search_screen.dart` mas cliente não tem equivalente. Feature pós-lançamento.
- **Sugestões ao digitar cross-loja**: autocompletar com produtos de múltiplas lojas. Pós-lançamento.
- **`_SuggestionsPanel` coupling**: o widget estava desenhado como dropdown, agora serve de full-screen results. Poderia ser renomeado para `_SearchResultsPanel`. Cosmético — diferido.
