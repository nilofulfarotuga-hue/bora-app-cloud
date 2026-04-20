---
name: state_validator_validation
description: Validation procedure for state_validator. Step-by-step checklist to run before and after any state/status change.
version: 2.1.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill executa o checklist de transição — nunca modifica código nem banco. Pré-condições, pós-condições e invariantes ancorados em `business_rules.md` §1.3 · §1.4 · §7.

# STATE VALIDATOR — VALIDATION PROCEDURE

## ROLE
Step-by-step validation procedure. Run before AND after any change to order state or status.

---

## OBJECTIVE

Confirmar que estado atual é válido, que a transição proposta é legal, e que não há inconsistência após a mudança.

---

## PASSOS

### 1. ANALISAR
- Identificar estado atual (qual `OrderStatus`?)
- Identificar estado esperado (para onde está indo?)
- Identificar tipo de pedido: restaurant / storeShopping / carryGroceries / sendPackage · parceiro ou não-parceiro (BR §1.2 · §10)

### 2. COMPARAR
- Inconsistência? (estado atual ≠ esperado sem transição válida?)
- Duplicação? (mesmo estado em stores diferentes?)

### 3. VALIDAR TRANSIÇÃO (contra `state_validator/rules`)
- Transição é legal na FSM de BR §1.3 / §1.4?
- Pré-condições do destino estão cumpridas?

### 4. DETECTAR ERRO
- Estado inválido → BLOQUEAR e reportar
- Estado duplicado → BLOQUEAR e reportar
- Estado ausente → BLOQUEAR e reportar

---

## PRÉ-CONDIÇÕES POR TRANSIÇÃO (BR §1.3 · §7)

### `created → preparing` (parceiro aceita) ou `created → callingDriver` (não-parceiro)
- [ ] Pagamento confirmado (para cash: valor ≤ €40, BR §3.2)
- [ ] Buffer Stripe +15% pré-autorizado se cartão + não-parceiro (BR §3.3)
- [ ] Endereço de entrega presente

### `preparing → callingDriver`
- [ ] Pedido está em `preparing` (parceiro já confirmou)
- [ ] Dispatch engine acionado

### `callingDriver → driverAccepted`
- [ ] `assigned_driver_id` preenchido
- [ ] `current_driver_offer_id` corresponde ao driver
- [ ] Driver não excede `MAX_ORDERS_PER_DRIVER = 3` (BR §6.4)
- [ ] Aceite dentro de `OFFER_TIMEOUT_SECONDS = 40 s` (BR §6.3)

### `driverAccepted → pickedUp`
- [ ] Driver está no local (confirmação manual)
- [ ] Se **não-parceiro**: checklist completa + `isPurchaseFinalized = true` + `finalTotal` guardado (BR §7.4)
- [ ] Se **parceiro**: saco confirmado pelo driver (BR §7.3)
- [ ] Se `sendPackage` ou `carryGroceries`: driver viu foto obrigatória (BR §7.5 · §7.6)

### `pickedUp → onTheWay`
- [ ] `isPurchaseFinalized = true` (se não-parceiro)
- [ ] Driver activo e com coordenadas
- [ ] Dropoff definido

### `onTheWay → delivered`
- [ ] Código **4 dígitos** correcto (BR §7.3)
- [ ] Driver no dropoff (confirmação manual + proximidade)
- [ ] Trigger `trg_award_tokens_on_delivery` dispara (BR §4.4)

### Excepções — `cancel` via RPC
- [ ] Driver actual em `tried_driver_ids`
- [ ] `assigned_driver_id` → null
- [ ] Status volta a `callingDriver` (BR §7.7)

---

## CHECKLIST PÓS-MUDANÇA

- [ ] Status correcto no banco (`orders.status`)?
- [ ] Sequência respeitada (BR §1.3)?
- [ ] Dados consistentes entre `OrderStore` e Supabase?
- [ ] Sem conflitos de driver (`assigned_driver_id` único)?
- [ ] `current_driver_offer_id` coerente com status?
- [ ] Se `delivered`: tokens atribuídos ao estafeta (+40, BR §4.2) e cashback cliente (3%, BR §4.2)?
- [ ] Realtime channel (`orders_channel`) recebeu UPDATE?
- [ ] Push enviado ao cliente (BR §22.1) — quando aplicável?

---

## EXEMPLOS WORKED

### Exemplo 1: Validar transição `pickedUp → onTheWay`

**Input (contexto real):**
Driver acabou de carregar no "Confirmar recolha" no fluxo de mercado não-parceiro (BR §7.4). `OrderStore._advanceStatus(OrderStatus.onTheWay)` está prestes a ser chamado.

**Processo:**
1. PASSO 1 — Estado actual: `pickedUp`. Destino: `onTheWay`. Tipo: storeShopping, não-parceiro.
2. PASSO 2 — Sem duplicação entre stores (verificado).
3. PASSO 3 — Consulta `state_validator/rules` → `pickedUp → onTheWay` existe em BR §1.3. LEGAL.
4. PASSO 4 — Pré-condições:
   - ✅ `isPurchaseFinalized = true` (foi marcado no passo anterior, BR §7.4 item 8)
   - ✅ Driver activo (coords recentes em `drivers.location`)
   - ✅ Dropoff definido (`orders.dropoff_lat/lng` presentes)

