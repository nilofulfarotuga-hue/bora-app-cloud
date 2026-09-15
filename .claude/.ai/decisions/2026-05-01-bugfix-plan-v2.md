# Bug Fix Plan v2 — Testes Reais Danilo (2026-05-01)

> **MODO:** Análise primeiro · NÃO executar até aprovação
> **Branch:** autonomous-night-2026-04-29 (continuação)
> **Verificação Supabase MCP:** ojykpzwqrtusfeakzrna
> **Bugs:** 5 (11-15) descobertos em testes pós-Fase 6

---

## SUMÁRIO EXECUTIVO

5 bugs novos identificados em teste real. **2 críticos** (BUG 11 cobrança errada, BUG 12 dispatch sem driver). **2 médios** (BUG 13/14 UI). **1 já-conhecido** (BUG 15 = launch blocker E1 Firebase).

Existe forte cascata: **BUG 12 explica por que Danilo não testou ainda Fase 2 — dispatch nunca chama driver, então cancelamento via X não tem chance de testar**.

**Ordem proposta:** 11 → 12 → 13/14 → 15.

---

## BUG 11 — Stripe cobra €7.68 em vez de €4.44 (DOUBLE MARKUP)

- **Severidade:** CRÍTICO
- **Causa raiz CONFIRMADA via reprodução MCP:**
  - `cart_store` envia `subtotal=14.92` (já marked-up 15% pelo `PricingService.calculateBreakdown` non-partner)
  - `cart_store` envia `product_lines` com `unit_price=14.92` (já marked-up)
  - `quote_order_pricing` (DB) recompute `v_subtotal_server = SUM(unit_price × quantity) = 14.92` e aplica `*= 1.15` outra vez = **€17.16** (DOUBLE MARKUP)
  - `pricing_calculate(storeShopping, 17.16, ...)` retorna service_fee=2.50 + delivery=2.50 → `customer_total = 22.16`
  - `charge_total = 22.16 - 15.48 = 6.68`
  - `payment_buffer_total = 6.68 × 1.15 = €7.68` (TRIPLE inflation no fluxo non-partner storeShopping)
  - Reprodução MCP: `quote_order_pricing` com payload exacto retorna `payment_buffer_total: 25.48` (sem wallet) — match com €7.68 com wallet 15.48
- **Ficheiros a tocar:**
  - `bora_app/supabase/migrations/20260501_fix_double_markup.sql` (nova migration)
    - Modificar `quote_order_pricing` para aceitar flag `prices_pre_marked_up: true` em product_lines
    - Modificar `create_order` v5 para mesma lógica
  - `bora_app/lib/stores/order_store.dart` startCardPaymentDraft + createOrder (passar flag)
- **Fix proposto:**
  - Adicionar campo `prices_pre_marked_up: BOOLEAN` ao payload (default `FALSE` para retrocompat)
  - Quando `TRUE`, RPCs SKIP o `*= 1.15` no `v_subtotal_server`
  - Cart_store passa `prices_pre_marked_up: true` (porque cart já tem markup local)
- **Risk:** HIGH (mexe em pricing + Stripe charge)
- **Tempo:** 30min
- **Smoke test:**
  - Reprodução MCP: payload Lidl com subtotal=14.92, distance=0.246, wallet=15.48 → buffer ≈ €4.44 × 1.15 = €5.11 (não €7.68)
  - Test E2E: criar pedido card real → Stripe sheet mostra valor consistente com cart_screen
- **Painel admin:** NÃO

---

## BUG 12 — Dispatch não chama estafeta (drivers.lat/lng stale)

- **Severidade:** CRÍTICO
- **Causa raiz CONFIRMADA via MCP:**
  - `dispatch-engine/index.ts:533` calcula distância usando `d.lat, d.lng` (tabela `drivers`)
  - Driver `978c0186-...`: `drivers.lat=38.7223, lng=-9.1393` (LISBOA — default), `updated_at='2026-04-29 14:53:15'` (2 dias atrás, stale)
  - `driver_locations` para este driver: **0 rows**
  - `DriverLocationPingService` (driver_location_ping_service.dart:40) escreve apenas em `driver_locations` via RPC `driver_update_location` — esta RPC NÃO actualiza `drivers.lat/lng`
  - `DriverLocationService` (driver_location_service.dart) é DEPRECATED no-op desde unification
  - `DriverStore.updateDriverLocation` actualiza `drivers.lat/lng` MAS só é chamado por `DriverMapScreen` (quando driver tem ordem aceite). Driver à espera de pedidos no `DriverHomeScreen` → drivers.lat/lng nunca actualiza.
  - Resultado: dispatch-engine vê driver "em Lisboa" → fora do raio de Guarda → não recebe oferta
