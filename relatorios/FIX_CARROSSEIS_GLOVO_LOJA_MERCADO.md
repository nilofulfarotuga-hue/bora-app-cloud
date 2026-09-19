# FIX — Ecrã da loja de mercado igual ao Glovo (todos os carrosséis)

**Data:** 2026-06-13 · **Modo:** PROTECÇÃO TOTAL · **Orquestrador:** CEO-AI
**Ficheiro tocado (1):** `lib/widgets/market/market_store_tab.dart`

## Problema (relato do Danilo + prints Glovo)
O ecrã da loja mostrava a grelha "Comprar por categoria" e **parava** após
poucos carrosséis. O Glovo empilha a grelha + **TODOS** os carrosséis de
categoria, por ordem de `sort_order`, em scroll vertical até à última categoria.

## Causa-raiz (investigada, não adivinhada)
Em `market_store_tab.dart` (tab "Loja"):
- A grelha usava `_topCategories` → **top 8** categorias **por contagem**.
- Os carrosséis usavam `_topCategorySections` → **top 5** categorias **por
  contagem** (`_maxCategorySections = 5`), construídos **eagerly** (`for` +
  `SliverToBoxAdapter`), com gate `>= 3` produtos.
→ Resultado: no máximo ~5 carrosséis, ordem errada (contagem, não sort_order).

**Descoberta-chave:** `RestaurantStore.loadFullStoreProducts` já busca os
produtos `ORDER BY sort_order ASC, id ASC` (restaurant_store.dart:138) e
`partnerProductsForRestaurant` **preserva essa ordem**. Como um `Map` literal
Dart é `LinkedHashMap`, agrupar por categoria com `putIfAbsent` devolve as
categorias **na ordem de 1ª aparição = ordem de sort_order**. Logo, **NÃO foi
preciso tocar no modelo, na store nem na query** — só na camada de UI.

## Fix (cirúrgico, 1 ficheiro)
1. **Grelha:** agora lista **TODAS** as categorias por sort_order (era top 8).
2. **Carrosséis:** novo `_orderedCategories()` devolve todas as categorias por
   sort_order; render via **`SliverList` + `SliverChildBuilderDelegate`
   (lazy — só constrói os visíveis)**, `childCount = nº categorias`. Sem cap,
   sem gate → vai até à última (ex.: 38 no Continente).
3. Cada carrossel mostra os **primeiros 12 produtos** (`_maxCarouselProducts`)
   na ordem natural (sort_order); seta "→" abre `StoreProductsScreen` da
   categoria completa (ecrã inalterado, já funcional).
4. Removidos helpers mortos (`_topCategories`, `_topCategorySections`,
   `_productsForCategory`) e constantes (`_maxCategoryGridItems`,
   `_maxCategorySections`). Mantidos os rails "Em promoção"/"Mais vendidos"
   (gated ≥3) — não estragar o que funciona.

## Cobertura — todas as lojas de mercado
Todas as lojas entram por `StoreCategoriesScreen → MarketStoreScreen →
MarketStoreTab`. Logo o fix aplica-se automaticamente a: **Continente, Auchan,
Mercadona, Pingo Doce, Lidl, Wells, Worten, Leroy Merlin, Kiwoko, Zippy.**

## Zonas protegidas — NÃO tocadas
pricing / create_order / Stripe / dispatch / tokens / fotos de produto / preços.
Sem mudanças em modelo, store, query, migrations ou Edge Functions.

## Validação
- `flutter analyze` (ficheiro alterado): **0 errors, 0 warnings** (5 `info`
  pré-existentes em widgets NÃO tocados — _BackButton/_StatsRow/_Footer).
- `flutter analyze` (projeto completo): **0 errors**; as warnings existentes
  são todas pré-existentes noutros ficheiros (driver_map, profile,
  register_partner, chat_bubble, refund_choice, 1 teste) — nenhuma neste fix.

### Checklist (confirmar no device, build > atual via CI)
- [ ] Continente abre → grelha com TODAS as categorias.
- [ ] Scroll mostra TODOS os carrosséis (até à última, ~38), nenhum em branco.
- [ ] Ordem dos carrosséis = sort_order (Frutas → Talho → Charcutaria → …).
- [ ] Seta "→" abre a categoria completa.
- [ ] Repetir em Auchan, Mercadona, Lidl.

## PENDENTE — McDonald's / BK / KFC (fluxo restaurante)
NÃO tocado. Conforme instrução, **aguarda os prints do Glovo (McDonald's)**
antes de mexer em `restaurant_menu_screen.dart`. Nota: esse ecrã já refere
("M9 paridade Glovo") que os produtos chegam por sort_order — a confirmar com
os prints se já empilha por categoria ou tem o mesmo defeito.
