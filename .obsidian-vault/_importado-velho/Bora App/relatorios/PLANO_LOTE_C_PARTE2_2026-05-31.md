# 📐 PLANO — LOTE C PARTE 2 (C3, C4, C5)
> Data: 2026-05-31 · Modo: PROTECÇÃO TOTAL · **NADA editado nesta Parte 2** (só análise read-only).
> Regra de sugestões: só o que existe em Glovo/Uber Eats/iFood. Aprovação do Danilo antes de implementar.

---

## C3 — "Pedir de novo" (reorder 1-toque)

### Estado real
- 🟢 **A lógica já está toda escrita e testada** em `lib/services/reorder_service.dart`:
  - `isReorderable(order)` — só restaurant/storeShopping com itens.
  - `applyTo(cart, order, ...)` — limpa carrinho, reconfigura sessão, re-adiciona itens **com o preço atual**, e devolve a lista de itens cujo preço mudou (para avisar o cliente).
- 🔴 **Nunca é chamada** (0 callers). `MarketReorderTab` (`market_reorder_tab.dart`) é só um placeholder "Em breve", instanciado em `market_store_screen.dart:82` como `const MarketReorderTab()` (sem params).

### Desenho proposto (pequeno)
1. `MarketReorderTab` passa a receber `restaurantId` + `storeName` + `isPartnerStore` (já disponíveis no `market_store_screen`).
2. Converter para StatefulWidget (ou consumir `OrderStore`): listar os pedidos passados do cliente **desta loja** (`OrderStore` já tem os pedidos do cliente; filtrar por `vendorName == storeName` + `ReorderService.isReorderable`).
3. Cada pedido → card com itens/total/data + botão "Pedir de novo".
4. No toque: `ReorderService.applyTo(...)` → se devolver itens com preço alterado, `SnackBar` "Alguns preços mudaram: X, Y" → navegar para o carrinho/checkout.
5. Tratamento de produto que já não existe: o `applyTo` re-adiciona pelo histórico; para parceiros faz match com produto vivo (preço atual). **Falta** tratar "produto descontinuado" — proposta: se o produto não existe na loja viva (partner), omitir e avisar. (Para não-parceiros não há catálogo vivo fiável por item → reusa preço histórico, aceitável.)

### Ficheiros afetados
- `lib/widgets/market/market_reorder_tab.dart` (reescrever o placeholder).
- `lib/screens/market/market_store_screen.dart:82` (passar params).
- (leitura) `OrderStore` para a lista de pedidos do cliente.

### Zonas sensíveis · Risco · Esforço
- **Toca:** carrinho (`cart.clearCart` + `configureSession` + `addItem`) — mas via `ReorderService` já existente, que segue o mesmo caminho do fluxo normal. **Não toca pricing/RPC/Stripe.**
- **Risco:** BAIXO. A parte arriscada (mexer no carrinho) já está encapsulada e testada.
- **Esforço:** PEQUENO (~½ dia). É essencialmente UI + ligar o que já existe.
- **Recomendação:** ✅ **PODE SER ANTES DO LANÇAMENTO** — alto valor (paridade Glovo/Uber/iFood), baixo risco, lógica pronta.

---

## C4 — Preferência de substituição (mercados)

### Estado real (nuance importante)
- 🟢 **Já existe um sistema de substituição — mas REATIVO, via chat:**
  - `OrderModel.substitutionResponses` (`Map<String,bool>`) + coluna `substitution_responses` (orders).
  - `MessageType.substitution` + `MessageModel.substitution` + `SubstitutionContent` (`message_model.dart`).
  - `chat_store.dart:123` insere proposta; `order_store.dart:1880` grava a resposta; `chat_screen.dart` mostra e o cliente aprova/rejeita por item.
  - Fluxo atual: estafeta na loja propõe substituição de um item → cliente aprova/rejeita **no chat, item a item**.
- 🔴 **NÃO existe** a preferência **proativa** definida no checkout (substituir por similar / não substituir / contactar-me). Não há campo `allowSubstitution` no carrinho/order.

### Desenho proposto
1. No checkout (mercados/storeShopping), seletor de **default de substituição**: `substituir por similar` · `não substituir (reembolsar)` · `contactar-me` (este último = comportamento atual via chat).
2. Novo campo `cart → finishOrder(substitutionPolicy) → createOrder → coluna orders.substitution_policy` (text).
3. O estafeta vê a política no fluxo storeShopping V2 (inline em `driver_map_screen`): se "substituir por similar", pode substituir sem chat (até ao threshold €5 já existente — Decisão J); se "não substituir", marca indisponível direto; se "contactar-me", usa o chat atual.

