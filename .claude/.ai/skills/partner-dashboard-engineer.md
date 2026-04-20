---
name: partner-dashboard-engineer
description: Use this skill when the user says "SKILL: partner-dashboard-engineer", or when work touches the partner panel — live orders, menu management, reservations toggle, takeaway, vendor settings. Triggers on any edit to lib/screens/partner/** or partner flows.
version: 1.0.0
protection_mode: read-only
---

> **MODO PROTECÇÃO:** read-only. Esta skill planeia o painel do parceiro — nunca edita `pricing_service.dart`, `dispatch-engine` ou triggers. Toggles visuais controlam colunas DB documentadas em BR §14.10.

# PARTNER DASHBOARD ENGINEER

## ROLE
Especialista no painel do parceiro (restaurante / loja). Desenha UX e lógica para gestão de pedidos ao vivo, cardápio digital, reservas de mesa e takeaway.

---

## EXEMPLOS WORKED

### Exemplo 1 — Parceiro abre dashboard

**Input (contexto real):**
Parceiro "Pizzaria Romana" abre `lib/screens/partner/partner_home_screen.dart`. Tem 3 pedidos em curso, 2 reservas pendentes, menu com 42 pratos, e o toggle `reservations_enabled` está a `true`.

**Processo:**
1. Consultar BR §14 · §14.10 · §15 → painel deve conter:
   - Pedidos ao vivo (live feed ordenado por status)
   - Reservas pendentes (BR §14.7)
   - Menu / cardápio digital (BR §14.3)
   - Toggle "Activar reservas de mesa" (BR §14.10) — **crítico**
   - Estatísticas básicas (BR §14.7: reservas mensais, receita, no-shows)
2. Realtime via `partners_orders_channel` (padrão de `orders_channel` em BR §1.3).
3. Confirmar que cada pedido exibe: nome cliente, items, observações por prato (BR §14.2 "sem cebola, molho à parte"), hora pedido, status.
4. Confirmar que o toggle `reservations_enabled` é visível e clicável — sem ele, parceiros sem mesas ficam obrigados a receber reservas.

**Output esperado:**
```
✅ PLANO PARTNER DASHBOARD — BR §14 · §14.10 · §15
Secções: [pedidos_live, reservas_pendentes, menu, toggle_reservations, stats_mensais]
Realtime: partners_orders_channel + reservations_channel
Toggle reservations_enabled: SIM (UI → UPDATE restaurants.reservations_enabled)
Delegar a: executor (screens + stores + realtime subscription)
```

**Failure mode:**
Falha se esquecer o toggle `reservations_enabled` — parceiros sem mesa ficariam com reservas ligadas por defeito. Falha se expor à UI valores de pricing (markup é invisível por BR §2.4).

---

### Exemplo 2 — Parceiro activa reservas de mesa

**Input (contexto real):**
Parceiro "Café do Mercado" nunca teve reservas activas. Agora quer experimentar. Carrega no toggle "Activar reservas de mesa" no painel.

**Processo:**
1. Consultar BR §14.10 → acção é `UPDATE restaurants SET reservations_enabled = true WHERE id = {partner_id}`.
2. Imediatamente:
   - Botão "Reservar mesa" passa a aparecer na página do restaurante no lado cliente
   - Cliente pode escolher número pessoas, data, hora (slots 30min — BR §14.4), tipo refeição
   - Parceiro passa a receber notificações de reservas pendentes (BR §14.7)
3. Se toggle vai a `false` novamente:
   - Botão desaparece imediatamente
   - Reservas já aceites continuam válidas (não cancela existentes)
   - Parceiro só não aceita novas
4. Guard do lado cliente: `RestaurantModel.reservationsEnabled` deve ser respeitado no `restaurant_detail_screen.dart` antes de mostrar o botão.

**Output esperado:**
```
✅ PLANO TOGGLE RESERVATIONS_ENABLED — BR §14.10
Acção DB: UPDATE restaurants SET reservations_enabled = {bool}
Efeito UI cliente: botão "Reservar mesa" aparece/desaparece realtime
Efeito existente: reservas já aceites mantidas (não cascateia)
Guard cliente: restaurant_detail_screen.dart só mostra botão se reservations_enabled = true
Delegar a: executor (migration nova sessão + UI + realtime)
```

**Failure mode:**
Falha se toggle cancelar reservas já aceites — isso viola confiança do cliente. Falha se guard cliente não respeitar o flag (botão aparecia quando parceiro já desligou).

---

## REFERÊNCIAS BORA APP

| Recurso | Utilidade |
|---|---|
| `lib/screens/partner/` (pasta inteira) | Ecrãs do painel parceiro |
| `lib/screens/partner_reservations_screen.dart` | Lista reservas pendentes + timeline dia |
| `lib/models/restaurant_model.dart` | Adicionar campo `reservationsEnabled` quando migration criada |
| `lib/stores/restaurant_store.dart` · `partner_product_store.dart` | State management do menu + toggle |
| `.claude/.ai/business_rules.md` §14 · §14.10 | Cardápio digital + toggle reservas |
| `.claude/.ai/business_rules.md` §15 | Onboarding parceiro (IBAN, NIF, documentos) |
| `.claude/.ai/business_rules.md` §16 | Painel admin aprova parceiros antes de dashboard ser acessível |
| skill `partner-onboarding` | Fluxo entrada parceiros novos |
| skill `admin-panel-engineer` | Admin aprova antes de dashboard activar |
| skill `notifications-engineer` | Notify parceiro em novos pedidos/reservas |

---

## BENCHMARK UBER / IFOOD / GLOVO

> **Uber Eats Restaurant Manager** — app dedicada iOS/Android + web portal. Features: orders live, menu builder com fotos, hours editor, items 86'd (esgotado), promotions. Toggle de "Accepting orders" pausa novos sem cancelar existentes — exactamente o modelo do `reservations_enabled` de BR §14.10.
>
> **iFood Gestor** — web + app. Forte no "prep time editor" (parceiro ajusta tempo de preparação em tempo real). Integração POS directa para restaurantes grandes.
>
> **Glovo Partner** — foco em ops fleet: vê estafeta atribuído, tempo de espera, rating live. Menu é editado num CMS web separado.
>
> **Bora equivalente:** BR §14 + §14.10 ganha em oferecer **3 modalidades na mesma página** (delivery, takeaway, reserva) — nenhum concorrente tem reserva integrada na Guarda. Toggle é diferenciador: parceiros sem mesa não perdem nada activando apenas delivery.

---

## RESPONSABILIDADES

- ✅ Desenhar painel com 5 secções (pedidos, reservas, menu, stats, toggle)
- ✅ Garantir toggle `reservations_enabled` visível e com efeito imediato
- ✅ Realtime de pedidos e reservas via canal Supabase
- ✅ Menu digital: CRUD de pratos com foto, preço, categoria, disponibilidade horária (BR §14.3)
- ✅ Suporte a 3 respostas a reservas: aceitar / sugerir alternativa / recusar (BR §14.4)
- ✅ Botão "Marcar sentado" → `customer_arrived` (BR §14.8)

## FRONTEIRAS

| Situação | Skill correcta |
|---|---|
| UI/UX painel parceiro, menu, reservas, toggle | **partner-dashboard-engineer** (eu) |
| Onboarding de parceiro novo (IBAN, aprovação) | `partner-onboarding` |
| Admin aprova candidatura antes do dashboard | `admin-panel-engineer` |
| Notificações push parceiro | `notifications-engineer` |
| Cancelamento de reserva (BR §14.5 refund €3) | `cancellation-engineer` |
| Pré-pagamento €3 Stripe | `payment_manager` |
| Pricing / markup 10+5+5 | **intocável** (`pricing_service.dart`, BR §25.3) |

## NÃO PODE FAZER

- ❌ Expor markup ou comissão ao parceiro na UI (é invisível — BR §2.4)
- ❌ Criar migration DB nesta sessão (sessão dedicada quando implementar toggle)
- ❌ Tocar em `dispatch-engine` (takeaway bypass pertence à skill que orquestra dispatch)
- ❌ Editar `pricing_service.dart`
- ❌ Cobrar ao parceiro sem passar por `payment_manager`

---

## RULES

- Source of truth: `.claude/.ai/business_rules.md` v2 §14 · §14.10 · §15 · §16
- Cada feature → `(BR §X.Y)`
- Toggle `reservations_enabled` é crítico: sem ele, parceiros sem mesa recebem reservas por defeito (bug de UX grave)
- Ordem canónica: `decision_engine` → **partner-dashboard-engineer** → `state_validator` → `guardian` → `executor`
- Nunca desligar realtime de pedidos sem escalar — parceiro cego = pedidos perdidos
