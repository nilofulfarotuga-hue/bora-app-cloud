# MEGA-FIX 2026-07-18 — RODADA 2 (relatório)

Branch: `autonomous-night-2026-04-29` · Modo PROTECÇÃO TOTAL · CEO-AI carregado (mesma sessão).
Perímetro protegido respeitado: pricing_service, dispatch_engine, finalizePurchase, bora_tokens
(tabela/ledger), webhook Stripe, RLS financeira.

Continuação de `mega-fix-2026-07-18.md`. Partes em ordem, 1 commit por parte `fix(rodada2-N): …`.

---

## PARTE 1 — Ligar o IncomingJobAlert DE VERDADE (o furo da rodada 1)

**Estado: FEITA (wiring code-complete + analyze limpo; confirmação audível/visual precisa de device).**

O `IncomingJobAlert` (rodada 1) tinha ZERO chamadas. Ligado nos 3 sítios, reutilizando os hooks
realtime já existentes (aditivo, sem novas subscrições onde já havia):

1. **Parceiro** (`partner_dashboard_screen.dart`) — `_handleNewOrders` já detetava pedidos
   `created` novos e tocava som; agora dispara também `IncomingJobAlert.show(type:'new_order')` por
   cada pedido novo (heads-up full-screen do sistema, canal urgente) e **dispensa** o alerta quando
   o pedido sai de `created` (aceite/expirado). O `type:'new_order'` já é roteado pelo tap handler.
2. **Limpeza** (`cleaner_store.dart`) — o `_subscribe` já ouvia `offer_cleaner_id = eu`; adicionei
   `_maybeAlertNewCleaningOffer` no callback (dedup por booking id; não alerta se já aceite) →
   `IncomingJobAlert.show(type:'cleaning_offer')`; `dismiss` em accept/reject. (App fechado é
   coberto pela Edge Fn `notify-cleaner` da rodada 1; isto cobre o app aberto.)
3. **TVDE A2** (`tvde_driver_home_screen.dart`) — a oferta de **corrida** TVDE em foreground JÁ
   abria `TvdeOfferScreen` com som (`bora_alert` em loop) — confirmado, sem gap. O que era
   silencioso (ordem 9016) era a oferta de **entrega/favor** a chegar enquanto no mapa TVDE
   (overlay visual, sem som): adicionei `_maybeAlertDeliveryOffers` (dedup + dismiss) que dispara
   `IncomingJobAlert` com tipo próprio `tvde_incoming_delivery` (não colide com o gate do estafeta).

Gotcha: `OrderModel` não estava importado no `tvde_driver_home_screen.dart` — o erro apareceu como
"receiver pode ser null" no `.map`, resolvido ao adicionar o import. `flutter analyze` dos 3 →
**0 erros, 0 issues novos** (os 15 restantes são deprecated/const pré-existentes em build methods).

**Limitação honesta:** o disparo real do heads-up/som só é observável num device Android com a app
a correr e ligada ao realtime; inserir linhas via SQL sozinho não prova (não há app a ouvir). O
caminho de código está completo e verificado por analyze + lógica.

### Ficheiros tocados
- `lib/stores/cleaner_store.dart`, `lib/screens/partner_dashboard_screen.dart`,
  `lib/screens/driver/tvde/tvde_driver_home_screen.dart`

**Commit:** `742d3fe` · **Push:** OK (`a17480f..742d3fe`).

---

## PARTE 2 — TVDE: destravar os 2 ficheiros retidos (revisão crítica de dinheiro feita)

**Estado: FEITA. Backend confirmado LIVE + revisão crítica passou → os 2 ficheiros commitados.**

Verificação de backend (SQL, agora): `tvde_rides.tokens_applied_count` +
`tokens_applied_value_cents` existem; `tvde_finish_ride` processa tokens; `tvde_request_ride` e
`tvde_finish_ride` aceitam `tokens_to_apply`. → O Dart é só o fecho de algo JÁ aplicado.

**Revisão crítica do `tokensUsed` (condição 1 — dinheiro):**
- `tvde_store.dart`: envia `p_tokens_to_apply: tokensUsed` (param, default 0). **Nenhum cálculo.**
- `tvde_request_ride_screen.dart`: `_calculateTokensToUse()` calcula a **contagem** de tokens (o
  parâmetro, limitada a `_tokenMaxPct%` da tarifa para UX — o servidor RE-VALIDA); `tokenDiscount
  = tokensToUse * 0.005` é **só display** (subtítulo "-€X", linha 969). **NADA calcula o valor
  cobrado nem o ganho** — isso é server-side (`tvde_request_ride`/`tvde_finish_ride`). Ou seja: só
  ENVIA o parâmetro e MOSTRA o desconto (exatamente o permitido). Não houve linha para parar.
