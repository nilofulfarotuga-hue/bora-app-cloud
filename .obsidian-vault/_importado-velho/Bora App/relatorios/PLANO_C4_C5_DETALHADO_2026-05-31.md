# 📐 PLANO DETALHADO — C4 (Substituição) · C5 (Entrega agendada)
> Data: 2026-05-31 · Modo: PROTECÇÃO TOTAL · **NADA editado** (só análise). Aprovação do Danilo antes de implementar.
> Verdade confirmada por MCP: `orders.substitution_responses` existe (reativo via chat); **NÃO** existe `allow_substitution`; **NÃO** existe `scheduled_for`/`deliver_at`.

═══════════════════════════════════════════
## C4 — Preferência de substituição no checkout
═══════════════════════════════════════════

### Estado atual (confirmado)
- Existe substituição **REATIVA**: estafeta na loja propõe via chat (`MessageType.substitution`), cliente aprova/rejeita item-a-item (`orders.substitution_responses` Map). Falta a **preferência PROATIVA** definida no checkout.

### 1. Migration exata (proposta — NÃO aplicar)
**Decisão de granularidade:** **por pedido** (1 default), não por item. Glovo/Uber/iFood usam um default único por pedido (3 opções), com o ajuste fino item-a-item a acontecer depois via chat (que já temos). Por-item em `order_purchase_items_v2` seria UX má no checkout (escolher por cada produto) e duplicaria o chat.

```sql
-- Migration proposta (NÃO aplicada)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS substitution_policy TEXT
  CHECK (substitution_policy IN ('substitute','no_substitute','contact'));
-- default NULL = comportamento atual (contact via chat) para apps antigas.
COMMENT ON COLUMN public.orders.substitution_policy IS
  'Preferência proativa do cliente p/ substituições em storeShopping: '
  'substitute=trocar por similar | no_substitute=reembolsar | contact=perguntar no chat (default).';
```
- `create_order` passa a ler `p_input->>'substitution_policy'` e gravar a coluna (mudança pequena, **não** toca pricing — é um campo informativo).

### 2. UI checkout
- **Onde:** `payment_method_screen.dart` (ou `cart_screen.dart`), **só quando** `serviceType == storeShopping` (mercados). Não aparece em restaurante/encomenda/levar-compras.
- **Componente:** 3 `RadioListTile` (ou segmented) num card: "Substituir por similar" · "Não substituir (reembolsar)" · "Contactar-me primeiro" (default).
- Liga a `cart` → `finishOrder(substitutionPolicy:)` → `createOrder(substitutionPolicy:)` → input `substitution_policy`.

### 3. Ligação ao fluxo do estafeta (complementa, NÃO substitui o chat)
- O `substitution_responses` reativo **mantém-se** para o ajuste caso-a-caso.
- A `substitution_policy` é o **default** que reduz fricção:
  - `no_substitute` → no fluxo V2 (`driver_map_screen`), o botão "Não tem" marca indisponível **direto** (sem chat).
  - `substitute` → estafeta pode substituir até ao **threshold €5 já existente** (Decisão J) **sem chat**; acima do threshold continua a exigir chat (regra atual intacta).
  - `contact` → comportamento atual (sempre chat).
- **Sem conflito:** a policy decide o *default*; o chat continua a ser o canal quando é preciso confirmar. O threshold €5 e o `substitution_responses` ficam intactos.

### 4. Zonas tocadas · risco
- ⚠️ **storeShopping V2** (`driver_map_screen` finalize) — lógica de decisão do estafeta.
- Estrutura do pedido (nova coluna) + migration DB.
- **NÃO toca** pricing/Stripe/tokens/dispatch. **Risco: MÉDIO** (o cuidado é não contradizer o threshold €5 nem o fluxo de chat).

### 5. Divisão de trabalho
| Parte | Quem |
|---|---|
| Migration `substitution_policy` + `create_order` lê/grava | **Claude.ai (MCP)** |
| Flutter: UI checkout + `cart_store`/`order_store`/`order_model` + leitura no `driver_map_screen` | **Claude Code** |

### 6. Admin
- `admin_order_detail_screen` deve **mostrar** a `substitution_policy` do pedido (read-only) para suporte perceber decisões de substituição. Registar (não construir agora).

### 7. Recomendação honesta
🟡 **Pós-lançamento (logo a seguir).** Dá para fazer com segurança, mas **toca o fluxo V2** do estafeta — zona sensível de settlement. Como a substituição reativa via chat **já cobre o caso de segurança** (o cliente decide quando há substituição), isto é uma melhoria de UX, não um bloqueador. Fazer com calma + teste E2E real do fluxo storeShopping.

═══════════════════════════════════════════
## C5 — Entrega agendada (scheduled delivery)
═══════════════════════════════════════════
> A mais pesada. Toca **dispatch + Stripe + lifecycle** (3 zonas proibidas). Avaliação sem otimismo.