**Output esperado:**
```
✅ STATE VALIDATOR: TRANSITION APPROVED
FROM: pickedUp
TO:   onTheWay
BR REF: §1.3 · §7.4 (não-parceiro)

Pré-condições:
  ✅ isPurchaseFinalized = true
  ✅ Driver activo
  ✅ Dropoff coords presentes

Pós-checklist a verificar (após UPDATE):
  - orders.status = 'onTheWay' no banco
  - realtime channel propaga UPDATE
  - cliente recebe push "Estafeta a caminho" (BR §22.1)
```

**Failure mode:**
A skill falha se aprovar sem verificar `isPurchaseFinalized` — em não-parceiros, pular esta verificação significa que o valor real (`finalTotal`) não está guardado e o cliente paga estimativa errada.

---

### Exemplo 2: Validar transição `onTheWay → delivered` com código 4 dígitos

**Input (contexto real):**
Driver chega ao cliente (fluxo `sendPackage`). UI do driver pede o código de 4 dígitos e submete `_advanceStatus(OrderStatus.delivered)`.

**Processo:**
1. PASSO 1 — Estado actual: `onTheWay`. Destino: `delivered`. Tipo: sendPackage.
2. PASSO 3 — Legal em BR §1.3.
3. PASSO 4 — Pré-condições:
   - ✅ Código 4 dígitos: driver inseriu `1234`; `orders.delivery_code` na DB é `1234`. Match.
   - ✅ Proximidade: `distance(driver_loc, dropoff) < 100m`.
   - ⚠️ Verificar se `trg_award_tokens_on_delivery` está activo (confirmar em `supabase/migrations/`).

**Output esperado:**
```
✅ STATE VALIDATOR: TRANSITION APPROVED
FROM: onTheWay
TO:   delivered
BR REF: §1.3 · §7.3 (código 4 dígitos) · §4.2 (tokens)

Pré-condições:
  ✅ delivery_code match (4 dígitos)
  ✅ Driver próximo do dropoff
  ✅ Trigger bora_tokens activo (BR §4.4)

Pós-checklist a verificar (após UPDATE):
  - Driver recebe +40 tokens (BR §4.2)
  - Cliente recebe 3% cashback em tokens (BR §4.2)
  - Push ao cliente: "Pedido entregue" (BR §22.1)
  - Chat driver↔cliente fecha (BR §23.1)
  - Se ganho driver ≥ €10 acumulado até segunda: entra no batch de payout (BR §3.4)
```

**Failure mode:**
A skill falha se aprovar com código errado — é o anti-fraude central. Também falha se não lembrar que `trg_award_tokens_on_delivery` é server-side; qualquer tentativa client-side de dar tokens é bug em espera.

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/stores/order_store.dart` método `_advanceStatus` | Ponto único de transição no código |
| `lib/stores/order_store.dart` `_statusFlow` | Tabela interna da FSM — confirmar que bate com BR §1.3 |
| `lib/screens/driver_*.dart` · `driver_order_action_helper.dart` | UI que dispara transições no driver |
| `lib/screens/order_tracking_screen.dart` | UI que reflecte transição no cliente |
| `supabase/migrations/*.sql` | Constraints + triggers que reagem a mudança de status |
| `.claude/.ai/business_rules.md` §1.3 · §1.4 | Sequências imutáveis |
| `.claude/.ai/business_rules.md` §7 | Fluxo do estafeta (pré-condições por transição) |
| `.claude/.ai/business_rules.md` §4.2 · §4.4 | Tokens atribuídos em `delivered` |
| `.claude/.ai/business_rules.md` §22 | Notificações push por transição |
| skill `state_validator/rules.md` | Policy — complemento desta skill |
| skill `guardian` | Alerta se transição faz `setState` após await sem mounted |

**NOTA:** skill consulta, nunca modifica. Cada transição deve bater todos os items do checklist antes de aprovar.

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber** faz "Pre/Post Condition Checks" em cada transição do Trip State Machine — assertion formal em código + validação server-side. Falha de invariante → rollback automático.
>
> **iFood** tem "Status Event Sourcing" — cada transição é um evento auditável com pré-condições declaradas. Serviço de orders valida contra event log antes de aplicar.
>
> **Glovo** usa "Contract Tests" entre componentes (mobile ↔ backend) — cada transição tem contract fixo que impede mobile e backend de divergirem.
>
> **Bora App equivalente:** `state_validator/validation.md` executa checklist por transição, cita BR §X para cada pré-condição. Cobre o papel das três técnicas num único documento, sem automação ainda (opcional futuro: testes unitários por transição, estilo Glovo).

---

## RESPONSABILIDADES

- ✅ Validar estado antes e depois de mudanças
- ✅ Bloquear transições ilegais ou com pré-condições em falta
- ✅ Ancorar cada verificação em BR §X
- ✅ Emitir checklist pós-mudança que o executor deve confirmar

## NÃO PODE FAZER

- ❌ Corrigir o estado incorrecto (reportar + delegar a skill especialista)
- ❌ Executar mudanças no banco
- ❌ Modificar ficheiros (é read-only)

## FRONTEIRAS

| Situação | Skill correta |
|---|---|
| Validar transição de estado passo a passo | **state_validator/validation.md** (eu) |
| Política e regras de estado (FSM imutável) | `state_validator/rules.md` |
| Saúde geral do sistema | `system_validator` |
| Checklist técnico de código | `guardian` |

## RULES

- Sequência INVIOLÁVEL: `created → preparing → callingDriver → driverAccepted → pickedUp → onTheWay → delivered` (BR §1.3)
- Reserva: sequência BR §1.4 · §14.8
- Qualquer transição fora dessas sequências é bloqueada
- Todo veredicto cita BR §X
- Source of truth: `.claude/.ai/business_rules.md` v2
