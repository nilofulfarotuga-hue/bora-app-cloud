# Bora App — Product Requirements Document (TestSprite)

> **Propósito:** documentação funcional para configuração de testes automáticos no TestSprite.
> **Data:** 2026-05-28
> **Branch:** `autonomous-night-2026-04-29`
> **Stack:** Flutter (mobile) + Supabase (Postgres + Edge Functions + Auth + Storage + Realtime) + Stripe + Firebase Cloud Messaging.

---

## 0. Visão geral

A Bora App é uma plataforma de delivery, dine-in e reservas a operar em Guarda, Portugal. Liga três tipos de utilizador num único marketplace:

- **Cliente** — encomenda, paga, segue entrega, avalia.
- **Estafeta (Driver)** — recebe oferta, faz pickup, entrega e marca delivered com PIN.
- **Parceiro (Restaurante/Loja)** — gere menu, aceita pedidos, vê comissões e settlements.
- **Admin (interno Bora)** — fora do scope TestSprite (não testar UI admin).

**Roles** persistem em `SessionStore` (SharedPreferences `bora_app.user_role`) e em Supabase `user_metadata.bora_role` (`client` / `driver` / `partner`). Admins têm `app_metadata.role='admin'` (imutável via trigger DB).

**Order lifecycle (enum `OrderStatus`):**
`created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered` (com ramos `rejected` e `cancelled`).

---

## 1. CLIENTE

### 1.1 Registo e Login

| Funcionalidade | Comportamento esperado (sucesso) | Edge case / erro |
|---|---|---|
| Signup email+password | Cria `auth.users` + perfil em `profiles` com `bora_role=client`. Persistência draft (recupera form ao reabrir app). | Email duplicado → erro "este email já existe". Password < 6 chars → erro inline. Sem ligação → mostra retry. |
| Signup Google | OAuth Supabase; primeiro login pede foto + morada. | TODO: verificar se feature-flag activa em prod. |
| Signup Apple | Skeleton existente, feature-flagged. | TODO: verificar — Apple Sign-In em iOS apenas. |
| Login email+password | JWT emitido; `SessionStore.setRole('client')`; `_RootNavigator` muda para `ClientHomeScreen`. | Credenciais erradas → erro "email/password inválidos". Conta banida → bloqueio com motivo. |
| Forgot password | Edge function `support-password-reset` envia link por email. | Email inexistente → resposta neutra ("se existir, recebe link") (anti-enumeration). |
| Logout | Limpa SharedPreferences + `supabase.auth.signOut()`. | — |

**Demo account:** `cliente@bora.app` / `123456` (sempre disponível offline).

### 1.2 Perfil

- Editar nome, foto de perfil (upload via Edge Fn `upload-avatar` → bucket `avatars`).
- Gerir moradas (tabela `addresses` ligada a `user_id`).
- Definir morada por defeito.

**Edge case:** upload foto > 5 MB → erro "imagem demasiado grande".

### 1.3 Descoberta (listagens)

- **Restaurantes** — `restaurants` WHERE `business_category='restaurant'` AND `is_active=true`.
- **Mercados/Lojas** — `business_category IN ('supermarket','pharmacy','store')`.
- **Pesquisa global de produtos** — full-text em `products.name`.

**Comportamento esperado:** lista vazia mostra empty state ("nenhum resultado para …"); shimmer loading durante fetch; pull-to-refresh.

### 1.4 Carrinho e Checkout

- `CartStore` em memória + persistência SharedPreferences.
- Adicionar produto com variantes (tamanho/extras) — obrigatório escolher antes de "Adicionar".
- Aplicar **promo code** (`client_redeem_promo_tokens` RPC).
- Aplicar **tokens Bora** (max 50% desconto — 100 tokens = €0,50).
- **Sacos:** restaurante €0,30 fixo / mercado €0,10 por saco.
- **Markup non-partner:** 15% calculado em runtime via `pricing_calculate`.

### 1.5 Pagamento

| Método | Edge Function | Comportamento |
|---|---|---|
| Cartão Stripe | `create-payment-intent` | PaymentSheet flutter_stripe. Sucesso → `stripe-webhook` (`payment_intent.succeeded`) → order paga + dispatch. |
| MB Way | `create-mbway-payment-intent` (LIVE) | Push automático para app MB Way (phone E.164). Webhook confirma. Timeout 4 min. |
| Dinheiro | local (sem backend) | Máx €40 (€30 em prod recentemente). Driver recolhe → trigger `orders_cash_settlement` cria entry em `driver_transactions`. |
| Apple Pay | Stripe PaymentSheet | iOS apenas. |
| Saved card | `list-saved-cards` + `create-payment-intent` com `payment_method_id` | Re-usa Stripe Customer guardado. |

