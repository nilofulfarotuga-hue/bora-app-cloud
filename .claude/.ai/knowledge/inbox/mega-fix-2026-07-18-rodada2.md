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

---
