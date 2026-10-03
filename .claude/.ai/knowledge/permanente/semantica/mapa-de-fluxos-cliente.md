---
id: mapa-de-fluxos-cliente
tipo: semantica
origem: [missão noturna 2026-07-09 Fase 1 — varredura do código cliente]
ultima_confirmacao: 2026-07-10
zona: verde
confianca: verificado-no-codigo
---

# Mapa de Fluxos — CLIENTE (11 fluxos)

> Convenções e isolamento: ver `mapa-de-fluxos.md`. `ClientMainScreen` = IndexedStack com
> 4 tabs (`Início/Entrega/Reserva/Perfil` via `BoraBottomNavV2`).

## 1. Registo + login + persistência
- Ficheiros: `client_login_screen.dart`, `register_client_screen.dart`, `session_store.dart`, `auth_store.dart`
- Pré: demo `cliente@bora.app`/`123456` (pré-preenchido só kDebugMode)
- Passos: 1. RoleScreen → Cliente 2. Campos "Email"/"Palavra-passe" → **Entrar** → `loginClientAsync` → `setRole(client)` (RootNavigator reage) 3. Alt: **Entrar com biometria** · **Esqueceu a palavra-passe?** · **Criar conta** → RegisterClientScreen (nome/email/telefone/pw/confirmar + referral `BORA-ABC-1234`) → **Criar conta**
- Estado final: SharedPreferences role=client; FCM token `saveTokenForClient`; sessão sobrevive a restart

## 2. Delivery restaurante PARCEIRO [2-DEVICES]
- Ficheiros: `client_home_screen.dart`, `restaurants_screen.dart`, `restaurant_menu_screen.dart`, `cart_screen.dart`, `payment_method_screen.dart`, `order_tracking_screen.dart`
- Pré: sessão + **endereço definido** (guard: "Define o teu endereço de entrega para continuar.")
- Passos: 1. Início → tile **Restaurantes** 2. restaurante → menu → adicionar itens 3. Carrinho: toggles `Ir buscar (takeaway, sem entrega)` · `Entregar no apartamento (+€1.50)` · gorjeta → **Finalizar pedido** 4. PaymentMethodScreen → **Confirmar pagamento** 5. OrdersScreen; quando estafeta aceita → auto-push OrderTrackingScreen 6. [Device 2 estafeta] aceita → recolhe → entrega (PIN) → `delivered` → RatingScreen no cliente (≤48h)
- Pagamento: Cartão (Stripe payment-first) · MB Way (dialog poll 120s) · Dinheiro (bloqueado >€40) · toggle "Usar saldo Bora" · toggle "Usar Bora Tokens" (≤50%)
- Estado final: `orders.status=delivered`; parceiro absorve saco (€0)

## 3. Delivery loja NÃO-PARCEIRO — storeShopping V2 [2-DEVICES]
- Ficheiros: `stores_screen.dart`, `market/market_store_screen.dart`, tracking + `driver_map_screen.dart` (estafeta finaliza)
- Pré: sessão + endereço; dialog "Carrinho activo" (`Voltar`/`Sim, novo pedido`) ao trocar de loja
- Passos: 1. Início → `Supermercados`/`Farmácia`/`Lojas` 2. adicionar produtos → checkout (paga estimativa) 3. [Device 2] estafeta compra, sacos (slider 0..5) + talão → `finalize_storeshopping_purchase` → recalcula `final_total`
- Pagamento: cartão → `extraRequired` + charge off_session; cash → `cash_total_due` ("RECEBER €X" no estafeta). Saco €0,10×real (cap 5)
- Estado final: `orders.final_total`; `order_receipts_v2` com talão

## 4. Mercados (6 lojas) [2-DEVICES]
- Igual §3 com `initialCategory supermarket` (Continente etc.). Mercado parceiro absorve saco; não-parceiro €0,10/un (linha "Saco para viagem")

