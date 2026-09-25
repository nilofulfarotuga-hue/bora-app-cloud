# TVDE — POLIMENTO FINAL 2 (blocos B1 + C · D · E · F · G)

> 2026-07-02 · CEO-AI / Claude Code (Opus 4.8) · branch `autonomous-night-2026-04-29`
> Continuação de `TVDE_POLIMENTO_FINAL.md` (commit 6125162, que fechou A/B-UI/H2).
> Regra de ouro respeitada: **NADA às cegas** — cada mudança reutiliza a fonte já
> localizada (DirectionsService, chat do delivery, notify-tvde-*, admin RPCs).
> Zonas protegidas (dispatch-engine v58, pricing_service, pricing_calculate,
> finalizePurchase, stripe webhook, RLS de orders/wallets/ledger, bora_tokens,
> notify-driver do delivery) — **intactas**.

---

## B1 — TARIFA POR ROTA REAL ✅ (autorizado "vai no B1")
**Coeficientes de `tvde_calculate_fare` INTOCADOS** (base 500c, 6 km incl., +50c/km).
Só mudou a **FONTE da distância**: haversine → rota real (DirectionsService, mesma
chave Google do estafeta). Fallback haversine se a rota falhar, registado no ride.

- **Cliente (estimativa)** — `tvde_request_ride_screen.dart`: `_recalcEstimate` passa a
  pedir `DirectionsService.fetchRoute(pickup,dest).distanceKm`; fallback haversine;
  `_distanceSource` regista qual foi. `estimateFareCents` e `requestRide` usam a rota.
- **Motorista (final)** — `tvde_ride_active_screen.dart` `_finish`: busca a rota
  recolha→destino no momento de finalizar e passa essa distância a
  `finishRide(rideId, km, distanceSource:)`. Fallback = `ride.estDistanceKm`.
- **DB (aditivo)** — migration `tvde_b1_route_distance_source`:
  `ALTER TABLE tvde_rides ADD COLUMN final_distance_source text` +
  `tvde_finish_ride` ganha `p_distance_source text DEFAULT NULL` (grava a coluna;
  **nenhuma linha de matemática de tarifa/ganho alterada**).
- **Gate**: Juiz anti-trapaça no diff (base HEAD) ✅ · advisors 0 ERROR ✅.

## C — TELA DO CLIENTE ✅
`tvde_request_ride_screen.dart`:
- **C1 — mapa na tela inicial** com o pin verde da recolha (`_PickupMap`, reusa
  google_maps_flutter + `toGMaps()` do delivery). Destino aparece como pin laranja.
- **C2 — recolha editável**: pin **arrastável** → `_onPickupDragEnd` faz
  `LocationService.reverseGeocode` (mesma chave); **autocomplete** de recolha
  (`AddressAutocompleteField`, o do destino) + botão "usar a minha localização".
- **C3 — planos visíveis** na tela principal: card discreto `_PlansTeaser` → abre planos.
- **C4 — planos clicáveis → "Quero aderir"** (`tvde_plans_screen.dart`): cada plano tem
  botão que cria `tvde_plan_requests` (RPC `tvde_request_plan`) → **notifica admin**
  (`notify_admin_event`) → cliente vê "pedido enviado" + banner "pendente".
- **DB (aditivo)** — migration `tvde_c4_plan_requests`: tabela `tvde_plan_requests` +
  RLS (cliente vê os seus; admin vê tudo) + RPCs `tvde_request_plan`,
  `admin_tvde_plan_requests_list`, `admin_decide_tvde_plan_request`.

## D — CARTÕES ✅
- **D1 migration** `tvde_d1_vehicle_color_make_model`: `drivers.vehicle_color`,
  `drivers.vehicle_make_model` (aditivo). `license_plate`/`vehicle_photo_url` já existiam.
- **D1 onboarding** (`driver_signup_screen.dart`): campos "Marca e modelo" + "Cor" no
  step 4 (só não-bicicleta) → passados a `driver_register_or_update` (RPC estendida,
  aditivo) + guardados no draft.
- **D1 card do motorista pro cliente** (`tvde_ride_tracking_screen.dart` `_StatusPanel`):
  foto (avatar NetworkImage), nome, ⭐ avaliação, **carro** (marca/modelo · cor · matrícula).
  `_pollDriver` passou a ler `photo_url, vehicle_make_model, vehicle_color, license_plate, phone`.