**Edge cases:**
- Pagamento falha → order fica `pending_payment`; cliente pode retry sem recriar order.
- MB Way timeout → push notification "Pagamento expirou".
- Stripe minimum €0,50 — orders abaixo bloqueadas server-side.
- Valor manipulado client-side → `create-payment-intent` valida contra `orders.payment_buffer_total` (±5% tolerância). Rejeita se fora.

### 1.6 Wallet e Tokens

- `bora_tokens` — award por entrega (cliente 3% subtotal min 1 token). Expira em 60 dias.
- `client_wallets` — saldo livre (cents) usado para refunds (80% saldo + 20% tokens).
- RPC `wallet_get_balance(user_id)` → `{free_cents, tokens_balance, last_transactions[]}`.

### 1.7 Acompanhamento (tracking)

- Mapa em tempo real (`google_maps_flutter` + `latlong2`).
- Subscrição realtime ao canal `public:drivers` → posição animada (12 steps × 80 ms).
- Estados visíveis: "A preparar" → "À procura de estafeta" → "Estafeta a caminho" → "Recolhido" → "A caminho" → "Entregue".
- Botão "Reenviar código PIN" no tracking screen (PIN obrigatório no delivery).
- Chat com estafeta (tabela `messages` + Edge Fn `notify-chat-message`).

**Edge cases:** driver perde GPS → última posição conhecida + aviso. Cancelamento pelo driver → reassign automático via `dispatch-engine`.

### 1.8 Histórico de pedidos

- Lista `orders` WHERE `user_id = auth.uid()` ORDER BY `created_at DESC`.
- Detalhe de pedido com recibo, avaliação, repedir.

### 1.9 Avaliações

- Pós-entrega: estrelas (1-5) + comentário opcional para restaurante e estafeta.
- Tabela `ratings` (TODO: verificar nome exacto).
- Avaliação < 3 estrelas dispara `notify-partner-low-rating`.

### 1.10 Cancelamento

| Quando | Edge Function | Comportamento |
|---|---|---|
| Antes de aceite por driver (`created` / `preparing`) | `client-cancel-order` | Refund 100% (cartão/MB Way) ou cancela (cash). |
| Após `driverAccepted` | `cancel-order-with-choice` | Escolha motivo. Pode haver fee (drive até pickup). |
| Em qualquer fase (admin) | `admin-cancel-order` | Force-cancel. |

**Edge case:** refund duplo bloqueado por idempotency key (TODO: verificar BUG-MN-004 cap). Refund cap pendente.

### 1.11 Reserva de mesa

- Selecciona restaurante → escolhe data/hora → número de pessoas → mesa (floor plan editor partner-side).
- `create-reservation-payment-intent` se restaurante pede pré-pagamento.
- Pacing rules (limita reservas/intervalo) definidas pelo parceiro.

### 1.12 Takeaway

- Sub-tipo de `restaurant` order — sem driver, cliente recolhe no balcão.
- Estados: `preparing → ready_for_pickup → completed`.
- Comissão parceiro 20% (vs 25% delivery).

### 1.13 GDPR

- Consentimento técnico real bloqueia FCM + GPS até aceitar (Batch F).
- `delete-account` Edge Fn → GDPR account deletion.

---

## 2. ESTAFETA (DRIVER)

### 2.1 Registo

Multi-step (4 passos):
1. Telefone + password (email sintético `{phone}@driver.bora.app`).
2. Dados pessoais + selfie de registo (campo `registration_selfie_url`).
3. Documentos: CC/passaporte (frente+verso), carta de condução, documento veículo.
4. IBAN para payouts.

**Validações:**
- IBAN PT + **21 dígitos** (23 chars total). Validador rejeita 22 dígitos (BUG-PARTNER-IBAN corrigido em 2026-05-26).
- Selfie + documento + veículo obrigatórios.
- Matrícula visível no admin para aprovação.

**Edge case:** signup falha a meio → defensive UPDATE retoma sem perder dados.

### 2.2 Login

- Phone + password.
- `loginDriverAsync` valida in-memory cache + Supabase fallback.
- Verifica `user_metadata.bora_role='driver'`.

**Demo:** `910000000` / `123456`.

### 2.3 Aprovação

- Driver fica `is_approved=false` até admin aprovar documentos.
- Bloqueado de entrar Online enquanto não aprovado.

### 2.4 Online/Offline

- Toggle inicia **Foreground Service** Android (`flutter_foreground_task`) — sempre online.
- 4 permissões obrigatórias gate antes de Online:
  1. Notificações.
  2. Location (background).
  3. Battery exemption.
  4. `USE_FULL_SCREEN_INTENT`.
