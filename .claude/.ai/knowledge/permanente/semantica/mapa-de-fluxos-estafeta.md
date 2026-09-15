---
id: mapa-de-fluxos-estafeta
tipo: semantica
origem: [missão noturna 2026-07-09 Fase 1 — varredura do código estafeta/TVDE]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado-no-codigo
---

# Mapa de Fluxos — ESTAFETA + MOTORISTA TVDE (11 fluxos)

## 1. Candidatura de estafeta (fluxo ÚNICO — BR §7)
- Ficheiros: `driver_signup_screen.dart` (Stepper 4 passos), RPC `driver_register_or_update` (só overload 14-param), EF `upload-driver-document`, `driver_pending_screen.dart`
- Regra: "cadastro NUNCA bloqueia" — quase tudo opcional; gate único = email+password+termos
- Passos: 1. Step1 Dados Pessoais → **Continuar** 2. Step2 Conta (email*, pw* ≥6, termos) → **Criar Conta** (signUp bora_role=driver + RPC, approval pending) 3. Step3 Documentos & Fotos (selfie, doc dropdown [Cartão Cidadão/BI/Título Residência/Passaporte], fotos — opcionais) → **Continuar** 4. Step4 Veículo & Pagamento (SegmentedButton Moto/Carro/Bicicleta/**Carro — Passageiros**, matrícula, IBAN, MBWay) → **Enviar Candidatura** → logout + DriverPendingScreen
- Estado final: `drivers.approval_status='pending'`; bucket `driver-documents`

## 2. Login + online gate
- Ficheiros: `driver_login_screen.dart`, `permission_gate_service.dart`, `driver_home_screen.dart` (`_handleOnlineToggle`), `driver_store.dart`
- Pré: `approval_status='approved'` (pending→PendingScreen; rejected→RejectedScreen+logout). Debug pré-preenche **driver@bora.app/123456**
- Passos: 1. **Entrar** (ou **Entrar com biometria**) 2. guard bora_role + approval → FCM 3. toggle **Online** → `ensureDriverOnlinePermissions` (localização background, notificações, SYSTEM_ALERT_WINDOW, bateria) → `is_online=true` + FGS "Bora — Online" + realtime `driver-offer:{driverId}`
- Bloqueios: permissões negadas (online); `activeAssignments` não vazio (offline)

## 3. Receber OFERTA [2-DEVICES]
- Ficheiros: `notification_service.dart` (canal `bora_orders_urgent_v3`, Importance.max, fullScreenIntent), `offer_presentation_gate.dart`, `driver_order_overlay.dart`, backend `dispatch-engine` 🔴 + `notify-driver`
- Passos: 1. dispatch-engine grava `current_driver_offer_id` + expiração **40s** 2. híbrido: realtime broadcast (<1s) + FCM data-only → `OfferPresentationGate` (dedup) 3. FG → cartão laranja; BG → FlutterOverlayWindow + fullScreenIntent (acorda ecrã bloqueado); som `bora_alert.wav` loop 4. **Aceitar · +€X** / **Recusar**/**Rejeitar** 5. timeout/reject → roda (`tried_driver_ids`)
- Estado final: `orders.assigned_driver_id` ou oferta libertada
- **Isolamento de teste:** ver `mapa-de-fluxos.md` — ser o ÚNICO driver online elegível

## 4. Entrega completa [2-DEVICES]
- Ficheiros: `driver_order_action_helper.dart`, `driver_map_screen.dart`, `order_store.dart` 🔴 (só ler)
- Pré: `driverAccepted`; não-parceiro exige compra finalizada antes (`isPurchaseFinalized`)
- Passos: 1. **Recolher pedido** → `pickedUp` 2. **Iniciar entrega** → `onTheWay` 3. **Concluir entrega** → dialog **"Código de entrega"** (PIN 4 dígitos, "Peça ao cliente o código de 4 dígitos"; errado → "Código incorreto. Tente novamente.") 4. correto → `delivered`
- ⚠️ PIN validado client-side (BUG #15 P0 aberto: falta validação server-side)

## 5. Prova de entrega
- PIN 4 dígitos obrigatório. SEM foto na entrega (foto só signup e sendPackage). **No-show cliente €3.50 NÃO implementado** (gap — só cancel fees + no-show TVDE)

## 6. Mapa heading-up
- Ficheiros: `driver_map_screen.dart`, `tvde_ride_active_screen.dart` (`_kNavZoom=17.5`, `_kNavTilt=45`), `directions_service.dart`
- Câmara segue bearing GPS (estilo Waze), seta verde, rota DirectionsService; **Navegar até à recolha/destino** abre Google Maps/Waze externo

## 7. Ganhos (BR §3) 🔴 números
- Parceiro: €3,80 + €0,20×km + apt + (stacked? +€3) · Não-parceiro storeShopping: €3,80 + €0,80 + €0,20×km + apt + 30%×boraNet · Não-parceiro restaurante: €3,80 + €0,20×km + apt + 30%×boraNet · Logística: €4,00 + €0,50×km + €0,80 + apt
- Validar: trio em `ledger_entries` (earning/platform/commission)

## 8. Multi-papel
- Ficheiros: `driver/driver_role_apply_screen.dart`
- User autenticado adiciona 2º papel (prefill nome/telefone): veículo [Mota/Carro entregas/**Carro (viagens/TVDE)** = `carro_passageiros`] + matrícula* + IBAN + CC* + selfie* → **Enviar candidatura** (mesma row `drivers`)
- Driver aprovado `carro_passageiros` recebe entregas E corridas TVDE

## 9. TVDE motorista — corrida [2-DEVICES]
- Ficheiros: `driver/tvde/tvde_offer_screen.dart`, `tvde_ride_active_screen.dart`, `tvde_driver_rate_screen.dart`, `tvde_driver_store.dart`, EF `notify-tvde-driver` v3
- Pré: `carro_passageiros`, online, oferta `current_offer_driver_id`=uid
- Passos: 1. TvdeOfferScreen (som loop, countdown) → **Aceitar**/**Recusar** 2. `motorista_a_caminho` → **Cheguei ao passageiro** 3. `motorista_chegou` → **Iniciar viagem**; no-show habilita após `tvde_noshow_wait_minutes` (5) via ⋮ **Passageiro não compareceu** 4. paradas: **Cheguei à parada**; ida-e-volta = banner fila 5. `em_andamento` → **Finalizar viagem** → **`tvde_finish_ride` (3 args: p_ride_id, p_final_distance_km, p_distance_source)** 🔴 6. TvdeDriverRateScreen
- Pagamento: `TvdePayBadge`; cash → dívida em `tvde_driver_balances` 🔴; plano cobra `tvde_ride_charge_cents`
- Estado final: `tvde_rides.status='finalizada'`; `tvde_ride_events` com `push_enviado`/`push_falhou`

## 10. Planos TVDE
- Ficheiros: `tvde_plans_screen.dart`, RPC `tvde_plan_price_cents` 🔴, EF `tvde-plan-payment` 🔴 (isolada, SEM webhook)
- Planos: Semanal €40 / Quinzenal €70 / Mensal €132 — corridas 5/10/22 dias úteis × 2/dia, "Segunda a Sexta · 2 por dia útil"; fim-de-semana = tarifa normal (aviso no ecrã)
- Passos: cartão do plano → **Aderir** → MBWay/cartão → ativa OU pedido pendente (admin ativa)
- Validar: `tvde_subscriptions` + `tvde_ride_counters` (consome 1/corrida via `tvde_consume_subscription_ride` 🔴)

## 11. Batching/stacking
- Ficheiros: `dispatch/driver_capacity_service.dart` (client), `dispatch-engine/index.ts` 🔴 (decisor real)
- Client: `maxBatchOrders=3`; errand NUNCA batchável; params 800m/2 parceiro são legacy não-usados (decisão real no server, FIFO ≤200m; BR §6 raio 3 km)
- Backend exclui drivers com ≥3 ativos
- Validar: `driver.activeAssignments` ≤3

## Labels-chave (Maestro por texto)
`Entrar` · `Entrar com biometria` · `Criar Conta` · `Continuar` · `Enviar Candidatura` · `Online`/`Offline` · `Aceitar · +€X` · `Recusar` · `Rejeitar` · `Recolher pedido` · `Iniciar entrega` · `Concluir entrega` · `Código de entrega` · `Cheguei ao passageiro` · `Iniciar viagem` · `Finalizar viagem` · `Cheguei à parada` · `Passageiro não compareceu` · `Aderir` · `Navegar até à recolha`/`…destino`