- **D2 foto do cliente pro motorista** (`tvde_ride_active_screen.dart` `_ActionPanel`):
  avatar do passageiro + nome, via RPC guardada `tvde_ride_passenger_card`
  (nome+foto+telefone; só o motorista da corrida lê).
- **D3 botões arredondados**: chat/ligar/planos/navegar com `Radii.md` (radius do design).

## E — COMUNICAÇÃO ✅
Chat bidirecional reutilizando o padrão do delivery, **sem tocar** em `messages`/`orders`
(order_id é uuid + RLS ligada a orders — não serve TVDE).
- **DB** — migration `tvde_e_chat_messages`: tabela `tvde_messages` (scoping por
  `tvde_ride_id`) + RLS de participantes (cliente/motorista da corrida) + realtime +
  trigger `_notify_tvde_chat_trigger` (padrão do `_notify_chat_message_trigger`).
- **Edge** — `notify-tvde-chat` (deploy v1, clone de `notify-tvde-client`): push FCM ao
  **outro** participante (cliente↔motorista) na nova mensagem.
- **Flutter** — `TvdeChatStore` (realtime `.stream()`, padrão do `ChatStore`) +
  `TvdeChatScreen` (bolhas + input) em `lib/screens/shared/`; registado no `main.dart`.
- **Ligar (tel:)** nos dois lados (cliente e motorista) quando o número existe
  (`url_launcher`, padrão do projeto).

## F — HOME DO MOTORISTA ✅ (o que não foi adaptado, justificado)
`tvde_driver_home_screen.dart`:
- **Suporte** ✅ — botão no appbar abre `BoraSupportSheet` (a folha do delivery: Bora IA
  + WhatsApp + Email).
- **Avaliação média recebida (M14)** ✅ — no cartão: `avg_rating · N avaliações`
  (de `DriverStore.currentDriver`).
- **Tempo online (M4)** ✅ — relógio da **sessão** no cartão ("Online há Xh Ymin").
  ⚠️ *Justificação*: agregação **diária** real (somar heartbeats do dia) precisa de
  backend dedicado — fica como follow-up; a sessão cobre o essencial no device.
- **Histórico de corridas com detalhe** — já existe em `TvdeDriverEarningsScreen`
  (dia/semana + lista de corridas), acessível pelo botão "Ganhos". Não duplicado.

## G — ADMIN (PT-BR) ✅ / parcial justificado
- **Pedidos de plano** ✅ — novo `AdminTvdePlanRequestsScreen` (ligado no dashboard):
  lista pedidos (filtro pendente/aprovado/recusado), **aprovar/ativar num clique**
  (`admin_decide_tvde_plan_request` → `admin_grant_subscription`) ou recusar. Mostra
  nome/email/telefone do cliente.
- **Campos do carro visíveis** ✅ — `admin_tvde_drivers_screen.dart`: foto do motorista
  + linha do carro (marca/modelo · cor · matrícula). `admin_tvde_drivers_list` estendida.
- **Campos do carro editáveis** ✅ — `admin_driver_detail_screen.dart` (form de edição):
  campos "Marca e modelo (TVDE)" + "Cor (TVDE)"; `admin_update_driver` estendida (aditivo,
  com audit `_admin_log_driver_field_change`) via `AdminDriverService.updateDriver`.
- **Fotos de TODOS (clientes/estafetas/parceiros) em lista+detalhe+KYC** — ⚠️ *parcial*:
  entregue para **motoristas TVDE** (lista admin). Varredura completa de todas as listas
  admin (clientes/parceiros) fica como follow-up (fora do âmbito seguro desta sessão sem
  auditar cada RPC de listagem).

---

## TABELA DE CORRESPONDÊNCIA ADMIN (esta sessão + anterior)
| Feature (app) | Correspondência no Admin |
|---|---|
| B1 tarifa por rota (`final_distance_source`) | Corridas TVDE (`AdminTvdeRidesScreen`) — financeiro motorista/Bora já listado |
| C4 pedido de plano | **`AdminTvdePlanRequestsScreen`** (novo) — aprovar/ativar/recusar |
| D1 carro (cor/marca/modelo/matrícula) | Lista TVDE (visível) + detalhe do motorista (editável) |
| D foto do motorista | Lista TVDE (avatar) |
| E chat TVDE (`tvde_messages`) | *(follow-up: visor de chat TVDE no admin, se pedido)* |
| A/B (sessão anterior) | `AdminTvdeRidesScreen` / `AdminTvdeDriversScreen` já cobrem |