### Ficheiros afetados
- `lib/screens/payment_method_screen.dart` (seletor).
- `lib/stores/cart_store.dart` + `lib/stores/order_store.dart` (passar o campo).
- `lib/models/order_model.dart` (novo campo + serialização).
- DB: nova coluna `orders.substitution_policy` (migration).
- `lib/screens/driver_map_screen.dart` (estafeta lê a política no fluxo V2).

### Zonas sensíveis · Risco · Esforço
- **Toca:** storeShopping V2 (fluxo de compra do estafeta) + estrutura do pedido + migration DB. ⚠️ **zona sensível** (settlement/compra).
- **Risco:** MÉDIO. Não toca pricing nem dinheiro diretamente, mas altera o comportamento de compra do estafeta e o threshold €5 já existente — precisa de cuidado para não duplicar/contradizer a lógica de chat atual.
- **Esforço:** MÉDIO (~1-2 dias) — toca 5 ficheiros + 1 migration + lógica do estafeta.
- **Recomendação:** 🟡 **PÓS-LANÇAMENTO** (ou logo depois). O sistema reativo via chat **já cobre o caso** (cliente decide quando há substituição). A preferência proativa é uma melhoria de UX, não um bloqueador. Fazer com calma para não partir o fluxo V2.

---

## C5 — Entrega agendada (scheduled delivery)

### Estado real
- 🔴 **Não existe.** Todos os pedidos são "asap": `create_order` cria → dispatch imediato (trigger em `callingDriver`). Não há coluna de agendamento nem scheduler.

### O que envolve (honestamente — a mais pesada)
1. **UI:** escolher data/hora no checkout, **limitada pelos horários da loja** (`business_hours` / `isOpenNow` já existem mas para "agora", não para slots futuros) + slots (ex. 30 min).
2. **Modelo/DB:** coluna `orders.scheduled_for` (timestamptz) + um estado novo tipo `scheduled` (antes de `created`/`preparing`). Mexe no `OrderStatus` enum (zona core do lifecycle).
3. **Dispatch (ZONA PROIBIDA):** o `dispatch-engine` é "asap". Um pedido futuro **não pode** entrar no dispatch à criação — precisa de um **scheduler** (pg_cron) que liberte o pedido para `callingDriver` ~X min antes da hora. Isto é arquitetura nova no coração do dispatch.
4. **Pagamento (Stripe — ZONA PROIBIDA):** decidir cobrar **na hora do agendamento** (pré-autorização/captura — Stripe auth válido 7 dias) vs **na hora do envio**. Cada opção tem implicações (preço pode mudar até lá; autorização pode expirar).
5. **Cancelamento:** política para pedido agendado (janela de cancelamento sem taxa, no-show da loja, etc.).
6. **Edge cases:** loja fecha entretanto, sem estafetas no slot, preço/stock muda até à hora.

### Ficheiros/áreas afetadas
- Flutter: checkout, novo seletor de slot, `order_model`, `cart_store`, `order_store`.
- DB: migration (`scheduled_for` + estado), **novo pg_cron scheduler**, alterações em `create_order`.
- **dispatch-engine** (Edge Fn) + triggers de dispatch — **zona proibida**.
- Stripe (timing de captura) — **zona proibida**.

### Zonas sensíveis · Risco · Esforço
- **Toca:** dispatch, pricing/Stripe, lifecycle do pedido, schema — **as 3 zonas proibidas ao mesmo tempo**.
- **Risco:** ALTO. É uma feature transversal que mexe no núcleo (dispatch + pagamento + estados).
- **Esforço:** GRANDE (vários dias, com testes E2E reais; precisa de decisões de negócio sobre pagamento/cancelamento).
- **Recomendação:** 🔴 **PÓS-LANÇAMENTO, sem dúvida.** Não dá para fazer rápido nem com segurança antes do launch. É uma feature de "fase 2" que exige desenho dedicado (semelhante ao plano da distância de estrada). Glovo/Uber/iFood têm-na, mas nenhum lançou com ela no dia 1.

---

## RESUMO / RECOMENDAÇÃO
| Feature | Estado | Risco | Esforço | Quando |
|---|---|---|---|---|
| **C3 Reorder** | lógica pronta, só ligar UI | BAIXO | pequeno | ✅ **pode ser antes do launch** |
| **C4 Substituição (proativa)** | reativa via chat já existe | MÉDIO | médio | 🟡 pós-launch (chat já cobre) |
| **C5 Entrega agendada** | não existe | ALTO (3 zonas proibidas) | grande | 🔴 **pós-launch obrigatório** |

> Sugestão de ordem: **C3 agora** (alto valor/baixo risco) → C4 depois do launch → C5 numa fase 2 dedicada.
