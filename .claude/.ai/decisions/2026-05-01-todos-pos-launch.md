# TODOs Pós-Launch — 2026-05-01

Lista de itens identificados durante a sessão BUG 16+17+18 que NÃO bloqueiam launch e ficam para depois do produto estar estável.

---

## BUG 24 — Admin reset foto estafeta (MÉDIO)

Admin pode editar nome/phone/veículo/matrícula/IBAN/NIF do estafeta em [admin_driver_detail_screen.dart](../../lib/screens/admin/admin_driver_detail_screen.dart) (`_EditDriverSheet` L258, `updateDriver()` chamada com 6 campos), mas **NÃO tem botão para resetar/upload da `photo_url`**. Driver pode mudar a foto via [profile_screen.dart](../../lib/screens/profile_screen.dart), mas se a foto for ofensiva/corrompida, o admin não consegue intervir.

**Fix proposto:** adicionar widget photo editor em `_EditDriverSheet` ou novo botão "Resetar foto" em `_OverviewTab` que permita ao admin:
- Limpar `photo_url` (volta para iniciais)
- Substituir por upload manual

**Risk:** LOW (cosmético + moderação)
**Tempo estimado:** ~30 min
**Audit:** registar em `admin_audit_log` com action='driver_photo_reset'

---

## Tech-debt — Alinhar shell estafeta com cliente (BAIXO)

[driver_home_screen.dart](../../lib/screens/driver_home_screen.dart) usa Scaffold + AppBar simples + `Navigator.push` para navegar entre telas (driver_map default + AppBar icons para Perfil/Ganhos), enquanto [client_main_screen.dart](../../lib/screens/client_main_screen.dart) usa IndexedStack + `BoraBottomNav` com 3 tabs (Início / Pedidos / Perfil).

Inconsistência arquitectural mas funcional. O fix actual (Opção 2 — profile icon no AppBar) preserva o shell driver tal como estava, evitando risco de regressão sobre dispatch/GPS/lifecycle do mapa (que é PRONTO no launch checklist).

**Refactor proposto:** Driver shell para IndexedStack + BoraBottomNav com 3 tabs:
- Tab 0: `DriverMapScreen` (Mapa)
- Tab 1: `DriverEarningsScreen` (Ganhos)
- Tab 2: `ProfileScreen` (Perfil)

**Vantagens:**
- Padrão unificado driver↔cliente
- Tabs persistentes (vs Navigator.push) preservam estado de cada tela
- UX mais familiar

**Risco MÉDIO:** toca lifecycle do mapa (`_listenToDriverLocation`, `WidgetsBindingObserver`), GPS tracking idle, realtime channels do `DriverStore`/`OrderStore`. Risco de regressão BUG-002 (realtime sync) ou BUG-016 (GPS unificado).

**Pré-requisitos:**
- Launch estabilizado (sem incidentes 1 semana)
- TEST_CHECKLIST.md driver flow re-validado pós-refactor
- Branch separada draft + smoke E2E completo

**Tempo estimado:** 1-2h + 30min smoke

---

## BUG 30 — Pickup sem finalizar storeShopping (MÉDIO)

[driver_order_action_helper.dart](../../lib/screens/driver_order_action_helper.dart) permite `markPickedUp` em storeShopping não-parceiro mesmo sem `isPurchaseFinalized=true`. Estafeta pode marcar pickup sem ter finalizado a compra, levando a `final_total=NULL` e bag_fee/items_added perdidos.

**Fix proposto:**
- Server-side guard em `pickUpOrder` RPC ou trigger DB que recusa transição `driverAccepted → pickedUp` quando `service_type='storeShopping' AND isPartnerStore=false AND is_purchase_finalized=false`.
- Mensagem clara ao estafeta: "Tens de confirmar a compra primeiro."

**Risk:** LOW (server-side guard)
**Tempo estimado:** ~20 min + smoke

---

## Admin gap — Cash collected display (BAIXO)

Painel admin order detail ([admin_order_detail_screen.dart](../../lib/screens/admin/admin_order_detail_screen.dart)) não mostra "Cash recebido pelo estafeta: €X" para storeShopping cash. Audit log já tem os dados (`final_total_cents`, `payment_method='cash'`, `bought_total_cents`).

**Fix proposto:** Adicionar secção "Reconciliação cash" em admin_order_detail mostrando:
- `final_total` (esperado a receber)
- Estado: collected (delivered) | pending | not_applicable (não-cash)
- Driver settlement reference (futuro)

**Risk:** LOW (read-only display)
**Tempo estimado:** ~25 min

---

## BUG 39 — Polyline rota não acompanha estafeta em tempo real (MÉDIO)

Linha azul do mapa do estafeta é actualizada via `_trimRouteBehindDriver(currentPos)` ([driver_map_screen.dart:352](../../lib/screens/driver_map_screen.dart#L352)) e `_updateRouteMulti(driverPosition, stops)` ([driver_map_screen.dart:809](../../lib/screens/driver_map_screen.dart#L809)). Mas:

- **50 m throttle** ([L832-839](../../lib/screens/driver_map_screen.dart#L832-L839)): só re-fetch da rota se driver mexeu ≥50m. Pode parecer estática em movimentos curtos.
- **Trim only ≥3 points** ([L355](../../lib/screens/driver_map_screen.dart#L355)): rotas curtas não são trimmadas.
- **Key cache** ([L828](../../lib/screens/driver_map_screen.dart#L828)): se origin+stops não mudou, ignora — quando driver desvia da rota original (ex: GPS imprecisão ou rua fechada), polyline fica congelada na rota desactualizada.

**Fix proposto (sessão separada — toca lifecycle GPS BUG-016 PRONTO):**
- Detectar deriva da rota: `_distanceFromRoute(currentPos)` ([L375](../../lib/screens/driver_map_screen.dart#L375)) já existe. Se >50m da rota, force `forceRouteRefresh()` ([L387](../../lib/screens/driver_map_screen.dart#L387)).
- Reduzir 50m throttle para 20-30m em mode active delivery (status pickedUp/onTheWay).
- Stream de driver_locations realtime → trigger trim+update sem 50m gate.

**Risk:** MED (toca lifecycle GPS BUG-016 PRONTO no checklist).
**Tempo estimado:** 45 min + smoke E2E em movimento real.
**Pré-requisito:** launch estabilizado, branch separada.

---

## Tech-debt referenciado em decisão paralela

Ver [2026-05-01-tech-debt-financial-bypass-guc.md](2026-05-01-tech-debt-financial-bypass-guc.md) — refactor do trigger `enforce_financial_immutability` para usar `current_user='postgres'` em vez de GUC `app.financial_bypass`. Pós-launch.

---

## Critério para começar a executar

Estes TODOs ficam parados até:
1. Launch público a primeiros utilizadores reais ✓
2. 7 dias sem incidentes críticos no flow de pagamento ✓
3. Stripe LIVE validado em produção real ✓
4. GPS BUG-016 fix testado com 2 dispositivos simultâneos ✓

Quando todos os 4 acima forem verdade, abrir uma issue (ou esta lista) para priorização.