### 1. Modelo de dados (proposta — NÃO aplicar)
```sql
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ NULL,        -- hora alvo de entrega
  ADD COLUMN IF NOT EXISTS dispatch_released BOOLEAN NOT NULL DEFAULT TRUE; -- false = agendado, ainda não entra no dispatch
```
- `scheduled_for NULL` + `dispatch_released TRUE` = pedido normal "asap" (comportamento atual — zero impacto).
- Agendado: `scheduled_for = <futuro>`, `dispatch_released = FALSE`.
- **Estado novo no lifecycle?** Duas opções:
  - (A) **Sem novo estado** — manter `status='created'` mas com `dispatch_released=FALSE` a impedir o avanço. **Menos invasivo no `OrderStatus` enum** (preferível).
  - (B) Novo `OrderStatus.scheduled` antes de `created` — mais limpo semanticamente mas mexe no enum core (`_statusFlow` em `order_store` + todos os switches). **Mais risco.** → **Recomendo (A).**

### 2. Dispatch (ZONA PROIBIDA — só descrever)
- Hoje: `create_order` → trigger avança para `callingDriver` → `fn_dispatch_on_calling_driver`/`invoke_dispatch_engine` (HTTP → Edge `dispatch-engine`).
- Agendado: o pedido **não pode** ir a `callingDriver` à criação. Mecanismo de **release**:
  - Novo **pg_cron** (ex. a cada 1-2 min) que faz: `SELECT orders WHERE scheduled_for IS NOT NULL AND NOT dispatch_released AND scheduled_for - now() <= '<lead_time>'` → marca `dispatch_released=TRUE` e injeta no fluxo normal (preparing→callingDriver).
  - **O `dispatch-engine` em si NÃO muda** — continua a despachar quando é chamado. O que muda é **quando** o pedido entra. ✅ isto isola a mudança do motor.
  - 🔴 **Risco para pedidos imediatos:** o trigger de dispatch e o novo cron têm de filtrar **explicitamente** `dispatch_released`/`scheduled_for` para **nunca** atrasar um pedido asap. Precedente de alerta: o cron `bora_dispatch_maintenance` **falha 97.8%** hoje (bug `extensions.net.http_post`) — **adicionar outro cron perto do dispatch é arriscado enquanto esse não estiver são.**
- **Lead time** (quanto antes libertar): configurável em `platform_settings` (ex. `scheduled_lead_minutes=20`).

### 3. Pagamento (ZONA PROIBIDA — só descrever)
- Duas opções:
  - **(A) Cobrar no momento do agendamento** (recomendado): bloqueia o preço, simples, consistente com o fluxo atual. Risco: cliente paga já por algo que recebe mais tarde (normal em Glovo/Uber agendado).
  - (B) Pré-autorizar e capturar na hora: a autorização Stripe vale ~7 dias; permite ajustar valor, mas adiciona complexidade (captura diferida, expiração, price-change). **Mais risco.**
- → **Recomendo (A)**, mas é decisão de negócio. Toca `create-payment-intent`/`stripe-webhook` (forbidden) — não implementar sem desenho dedicado.

### 4. Horários da loja
- Validar `scheduled_for` dentro do horário da loja: já existe `business_hours` + `isOpenNow()`; falta um **`isOpenAt(DateTime)`** + geração de **slots** (ex. 30 min) só dentro do horário. UI de date/time picker limitada a slots válidos.

### 5. Cancelamento / no-show
- Janela de cancelamento sem taxa para agendados (ex. até X h antes) — nova regra de negócio.
- Edge cases: loja fecha entretanto, sem estafetas no slot, stock/preço muda até à hora → política de fallback (notificar + reembolsar) a definir.

### 6. Esforço realista · dependências
- **Esforço: GRANDE — ~5 a 8 dias** com teste E2E real (driver + pagamento reais).
- **Dependências:** (a) o cron de dispatch tem de estar **são** primeiro (bug `bora_dispatch_maintenance` resolvido); (b) decisões de negócio sobre pagamento/cancelamento; (c) idealmente depois da feature de distância de estrada (para o preço agendado ser fiável).

### 7. Admin
- Novo ecrã/secção: **fila de pedidos agendados** (próximos slots), com ver/cancelar/forçar-release. Registar como parte do scope (não construir agora).

### 8. Recomendação final (sem otimismo)
🔴 **PÓS-LANÇAMENTO, obrigatório.** Mexe no **coração do negócio** (dispatch) + pagamento + lifecycle, com um cron de dispatch que **já está a falhar** hoje. O risco de partir o fluxo imediato (que é o que faz dinheiro no dia 1) não justifica fazer antes do launch. É uma feature de **Fase 2** com desenho dedicado próprio — tratar como projeto separado, não como "mais uma feature".

═══════════════════════════════════════════
## RESUMO
| Feature | Migration? | Zonas | Risco | Esforço | Quando |
|---|---|---|---|---|---|
| **C4 Substituição** | sim (`substitution_policy`) | storeShopping V2 | MÉDIO | 1-2 dias | 🟡 pós-launch (logo a seguir) |
| **C5 Entrega agendada** | sim (`scheduled_for`+`dispatch_released`) | dispatch + Stripe + lifecycle | ALTO | 5-8 dias | 🔴 pós-launch obrigatório (Fase 2) |