- **Condição 2 (default idêntico):** `_useTokens` arranca false → `tokensUsed=0` → `p_tokens_to_apply:0`
  → corrida sem tokens IDÊNTICA à de antes.
- **Condição 3 (incluídos no mesmo commit):** `activeRoundtripCredit()` valida `res['id'] != null`
  (defesa dupla) + card "Planos Bora Motorista" com padding inferior safe-area (não cortado).

`flutter analyze` dos 2 → **0 erros** (3 info pré-existentes). Autorização: Danilo mandou "tudo" +
verificação de que não há cálculo de preço/ganho no Dart.

### Ficheiros tocados
- `lib/stores/tvde_store.dart`, `lib/screens/client/tvde/tvde_request_ride_screen.dart`

**Commit:** `89d3d72` · **Push:** OK (`742d3fe..89d3d72`).

---

## PARTE 3 — Favores: o wiring que faltava (fundação da rodada 1 → ligada)

**Estado: FEITA a persistência (o bug de dados provado); a display do estafeta na execution
sheet ficou BLOQUEADA por permissões; coreografia multi-perna documentada.**

### Item 1 — persistência (RESOLVE o bug b7867337: morada da casa deitada fora)
Encontrei o ponto de integração ideal: a `payment_method_screen` já obtém o `orderId`
(`waitForOrderFromDraft` / `lastCreatedOrderId`) e já chama uma RPC pós-pedido para o favor
(`client_set_errand_request_photo`). Liguei ali:
- `cart_store.dart` `ErrandSession` + `configureErrandSession` → campos novos `homeStopAddress`,
  `homeStopCashCents`, `returnLeg`.
- `errand_form_screen._goToCheckout` → passa `_homeCtrl.text` (morada, antes descartada),
  `homeStopCashCents` (= orçamento levado em cash quando motivo=dinheiro), `returnLeg` (true para
  pagar-conta). **Validação:** motivo dinheiro → cash > €0 obrigatório.
- `payment_method_screen` → helper `_persistErrandHomeStop(cart, orderId)` chama a RPC
  **`errand_set_home_stop`** (não-financeira, da rodada 1) nos **3 caminhos** (cartão, MBWay,
  dinheiro), ANTES do `clearCart`. **NÃO toca no create_order que cobra** (Lista Vermelha intacta).
- `flutter analyze` dos 3 → **0 erros**.

### Item 2 — coreografia do estafeta
A `errand_execution_sheet.dart` JÁ tem máquina de fases (`_phase`: recolha em casa → compra →
…) com motivo + cash. Com os dados agora populados, a fase de recolha já funciona e o mapa pode
rotear às coords da casa. **Tentei acrescentar a MORADA + banner "PEGAR €X EM DINHEIRO" na fase de
recolha, mas o ficheiro está BLOQUEADO por permissões nesta sessão** ("directory denied by
permission settings") — respeitei a recusa, não insisti. Fica como próximo passo (edição simples,
os dados já lá estão no OrderModel: `errandHomeStopAddress`, `errandHomeStopCashCents`,
`errandReturnLeg`, `errandLeg`).

A 3ª perna (volta à casa) usa `errand_return_leg`/`errand_leg` (já no schema+modelo) — a sua
adição à sheet fica no mesmo bloqueio de permissão.

### Ficheiros tocados
- `lib/stores/cart_store.dart`, `lib/screens/errand_form_screen.dart`,
  `lib/screens/payment_method_screen.dart`
- (bloqueado por permissões: `lib/widgets/errand_execution_sheet.dart`)

**Commit:** `ac23a20` · **Push:** OK (`89d3d72..ac23a20`).

---

## PARTE 4 — Wizard de cadastro ramificado por tipo

**Estado: FEITA.**

Causa (fotos do Danilo): o dropdown "Categoria" estava no FIM do passo 1, e `_selectedCategory`
arranca em `restaurant` → uma farmácia via "Tipo de cozinha" até rolar até ao fim e trocar.