- Heartbeat task isolate chama `driver_heartbeat_by_id` periodicamente.

### 2.5 Oferta de pedido

**Fluxo crítico (3 paths):**

| Estado do device | Apresentação | Implementação |
|---|---|---|
| FG (app aberta) | Cartão laranja inline na home com botões Accept/Reject | `DriverHomeScreen` + `OfferPresentationGate` |
| BG unlocked | Fullscreen Material dialog via `navigatorKey` global | `DriverFullScreenOfferDialog` |
| Locked / dead | CallKit notification estilo chamada | `connectycube_flutter_call_kit` ^2.8.2 |

- Realtime channel `driver-offer:{id}` recebe UPDATE.
- Som dedicado `bora_alert` (canal notif v3 com `setSound`).
- Auto-reject após `_offerTimeout` (10s default; 40s spec).
- FCM data-only + `fullScreenIntent` + `default_notification_channel_id`.

**Edge case:** rehydrate `pending_offer` (resolve race "realtime subscribe perde UPDATE pré-arranque").

### 2.6 Aceitar / Rejeitar

- Aceitar → RPC `accept_offer` → order avança para `driverAccepted` → mapa mostra rota até pickup.
- Rejeitar → RPC `driver_reject_offer` → `dispatch-engine` oferece a próximo driver.

### 2.7 Recolha (pickup)

- Mapa com rota Google Directions.
- Foto obrigatória na recolha (storage bucket `pickup_photos`).
- Marcar "Picked up" → status `pickedUp` → `onTheWay` quando arranca.

### 2.8 Entrega

- **PIN obrigatório** (Batch F — BUG-DR-009) — driver pede ao cliente código 4 dígitos.
- Marcar "Delivered" → status `delivered` → triggers:
  - `trg_award_tokens_on_delivery` (cliente 3% / driver 40 tokens / 50 partner).
  - `orders_post_to_ledger` (earning + commission split).
  - `orders_cash_settlement` (se cash, regista em `driver_balances`).

### 2.9 Batching (pedidos empilhados)

- Logistics (`carryGroceries`/`sendPackage`) — nunca batched.
- Partner — máx 2; segundo da mesma loja OU ≤800 m.
- Non-partner — máx 3 da mesma loja.
- FIFO ≤200 m. Bónus +€3 stacked partner.

### 2.10 Ganhos e Tokens

- Earnings dashboard: hoje / semana / mês.
- Base: €3,80 + €0,20/km. Bónus +€0,80 (storeShopping/carry/send).
- 30% share lucro líquido Bora (non-partner) — Batch D.
- Payout via IBAN ou MB Way.
- Token wallet (40 normal / 50 partner — 100 tokens = €0,50).

### 2.11 Histórico

- Lista deliveries pessoais.
- Filtro por dia / loja.

### 2.12 Suporte

- Chat com support-chatbot (Gemini RAG).
- Botão SOS para admin urgente.

---

## 3. PARCEIRO (RESTAURANTE / LOJA)

### 3.1 Registo

Multi-step (4 passos):
1. Email + password (real).
2. Dados restaurante: nome, NIF, IBAN, NIB, hero, logo.
3. Foto **obrigatória** do restaurante (Batch E).
4. Documentos opcionais (alvará).

- Edge Fn `register-partner` valida IBAN PT+21 dígitos.
- `is_approved=false` até admin aprovar.

### 3.2 Login

- Email + password (real, não sintético).
- Verifica `user_metadata.bora_role='partner'`.

### 3.3 Gestão de menu

- CRUD produtos (`products` table).
- Categorias canónicas (22 secções).
- Variantes obrigatórias (tamanho/extras).
- Foto produto via Edge Fn `upload-restaurant-asset`.
- Mutations **async + rollback optimístico** (Batch E).
- Toggle `is_available` por produto.

### 3.4 Receber pedidos

- Push FCM (canal `partner_orders`) + som persistente.
- Lista pedidos pendentes em real-time.
- Aceitar → `restaurantAcceptOrder` → `preparing`.
- Marcar pronto → `restaurantMarkReady` → `callingDriver` (dispatch arranca).
- Rejeitar com motivo → `rejected` + refund cliente.

**Edge case (BUG-PT-006):** parceiro sem som em novo pedido — launch blocker pendente.

### 3.5 Comissões e settlements

- Modelo **10+5+5%** (visible / hidden / service fee):
  - 10% `partner_commission_visible` — parceiro paga no settlement.
  - 5% `partner_markup_hidden` — embutido no preço (cliente não vê).
  - 5% `partner_service_fee_client` — taxa visível no recibo.
- Dashboard de receita diária / semanal / mensal.
- Payout settlement em lote (admin gere).

### 3.6 Reservas e dine-in