## 5. Favores v3 (errand) [2-DEVICES]
- Ficheiros: `errand_form_screen.dart`, `errand_budget_banner.dart`, `errand_execution_sheet.dart` 🔴
- Passos: 1. Início → **Favores** ("Pedir um favor") 2. descrever · toggle "Este favor inclui uma compra?" · foto (**Tirar foto**/**Escolher da galeria**/**Trocar**) 3. velocidade: **🕐 Normal = €6** (até 3h) ou **⚡ Expresso = €10** (45-60min) 4. compra>€40 cash → dialog "Compra acima de €40" (`Voltar a escolher`/`Ativar paragem em casa` +€2) 5. pagamento
- Pagamento: cartão = garantia ×1,2; cash ~estimativa; **SEM tokens** (tokensToUse=0)
- Consent over-budget: banner no tracking → "Autorizar compra maior?" → **Autorizar**/**Recusar** → `client_respond_budget_increase`
- Estado final: `orders errand` (`errand_budget_status`); foto via `client_set_errand_request_photo`

## 6. Reservas (€3 pré-pagamento)
- Ficheiros: PRO `reservation_availability_screen.dart`→`reservation_checkout_screen.dart`; legado `reservation_flow_screen.dart` (coexistem!)
- Passos: 1. Início → `Reservar Mesa` → restaurante 2. data/hora/pax → **Pagar €3 e reservar** (termos: "€3 retidos", "no-show: €3 não devolvidos")
- Pagamento: Stripe €3 cartão/MB Way. **Split real: €2 parceiro + €1 Bora (BR §18)**; chegada = crédito €2 (`partner_mark_arrival`). Cancel <2h → €3 Bora; ≥2h → refund
- Estado final: `reservations` pending→approved→arrived/no_show; `restaurant_menu_credits` €2

## 7. Limpeza doméstica (T0–T4)
- Ficheiros: `cleaning_wizard_screen.dart` (3 passos), `cleaning_payment_flow.dart`, `cleaning_tracking_screen.dart`
- Pré: `cleaning_enabled=true`
- Passos: 1. Início → **Limpeza** → wizard 2. tamanho **T0/T1 €35 · T2 €45 · T3 €55 · T4+ €70**; profunda +40%; pós-obras +60%; produtos +€3; recorrência −10% 3. cidade/slot ("Primeira disponível (recomendado)") → **Continuar** → **Confirmar reserva**
- Pagamento: `Dinheiro (no local)` · cartão/MB Way cobram na reserva (`cleaning-checkout` 🔴, sem webhook). Split 85/15. Cancel >24h grátis · 24-2h 50% · <2h 100%
- Estado final: `cleaning_bookings`; tokens via `_cleaning_complete` (role `cleaner`) — ⛔ não mexer

## 8. TVDE cliente [2-DEVICES]
- Ficheiros: `client/tvde/tvde_request_ride_screen.dart`, `tvde_ride_tracking_screen.dart`, `tvde_plans_screen.dart`, `tvde_unlock_screen.dart`
- Pré: **categoria escondida** — entrada "Quero desbloquear uma categoria exclusiva" → TvdeUnlockScreen → admin aprova `tvde_access` → tile **Bora Motorista**
- Passos: 1. tile → pin recolha (arrastável) + destino → **Solicitar corrida** → folha de pagamento 2. Ida+volta: toggle "Garantir a volta" → **Garantir ida e volta · €X** (€8) → card "Tens uma volta garantida" → **Chamar a volta** 3. paradas por pin
- Pagamento: cartão/MB Way ANTES de criar corrida; plano → só excesso ("Corrida do plano — só pagas o excesso", EF v2 cobra `tvde_ride_charge_cents` 🔴); tokens ≤50% (cap server-side)
- Estado final: `tvde_rides`; `tvde_subscriptions.ridesLeft`; vale-volta

## 9. Cancelamento E1–E4
- Ficheiros: `order_tracking_screen.dart` (`_feeLabelForStatus`), EF `client-cancel-order` 🔴
- Passos: tracking → **Cancelar pedido** → **Motivo (obrigatório)** (dropdown) → **Confirmar cancelamento**
- Escalões: **E1** sem estafeta E ≤180s → `Grátis` (countdown mm:ss) · **E2** created/preparing/callingDriver → €1,00 · **E3** driverAccepted → €2,50 · **E4** pickedUp/onTheWay → 100%. `readyForPickup` takeaway → não cancelável
- Refund eletrónico: escolha `De volta ao cartão (~5 dias úteis)` ou `Na carteira, imediato (80% saldo + 20% pontos)`
- Estado final: `orders.status=cancelled` + `cancel_fee`; split 80/20

## 10. Wallet e bora_tokens 🔴 (só ler)
- Ficheiros: `wallet_history_screen.dart`, `wallet_service.dart`, carrinho/pagamento
- Regras vivas: 100 tokens = €0,50; cliente ganha **3 tokens/€**; validade 60d FIFO; uso ≤50% (`consume_tokens` cap server-side). Refund carteira 80/20. Dívida: linha "Saldo devedor anterior"; cash bloqueado com dívida+total>€40
- Validar (read-only): `client_wallets.free_balance_cents`/`debt_cents`; `bora_tokens`; `wallet_transactions`

## 11. Chat + Suporte (Robot A)
- Ficheiros: `chat_screen.dart`, `support_chat_screen.dart` (EF `support-chatbot`), `bora_support_fab.dart`
- Passos: tracking → **Falar com o Estafeta** / **Falar com o Restaurante** → ChatScreen. Suporte: FAB no Início → chat IA (hint "Escreve a tua dúvida…") → **Falar com humano** → "Transferido para humano."
- Estado final: `messages` (read flags); `support_chatbot_messages`; ticket ao escalar