Fix mínimo e limpo em `register_partner_screen.dart`: movido o `DropdownButtonFormField`
("Tipo de negócio") para o **1º campo** do passo 1 (antes do nome). Os campos condicionais já
existiam de rodadas anteriores e reagem à escolha:
- "Tipo de cozinha" → só `BusinessCategory.restaurant`.
- Switches "Aceito reservas de mesa"/"Aceito ir buscar" → só restaurante (rodada 1 Parte 5).
- Beleza → a Edge Fn `register-partner` já roteia para `service_providers` (rodada 1 Parte 4).
- Supermercado/Loja/Farmácia → sem campos de comida.

`flutter analyze` → **0 erros** (6 info pré-existentes).

### Ficheiros tocados
- `lib/screens/register_partner_screen.dart`

**Commit:** `9e01d17` · **Push:** OK (`ac23a20..9e01d17`).

---

## PARTE 5 — Retalho mínimo viável (super/loja/farmácia)

**Estado: núcleo FEITO (alergénios condicionais + receita); toggle esgotado JÁ existia;
importador CSV admin + badge cliente DOCUMENTADOS como follow-up.**

1. **Alergénios só restaurante + receita farmácia** — migration `20260718007000`:
   `products.requires_prescription boolean default false` (aplicada). `add_product_screen.dart`:
   a secção de alergénios (comida) agora só aparece se `widget.restaurant.category ==
   BusinessCategory.restaurant` (farmácia/loja deixam de ver comida — bug provado nas fotos); e
   para `pharmacy` há um switch "Requer receita médica". Threading completo do write:
   `add_product → PartnerProductStore.addProduct → RestaurantStore.addPartnerProduct → insert`
   (`requires_prescription`). `flutter analyze` → **0 erros**.
2. **Toggle "Esgotado"** — **JÁ existia**: `partner_products_screen._toggleAvailability` +
   `store.toggleAvailability` + `Switch` (→ `products.is_available`). Coluna confirmada existente.
   Nada a criar.
3. **Importação CSV no admin** — **DEFERIDO**: é um ecrã novo de admin (colar CSV
   nome;descrição;preço;categoria → insert em `products` + pré-visualização + relatório de linhas
   rejeitadas). É trabalho de um ecrã completo; adiado para caber sem cortar as Partes 6–10.
   Fundação pronta (o insert de `products` já aceita os campos).

**Follow-up documentado:** badge de receita + esmaecer indisponível no cartão do CLIENTE precisam
do campo `requires_prescription` no modelo `PartnerProduct` (leitura) + no cartão do cliente. O
write já persiste; a leitura/badge é o passo seguinte.

### Ficheiros tocados
- `supabase/migrations/20260718007000_products_requires_prescription.sql` (novo, aplicado)
- `lib/screens/add_product_screen.dart`, `lib/stores/partner_product_store.dart`,
  `lib/stores/restaurant_store.dart`

**Commit:** `07345ef` · **Push:** OK (`9e01d17..07345ef`).

---

## PARTE 6 — Beleza: rotear parceiro aprovado ao dashboard de serviços

**Estado: VERIFICADO — o routing JÁ está correto (sem bug). Conta "teste" APROVADA para o teste
ponta-a-ponta.**

Segui o caminho completo no código e confirmei que já está ligado:
- `partner_login_screen._finishPartnerLogin`: se não há `restaurants` para o email → faz
  `appointmentsStore.loadMyProvider()` (pré-aquece) e segue com `setRole(partner)` (linhas 354-368,
  com comentário a explicar exatamente o caso Serviços/Barbearias).
- `PartnerEntryScreen`: sem `partnerRestaurant` e sem restaurante por email →
  `_PartnerNoRestaurantRouter` → `loadMyProvider()` (por `service_providers.user_id = auth.uid()`,
  sem filtro de aprovação) → **`PartnerServicesHubScreen`** (o dashboard de serviços/marcações).
- Prova viva: **Barbearia Nobre** (approved, user_id definido) já cai no hub por este caminho.

Dados confirmados: a conta **"teste"** (beauty) tem `user_id` (b69da1b3…) — logo o `loadMyProvider`
encontra-a. **Aprovei-a via admin** (approval_status pending→approved) para exercitar o caminho
candidatura→aprovação→dashboard de ponta a ponta. O microSaaS de agenda (`lib/screens/partner/
services/`) já existe e é para onde o hub aponta.

**Conclusão:** não era preciso "corrigir" — a ligação já existe e está correta; o que faltava era
**aprovar** a candidatura de teste (feito). Nenhuma mudança de código.

### Ficheiros tocados
- (nenhum código; ação de dados: `service_providers` "teste" → approved)

---