- **Ficheiros a tocar:**
  - `bora_app/supabase/migrations/20260501_driver_update_location_writes_drivers.sql`
    - Estender RPC `driver_update_location` para também `UPDATE drivers SET lat=p_latitude, lng=p_longitude, is_online=p_is_online, updated_at=NOW()`
- **Fix proposto:**
  - **Opção escolhida (cirúrgica):** RPC `driver_update_location` faz DUAS escritas atómicas:
    1. UPSERT `driver_locations` (mantido)
    2. UPDATE `drivers` SET lat/lng/is_online
  - Legacy reads em `dispatch-engine` continuam a funcionar (não muda código Edge Fn)
  - Long-term: migrar dispatch-engine para `driver_locations` (próxima refactor)
- **Risk:** MEDIUM (DDL + RPC, afecta dispatch — testar bem)
- **Tempo:** 20min
- **Smoke test:**
  - Driver online em Guarda → app real → 30s depois `SELECT lat, lng FROM drivers` mostra coordenadas reais (não 38.72/-9.13)
  - Cliente cria pedido cash em Guarda → dispatch atribui driver → driver recebe oferta
  - `current_driver_offer_id` actualiza correctamente
- **Painel admin:** NÃO (mas admin já tem live ops map que usa driver_locations)
- **Nota:** O ping só funciona enquanto driver app está em foreground (LAUNCH BLOCKER E1 — background service requer Foreground Service Android)

---

## BUG 13 — Botão Uber tapa Total no order_detail

- **Severidade:** MÉDIO (UX)
- **Causa raiz:** `order_details_screen.dart:38` AppBar simples mas o "Uber button" referido é provavelmente um widget dentro do `_OrderInfoCard` ou um overlay. Necessário ver screenshot ou ler linhas posteriores. Hipótese: botão "Pedir Uber" para alternativa quando estafeta não vem, posicionado em `Stack` que sobrepõe Total.
- **Ficheiros a tocar:**
  - `bora_app/lib/screens/order_details_screen.dart`
- **Fix proposto:**
  - Pedir screenshot ao Danilo OR ler `_OrderInfoCard` widget completo
  - Substituir Stack por Column/Row com spacing apropriado
  - Adicionar margin/padding ao Total
- **Risk:** LOW
- **Tempo:** 15min (depende de localização exacta)
- **Smoke test:** abrir order detail → Total visível inteiro, sem sobreposição
- **Painel admin:** NÃO

---

## BUG 14 — Order detail mostra só Total/Taxa entrega/Cash (falta breakdown)

- **Severidade:** MÉDIO (transparência financeira)
- **Causa raiz:** `_OrderInfoCard` widget actualmente só mostra 3 campos. Falta:
  - Subtotal (preço dos items antes de fees)
  - Service Fee
  - Bag Fee (se mercado)
  - Apartment Surcharge (se aplicável)
  - Wallet aplicado (se >0)
  - Menu Credit aplicado (se >0)
  - Tip (se >0)
  - Driver earnings (NÃO mostrar — interno)
- **Ficheiros a tocar:**
  - `bora_app/lib/screens/order_details_screen.dart` — refactor `_OrderInfoCard`
- **Fix proposto:**
  - Adicionar componente `_BreakdownSection` ao `_OrderInfoCard`
  - Layout estilo Uber Eats: cada linha (label + valor)
  - Mostrar campos condicionalmente (só se >0)
  - Total final em bold + separador
- **Risk:** LOW
- **Tempo:** 25min
- **Smoke test:** abrir pedido com wallet+tip → todas as linhas visíveis com soma correta
- **Painel admin:** NÃO

---

## BUG 15 — Notificação push estafeta (Firebase)

- **Severidade:** ALTO (mas já documentado como LAUNCH BLOCKER E1)
- **Causa raiz:** `notify-driver/index.ts:38-43` é graceful no-op quando `FIREBASE_PROJECT_ID` ou `FIREBASE_SERVICE_ACCOUNT` não estão definidos. Retorna `{ok:false, reason:'firebase_not_configured'}` com 200 → dispatch funciona mas push silencioso.
  - Fallback existe: driver recebe oferta via Realtime channel `orders_channel` (DriverStore subscription). Não dependente de FCM.
  - Mas: app em background não dispara realtime → driver precisa abrir app → vê oferta nos primeiros 40s.