- Floor plan editor (mesas configuráveis).
- Walk-in waitlist.
- Pacing rules (max reservas/15 min).

### 3.7 Avaliações

- Dashboard ratings.
- Alerta automático quando rating < 3 (notify-partner-low-rating).

---

## 4. FLUXOS CRÍTICOS (obrigatórios para TestSprite)

### 4.1 Happy path E2E — Cliente novo

1. Registo cliente (email/password).
2. Confirmação email (se activado).
3. Adiciona morada.
4. Browse restaurantes → escolhe loja.
5. Adiciona 2 produtos (com variantes) ao carrinho.
6. Aplica tokens (se tiver).
7. Checkout → escolhe cartão Stripe.
8. PaymentSheet → cartão de teste `4242 4242 4242 4242`.
9. Order criada → driver recebe oferta → aceita → pickup → delivered.
10. Cliente avalia 5 estrelas → tokens awarded.

**Verificações:** `orders.status='delivered'`, `bora_tokens` entry, `ledger_entries` 3 linhas (earning + commission + share), rating em DB.

### 4.2 Cancelamento antes de driver aceitar

1. Cliente cria order.
2. Status fica `created → preparing → callingDriver`.
3. Cliente cancela via `client-cancel-order` antes de qualquer driver aceitar.
4. **Esperado:** refund 100% (se cartão/MB Way) ou order cancelled (cash). Dispatch loop para. Sem entry em `ledger_entries`.

### 4.3 Cancelamento após driver aceitar

1. Order em `driverAccepted`.
2. Cliente cancela via `cancel-order-with-choice` → escolhe motivo.
3. **Esperado:** fee parcial (drive até pickup). Driver compensado via `driver_transactions`. Refund parcial cliente.

### 4.4 Pagamento Stripe cartão

1. Cliente checkout → `card`.
2. Edge Fn `create-payment-intent` cria PI server-validated (±5% buffer).
3. Cliente confirma na PaymentSheet.
4. `stripe-webhook` recebe `payment_intent.succeeded` → marca `paid=true`, dispara dispatch.

**Edge cases:** cartão `4000 0000 0000 0002` (declined) → erro inline. `4000 0025 0000 3155` (3DS) → flow secundário.

### 4.5 Pagamento dinheiro

1. Cliente checkout → `cash`.
2. Order criada com `payment_method='cash'`, `paid=false`.
3. Driver entrega + recebe dinheiro físico.
4. Mark delivered → `orders_cash_settlement` trigger debita `driver_balances` com o valor (driver fica a dever à Bora).

**Edge case:** order > €40 com cash → bloqueada server-side.

### 4.6 Pagamento tokens (parcial)

1. Cliente tem 200 tokens (€1).
2. Order subtotal €10.
3. Aplica máx 50% → desconto €5 = 1000 tokens. **Só tem 200** → desconto efectivo €1.
4. Tokens debitados via `client_redeem_promo_tokens`.
5. Restante €9 via cartão/MB Way/cash.

### 4.7 Push notification driver

1. Order entra em `callingDriver`.
2. `dispatch-engine` selecciona driver elegível.
3. Edge Fn `notify-driver` envia FCM data-only.
4. **Driver com app em FG:** cartão laranja inline.
5. **Driver com app em BG (unlocked):** fullscreen dialog.
6. **Driver com device locked:** CallKit ring.
7. Som `bora_alert` toca em todos.

**Verificação:** check `partner_push_tokens` / driver token actual + log Edge Fn (`200 {ok:true}`).

---

## 5. EDGE CASES TRANSVERSAIS

- **Realtime disconnect:** fallback Timer 3s (`refresh()` notifyListeners).
- **Re-login com role diferente:** `_RootNavigator` rebuilda tree sem `Navigator.push`.
- **App killed durante order:** `pending_offer` rehydrate ao re-abrir.
- **GPS off no driver:** Foreground Service mantém WAKE_LOCK; heartbeat continua mas sem update location.
- **Stripe webhook duplicado:** idempotency via `stripe_event_id` (TODO: verificar implementação).
- **Refund duplicado:** idempotency key obrigatória (TODO: BUG-MN-004 cap pendente).
- **Concurrent driver accept:** RPC `accept_offer` é atómica (primeiro ganha; segundo recebe erro "offer no longer available").

---

## 6. NÃO TESTAR (out of scope TestSprite)

- UI Admin web.
- Edge Functions `admin-ai-assistant`, `reindex-knowledge`, `analyze-conversations`.
- Scraping de mercados (Wells, Continente, etc.).
- Notificação `notify-admin-*`.

---

**Fim do PRD.** Para detalhes de endpoints, schema e RLS ver `testsprite-api-docs.md`.