---

## OBJETOS ALTERADOS
**Flutter (13 M + 3 novos):** `tvde_request_ride_screen`, `tvde_plans_screen`,
`tvde_ride_tracking_screen`, `tvde_ride_active_screen`, `tvde_driver_home_screen`,
`tvde_store`, `tvde_driver_store`, `driver_signup_screen`, `main.dart`,
`admin_dashboard_screen`, `admin_driver_detail_screen`, `admin_tvde_drivers_screen`,
`admin_driver_service` · **novos:** `stores/tvde_chat_store.dart`,
`screens/shared/tvde_chat_screen.dart`, `screens/admin/admin_tvde_plan_requests_screen.dart`.
**DB (migrations aditivas):** `tvde_b1_route_distance_source`,
`tvde_d1_vehicle_color_make_model`, `tvde_c4_plan_requests`,
`tvde_d1_driver_register_vehicle_fields`, `tvde_e_chat_messages`,
`tvde_d2_passenger_card`, `tvde_g_admin_vehicle_fields`.
**Edge:** `notify-tvde-chat` (v1, novo).
**Não tocado:** dispatch-engine, pricing, `tvde_calculate_fare` (coeficientes),
Stripe, ledger/tokens, notify-driver do delivery, `messages`/`orders`.

---

## GATES DE FECHO
- `flutter analyze` — **0 erros** (projeto completo).
- Juiz anti-trapaça (`--base HEAD`, diff da sessão: 14 ficheiros, 0 testes tocados) — **✅ CLEAN**.
  (Nota: a base default `merge-base main HEAD` apanha 2249 ficheiros de commits antigos —
  base errada para esta sessão; a base correta é HEAD/6125162.)
- Advisors de segurança — **0 ERROR** (as WARN `*_security_definer_function_executable`
  são o padrão pré-existente de TODAS as funções SECURITY DEFINER do projeto; as novas
  têm guards internos: `auth.uid()`, `is_admin()`, `driver_id = auth.uid()`).

---

## CHECKLIST DE TESTE NO DEVICE
1. **B1 km/tarifa por rota:** Av. do Rio Diz 26 → Rua do Torreão 4 (Guarda) — a estimativa
   e a tarifa final refletem a **distância de rota** (> linha reta); com API off, cai para
   haversine e o ride marca `final_distance_source='haversine'`.
2. **C1 mapa recolha:** a tela inicial mostra o mapa com o pin verde na tua posição.
3. **C2 pin arrastável:** arrastar o pin → a morada de recolha atualiza (reverse geocode)
   e a estimativa recalcula; escrever no campo de recolha (autocomplete) também funciona.
4. **C3/C4 planos:** card de planos visível na home; "Quero aderir" → "pedido enviado";
   no admin aparece em **Pedidos de plano** → aprovar ativa a assinatura.
5. **D1 card do carro:** com corrida atribuída, o cliente vê foto+nome+⭐+carro do motorista.
6. **D2 foto do cliente:** o motorista vê foto+nome do passageiro no painel.
7. **E chat:** abrir "Mensagem" nos dois lados — as mensagens aparecem ao vivo; com a app
   em background chega **push** de nova mensagem.
8. **E ligar:** botão "Ligar" abre o marcador (tel:) com o número do outro (se existir).
9. **F home motorista:** botão **Suporte** abre a folha; cartão mostra **avaliação média**
   e **tempo online** da sessão.
10. **G admin:** lista TVDE mostra **foto + carro**; no detalhe do motorista os campos
    "Marca e modelo" + "Cor" são **editáveis** (com motivo); **Pedidos de plano** aprova/ativa.

## DECISÕES DO DANILO (pendentes)
- Pagamento online de planos TVDE (Fase 7) — hoje o admin ativa sem cobrança.
- Cobrança de no-show (`tvde_cancel_fee_cents=0`, fluxo pronto).
- Follow-ups: agregação diária de tempo online (backend); fotos em TODAS as listas admin
  (clientes/parceiros); visor de chat TVDE no admin (se desejado).