- **Ficheiros a tocar:** nenhum directamente (config-only)
- **Fix proposto (não-código):**
  - Danilo configurar Firebase secrets em Supabase Dashboard (`supabase secrets set FIREBASE_PROJECT_ID=... FIREBASE_SERVICE_ACCOUNT=...`)
  - Doc: `.claude/.ai/decisions/2026-04-30-firebase-setup.md` (criar nesta fase)
- **Risk:** LOW (apenas config)
- **Tempo:** 5min code (criar doc) + 30min Danilo (Firebase Console + Supabase secrets)
- **Smoke test:** após setup, dispatch atribui order → driver recebe push notification em < 2s
- **Painel admin:** já existe `admin_send_notification_screen.dart` (verificar se usa notify-driver ou outro)

---

## ORDEM DE EXECUÇÃO PROPOSTA

| Fase | Bug | Tempo | Risk | Dependência |
|------|-----|-------|------|-------------|
| 1 | BUG 11 (double markup) | 30m | HIGH | nenhuma — bloqueia teste real |
| 2 | BUG 12 (drivers.lat/lng) | 20m | MEDIUM | nenhuma — desbloqueia dispatch |
| 3 | BUG 13 (Uber button overflow) | 15m | LOW | precisa screenshot/repro |
| 4 | BUG 14 (breakdown completo) | 25m | LOW | nenhuma |
| 5 | BUG 15 (Firebase doc) | 5m | LOW | manual setup Danilo |

**Total estimado:** ~95min code + 30min config Danilo (Firebase).

---

## RISCO GERAL

- **HIGH-RISK:** BUG 11 (mexe em pricing + Stripe). Stripe LIVE — cuidado dobrado.
- **Smoke test obrigatório antes de cada commit:**
  - Reprodução em SQL via MCP
  - flutter analyze 0 erros
  - Verificação em prod via MCP

---

## BUGS COLATERAIS DESCOBERTOS

Nenhum bug novo descoberto durante análise (BUGs 11-15 são os reportados, todos confirmados).

**Observação adicional:** Durante reprodução BUG 11, descobriu-se que `payment_buffer_total = chargeTotal × 1.15` para non-partner storeShopping não está documentado claramente. É uma "TRIPLE inflation" intencional: subtotal markup + buffer markup. Isto é correto para storeShopping (driver compra com buffer pré-pago e ajusta no purchase finalize). MAS o bug actual é o DOUBLE markup no subtotal_server (não no buffer), corrigível com flag `prices_pre_marked_up`.

---

## CONFIRMAÇÕES MCP RECOLHIDAS

- ✅ payment_drafts row `b9d0cef8-...` mostra amount_cents=768, wallet_applied_cents=1548
- ✅ pricing_calculate(storeShopping, 14.92, 0.246, FALSE, ...) → customer_total=19.92 (correcto raw)
- ✅ pricing_calculate(storeShopping, 17.16, 0.246, FALSE, ...) → customer_total=22.16 (após double markup)
- ✅ quote_order_pricing reproduzido: subtotal=17.16, customer_total=22.16, buffer=25.48 (sem wallet)
- ✅ drivers.lat=38.7223, lng=-9.1393 (Lisboa default), updated_at=2026-04-29 (stale 2 dias)
- ✅ driver_locations para 978c0186: 0 rows
- ✅ Order 79ca3c7a status=callingDriver, current_driver_offer_id=978c0186, driver_id NULL (oferta enviada mas não aceite por dispatch loop)
- ✅ RPC `driver_update_location` faz só UPSERT em driver_locations (não actualiza drivers)
- ✅ dispatch-engine linha 533 usa `d.lat, d.lng` (drivers table)
- ✅ notify-driver retorna 200 graceful quando Firebase secrets ausentes

---

## PRÓXIMO PASSO

Aguardar aprovação Danilo. Após luz verde, executar Fase 1 (BUG 11) — risco HIGH, smoke test SQL primeiro.

Sugestão: começar BUG 12 antes de BUG 11 porque:
- BUG 12 é blocker para Danilo testar BUG 11 fix em prod (sem driver chamado, não há fluxo)
- BUG 12 risco MEDIUM, BUG 11 risco HIGH

**Ordem alternativa proposta:** 12 → 11 → 14 → 13 → 15.
