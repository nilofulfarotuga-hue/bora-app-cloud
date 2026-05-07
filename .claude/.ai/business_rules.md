# BORA APP — REGRAS DE NEGÓCIO v2

**Versão:** 2026-04-17
**Projeto:** Bora App — Plataforma de Entregas, Restauração e Serviços (Guarda, Portugal)
**Stack:** Flutter + Supabase
**Contacto:** +351 937 501 673 · boraappbora@gmail.com
**Logótipo:** "B" verde escuro (#1B5E20) + motociclista vermelho/laranja

---

## 1. ESTRUTURA GERAL DA PLATAFORMA

### 1.1 Tipos de Utilizador
- **Cliente** — faz pedidos/reservas, paga, recebe entregas ou serviços
- **Estafeta (Driver)** — aceita pedidos, faz recolha e entrega
- **Empregada de Limpeza** — presta serviços de limpeza (futuro)
- **Parceiro** — restaurante/loja com acordo comercial
- **Admin** — Danilo (único por agora)

### 1.2 Tipos de Serviço
- `restaurant` — restaurante parceiro (saco pronto para recolha)
- `storeShopping` — compra no mercado (estafeta compra por conta do cliente)
- `carryGroceries` — levar compras que o cliente já fez (requer carro)
- `sendPackage` — enviar encomenda de A para B
- `restaurantReservation` — reserva de mesa em restaurante parceiro (lançamento)
- `restaurantTakeaway` — cliente vai buscar ao restaurante (lançamento)
- `homeCleaning` — limpeza de casa (futuro, ver secção 18)
- `marketplace` — compra internacional (futuro, ver secção 17)

### 1.3 Progressão de Status do Pedido (Delivery)
`created` → `preparing` → `callingDriver` → `driverAccepted` → `pickedUp` → `onTheWay` → `delivered`

### 1.4 Progressão de Status da Reserva de Mesa
`reservation_requested` → `restaurant_responding` → (`accepted` | `suggested_alternative` | `rejected`) → `confirmed` → `customer_arrived` → `completed` ou `no_show`

---

## 2. TAXAS E PREÇOS (DELIVERY LOCAL)

### 2.1 Taxa de Entrega (cliente paga)
- Até 4 km: **€2,50**
- Acima de 4 km: **€2,50 + €0,50 por km adicional**

### 2.2 Taxa de Serviço (CONFIRMADO via MCP — Sessão 2 · 2026-05-03)

| Tipo de pedido | Taxa de serviço (cliente paga) | Fonte |
|---|---|---|
| **Parceiro** (restaurant + storeShopping com `is_partner_store=true`) | **5% × subtotal** | `client_service_fee_pct = 0.05` |
| **Não-parceiro** (restaurant + storeShopping com `is_partner_store=false`) | **€2,50 FIXO** (não percentagem) | `delivery_base_fee_cents = 250` |
| **Logística** (carryGroceries / sendPackage) | Incluída no `packageFee` (sem taxa separada) | — |

> ⚠️ Confundir parceiro vs não-parceiro = erro grave. Verificar SEMPRE `is_partner_store`.

### 2.2.1 Pagamento ao Estafeta (driver_earnings)

| Caso | Fórmula | Notas |
|---|---|---|
| **Parceiro** (rest. + retail) | `€3,80 + €0,20×km + apt + (stacking? €3 : 0)` | SEM €0,80, SEM 30% lucro Bora |
| **Não-parceiro `storeShopping`** | `€3,80 + €0,80 + €0,20×km + apt + 30%×boraNet` | €0,80 porque estafeta compra E entrega |
| **Não-parceiro `restaurant`** | `€3,80 + €0,20×km + apt + 30%×boraNet` | SEM €0,80 (não compra) |
| **Logística** (carryGroceries / sendPackage) | `€4,00 + €0,50×km + €0,80 + apt` | Base mais alta + €0,80 sempre |

`boraNet = (subtotal×0,15 + deliveryFee + serviceFee) − driverFixed`

### 2.3 Entrega no Apartamento
- Surcharge adicional de **+€1,50** quando cliente ativa
- Divisão: **€1,00 estafeta / €0,50 Bora**

### 2.4 Markup nos Produtos (Delivery Local)
**Parceiro** (total 20% em 3 camadas):
- 10% comissão cobrada ao parceiro
- +5% adicional no preço do produto (invisível, cliente não percebe)
- +5% taxa de serviço ao cliente

**Não-Parceiro:** 15% sobre o preço (invisível, lucro da Bora)

### 2.5 Sacos de Transporte (Sessão 3 · 2026-05-04)

| Cenário | Quem cobra | Quando | Valor |
|---|---|---|---|
| Restaurante **parceiro** | — | — | €0 (parceiro absorve) |
| Restaurante **não-parceiro** | Cliente no checkout | Imediato (RPC `create_order`) | **€0,30 fixo** |
| Mercado **parceiro** (storeShopping) | — | — | €0 (parceiro absorve) |
| Mercado **não-parceiro** (storeShopping) | Estafeta no fim da compra | Pós-finalização (RPC `finalize_storeshopping_purchase`) | **€0,10 × sacos reais** (cap 5 sacos = **€0,50 max**) |

#### Cobrança pós-entrega (mercado não-parceiro)

```
Estafeta finaliza compra (slider 0..5 sacos)
                 ↓
RPC finalize_storeshopping_purchase
   • cap valida 0 ≤ bag_count ≤ 5; >5 → RAISE EXCEPTION
   • bag_fee = bag_count × €0,10
   • Recalcula final_total
                 ↓
   ┌─────────────┴─────────────┐
payment_method = card/mbway   payment_method = cash
   • marca payment_status        • UPDATE orders SET cash_total_due
     = 'extraRequired'             = COALESCE(cash_total_due, final_total)
   • Sessão 3B implementa        • Estafeta vê banner "RECEBER €X EM
     charge automático             DINHEIRO" + "inclui +€Y de sacos"
     off_session via              ([driver_map_screen.dart](lib/screens/driver_map_screen.dart))
     pending_charges
```

#### Status checkpoint B3→B4 (decisão CEO-AI · 2026-05-04)

- **B4 ADIADO** para Sessão 3B (charge automático off_session)
- **Bloqueio técnico real**: `setup_future_usage` propositadamente OMISSO em
  `create-payment-intent` ("cartão nunca gravado sem consent"); sem
  `stripe_customer_id`/`stripe_payment_method_id` em `orders`
- **Sessão 3B** (futura): rewrite `charge-extra` off_session + webhook handler
  `metadata.reason='market_bags'` + drenagem `pending_charges` (cron ou pg_net)
- **Sessão 3C** (futura): consent flow checkout (UI + DB schema +
  `setup_future_usage='off_session'`)
- **Política Uber/Glovo** (referência): charge automático pós-entrega com
  idempotency-key `${order_id}_bags`; SCA recusa → push retry; cap €0,50

#### Tabela técnica

- Constants: `BRBags.MARKET_BAG_FEE = 0.10`, `BRBags.RESTAURANT_BAG_FEE = 0.30`
  ([lib/config/business_rules.dart](lib/config/business_rules.dart))
- DB cap: `pending_charges.amount_cents BETWEEN 1 AND 50` (Sessão 3 migration)
- DB column: `orders.cash_total_due NUMERIC NULL` — NULL = usar `final_total`
- Pedidos legado `bag_count > 5`: 0 (validado Sessão 3 Fase A)

### 2.6 Fonte autoritativa do pricing (Sessão 2 · 2026-05-03)

- **RPC `pricing_calculate` (server-side)** = ÚNICA fonte autoritativa. Lê `platform_settings`:
  `driver_base_fee_cents=380`, `driver_per_km_cents=20`, `driver_surcharge_cents=80`,
  `driver_profit_share_pct=0.30`, `delivery_base_fee_cents=250`,
  `client_service_fee_pct=0.05`, `partner_visible_commission_pct=0.10`,
  `partner_hidden_markup_pct=0.05`, `non_partner_markup_pct=0.15`,
  `bag_fee_restaurant_cents=30`, `bag_fee_supermarket_per_bag_cents=10`.
- **`OrderStore.createOrder`** ([lib/stores/order_store.dart:714-769](lib/stores/order_store.dart#L714-L769))
  invoca `create_order` RPC e popula `OrderModel` integralmente a partir do `rpcData`
  (`service_fee`, `driver_earnings`, `platform_commission`, `bag_fee`, `payment_buffer_total`).
- **`PricingService.calculateBreakdown`** ([lib/services/pricing_service.dart](lib/services/pricing_service.dart))
  é classificado **PREVIEW-ONLY [X]**: usado só para estimativa UX no carrinho e payment_method;
  os valores finais do pedido não dependem deste cálculo. Mesmo assim, fórmulas Flutter
  são byte-equivalentes às RPC (validado Sessão 2 — divergência esperada €0,00 nominal).

---

## 3. PAGAMENTOS

### 3.1 Métodos Aceites
- Cartão de crédito/débito (Stripe)
- MBWay
- Dinheiro

### 3.2 Limite de Dinheiro
- **Máximo €40,00** por pedido
- Validação em duas camadas: Flutter + trigger DB

### 3.3 Buffer Stripe 15% (cartão em não-parceiros)
Pré-autorização de **+15% a mais** do valor estimado.

**Finalidade:** cobrir variações do preço final (produto em falta, troca por similar).

**Importante:** cliente não perde este dinheiro. É libertado automaticamente após a compra real.

**Aviso obrigatório ao cliente antes de pagar:**
> "Reservámos no teu cartão 15% a mais do valor estimado, por segurança. Se algum produto estiver em falta, o estafeta pode trocá-lo por outro de preço parecido. Pagas apenas o valor real — o extra é libertado do teu cartão."

**Trocas em caso de falta:**
- Estafeta pergunta ao cliente pelo chat primeiro
- Se cliente não responder, estafeta pode trocar sozinho por produto de preço parecido
- Estafeta usa os 15% de reserva para cobrir diferenças

### 3.4 Pagamento ao Estafeta
- Automático semanal, segunda-feira às 3h (`bora_weekly_auto_payout`)
- Valor mínimo para processar: **€10,00** (abaixo acumula para a semana seguinte)

---

## 4. SISTEMA DE TOKENS

### 4.1 Valor e Conversão
- **100 tokens = €0,50**
- Validade: **60 dias**
- Consumo: **FIFO** (primeiros a entrar, primeiros a sair)

### 4.2 Como se Ganham Tokens

| Quem | Quando | Quantidade |
|---|---|---|
| Estafeta | Por entrega | **+40 tokens** |
| Estafeta | Entrega adicional (stacking) | **+50 tokens** |
| Cliente | Por pedido | **3% do valor** em tokens |

### 4.3 Como se Usam Tokens
**Cliente:** desconto até **50% do valor do pedido**

**Estafeta (Prioridade no dispatch):**
- 5 min → 50 tokens
- 10 min → 90 tokens
- 15 min → 125 tokens
- 1 hora → 400 tokens

**Estafeta:** converter em € no pagamento semanal

### 4.4 Tabelas e Triggers
- Tabela: `bora_tokens`
- Trigger: `trg_award_tokens_on_delivery`
- **Constraint:** `amount INTEGER CHECK (amount > 0)` — saldo negativo virtual **não** suportado.
  Para reduzir saldo de um utilizador, usar `admin_revoke_token_grant(token_id, reason)` em
  grants específicos (audit trail mais limpo). Grants individualmente revogados ficam
  marcados `is_used=true` e deixam de contar para o balance.

### 4.5 Gorjetas (Tips)
- Cliente pode dar gorjeta na altura de pagar **ou** depois da entrega (ao avaliar)
- Valores sugeridos: **1€ · 2€ · 3€ · 5€** + campo livre
- Divisão: **80% estafeta, 20% Bora**

---

## 5. REMUNERAÇÃO DO ESTAFETA

### 5.1 Cálculo por Entrega
- Base: **€3,80**
- Distância: **+€0,20 por km**
- Taxa de entrega: **+€0,80**
- Parceiro: **+€3,00 adicional** por entrega parceira

### 5.2 Driver Help (ajudante)
**Quando:** só em mercados e restaurantes **não-parceiros**

**Quem pede:** o estafeta principal carrega no botão "Preciso de ajuda" na app

**Quem ajuda:** dispatch normal escolhe o estafeta mais próximo (40s para aceitar)

**Quanto ganha o ajudante:** **€4** fixos

**De onde sai:** do ganho do estafeta principal (não é custo extra para a Bora)

**Exemplo:** Compra de 150€ no mercado. Principal ia ganhar 12€ sozinho. Com ajuda: principal recebe 8€, ajudante recebe 4€.

### 5.3 Pagamento Semanal
- Processado segunda-feira às 3h
- Mínimo €10 para processar (abaixo acumula)
- Transferido para o IBAN cadastrado

---

## 6. DISPATCH (ATRIBUIÇÃO DE PEDIDOS)

### 6.1 Arquitetura Geral
- Motor: **Edge Function** `dispatch-engine` (v31)
- Accionado por pg_cron (cada minuto) E imediatamente quando:
  - Novo pedido entra em `callingDriver`
  - Estafeta liga online
  - Estafeta recusa ou o timeout expira

### 6.2 Algoritmo de Seleção (ordem)
1. **SLA Crítico primeiro** (pedido com ≥7 minutos em espera)
2. **Não-parceiro primeiro** (`is_partner_store = false` tem prioridade)
3. **FIFO geográfico:** se há drivers a ≤200m do pickup, o mais próximo ganha
4. **Distância:** se nenhum a ≤200m, escolhe o mais próximo em ≤10km
5. **Prioridade:** drivers com `priority_until` ativo são preferidos

### 6.3 Timeout de Oferta
- **40 segundos** para o estafeta aceitar ou recusar
- Se não responder → próximo driver
- Driver recusante entra em `tried_driver_ids`
- Se todos tentados → reset do ciclo

### 6.4 Stacking (Múltiplos Pedidos)
- **Máximo 3 pedidos** em simultâneo por estafeta
- Oferecidos **1 de cada vez** — nunca 2 diálogos simultâneos
- Critério para juntar pedidos (batching): distância ≤ **3 km** entre lojas

### 6.5 Guard Anti-Duplicação (v31)
- `findNextDriver()` exclui drivers com oferta ativa noutro pedido
- `assignDriver()` usa lock optimista (UPDATE com WHERE guards)

### 6.6 Rota Multi-Stop
- **Sequência obrigatória:** TODOS os pickups primeiro, depois TODOS os dropoffs
- Exemplo com 3 pedidos: Loja 1 → Loja 2 → Loja 3 → Cliente 1 → Cliente 2 → Cliente 3
- Quando um pickup é confirmado, os stops são recalculados automaticamente

---

## 7. FLUXO DO ESTAFETA

### 7.1 Oferta de Pedido
Quando há novo pedido próximo, a app do estafeta:
- Toca **som de alerta**
- Mostra **diálogo com timer de 40 segundos**:
  - Nome do estabelecimento
  - Valor do pedido
  - Ganhos estimados
  - Distância
  - Tokens a ganhar
- **Regra crítica:** apenas **1 diálogo de cada vez** — se chegar segundo pedido enquanto há diálogo ativo, é descartado (não se empilha)
- Som para quando o diálogo é fechado (aceitar/recusar/timeout)
- Se diálogo for descartado pelo guard, não toca som

### 7.2 Mapa do Estafeta
- Marcador do estafeta: **seta verde** (#1B5E20) com bearing (direção de movimento)
- Rota desenhada com polylines
- Nome + km de cada stop (ex: "McDonald's · 1,2 km")
- Botão "Navegar" → abre Google Maps externo
- Botão de centralizar → centra câmara no driver
- Câmara roda com bearing (tipo Uber)

### 7.3 Fluxo em Restaurante Parceiro
1. Driver chega ao restaurante
2. Clica "Confirmar recolha" (saco já pronto)
3. Status → `pickedUp`
4. App dirige para o cliente
5. Entrega → **código de 4 dígitos** (cliente mostra o código)
6. Status → `delivered`

### 7.4 Fluxo em Não-Parceiro (mercado/loja sem acordo)
1. Driver chega ao estabelecimento
2. Abre checklist ("Ver compras")
3. Marca cada item: "Comprado" ✅ ou "Não há" ❌
4. Pode adicionar produtos extra (com preço)
5. Define número de sacos (€0,10 cada)
6. Clica "Confirmar compra"
7. Diálogo "Valor da compra" → driver preenche valor real do caixa
8. Confirma → `isPurchaseFinalized = true`, `finalTotal` guardado
9. **Só agora** aparece "Confirmar recolha"
10. Driver confirma → `pickedUp`
11. App dirige para o cliente
12. Entrega → código 4 dígitos → `delivered`

### 7.5 Fluxo `sendPackage` (enviar encomenda)
- Cliente **tem obrigatoriamente** de tirar foto da encomenda antes de pedir
- Estafeta vê a foto antes de aceitar → evita surpresas de tamanho/peso
- Recolha no ponto A → entrega no ponto B → código 4 dígitos

### 7.6 Fluxo `carryGroceries` (levar compras)
- Cliente já fez as compras
- Cliente **tem obrigatoriamente** de tirar foto das compras antes de pedir
- Estafeta vê a foto antes de aceitar
- **Requer carro** — motas/bicicletas não recebem este tipo de pedido
- Recolha em casa do cliente → entrega no destino → código 4 dígitos

### 7.7 Cancelamento pelo Estafeta
- Pode cancelar em `driverAccepted` ou `pickedUp`
- Diálogo de confirmação: "Cancelar pedido? O pedido volta para o sistema."
- Se confirmar:
  - Status volta a `callingDriver`
  - `assigned_driver_id` → null
  - Driver entra em `tried_driver_ids`
  - Dispatch re-invocado automaticamente
- Implementação: função DB `driver_cancel_order()` com SECURITY DEFINER

---

## 8. FLUXO DO CLIENTE

### 8.1 Fazer Pedido
1. Seleciona categoria (Restaurantes, Supermercados, Farmácia, Enviar Encomenda, Levar Compras, Reservas)
2. Escolhe estabelecimento
3. Adiciona produtos ao carrinho
4. Seleciona método de pagamento
5. Confirma endereço de entrega
6. Opção "Entregar no apartamento" (+€1,50)
7. Pode aplicar desconto de tokens (até 50%)
8. Pode adicionar gorjeta (1€/2€/3€/5€ ou valor livre)
9. "Finalizar pedido"

### 8.2 Acompanhamento
Ecrã "Estafeta a caminho" mostra:
- Mapa com posição do estafeta
- Nome e rating do estafeta
- Código de entrega (4 dígitos)
- Moradas de recolha e entrega
- Total do pedido
- Lista de items (com status: comprado/indisponível)
- Chat com o estafeta

### 8.3 Cancelamento pelo Cliente

| Momento | Taxa |
|---|---|
| Antes do estafeta aceitar | **€1,00** |
| Estafeta a caminho do restaurante | **€2,50** (taxa de entrega) |
| Estafeta já tem a comida/compras | **100%** do pedido (sem devolução) |

### 8.4 Reembolso por Falha de Serviço
Quando o serviço falha (estafeta não chegou, comida errada, compras estragadas):
- Cliente contacta suporte Bora
- Bora analisa e decide caso a caso
- Pode ser reembolso parcial, total, ou em tokens

#### 8.4.1 Cap server-side (T1.2 / BUG-MN-004 — 2026-04-30)
- `refund_amount` **NUNCA** pode exceder `stripe_charge_cents + wallet_applied_cents + tokens_applied_value_cents`
- Trigger `trg_enforce_refund_cap` em `orders` rejeita com `check_violation` (ERRCODE 23514)
- Erro: `refund_exceeds_paid: refund=X cents > paid=Y cents (stripe=A wallet=B tokens=C)`

#### 8.4.2 Split proporcional para pagamentos mistos
Quando cliente pagou com componentes mistos (wallet + Stripe + tokens):
- RPC `compute_refund_split(order_id, refund_eur)` retorna `wallet_cents`, `stripe_cents`, `tokens_cents`
- Distribuição **proporcional** ao valor pago em cada componente
- Erros de arredondamento vão para Stripe (mais simples)
- Exemplo: pago €6 Stripe + €3 wallet + €1 tokens (€10 total). Refund €5 → wallet €1.50 + tokens €0.50 + Stripe €3.00

#### 8.4.3 Idempotência (TODO follow-up)
- Adicionar `refund_idempotency_key` em `orders` para garantir que retries não duplicam
- Stripe Refund API já é idempotente via `idempotency_key` header — passar order_id+'-'+timestamp
- Pendente: Edge Function `refund` v13 com header `Idempotency-Key`

### 8.5 Histórico de Pedidos
- Tab "Pedidos" carrega imediatamente ao abrir (com spinner)
- Lista todos os pedidos por data
- Clicando → detalhes completos com items, preços e status

### 8.6 Perfil do Cliente
- Nome, email, telefone
- Foto de perfil (opcional, pode adicionar da galeria)
- Histórico de tokens
- Histórico de pedidos
- Histórico de reservas
- Suporte
- Apagar conta (ver secção 20)
- Terminar sessão

---

## 9. SLA (ACORDO DE NÍVEL DE SERVIÇO)

### 9.1 Tempo Base
- SLA base: **10 minutos** desde o pedido até dispatch confirmado
- SLA de alerta (crítico): **7 minutos** — pedido sobe na fila de prioridade

### 9.2 Alertas
- Aos 7 minutos sem driver: pedido marcado como crítico
- Dispatch continua tentando drivers até encontrar
- Admin recebe notificação no painel de pedidos críticos

---

## 10. CATEGORIAS DA APP

### 10.1 Restaurantes (Parceiros)
- Menu gerido pela Bora (parceiro edita no seu painel)
- Markup 10+5+5%
- Saco fixo €0,30
- Podem ter **reserva de mesa** e **takeaway** (ver secção 14)

### 10.2 Restaurantes (Não-Parceiros)
- Driver compra no local
- Markup 15% invisível
- Fluxo de checklist

### 10.3 Supermercados
- Fluxo de `storeShopping` (checklist completo)
- Driver compra os items listados pelo cliente
- Sacos a €0,10 cada

### 10.4 Farmácia
- Fluxo semelhante a supermercado
- Mesma lógica de checklist

### 10.5 Enviar Encomenda (sendPackage)
- Cliente prepara a encomenda
- **Foto obrigatória** antes de pedir
- Driver recolhe e entrega
- Requer veículo adequado ao tamanho

### 10.6 Levar Compras (carryGroceries)
- Cliente já fez as compras
- **Foto obrigatória** antes de pedir
- Serviço `carryGroceries`
- **Requer carro** (não aceita motas ou bicicletas)

### 10.7 Reservas de Mesa
- Nova funcionalidade do lançamento
- Ver secção 14 completa

---

## 11. CADASTRO E APROVAÇÃO DO ESTAFETA

### 11.1 Campos Obrigatórios
- Nome completo
- Email e password
- Telefone
- Tipo de veículo (mota, carro, bicicleta)
- Matrícula (obrigatória exceto bicicleta)
- IBAN português (PT50 + 21 dígitos = 25 caracteres)
- **Foto pessoal (selfie)**
- **Tipo de documento + Número do documento**
- **Foto do documento**
- **Foto do veículo** (obrigatória exceto bicicleta)
- **Aceitação obrigatória dos Termos e Política de Privacidade** (checkbox)

### 11.2 Fluxo de Aprovação
1. Estafeta submete candidatura
2. Status: `pending`
3. Admin revê fotos e documentos no painel
4. Se todos os campos obrigatórios preenchidos → pode aprovar
5. Se faltam campos → aprovação bloqueada com mensagem dos campos em falta
6. Aprovado: `approved` → estafeta pode trabalhar
7. Rejeitado: `rejected` com motivo

### 11.3 Tipos de Veículo e Capacidades

| Veículo | Pode fazer |
|---|---|
| **Mota** | Restaurantes parceiros e não-parceiros, pequenas compras, encomendas pequenas |
| **Carro** | Tudo, incluindo `carryGroceries` e encomendas grandes |
| **Bicicleta** | Entregas pequenas, sem matrícula obrigatória |

### 11.4 Armazenamento de Documentos
- Bucket: `driver-documents` (privado)
- Path: `{userId}/selfie.jpg`, `{userId}/document.jpg`, `{userId}/vehicle.jpg`

---

## 12. CANCELAMENTOS (RESUMO GERAL)

### 12.1 Pelo Cliente (Delivery)
Ver secção 8.3.

### 12.2 Pelo Estafeta (Delivery)
Ver secção 7.7.

### 12.3 Pelo Cliente (Reserva de Mesa)
- **Até 4 horas antes:** reembolso total do pré-pagamento €3
- **Menos de 4 horas antes:** perde os €3
- **No-show (não aparece):** perde os €3

### 12.4 Pelo Restaurante (Reserva)
- Restaurante pode **rejeitar** um pedido de reserva → cliente recebe reembolso total dos €3
- Ver fluxo completo em secção 14

### 12.5 Pelo Admin
- Admin pode cancelar qualquer pedido ou reserva manualmente pelo painel
- Motivo obrigatório no cancelamento (aparece ao cliente)
- Bora decide se há reembolso e quanto

> **Implementado em commit 11c7497 (Fase 4 BUG 3).**
> Gaps documentados: GAP-1 (full refund em pickedUp/onTheWay como decisão Q4 — Bora absorve), GAP-2 (cliente vê mensagem mapeada do reason_code, não o motivo literal), GAP-3 (refund parcial/tokens não suportados). Ver ADR `.claude/.ai/decisions/2026-04-29-fase4-bug3-refund-policy.md`.

---

## 13. AVALIAÇÕES (RATINGS)

### 13.1 Quem Avalia Quem

| Quem avalia | A quem | Público/Privado |
|---|---|---|
| Cliente | Estafeta | Pública (outros clientes não veem, mas o estafeta vê) |
| Cliente | Restaurante parceiro | Pública |
| Estafeta | Cliente | **Privada** (só a Bora vê) |

### 13.2 Formato
- **1–5 estrelas**
- **Etiquetas rápidas:** simpático, rápido, limpo, profissional, denúncia, etc.
- **Comentário opcional**

### 13.3 Regras
- **Opcional** (cliente/estafeta pode saltar)
- Avaliação do cliente pelo estafeta é **privada** — evita vinganças
- **Sem automatismo:** a Bora analisa casos problemáticos manualmente no painel admin (ver secção 16)

### 13.4 Gorjeta Associada
- No ecrã de avaliação, cliente pode dar gorjeta (se ainda não deu no pagamento)
- Ver divisão em secção 4.5

---

## 14. CARDÁPIO DIGITAL + RESERVAS (LANÇAMENTO)

### 14.1 Conceito
Cada restaurante parceiro tem uma **página digital completa** dentro da app, com **3 opções na mesma página:**
- Entrega ao domicílio
- Takeaway (cliente vai buscar)
- Reserva de mesa

**Diferenciação:** nenhuma plataforma na Guarda oferece reserva de mesa integrada. Uber Eats e Glovo só fazem entrega.

### 14.2 Estrutura da Página do Restaurante
- Nome, morada, horários, avaliação média
- Categorias de pratos em scroll horizontal (ex: combos, sushi, massas, menus)
- Cada prato: foto, nome, código, preço, descrição, botão "adicionar ao carrinho"
- Observações por prato: "sem cebola", "molho à parte", etc.

### 14.3 Cardápio Digital
- Restaurante gere totalmente o cardápio no seu painel
- Pode atualizar pratos, preços, fotos e disponibilidade a qualquer momento
- Disponibilidade por horário (ex: menu almoço só aparece 12h–15h)

### 14.4 Fluxo de Reserva de Mesa

**Passo 1 — Cliente pede:**
- Número de pessoas (1 a 8+)
- Data
- Hora (**slots de 30 minutos** — ex: 19:00, 19:30, 20:00)
- Tipo de refeição (almoço / jantar / criança com preço reduzido)
- Nota opcional (aniversário, mesa junto à janela, etc.)
- Cliente paga **€3 de pré-pagamento**
- Status: `reservation_requested`

**Passo 2 — Restaurante recebe notificação e responde:**
Restaurante tem 3 opções:
- **Aceitar** → `confirmed`, cliente recebe push
- **Sugerir outra hora** → `suggested_alternative` (ex: "às 20h estamos cheios, pode ser 20h30?")
- **Recusar** → `rejected`, cliente recebe reembolso total dos €3 automático

**Passo 3 — Se o restaurante sugeriu alternativa:**
- Cliente recebe a sugestão por notificação
- Pode: **aceitar** / **propor outra alternativa** / **desistir** (reembolso total)
- Diálogo continua até acordo ou desistência

### 14.5 Pré-Pagamento €3 (Anti No-Show)
**Se cliente comparece:**
- €3 são descontados da conta final
- Distribuição: **€1 Bora + €2 restaurante** (taxa de serviço + compensação mesa)

**Se cliente cancela até 4 horas antes:**
- Reembolso total ao cliente

**Se cliente cancela com menos de 4 horas OU não aparece:**
- Cliente perde €3
- Distribuição: **€1 Bora + €2 restaurante**

**Se restaurante rejeita o pedido:**
- Reembolso total automático ao cliente

### 14.6 Lembretes Automáticos
- **24 horas antes** → notificação push ao **cliente**: "Lembras-te da tua reserva amanhã às 20h no [Restaurante]?"
- **2 horas antes** → notificação push ao **cliente**: "A tua reserva é daqui a 2 horas. Ainda podes cancelar com reembolso total."
- **30 minutos antes** → notificação ao **restaurante** no painel: "Reserva daqui a 30 min — [nome cliente] ([nº pessoas] pessoas). Prepara a mesa."

### 14.7 Painel do Parceiro — Secção Reservas
- **Reservas pendentes** com:
  - Nome do cliente
  - Histórico na Bora (novo / cliente fiel / nº pedidos)
  - Detalhes (pessoas, data, hora, notas)
  - Confirmação do pré-pagamento
- **Botões:** Aceitar / Sugerir outra hora / Recusar
- **Timeline visual do dia** — todas as reservas organizadas por hora
- **Botão "Marcar sentado"** quando o cliente chega → status `customer_arrived`
- **Resumo mensal:** total de reservas, receita gerada, no-shows

### 14.8 Status da Reserva
`reservation_requested` → `restaurant_responding` → (`accepted` | `suggested_alternative` | `rejected`) → `confirmed` → `customer_arrived` → `completed` ou `no_show`

### 14.9 Takeaway
- Cliente escolhe "Ir buscar" em vez de "Entrega"
- Sem taxa de entrega (€2,50)
- Sem estafeta envolvido
- Cliente recebe notificação quando o pedido está pronto
- Hora estimada visível desde o início

### 14.10 Activação de Reservas pelo Parceiro
- Reservas de mesa são OPCIONAIS — não todos os restaurantes têm mesas
- Por defeito: reservas DESLIGADAS (reservations_enabled = false)
- O parceiro activa/desactiva no seu painel a qualquer momento
- Quando desligado: botão "Reservar mesa" NÃO aparece ao cliente
- Quando ligado: botão "Reservar mesa" aparece na página do restaurante
- Campo na DB: restaurants.reservations_enabled (boolean, default false)
- Só restaurantes com reservations_enabled = true mostram reservas

---

## 15. ENTRADA DE PARCEIROS (ONBOARDING)

### 15.1 Canais para Candidatura
O restaurante/loja pode candidatar-se por 3 vias:
- **Contacto direto:** telefone ou WhatsApp para +351 937 501 673
- **Formulário no site:** www.boraapp.pt/parceiro (quando existir)
- **Na app:** descarregar Bora e escolher "Sou parceiro" no registo

### 15.2 Dados Obrigatórios
- Nome do restaurante/loja
- Morada
- NIF / Nome da empresa
- Nome e telefone do responsável
- Email
- IBAN (para receber pagamentos)
- Foto do espaço / logotipo
- Horário de funcionamento
- Tipo de cozinha (italiana, japonesa, etc.)
- **Aceitação dos Termos e Condições parceiro** (checkbox obrigatório)

### 15.3 Prazo de Aprovação
- **Até 3 dias úteis** para resposta
- Admin revê candidatura no painel e aceita ou rejeita
- Candidato recebe notificação por email

### 15.4 Custo de Entrada
- **Grátis** — parceiro não paga taxa de adesão nem mensalidade
- Bora só ganha com a comissão por pedido (10+5+5%)

---

## 16. PAINEL ADMIN

### 16.1 Acesso
- **Só Danilo** por agora (único admin)
- Futuro: permissões por nível quando houver equipa

### 16.2 Áreas do Painel

**1. Pedidos ao Vivo (mapa global)**
- Vê todos os pedidos em tempo real
- Mapa com posição dos estafetas
- Alertas de SLA crítico

**2. Aprovação de Estafetas**
- Lista de candidaturas pendentes
- Revê fotos, documentos, veículo, IBAN
- Aprovar ou rejeitar com motivo

**3. Aprovação de Parceiros**
- Mesma lógica para restaurantes/lojas
- Prazo 3 dias úteis

**4. Gestão de Parceiros**
- Editar dados de parceiros existentes
- Suspender/ativar parceiro
- Ver histórico de vendas

**5. Ganhos e Pagamentos Semanais**
- Ver próximo payout (segunda-feira 3h)
- Histórico de transferências aos estafetas
- Acerto manual quando necessário

**6. Reclamações**
- Ver e responder a reclamações de clientes
- Decidir reembolsos caso a caso

**7. Avaliações Baixas**
- Lista de estafetas e parceiros com média < 3 estrelas
- Rever comentários privados
- Decidir ações (avisar, suspender, despedir)

**8. Gestão de Tokens**
- Dar tokens grátis a utilizadores (compensação, campanhas)
- Ver balance de todos os utilizadores
- Auditoria de transações

**9. Relatórios e Estatísticas**
- Pedidos por dia/semana/mês
- Receita total e por categoria
- Zonas mais quentes
- Conversão, ticket médio, etc.

**10. Bloquear/Suspender Utilizadores**
- Suspender cliente, estafeta ou parceiro
- Motivo obrigatório
- Notificação automática

**11. Cancelamento Manual de Pedidos**
- Admin pode cancelar qualquer pedido ativo
- Motivo obrigatório (aparece ao cliente)
- Decide reembolso manualmente

> **Implementado em commit 11c7497 (Fase 4 BUG 3).**
> Gaps documentados: GAP-1 (full refund em pickedUp/onTheWay como decisão Q4 — Bora absorve), GAP-2 (cliente vê mensagem mapeada do reason_code, não o motivo literal), GAP-3 (refund parcial/tokens não suportados). Ver ADR `.claude/.ai/decisions/2026-04-29-fase4-bug3-refund-policy.md`.

**12. Descontos Manuais**
- Admin pode aplicar desconto em qualquer pedido
- Usar para compensações, promoções especiais, VIP

---

## 17. MARKETPLACE (FUTURO)

### 17.1 Estado
- **Futuro** — planeado, não desenvolvido ainda

### 17.2 Categorias
- Tudo o que AliExpress vende (sem restrições)

### 17.3 Entrega
- **Correios normais** (CTT, DPD) — não envolve estafetas Bora
- Estafetas Bora focam-se só no delivery local

### 17.4 Duas Opções de Prazo
- **Entrega Rápida (Europa):** 3–7 dias (fornecedor europeu)
- **Entrega Padrão (AliExpress):** 2–4 semanas

### 17.5 Markup Escalonado

| Preço de custo | Markup |
|---|---|
| Até 10€ | **+40%** |
| 10–50€ | **+30%** |
| 50–150€ | **+30%** |
| Acima de 150€ | **+20%** |

Markup invisível. Cliente nunca vê preço de custo.

### 17.6 Devoluções
- **Cliente resolve direto com o fornecedor** — Bora é intermediária
- **Aviso obrigatório ao cliente** antes de comprar:
  > "Produto vendido por [fornecedor]. Problemas com o produto? Contactar [fornecedor]. A Bora é apenas intermediária."

---

## 18. LIMPEZA DE CASAS (FUTURO)

### 18.1 Estado
- **Futuro** — planeado, não desenvolvido ainda
- Lançamento após consolidação do delivery

### 18.2 Quem Faz
- **Empregadas domésticas independentes**, cadastradas na Bora (fluxo semelhante aos estafetas)
- Documentos, aprovação pelo admin, contas IBAN

### 18.3 Como Cobrar (cliente escolhe)
- **Por hora** (ex: 10€/hora)
- **Por tamanho da casa** (T0, T1, T2, T3, T4+)
- **Pacotes fixos** (limpeza básica, limpeza profunda, limpeza pós-mudanças)

### 18.4 Divisão do Valor
- **85%** para a empregada
- **15%** para a Bora

### 18.5 Produtos de Limpeza
Cliente escolhe na marcação:
- **Sem produtos** (cliente tem em casa, empregada só usa)
- **Com produtos** (empregada traz, **+€10** cobrado ao cliente)

---

## 19. STORAGE (BUCKETS)

### 19.1 Buckets Supabase
- `avatars` — fotos de perfil de clientes (público, upload por authenticated)
- `driver-documents` — documentos dos estafetas (privado)
- `product-images` — imagens dos produtos (público)
- `products` — outros ficheiros de produtos (público)
- `restaurant-photos` — logos e fotos dos parceiros (público)

### 19.2 Políticas
- Cada utilizador só faz upload para a sua própria pasta
- Path foto cliente: `avatars/{userId}.jpg`
- Path documentos driver: `{userId}/selfie.jpg`, `{userId}/document.jpg`, `{userId}/vehicle.jpg`

---

## 20. GDPR E PROTEÇÃO DE DADOS

### 20.1 Consentimento no Registo
- Checkbox **obrigatório** "Aceito os Termos e Política de Privacidade"
- Sem aceitar, não é possível registar
- Data/hora do consentimento guardada para prova legal

### 20.2 Apagar Conta
Utilizador pode pedir na app (Perfil → Apagar conta).

**Apaga imediatamente:**
- Nome, foto, telefone, endereços
- Conversas de chat
- Avaliações dadas
- Tokens
- Nome em pedidos antigos → substituído por "Utilizador apagado"

**Guarda 10 anos (obrigação legal AT):**
- Faturas (número, valor, data, NIF se fornecido)
- Extratos fiscais
- Comprovativos de pagamento Stripe

**Aviso obrigatório ao pedir apagar:**
> "Os teus dados pessoais serão apagados imediatamente. Por obrigação legal, os dados fiscais (faturas) são guardados por 10 anos. Confirmar?"

### 20.3 Consentimento de Cookies/Tracking
Banner na primeira abertura com **3 botões:**
- **Aceitar tudo**
- **Rejeitar**
- **Gerir preferências**

Rastreamento coberto: localização, análise de uso, notificações.

### 20.4 Contacto de Proteção de Dados
- Email: **boraappbora@gmail.com**
- Cliente pode pedir:
  - "Que dados têm sobre mim?"
  - "Corrige este dado"
  - "Dá-me os meus dados em ficheiro"
- Bora responde em até 30 dias (obrigação legal)

---

## 21. RLS (SEGURANÇA DE DADOS)

### 21.1 Tabela `orders`
- Cliente só vê os seus pedidos (`user_id = auth.uid()`)
- Driver só vê pedidos atribuídos a ele ou com oferta ativa
- Parceiro só vê pedidos do seu estabelecimento

### 21.2 Tabela `drivers`
- Driver só edita o seu perfil
- Admin lê todos

### 21.3 Tabela `driver_transactions`
- Driver lê e insere as suas transações
- Admin lê todas

### 21.4 Tabela `reservations`
- Cliente só vê as suas reservas
- Restaurante só vê as suas
- Admin lê todas

---

## 22. NOTIFICAÇÕES

### 22.1 Push Notifications (Firebase)
- **Driver:** notificação quando há nova oferta
- **Cliente:** atualizações de pedido (preparação, a caminho, entregue)
- **Cliente:** lembretes de reserva (24h, 2h antes)
- **Restaurante:** novo pedido, pedido de reserva, lembrete 30min antes
- Edge Function: `notify-driver`, `notify-customer`, `notify-partner`
- FCM token guardado na tabela respetiva

### 22.2 Som no App do Driver
- Toca som ao chegar oferta
- Para quando diálogo é fechado
- Não toca se o diálogo foi descartado pelo guard

---

## 23. CHAT

### 23.1 Chat Driver ↔ Cliente
- Disponível após driver aceitar o pedido
- Ambos podem enviar mensagens
- Visível enquanto o pedido estiver ativo

### 23.2 Chat Cliente ↔ Suporte
- Disponível sempre no Perfil → Suporte
- Futuro: chatbot de IA que aprende com Q&A

---

## 24. ATUALIZAÇÕES AUTOMÁTICAS DE PRODUTOS

### 24.1 Mercados (pg_cron)
Produtos atualizados automaticamente:
- Segunda: Mercadona
- Terça: Continente
- Quarta: Pingo Doce
- Quinta: Lidl
- Sexta: Auchan
- Sábado: Intermarché

### 24.2 Restaurantes Parceiros
- Próprio restaurante atualiza quando quiser (painel)
- 1× por mês (dia 1) — verificação automática de consistência

---

## 25. CONFIGURAÇÕES TÉCNICAS

### 25.1 Supabase
- Project ID: `ojykpzwqrtusfeakzrna`
- Edge Functions críticas: `dispatch-engine` (v31), `notify-driver`, `update-products`

### 25.2 Dispatch Engine — Constantes (NÃO alterar sem aprovação)
- Ficheiro: `supabase/functions/dispatch-engine/index.ts`
- Versão atual: v31
- Constantes:
  - `OFFER_TIMEOUT_SECONDS = 40`
  - `MAX_ORDERS_PER_DRIVER = 3`
  - `FIFO_RADIUS_KM = 0.2` (200m)
  - `BATCHING_RADIUS_KM = 3.0` (3 km entre lojas)
  - `SLA_CHECK_MINUTES = 7`
  - `SLA_BASE_MINUTES = 10`
  - `PREFERRED_RADIUS_KM = 10`

### 25.3 Flutter — Zonas Protegidas
Ficheiros críticos que NÃO devem ser editados sem análise prévia:
- `lib/services/pricing_service.dart`
- `lib/dispatch/driver_capacity_service.dart`
- `lib/stores/order_store.dart` (método `finalizePurchase`)
- Triggers DB: `bora_tokens`, `trg_award_tokens_on_delivery`
- Stripe: qualquer código de pagamento

---

## 26. CHECKLIST DE LANÇAMENTO

### 26.1 Funcionalidades Prontas ✅
- Dispatch engine (v31) com stacking até 3 pedidos
- Fluxo completo cliente (pedido → entrega)
- Fluxo completo estafeta (oferta → entrega)
- Sistema de tokens (ganho e uso)
- Pagamentos Stripe, MBWay, dinheiro
- Chat driver↔cliente
- Sacos (restaurante €0,30 fixo, mercado €0,10/saco)
- Checklist de compras no mercado
- Notificações push
- Cadastro e aprovação de estafetas
- Mapa com seta de bearing
- Cancelamento pelo estafeta
- Foto de perfil do cliente
- Histórico de pedidos
- Avaliações com etiquetas (BR §13) ✅
- Gorjetas/Tips — widget + DB (BR §4.5) ✅
- Fotos obrigatórias sendPackage/carryGroceries (BR §7.5/7.6) ✅
- Takeaway em parceiros (BR §14.9) ✅
- Reservas de mesa — fluxo base (BR §14) ✅
- Driver Help — botão + DB + RPC (BR §5.2) ✅
- Painel admin — reservas + avaliações (BR §16) ✅
- GDPR — checkbox registo, apagar conta, banner cookies (BR §20) ✅
- Cancelamento pelo cliente com taxas (BR §8.3) ✅
- Bugs corrigidos: botão voltar Android, foto perfil, checkbox estafeta ✅

### 26.2 A Desenvolver Para Lançamento
- Ecrã avaliação abrir automaticamente após entrega
- Botão "Reservar mesa" no ecrã do restaurante (com guard `reservations_enabled`, ver §14.10)
- Takeaway bypass no dispatch
- Gorjeta no checkout
- Pré-pagamento €3 nas reservas (Stripe)
- Toggle `reservations_enabled` no painel do parceiro (ver §14.10)

### 26.3 Futuro (Pós-Lançamento)
- Marketplace (secção 17)
- Limpeza de casas (secção 18)
- Chatbot de suporte IA
- Expansão para outras cidades

---

## 27. ATUALIZAÇÃO AUTOMÁTICA DE PRODUTOS DOS MERCADOS

### 27.1 Calendário Semanal (pg_cron)
- Segunda-feira: Mercadona (API pública tienda.mercadona.es)
- Terça-feira: Continente
- Quarta-feira: Pingo Doce
- Quinta-feira: Lidl
- Sexta-feira: Auchan
- Sábado: Intermarché
- Domingo: descanso / retry de falhas da semana

### 27.2 Requisitos de Qualidade (revisto 2026-04-18)

- Mínimo 5.000 produtos por mercado.
- **Fotos podem ser partilhadas entre mercados SE for o mesmo produto** (ex.: uma lata de Coca-Cola é a mesma em qualquer mercado). Match por `(nome_normalizado, marca, unidade)`.
- **PROIBIDO** usar fotos fictícias (placeholder recoloriado, imagem gerada, fallback repetido em lote).
- **PROIBIDO** usar foto de produto diferente (ex.: foto de leite num produto de iogurte).
- **Preços NUNCA partilhados** — cada mercado guarda o seu preço real, actualizado na mesma operação do scraper.
- Nomes dos produtos em português.
- Cascata canónica de imagens (tentar por ordem, parar no primeiro hit válido):
  1. **L1** — site oficial do próprio mercado (CDN do mercado).
  2. **L2** — biblioteca partilhada de outros mercados (Mercadona primeiro, depois os restantes), match por `(nome_normalizado, marca, unidade)`.
  3. **L3** — site oficial da marca (`brand_low` / `brand_mid` / `brand_premium`).
  4. **L4** — pesquisa de imagens: Bing Image Search (1.000/mês grátis) primeiro, Google Custom Search (3.000/mês grátis) como fallback.
  5. Se todos falharem → `photo_url = NULL` + `needs_photo = true`. **Nunca** guardar foto fictícia.
- Orçamento L4: €50/mês tecto máximo. Alerta admin aos €30 (80 %). Paragem obrigatória aos €50.

### 27.3 Mercadona (funciona)
- API pública: https://tienda.mercadona.es/api/categories/
- Extrai: nome, preço, foto CDN, unidade
- Tradução automática PT via mapCategoryPT()
- Estado actual: 5.011 produtos ✅

### 27.4 Outros Mercados (a implementar)
- Continente: API semi-aberta (Salesforce Commerce Cloud)
- Pingo Doce: scraping pingodoce.pt
- Lidl: scraping lidl.pt
- Auchan: scraping auchan.pt
- Intermarché: scraping intermarche.pt
- Análise legal obrigatória antes de implementar cada scraper

### 27.5 Regras Anti-Falha
- Se scraper falha → log + alerta admin + retry no domingo.
- Se menos de 5.000 produtos → alerta admin.
- Se foto em falta depois da cascata L1→L4 (§27.2) → `photo_url = NULL` + `needs_photo = true`. **PROIBIDO** usar foto fictícia ou foto de produto diferente como fallback.
- Máximo 1 pedido por segundo por mercado/host (anti-blocking).
- Orçamento L4 (Bing/Google Images): alerta aos €30, paragem obrigatória aos €50 por mês.

### 27.6 Estado Actual (pós-Fase 4, 2026-04-18)

Âmbito actual: cidade Guarda (`restaurant_id` com sufixo `-guarda`). Expansão a outras cidades é pós-lançamento.

Pós Fase 4 (Continente + Auchan via SFCC HTTP directo):

| Mercado             | Produtos | Com foto | L1    | L2  | `needs_photo` | Meta ≥5.000 | Estado              |
|---------------------|---------:|---------:|------:|----:|--------------:|:-----------:|---------------------|
| mercadona-guarda    | 5.011    | 5.011    | 5.011 | 0   | 0             | ✅          | OK                  |
| continente-guarda   | **6.332**| 4.304    | 4.303 | 1   | 2.028         | ✅          | +1.500 bestsellers L1 |
| auchan-guarda       | **4.503**| 1.505    | 1.500 | 5   | 2.998         | ❌ (−497)   | +1.500 bestsellers SFCC L1; reharvest restantes |
| pingodoce-guarda    | 3.101    | 64       | 59    | 5   | 3.037         | ❌ (−1.899) | Deferido — sem endpoint HTTP público |
| lidl-guarda         | 3.002    | 0        | 0     | 0   | 3.002         | ❌ (−1.998) | Deferido — SPA com auth 401; falta scraper |
| intermarche-guarda  | 3.004    | 5        | 0     | 5   | 2.999         | ❌ (−1.996) | Deferido — sem loja online; fallback OFF existente |

Fotos cleared na Fase 3: **14.064** (3.888 badges + 10.176 cross-leaks sem match). Fase 4 adicionou **+3.000 L1** reais em 2 mercados via SFCC HTTP directo (zero Playwright). Scraper SFCC funciona para Continente e Auchan (ambas `demandware.store/Sites-*-Site/*/Search-UpdateGrid?srule=best-sellers`). Pingo Doce/Lidl/Intermarché ficam deferidos para Fase 4b (Playwright ou folheto PDF). Reharvest L2→L4 dos `needs_photo` pertence ao par `market-scraper` + `market-harvester`, orquestrado por `products-updater`.

---

## 18. RESERVAS — PRÉ-PAGAMENTO €3 (SPLIT €2/€1)

> v2 corrigida 2026-04-30. v1 (€3 inteiros como crédito) DEPRECATED.
> Decisão: `decisions/2026-04-30-reservas-prepagamento-design.md`

### 18.1 Pré-pagamento e split

Cliente paga **€3** à Bora via Stripe (cartão/MBWay) no acto da reserva.
Settings (`platform_settings`):
- `reservation_prepayment_cents = 300` (€3)
- `reservation_partner_payout_cents = 200` (€2 — vai ao parceiro)
- `reservation_bora_service_cents = 100` (€1 — Bora retém)

**Restaurante NÃO paga nada** — feature gratuita ao parceiro. Bora repassa €2 no settlement semanal sempre que cliente chega.

### 18.2 Estados e fluxo de dinheiro (v2)

| Evento | Status | Cliente paga | Cliente recebe | Bora retém | Parceiro recebe (settlement) |
|---|---|---|---|---|---|
| Reserva criada (Stripe pre-auth) | `pending_payment` → `pending` | €3 | — | €3 ringfenced | — |
| Parceiro aprova | `approved` | €3 | — | €3 ringfenced | — |
| Parceiro **rejeita** | `rejected_refunded` | €3→refund | €3 (Stripe 5-10d) | €0 | €0 |
| Cliente cancela **≥2h antes** | `cancelled_refunded` | €3→refund | €3 (Stripe 5-10d) | €0 | €0 |
| Cliente cancela **<2h antes** | `cancelled_no_refund` | €3 | €0 | **€3** | €0 |
| Cliente **chega** (parceiro confirma) | `arrived` | €3 | **€2 menu credit** no próximo pedido | **€1** taxa serviço | **€2** payout pendente |
| Cliente **falta** (≥60min após `reserved_for`) | `no_show` | €3 | €0 | **€3** | €0 |

**Receita Bora possível:** €1 (chegada) · €3 (no-show ou cancel <2h) · €0 (refund).

### 18.3 Janela de cancelamento
- `reservation_cancel_window_hours = 2`
- ≥2h antes de `reserved_for` → Stripe refund total
- <2h antes → Bora 100%, parceiro €0

### 18.4 Crédito de menu (`restaurant_menu_credits`)
- Criado pelo `partner_mark_arrival(reservation_id)` com **€2** (não €3)
- Aplicado automaticamente em `create_order(p_partner_restaurant)` via `consume_menu_credit_for_order`
- Coluna `orders.menu_credit_applied_cents` regista uso (default 0)
- Stripe charge = `price - wallet - menu_credit` (validado em Edge Fn `create-payment-intent` v19)
- Expira **30 dias** após `arrived_at`
- Não cumulável (1 crédito por uso, FOR UPDATE SKIP LOCKED)

### 18.5 Payout obligation (`partner_reservation_payouts`)
- Criada simultaneamente com `restaurant_menu_credits` em `partner_mark_arrival`
- Status: `pending → paid → cancelled`
- Settlement semanal via `admin_mark_partner_payouts_paid(partner_id, payout_external_id)`
- Admin vê total pendente em `admin_partner_payout_summary(partner_id, period_start, period_end)`

### 18.6 Cron no-show
- `auto_close_no_show_reservations()` corre `0 * * * *` (cron)
- Marca `no_show` quando `status='approved' AND arrived_at IS NULL AND reserved_for < NOW() - 60min`
- Bora retém €3, **NÃO** cria payout entry, **NÃO** cria menu credit
- Notifica cliente via in-app

### 18.7 Exemplos numéricos (sanity check)

**Caso A — cliente chega, faz pedido €20 nesse restaurante:**
- Cliente: paga €3 reserva + €18 pedido (€20 - €2 credit) = €21 total
- Parceiro: recebe €18 do pedido (após comissão Bora) + €2 settlement reserva = €20 efectivo do cliente
- Bora: €1 (taxa serviço reserva) + comissão pedido

**Caso B — cliente falta:**
- Cliente: pagou €3, perdeu
- Parceiro: €0 (lugar reservado vazio = sem custo, sem ganho)
- Bora: €3

**Caso C — cancela 5h antes:**
- Cliente: paga €0 efectivo (Stripe refund)
- Parceiro: €0
- Bora: €0 (Stripe fee minimal aceitável)

---

## §28 — Wallet com Saldo Negativo (Sessão 3B-NOVA, 2026-05-04)

### §28.1 Contexto e regime fiscal

A Bora opera sob o **regime simplificado Art. 53.º CIVA** (isenção de IVA enquanto facturação anual <€15.000). Confirmado com contabilista: aceitar saldo negativo até **−€20** sem documento fiscal imediato é compatível com este regime, desde que cada movimento gere registo interno em `wallet_transactions` referenciado na próxima factura emitida.

Quando facturação ultrapassar €15.000 → emissão automática de factura/nota débito por cada `wallet_transactions` com `kind='debit'` (TODO Sessão futura — ver `.claude/.ai/todos/sessao_3b_pending.md`).

Esta política substituiu o plano original Stripe off_session (abandonado por bloqueios A4 MBWay + A8 STRIPE_MODE + A9 termos legais).

### §28.2 Limites

| Limite | Valor | Onde se aplica |
|---|---|---|
| Soft cap (gate) | **−€10** | `create_order` RAISE `WALLET_BLOCKED` |
| Hard floor (DB CHECK) | **−€20** | `client_wallets.free_balance_cents >= -2000` |
| Cap absoluto / pedido | **€10** | `wallet_apply_post_delivery_adjustment` |
| Alerta admin | **90 dias** sem actividade | `pg_cron wallet_overdue_alerts` |
| Acção obrigatória admin | **180 dias** sem actividade | mesmo cron, action='wallet_action_required' |

Configuráveis via `platform_settings`:
- `wallet_max_negative_balance_cents` (-1000)
- `wallet_hard_floor_cents` (-2000)
- `max_extra_charge_cents` (1000)
- `wallet_negative_alert_days` (90)
- `wallet_negative_action_days` (180)
- `wallet_negative_enabled` (true) — kill-switch

### §28.3 Casos de uso (gera saldo negativo)

1. **Sacos mercado extras:** estafeta usa N sacos (€0.10/saco, cap 5).
2. **Substituição de produto:** troca por mais caro (cap +30% subtotal já existe).
3. **Adição de produto extra:** cliente concorda, markup 15% aplicado.
4. Cap absoluto combinado **€10/pedido** (1+2+3).

Cash continua a usar `cash_total_due` (Sessão 3, sem mudança).

### §28.4 Ordem de operações `create_order` (CRÍTICA)

1. SELECT FOR UPDATE wallet (incondicional)
2. Gate: `balance < wallet_max_negative_balance_cents` → RAISE `WALLET_BLOCKED`
3. Cálculo subtotal (markup non-partner) + pricing
4. `consume_menu_credit_for_order` (tokens/menu credits descontam ANTES)
5. `v_charge_total = customer_total - wallet_eur - credit/100`
6. **Settlement:** se `balance < 0` → `charge_total += |balance|`, wallet→0, INSERT `wallet_transactions kind='settlement'`
7. INSERT order com charge_total final
8. `wallet_debit_for_order` se cliente aplicou saldo positivo

Esta ordem garante:
- Tokens descontam ANTES do settlement (cliente recebe desconto, depois paga dívida)
- Settlement aplicado UMA vez por pedido (FOR UPDATE evita race)
- Charge_total no INSERT é o valor real cobrado

### §28.5 Ordem de operações `finalize_storeshopping_purchase`

Quando há extra a cobrar em `card`/`mbway` E `wallet_negative_enabled=true`:
- Chama `wallet_apply_post_delivery_adjustment(order, user, amount, reason, 'debit')`
- Idempotente via `idempotency_key = 'adj_' + order_id + '_' + kind`
- Cap €10 validado dentro da RPC
- `payment_status` mantém `'paid'` (já paid no checkout)
- Em caso de falha (hard floor exceeded) → fallback `extraRequired` (Sessão 3)

### §28.6 Refund quando wallet negativa

`wallet_credit_refund_split` modificado:
- Se `balance < 0`: 1º abate dívida (`kind='settlement'`)
- 2º split do remanescente: 80% saldo livre + 20% tokens (regra original)

### §28.7 Notificações cliente (TODO Sessão futura)

Push templates desejados (a implementar quando Sessão 1B push validada em prod):
- "Sacos extras: €X descontados. Carteira: −€Y (cobrado próxima compra)" — quando wallet cruza zero
- "Saldo regularizado. Obrigado!" — quando settlement zera dívida
- "A sua carteira tem dívida pendente há 90 dias" — alerta cliente (broadcast admin)

In-app já implementado (Sessão 3B):
- Profile: card vermelho/amarelo/erro (`isNegative`/`isWarning`/`isBlocked`)
- Cart: linha "Saldo devedor anterior: +€X.XX" + bloqueio botão se < soft cap
- Wallet history: novos kinds com ícones distintos + `balance_after_cents`
- Orders: chip "Carteira" + modal detalhes ajustes
- Admin wallets: filtro "apenas negativo" + botão "Perdoar dívida" + CSV export

### §28.8 Política Uber/Glovo (referência)

Uber Eats e Glovo usam abordagem similar:
- Saldo negativo até X EUR, próxima compra liquida automaticamente.
- Bora segue mesmo padrão, com cap mais conservador (-€20 vs -€50 da concorrência).

### §28.9 Boas práticas implementadas

- Idempotency: `wallet_transactions.idempotency_key UNIQUE` para evitar débitos duplicados em retries.
- Audit trail: `balance_after_cents` em todas as transactions Sessão 3B.
- RLS: cliente lê só os seus; admin tudo. Mutações apenas via `SECURITY DEFINER` RPCs.
- `SELECT FOR UPDATE` em todas as operações que mutam wallet — race-safe.
- Kill-switch (`wallet_negative_enabled=false`) → comportamento Sessão 3 (`extraRequired`).
- Hard floor DB (CHECK) defende contra bugs RPC futuros.

### §28.10 Admin e governança

- Admin pode perdoar dívida via `admin_forgive_wallet_debt(user, reason)` — gera `wallet_transactions kind='forgive'`, audit log, wallet → 0.
- pg_cron diário 09:00 UTC: wallets com `balance<0` e inactividade ≥90d geram `admin_audit_log action='wallet_overdue_alert'`; ≥180d → `'wallet_action_required'`.
- Deduplicação 24h evita spam de alertas.

---

## §29. Housekeeping financeiro e DB conventions (Sessão 4 — 2026-05-04)

### §29.1 Tipos NUMERIC para colunas monetárias (regra-chave)

- **Nunca usar `double precision` em colunas monetárias.** Float binário introduz erros silenciosos em rounding (ex.: `0.1 + 0.2 ≠ 0.3`).
- Usar `NUMERIC` (precisão arbitrária) para qualquer coluna que represente euros, cêntimos como decimal, taxas, comissões, refunds.
- Pattern dual-write para migração faseada (ver §29.2).
- Excepção: cálculos transientes em PL/pgSQL podem usar `int` (cents) — só persistência exige NUMERIC.

**Status actual (2026-05-04):**
- ✅ `customer_total, subtotal, delivery_fee, service_fee, platform_commission, driver_earnings, bag_fee` → `numeric`
- ⚠️ `final_total` → `double precision` (em dual-write `final_total_numeric` desde B2; commit 2 swap futuro)
- 🐛 `extra_charge_amount` → `double precision` (mesmo padrão; sessão futura housekeeping)

**§29.1 actualização (B2 commit 2, 2026-05-05):**
- ✅ `final_total` migração `double precision` → `numeric` **CONCLUÍDA**.
- Trigger `trg_zz_final_total_dual_write` + função `fn_sync_final_total_numeric` removidos.
- Coluna única `orders.final_total` agora `numeric`. Sessão 4 C3 fechada.
- Migration: `b2c2_drop_rename_final_total` (apply_migration MCP).
- Achado lateral: trigger `orders_enforce_cash_limit` foi DROP+RECREATE (depende explicitamente de `final_total`).
- Achado lateral: RPC `agent_get_user_orders_summary` corrigida (referenciava `final_total_numeric` directamente — fix `CREATE OR REPLACE` na mesma transacção).
- 12 RPCs continuam a referenciar `final_total` por nome (todas funcionais).
- Próximo housekeeping: `extra_charge_amount` → numeric.

### §29.2 Trigger naming: sufixo `trg_zz_*` para última posição alfabética

- PostgreSQL dispara triggers do mesmo evento por ordem alfabética do nome.
- Para garantir que um trigger executa **APÓS** triggers críticos (ex.: financial_lock, financial_split), usar prefixo `trg_zz_*`.
- Convenção entra em vigor com `trg_zz_final_total_dual_write` (Sessão 4 B2).
- Nota: `trigger_*` (com 'i') é alfabeticamente posterior a `trg_zz_*` (porque 'g' < 'i'). Em colisão, preferir renomear o trigger de tipo `trigger_*` para `trg_*` se a ordem importar.

### §29.3 Edge Functions activas (snapshot 2026-05-04 pós-Sessão 4 B1)

Lista limpa pós-deletes:
- `dispatch-engine` (verify_jwt=false)
- `stripe-webhook` (verify_jwt=false)
- `create-payment-intent` (verify_jwt=false)
- `create-mbway-payment-intent` (verify_jwt=true, LIVE)
- `notify-driver` / `notify-partner` / `notify-client`
- `refund` / `charge-extra`
- `delete-account` / `client-cancel-order` / `cancel-order-with-choice` / `execute-cancellation`
- `update-products` / `admin-force-driver-logout` / `admin-cancel-order` / `upload-avatar`
- `create-reservation-payment-intent` / `finalize-order-from-intent`

**Apagadas em Sessão 4 B1 (2026-05-04):**
- `confirm-mbway-payment` (obsoleta — substituída por stripe-webhook PaymentIntent succeeded)
- `create-mbway-payment-intent-debug` (variante debug deixada em prod)

### §29.4 Settlement marker para `extra_charge_amount` (Sessão 4 B3)

Tabela `orders` ganhou 2 colunas:
- `extra_charge_settled_at TIMESTAMPTZ NULL` — timestamp da liquidação (NULL = pendente)
- `extra_charge_settled_via TEXT NULL CHECK IN ('wallet','cash','none')`

Histórico de `extra_charge_amount` é **preservado** após settlement (não setar a 0). A liquidação é apenas marcada nas 2 colunas novas.

`finalize_storeshopping_purchase` marca automaticamente `settled_via='wallet'` quando `wallet_apply_post_delivery_adjustment` succeeds.

Cash settlement path (estafeta cobra em mão) actualmente usa `cash_total_due` paralelo; settlement marker via `'cash'` será aplicado em sessão futura quando arquitectura for unificada.

### §29.5 Pricing Quote Consistency (Sessão 4 B4)

`quote_order_pricing` e `create_order` ambas usam `distance_km` do payload (não recalculam server-side).

**Caller é responsável por:**
1. Calcular `distance_km` UMA vez via método consistente (Haversine ou outro).
2. Enviar **MESMO** `distance_km` para quote E para create_order.
3. Não recalcular entre quote e create_order.

**Tolerância:** ± €0.01 paridade pricing (smoke obrigatório em alterações de pricing).

⚠️ **Sessão futura — anti-fraud:** validar server-side recalculando `distance_km` a partir de coords (`pickup_lat/lng → dropoff_lat/lng`) usando `earthdistance` ou PostGIS. Sem isto, cliente malicioso pode reduzir `delivery_fee` enviando distance fabricada.

### §29.6 Flutter `productId` (Sessão 4 B5 — mitigação dev-only)

`CartItem.productId` deve ser sempre o ID real da row em `products` (TEXT). Nunca o nome do produto.

**Defesa em profundidade:**
- Flutter (dev/debug): assert no construtor `CartItem` rejeita strings vazias, com espaço, ou >200 chars.
- ⚠️ Asserts são strip em release mode (produção) — mitigação NÃO protege prod actualmente.
- Server-side: fallback `unit_price` em `create_order` (Sessão 1) — defesa em profundidade, manter sempre.

**Pendente Sessão 4C:** fix transversal nos 107 call sites de `CartItem(...)`; limpeza retroactiva de `orders.items` históricos via lookup nome→SKU.

## §30. Knowledge Infra (Sessão Pré-5A — 2026-05-04)

### §30.1 Vault Obsidian canónico

A documentação interna não-código (notas, decisões, sessões, regras-history) vive em **`bora_app/.obsidian-vault/`** dentro do próprio repo.

**Antes (deprecated):** `C:\Users\danil\Desktop\Bora` (path local, fora do git, sem backup automático).
**Agora:** `bora_app/.obsidian-vault/` — backup natural via git, portátil entre máquinas.

### §30.2 Sync scripts — REMOVIDOS / NÃO CRIAR

INDEX.md (`.claude/.ai/knowledge/INDEX.md`) mencionava `from-obsidian/` como subfolder de sync unidireccional. **Foi planeamento futuro nunca implementado** e foi abandonado nesta sessão.

**Não existem sync scripts em `.claude/.ai/knowledge/`** e **não devem ser criados**:
- Vault vive dentro do repo → commits do git são o "sync" natural.
- Não há vault externo a manter.
- Eventuais backups externos (OneDrive/Dropbox) ficam fora do scope da app.

### §30.3 Source backup

Source `C:\Users\danil\Desktop\Bora` foi **preservado intactus** durante a migração (Copy-Item binary, source intactus drift=0).

**Critério para apagar source:**
- Mínimo 7 dias de uso OK em destino
- SHA256 weekly match check (manual)
- Após validação: apagar source em sessão futura ou manual

### §30.4 Conteúdo commitado vs ignorado

**Tracked (commitado):** 51 .md + `.obsidian/community-plugins.json` + `.obsidian/core-plugins.json` (lista plugins partilhável) + `appearance.json` + `graph.json` + `text-generator.json` (config base não-volátil).

**Ignored em `.gitignore`:** `workspace*`, `cache`, `app.json`, `plugins/` (binários), `themes/`, `.smart-env/` (cache Smart Connections, 4.9 MB, re-gerado pelo plugin), `.trash/`, `.obsidian/.obsidian/` recursivo (artefacto plugin com `.exe`).

---

## §31 — AGENTE IA SUPORTE (5A-1, 2026-05-04)

### §31.1 Stack
- **Provider**: Google Gemini 1.5 Flash (free tier ~1500 req/dia, function calling nativo).
- **Skills system**: playbooks markdown na tabela `support_skills` (DB-driven, versionable, admin edita sem redeploy).
- **Tabelas (6)**: `support_settings`, `support_skills`, `support_chatbot_sessions`, `support_chatbot_messages`, `support_chatbot_quota`, `support_agent_actions`.
- **Edge Functions (2)**: `support-chatbot` (verify_jwt=true, Gemini + tool-calling), `support-submit-ticket` (verify_jwt=true, tracking only).
- **Tickets**: `support_tickets` legacy preservado + 9 colunas novas aditivas (`channel`, `subject`, `body`, `assigned_to`, `admin_notes`, `updated_at`, `resolved_at`, `session_id`, `order_id`).

### §31.2 Limites configuráveis (`support_settings` singleton id=1)
- `rate_limit_per_user_day`: 30 mensagens/dia
- `max_messages_per_session`: 30 mensagens/sessão
- `max_output_tokens_per_call`: 8000 tokens
- `max_user_message_chars`: 2000 chars (truncate, com sanitização anti-injection)
- `max_tool_iterations`: 5 ciclos function-calling
- `shadow_mode`: true (skills write/cancel apenas propõem em 5B+)
- `support_agent_enabled`: true (kill switch global → app esconde FAB)

### §31.3 Regras críticas
- **Agente NUNCA calcula dinheiro**, refunds, créditos ou estimativas financeiras → escalar via skill `HUMAN_REQUEST`.
- **Agente NUNCA inventa valores** → se não tem info via tool, diz-o e oferece humano.
- **Tom**: PT europeu, amigável e directo, respostas ≤ 3 frases.
- **Marcador escalação**: `[HANDOFF_HUMAN]` no fim do reply → cria `support_tickets` channel='chatbot'.

### §31.4 RPCs whitelisted tool-calling (5)
Todas `SECURITY DEFINER`, todas usam `auth.uid()` directamente. **NENHUMA aceita `p_user_id`** (defesa contra impersonation via tool-call hallucination).

| RPC | Args | Returns |
|-----|------|---------|
| `agent_get_user_orders_summary(p_limit int=5)` | int 1-20 | Últimos pedidos (id, status, partner, total_cents, can_be_cancelled) |
| `agent_get_order_status(p_order_id text)` | order id | status, current_step, driver_name, can_be_cancelled |
| `agent_get_user_wallet_summary()` | — | free_balance_cents, is_blocked, soft/hard floor, explanation |
| `agent_get_user_tokens_summary()` | — | tokens_balance, expiring_soon_count |
| `agent_get_refund_status(p_order_id text)` | order id | refund_status, method, amount, ETA texto |

Order ownership validado em `agent_get_order_status` e `agent_get_refund_status` (lança `ORDER_NOT_FOUND_OR_NOT_OWNER`).

### §31.5 Defesas Edge Function `support-chatbot`
- Sanitização: strip control chars (preserva \\t, \\n) + reject `<<<SYSTEM>>>` / `<<<END_SYSTEM>>>` literais (400).
- System prompt em delimitador isolado + Gemini `system_instruction` nativo (belt-and-suspenders).
- Whitelist tool names — function call não whitelisted → handoff humano.
- Cap iter tool-calling: 5; cap msg/sessão: 30; cap msg/dia: 30; cap tokens output: 8000.
- Quota incrementada via `increment_chatbot_quota()` (UPSERT atómico, anti race-condition).

### §31.6 Canais de contacto
- WhatsApp: `+351937501673` (configurável `support_settings.whatsapp_number`)
- Email: `boraappbora@gmail.com` (configurável `support_settings.support_email`)
- WhatsApp tap **NÃO** cria ticket (anti-spam) — analytics futura via `support_channel_taps` (5B).

### §31.7 Skills 5A (read-only, seed em 5A-2)
9 skills aprovadas: `ORDER_STATUS_CHECK`, `WALLET_INFO`, `TOKENS_INFO`, `RESERVATION_INFO`, `RECEIPT_RESEND`, `FAQ_GENERAL`, `CONTACT_HUMAN`, `HUMAN_REQUEST`, `ESCALATION_FALLBACK`.

Skills WRITE/CANCEL/MARKET ficam para 5B (modo SHADOW 4 semanas → admin aprova).

### §31.8 RAG diferido
pgvector ausente — RAG embeddings de business_rules + sessões anteriores ficam para 5C.

### §31.9 Frontend integração (5A-2, 2026-05-04)

**Provider state global (anti-flicker 3-state):**
- `SupportSettingsProvider` carrega `support_settings` on app start + refresh on `AppLifecycleState.resumed`.
- `enum SupportSettingsState { loading, loaded, error }`:
  - `loading` → FAB não renderiza (sem flicker boot)
  - `loaded` → respeita `support_agent_enabled` real
  - `error` → esconde card "Bora IA"; WhatsApp/Email visíveis (degraded mode)

**Widgets criados:**
- `BoraScaffold` — wrapper minimal (sem refactor scaffolds existentes)
- `BoraSupportFab` — `FabPosition.{bottomRight,bottomLeft,topRight,topLeft}` (default BR; TR para screens com FAB próprio)
- `BoraSupportSheet` — 3 cards: "Bora IA" (condicional `shouldShowAiCard`), WhatsApp, Email
- `SupportChatScreen` — Realtime em `support_chatbot_messages` + Edge Fn `support-chatbot`
- `SupportEmailFormScreen` — submit via Edge Fn `support-submit-ticket`
- `AdminSupportTicketsScreen` — lista admin mínima + RPC `admin_resolve_ticket(p_ticket_id, p_notes)`

**Realtime publication:** `ALTER PUBLICATION supabase_realtime ADD TABLE support_chatbot_messages;` (migration `20260504080100`).

**WhatsApp tap NÃO cria ticket** — só `chat`/`email` criam (anti-spam §31.6).

**503 differentiation UX:**
- 503 + `error: 'GEMINI_API_KEY missing'` → "Sistema em configuração. Contacta WhatsApp/Email"
- 503 outros (settings off) → "Indisponível temporariamente"

### §31.10 Skills 5A-2 (seed read-only)

9 skills active=true em `support_skills`:
1. **ORDER_STATUS** — `agent_get_order_status`
2. **ORDER_HISTORY** — `agent_get_user_orders_summary`
3. **WALLET_INFO** — `agent_get_user_wallet_summary`
4. **WALLET_BLOCKED_HELP** — `agent_get_user_wallet_summary`
5. **TOKENS_INFO** — `agent_get_user_tokens_summary` (fórmula real `ROUND(price×3) min 1`, expira 60d)
6. **REFUND_STATUS** — `agent_get_refund_status` (placeholder; refund detail real em 5B)
7. **GENERAL_FAQ** — sem tools (cobertura Guarda, tipos serviço)
8. **APP_TROUBLESHOOTING** — sem tools (GPS, push, crash)
9. **HUMAN_REQUEST** — escalate (cria ticket channel='chatbot')

Todas idempotentes via `INSERT...ON CONFLICT(skill_name) DO UPDATE` (version++).

**Itens [VERIFICAR] pendentes para Danilo preencher:** ETA real (5C), prazo legal liquidação manual wallet, conversão "100 tokens=€0.50", refund amount real (5B), horário operacional, taxa entrega base, versão mínima Android/iOS.

### §31.11 Admin RPC

`admin_resolve_ticket(p_ticket_id uuid, p_notes text DEFAULT NULL)`:
- Requer `is_admin()` (RAISE `NOT_ADMIN` se não admin).
- UPDATE `status='resolved'`, `resolved_at=now()`, `updated_at=now()`.
- **Audit inline:** append `[timestamp] resolved by <auth.uid()>: <p_notes>` em `admin_notes` (preserva histórico).

---

## §32 — Architectural Debt (Sessão 7 dedicada)

### §32.1 BUG 39 — UUID/TEXT mismatch em `orders.id`
- `orders.id` é **TEXT** em produção (legado).
- Tabelas que referenciam `orders.id` com tipo **UUID** (mismatch):
  - `messages.order_id` (chat operacional cliente↔estafeta)
  - `bora_tokens.source_order_id`
- Triggers que cruzam tipos usam `::UUID` cast explícito — workaround deliberado.
- Plano: `decisions/2026-04-29-restaurants-id-uuid-refactor.md` (Sessão 7 dedicada).
- **Não corrigir ad-hoc** — mudança transversal exige sessão própria.

### §32.2 BUG 34 (related)
`orders.id`, `restaurants.id`, `products.id` todos TEXT em prod. Refactor único bundled.

### §32.3 BUG 35/37
- BUG 35: RPC `finalize_storeshopping_purchase` — corrigido em sessões anteriores; manter regressão.
- BUG 37: `fn_award_tokens_on_delivery` cast UUID — relacionado §32.1.

### §32.4 Tokens cliente — discrepância docs vs código (5A-2 detectado)

**Detectado:** business_rules.md secção tokens (§lugar tokens) diz **"3% do valor do pedido"** mas o trigger real `fn_award_tokens_on_delivery` em prod usa **`GREATEST(1, ROUND(price × 3))`** (validado via MCP 2026-05-04).

**Impacto:** se `price=10€`, doc esperaria `0.30 tokens` mas código atribui `30 tokens`. Discrepância 100x.

**Acção:**
- Skill `TOKENS_INFO` (5A-2 B17) cita **fórmula real** do código (`ROUND(price×3) min 1`, expira 60d).
- Confirmar com Danilo em sessão futura: qual é a fórmula desejada?
  - Se fórmula correcta é `ROUND(price×3)`: actualizar business_rules.md secção tokens.
  - Se fórmula correcta é "3% do valor": corrigir trigger `fn_award_tokens_on_delivery`.

**NÃO fixar nesta sessão** — escopo 5A-2 é frontend + skills seed.

### §32.5 Bug crítico 5A-1 corrigido em 5A-2 (B-FIX-1)

**Detectado em 5A-2 audit:** RPC `agent_get_order_status` (5A-1) mapeava estados snake_case (`pending`, `accepted`, `picked_up`, ...) que **NÃO existem em prod**. Estados reais em `orders.status` (validados via MCP DISTINCT) são camelCase Dart-like: `created`, `preparing`, `callingDriver`, `driverAccepted`, `pickedUp`, `onTheWay`, `delivered`, `cancelled`, `rejected`.

**Impacto antes do fix:** RPC devolvia `current_step = status` (fallthrough do CASE) para todos os estados — UX degradada (utilizador veria texto cru tipo "driverAccepted" em vez de "Estafeta a caminho do parceiro").

**Fix aplicado:** migration `20260504080000_5a2_fix_agent_order_status_camelcase.sql`. CASE actualizado com 9 estados reais + textos PT-EU. `can_be_cancelled` agora é `status IN ('created','preparing','callingDriver')` (corresponde ao flow real).

---

## §33 — Flutter productId integrity (Sessão 4C, 2026-05-04)

### §33.1 Source of truth
`productId` enviado em qualquer payload `create_order` (RPC) ou `cart_input` (Edge Fn `create-payment-intent`) **DEVE** vir de `ProductModel.id` (linha de DB em `public.products` ou `public.product_variants`). NUNCA do `name` / `title` / chave sintética que embuta nome.

### §33.2 Validação run-time em construtores
`CartItem` constructor (`lib/models/cart_item.dart`) valida via `if-throw ArgumentError` no body do constructor. **NÃO usar apenas `assert()`** — em Dart, `assert()` é STRIP em release mode (sempre). Asserts ficam como camada adicional dev/debug; o `if-throw` é a defesa primária em release.

### §33.3 Helper `isValidProductId(String id)`
Critério (`lib/stores/order_store.dart`, top-level):
- não vazio
- sem espaço
- length entre 3 e 200 chars

NÃO usar regex de prefixo. Produção tem 9+ formatos válidos confirmados via MCP: `pd`, `cnt`, `auc`, `merc`, `glv`, `cm`, `lidl`, `prod`, UUIDs hex puros sem prefixo, sentinelas `extra_<timestamp>` (driver-added items).

### §33.4 `validateOrderPayload(Map payload)` pré-RPC
Helper top-level em `order_store.dart`. Percorre `payload['product_lines']` e valida cada `product_id`. Lança `FormatException` se inválido. Logistics (`carryGroceries` / `sendPackage`) não tem `product_lines` → early return OK.

**Chamada obrigatória ANTES de cada invocation:**
- `order_store.dart:484` — antes de `supabase.functions.invoke('create-payment-intent')`
- `order_store.dart:721` — antes de `supabase.rpc('create_order')`

Caller apanha `FormatException` e devolve `null` / `false` sem chegar à rede.

### §33.5 Defesa em profundidade
Mitigação SQL 4B5 (fallback `unit_price` server-side) **MANTÉM-SE** em produção. Não removida. Camadas:
1. **Constructor `CartItem`** (release-safe `if-throw`) — bloqueia criação local
2. **Asserts** (4B5) — detector dev/debug
3. **`validateOrderPayload`** (4C) — bloqueia envio à rede
4. **SQL `unit_price` fallback** (4B5) — defesa final server-side se algo escapar

### §33.6 Lição arquitectural Dart
- `assert()` é STRIP em release mode SEMPRE (comportamento da linguagem).
- Asserts são **detectores dev**, nunca defesa primária.
- Defesas críticas em release usam `if (cond) throw` explícito no body do constructor / método.
- Initializer list (`: assert(...)`) também strip em release; só body executa sempre.

### §33.7 Sítios de cart-add corrigidos
- `lib/screens/product_detail_screen.dart:24` — `_variantKey(v) = v.id` (não embute nome)
- `lib/screens/store_products_screen.dart:1146` — `_variantKey = variant.id` (não embute nome)
- `lib/screens/restaurant_menu_screen.dart:188` — fallback `?? item.name` removido; throw `StateError` se `MenuItem.productId` null (bug a montante)

### §33.8 Logging
`debugPrint(...)` (Sentry / Crashlytics ausentes do projecto). Confirmado via grep em `lib/` + `pubspec.yaml`.

---

## 28. HOUSEKEEPING + UX SUPORTE (Sessão 6 · 2026-05-05)

### 28.1 Pedidos teste (`is_test_order`)
- Coluna `BOOLEAN NOT NULL DEFAULT false` em `orders`. Index parcial `WHERE is_test_order=true`.
- 4 pedidos pré-launch marcados (€253.08 stripe charges, testes Danilo 30/04+01/05): `1c561ae0…`, `31a5ccd3…`, `88e36c67…`, `b90966bf…`.
- Migration: `20260505060000_06_orders_is_test_order.sql` — usa `RAISE EXCEPTION` se UPDATE não marcar exactamente 4.
- TODO admin filter `is_test_order=false` em 3 dashboards (`admin_orders_screen`, `admin_order_detail_screen`, `admin_driver_detail_screen`).

### 28.2 Filosofia UX suporte (Danilo 2026-05-05)
- Bora App em fase TESTE pré-launch
- Robô IA = porta principal
- FAB cliente → **chat IA directo** (kill switch ON via `support_settings.support_agent_enabled`)
- WhatsApp/Email DENTRO do chat ("Falar com humano" rodapé discreto)
- Fallback emergência: kill OFF / Provider state=error/loading → bottomSheet (menu antigo)

### 28.3 Estatísticas robô IA
- RPC `admin_get_support_stats(p_from timestamptz, p_to timestamptz) → jsonb` SECURITY DEFINER admin-only via `is_admin()`.
- Migration: `20260505060100_06_admin_get_support_stats.sql`.
- 12 métricas: sessões totais/resolvidas/escaladas, resolution_rate_pct, avg_messages_per_session, tokens.{input,output,total}, cost_eur_estimated, top_skills[10], escalating_skills[5], tickets_by_channel, avg_satisfaction, satisfaction_responses.
- Custo Gemini Flash 2026-05: €0.067/M input + €0.27/M output (hardcoded RPC; USD→EUR ≈0.90).
- Screen: `lib/screens/admin/admin_support_stats_screen.dart`.
- TODO: migrar pricing para `support_settings.pricing_jsonb`.

### 28.4 BoraSupportFab compatibilidade
- Assinatura `BoraSupportFab({orderId, position, heroTag})` MANTIDA — 22 screens com FAB não afectadas.
- Comportamento `onTap` mudou: chat directo se kill ON, fallback `BoraSupportSheet` se OFF.
- `BoraSupportSheet` aceita `showAgentCard:bool=true` (default `true`); botão "Falar com humano" no chat passa `false` (só WhatsApp+Email).

## §35 — RAG Knowledge Base (Sessão 5C-α · 2026-05-05)

### 35.1 Infra
- Extensão `vector` instalada (schema `extensions`, default v0.8.0).
- Tabela `public.support_knowledge_chunks`:
  - `id uuid PK`, `source_file text`, `source_type text` CHECK
    (`obsidian` | `knowledge` | `business_rules`),
  - `chunk_index int`, `section_title text`, `chunk_text text`,
  - `char_count int GENERATED ALWAYS AS length(chunk_text) STORED`,
  - `content_hash text` (SHA256), `embedding extensions.vector(768)`,
  - `indexed_at timestamptz DEFAULT now()`,
  - UNIQUE(`source_file`,`chunk_index`) + UNIQUE(`content_hash`).
- RLS activa, policy `service_role_only` (`auth.role()='service_role'`).
- Índice HNSW cosine: `m=16, ef_construction=64` em `embedding`.
- Índice secundário em `source_type`.

### 35.2 Ingest (script local Deno)
- Ficheiro: `scripts/rag/ingest_knowledge.ts`.
- 3 fontes: `bora_app/.obsidian-vault/` (`obsidian`),
  `bora_app/.claude/.ai/knowledge/` (`knowledge`),
  `bora_app/.claude/.ai/business_rules.md` (`business_rules`).
- Gemini `text-embedding-004` (768 dims) via REST.
- Chunking: split por `^##` (regex multiline). Section title = primeira
  linha após `##`. Fallback `\n\n` quando ficheiro sem `##`.
- Cap `MAX_CHUNK_CHARS=8000` — sub-divisão por parágrafos.
- Rate limit 1 req/s. Retry 3× em 429 com backoff 60 s.
- Dedupe SHA256 — `content_hash` UNIQUE.
- Upsert por `(source_file, chunk_index)`.
- Secrets: `scripts/rag/.env` (gitignored). Template em `.env.example`.
  Vars: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `GEMINI_API_KEY`.
- Comando:
  ```
  cd scripts/rag
  deno run --allow-net --allow-read --allow-env \
    --env-file=.env ingest_knowledge.ts
  ```

### 35.3 RPCs
- `match_knowledge(query_embedding vector(768), match_count int=5,
  min_similarity float=0.5)` — `SECURITY DEFINER`, GRANT
  `authenticated, service_role`. HNSW cosine search.
- `admin_get_knowledge_stats() → jsonb` — admin-only
  (`is_admin()` guard, RAISE `NOT_ADMIN`). Devolve total_chunks,
  embedded_chunks, pending_chunks, by_source, last_indexed,
  avg/max_chunk_chars, unique_files.

### 35.4 RAG ACTIVO (Sessão 5C-β · 2026-05-06)
- `support_settings.rag_enabled BOOLEAN DEFAULT false` (kill switch SQL).
- `support-chatbot` v2 deployed (sha256 `d3a0c9f4...`):
  - `buildRagContext()` invocado se `settings.rag_enabled === true`
  - Try/catch wrapper → fallback graceful (sem RAG) em caso de erro
  - Cache lookup `support_embedding_cache` por SHA256(query lowercased trimmed)
  - Cache miss → `gemini-embedding-001` `RETRIEVAL_QUERY` 768 dims, timeout 1.5s
  - `match_knowledge(top=8, min_sim=0.5)` + dedup max 2/source_file → top-5
  - Skills (instruções) ANTES do ragContext (contexto) no system prompt
  - Logs `[RAG] cache HIT/MISS/no chunks above threshold` para debug
- Edge Fn `reindex-knowledge` v1 (admin-only, modes `pending`|`all`,
  max_chunks=100, rate-limited 1 req/s).
- Botão "Re-indexar agora" em `AdminKnowledgeScreen` ACTIVO com dropdown
  modo + warning modal para mode=`all`.
- Versão prévia para rollback: `support-chatbot` v1 sha256 `ac532794...`

### 35.5 Custo Gemini
- Free tier ≈ 1 500 req/dia.
- Ingest inicial estimado ≈ 410 chunks (~7 min @1 req/s, ≈ 27% quota).
- Re-ingest incremental: dedupe SHA256 → só chunks novos pagam.

### 35.6 Admin Screen
- `lib/screens/admin/admin_knowledge_screen.dart` — chama RPC,
  4 stat cards (Total / Indexados / Pendentes / Última Indexação),
  breakdown por fonte, métricas (avg/max/unique). Botão **Re-indexar agora**
  ACTIVO em 5C-β: dropdown modo (pending/all) + warning modal para
  mode=all. Linkado em `admin_dashboard_screen.dart` junto ao card
  "Estatísticas Suporte IA".

### 35.7 Performance + custo (5C-β)
- **Latência**: cache HIT ~+50ms · cache MISS ~+1-1.5s (1ª query)
- **System prompt cresce** ~5K chars (até 5 chunks dedup × ~1K avg) →
  ~1.25K tokens extra input/call
- **Custo Gemini Flash extra**: ~€0.000084/call input
- **Quota Gemini embedding**: free tier 100 RPD para `gemini-embedding-001`
  (cache mitiga exhaustion; cada query única consome 1 unidade)
- **Kill switch**: `UPDATE support_settings SET rag_enabled=false WHERE id=1`
  → próxima request sem `[RAG]` nos logs

## §36 — AGENTE IA WRITE Shadow (Sessão 5B-α · 2026-05-06)

### §36.1 Filosofia
**Robô PROPÕE → Danilo APROVA → só então EXECUTA.**
NUNCA executa automaticamente. Skills WRITE em modo `write_shadow`
gravam propostas em fila para aprovação manual.

### §36.2 Estrutura `support_pending_actions`
- Tabela fila: `id, session_id, user_id, skill_name, action_type,
  action_payload (jsonb), status, proposed_at, reviewed_at,
  reviewed_by, executed_at, execution_result, rejection_reason,
  user_message, agent_reasoning`
- `status`: `pending → executed | failed | rejected`
- RLS: clientes vêem só as suas (`user_id=auth.uid()`); admin vê
  todas (`is_admin()`); INSERT só `service_role`
- Realtime publication activa para badge admin instantâneo

### §36.3 Skills Grupo 1 (5B-α)
- `UPDATE_DELIVERY_INSTRUCTIONS` (mode=`write_shadow`):
  - Estados permitidos: `created, preparing, callingDriver, driverAccepted`
  - Bloqueado: `pickedUp, onTheWay, delivered, cancelled`
  - Limite: 200 chars, substitui (não acumula)
  - **Nota técnica:** skill name é `UPDATE_DELIVERY_INSTRUCTIONS` mas a
    coluna real DB é `orders.customer_notes` (mapeamento no RPC)
- `UPDATE_DELIVERY_ADDRESS` (mode=`write_shadow`):
  - Estados permitidos: `created, preparing` apenas
  - Reset `dropoff_lat/lng = NULL` → re-geocode no próximo dispatch
  - Fora-de-zona escala via `HUMAN_REQUEST`
- **Adiados para 5B-β**: `OTP_RESEND` (sem flow OTP no app + `pg_net`
  settings ausentes), Grupo 2, Grupo 3

### §36.4 Defesa em profundidade — RPCs admin
- `agent_propose_action` é `SECURITY DEFINER` + GRANT só a `service_role`
  → app cliente NUNCA pode chamar directo, só via Edge Fn `support-chatbot`
  com `adminClient`
- `admin_approve_action`/`admin_reject_action`/`admin_list_pending_actions`
  têm `IF NOT public.is_admin() THEN RAISE 'NOT_ADMIN'` no topo
- `admin_approve_action` envolve o CASE em `BEGIN/EXCEPTION WHEN OTHERS`:
  qualquer erro → `status='failed'` + `execution_result.error` populado
- `GET DIAGNOSTICS v_rows_affected = ROW_COUNT` após cada UPDATE:
  zero rows → `RAISE EXCEPTION 'NO_ROWS_AFFECTED'`
- `orders.id` é TEXT (legado) — RPC compara como text directo, sem cast UUID

### §36.5 Admin Inbox (Flutter)
- `lib/screens/admin/admin_pending_actions_screen.dart`
- AppBar: badge contador realtime para pendentes novas
- Filtro status: pending / executed / rejected / failed / all
- Pull-to-refresh + realtime channel `support_pending_actions`
- Cards: cliente, mensagem original, payload formatado, agent_reasoning,
  timestamps, botões Aprovar (modal confirmação) / Rejeitar (TextField motivo)
- Linkado em `admin_dashboard_screen.dart` junto ao card "Knowledge Base"

### §36.6 Edge Function `support-chatbot` v3
- Tool `agent_propose_action` adicionada ao `TOOL_WHITELIST`
- Routing especial: `agent_propose_action` é service_role only,
  chama `adminClient.rpc(...)` directo (NÃO via `callRpc(userJwt, ...)`)
- Outras 5 tools `agent_get_*` continuam via user JWT + RLS (read-only)
- Sanitização anti-injection (`stripControlChars`, `SYSTEM_DELIM`) inalterada
- RAG (5C-β) inalterado; chatbot funciona com ou sem RAG

### §36.7 Skills Grupo 2 (Sessão 5B-β1 · 2026-05-06)
- `ACCOUNT_UPDATE` (mode=`write_shadow`):
  - Campos permitidos: `name` (2-100 chars), `phone` (E.164)
  - **FORBIDDEN_FIELD** explícito: email, password, role, wallet, tokens, fcm_token
  - Backwards-compat: aceita `full_name` como alias para `name`
- `PASSWORD_RESET` (mode=`write_shadow`):
  - Email vem de `auth.users` (não `public.users` que pode ter NULL)
  - Fire-and-forget via `pg_net` → Edge Fn nova `support-password-reset`
  - Edge Fn: `verify_jwt=false` + check `Authorization === SUPABASE_SERVICE_ROLE_KEY`
  - Verifica `user_id ↔ email` match em auth antes de chamar `auth.resetPasswordForEmail`
- `CANCEL_PRE_PURCHASE` (mode=`write_shadow`, **dispatch externo**):
  - `admin_approve_action` retorna `EXCEPTION 'EXTERNAL_DISPATCH_REQUIRED'` para forçar Flutter a despachar
  - Flutter `AdminPendingActionsScreen._approveCancelPrePurchase` chama
    `admin-cancel-order` Edge Fn (com admin JWT) → Stripe refund automático
    → `admin_finalize_action` RPC para marcar como executed
  - Reason recomendado: `client_request: <texto>`

### §36.8 Trigger push admin (Sessão 5B-β1)
- `trg_zz_pending_action_notify_admin` AFTER INSERT em `support_pending_actions`
- Função `fn_notify_admin_pending_action()` SECURITY DEFINER
- Lookup admin: `users` WHERE `fcm_token IS NOT NULL` AND `auth.users.email IN (admin emails)`
- Guard `IS NOT NULL` em `app.supabase_url`/`app.service_role_key` →
  silent skip se settings ausentes (não bloqueia INSERT)
- Chama `notify-client` Edge Fn com `clientId=admin_id`, title="Nova proposta IA"

### §36.9 RPC `admin_finalize_action` (Sessão 5B-β1)
- Permite Flutter marcar pending action como executed/failed/rejected após
  dispatch externo (CANCEL_PRE_PURCHASE → admin-cancel-order Edge Fn)
- Signature: `admin_finalize_action(p_action_id uuid, p_status text, p_result jsonb, p_reason text)`
- Validações: is_admin() + status ∈ (executed,failed,rejected) + action ainda pending

### §36.10 Limitações conhecidas (actualizadas)
- `pg_net` settings (`app.supabase_url`, `app.service_role_key`) NÃO configurados
  em prod — `PASSWORD_RESET` falha em runtime com `PG_NET_NOT_CONFIGURED` até config
- Trigger push admin: idem — silent skip se settings null (badge realtime
  funciona como fallback desde 5B-α)
- Cliente não vê estado da sua proposta (apenas "aguarda aprovação");
  notificação in-app adiada para 5B-β2
- `users.email` é NULL para muitos registos — RPC PASSWORD_RESET lê de
  `auth.users` (source of truth)
- Email Resend SMTP custom: adiado para 5B-β2

### §36.11 Skills Grupo 3a (Sessão 5B-β2a · 2026-05-06)

Cancelamentos avançados — 2 skills `write_shadow` reais com integração externa.

**CANCEL_DURING_PURCHASE**
- Activação: cliente quer cancelar pedido com estafeta envolvido —
  status ∈ {`callingDriver`, `driverAccepted`, `pickedUp`, `onTheWay`}.
- Status ∈ {`created`, `preparing`} → redirige para `CANCEL_PRE_PURCHASE`.
- Pattern: `EXTERNAL_DISPATCH_REQUIRED` (ver §36.12).
- Dispatch target: `admin-cancel-order` Edge Fn (com admin JWT).
- Reembolso: admin decide caso a caso conforme §8.3 (taxas variam por fase);
  playbook NÃO menciona valor exacto.

**RESERVATION_CANCEL**
- Activação: cliente quer cancelar reserva de mesa em status
  ∈ {`pending`, `approved`}.
- Janela de reembolso: `platform_settings.reservation_cancel_window_hours = 2`
  (≥2h → reembolso total €3; <2h → Bora retém — ver §18.3).
- Pattern: `EXTERNAL_DISPATCH_REQUIRED` (ver §36.12).
- Dispatch target: `admin-cancel-reservation` Edge Fn (NOVA — espelha
  `admin-cancel-order` para reservas).
- RPC dedicada `admin_cancel_reservation_on_behalf_of(p_reservation_id, p_reason)`
  — SECURITY DEFINER, sem owner check; espelha `client_cancel_reservation`
  semanticamente mas auditada como acção admin.
- Stripe refund é processado pela Edge Fn (RPC só retorna `prepayment_pi`).

⚠️ **Inconsistência docs reportada**: §12.3 menciona janela de "4 horas",
contradizendo §18.3 e DB (2h). DB é fonte da verdade — corrigir §12.3 em
sessão de housekeeping.

### §36.12 Pattern `EXTERNAL_DISPATCH_REQUIRED` (Sessão 5B-β2a · 2026-05-06)

Pattern para skills `write_shadow` cuja execução envolve operação externa
irreversível (Stripe refund, push FCM, etc.) que não pode ser feita
fire-and-forget de dentro de uma RPC SECURITY DEFINER.

**Status flow:** `pending → dispatched → executed | failed`

1. **Aprovação (`pending → dispatched`)** — Admin clica "Aprovar" no inbox.
   `admin_approve_action` valida preconditions (status do pedido/reserva,
   ownership, payload schema) e:
   - Marca `support_pending_actions.status = 'dispatched'`
   - Preenche `dispatch_target` (e.g. `admin-cancel-order`,
     `admin-cancel-reservation`)
   - Preenche `dispatched_at = now()`
   - Devolve `execution_result = { action: 'EXTERNAL_DISPATCH_REQUIRED',
     target, ...metadata }`

2. **Dispatch (`dispatched → executed | failed`)** — Admin clica "Executar"
   no inbox. `AdminPendingActionsScreen`:
   - Modal de confirmação (dispatch é irreversível)
   - `switch (dispatch_target)` → `Supabase.functions.invoke(...)` com admin JWT
   - Captura resultado e chama `admin_finalize_action(p_action_id, p_status,
     p_result, p_reason)` (RPC pré-existente desde 5B-β1 — NÃO foi criada
     `admin_mark_action_dispatched`).
   - Refresh do inbox

**Razão arquitectural:** `pg_net.http_post` é fire-and-forget (perde resultado
real); chamar Stripe API directamente de dentro do PG seria síncrono mas
requer service_role secret no SQL config. Dispatch via Flutter resolve ambos:
admin tem feedback visível + secret fica no Edge runtime.

**Skills usando o pattern (5B-β2a):**
- `CANCEL_PRE_PURCHASE` (refactor 5B-β2a — antes raise EXCEPTION → failed)
- `CANCEL_DURING_PURCHASE` (5B-β2a)
- `RESERVATION_CANCEL` (5B-β2a)

### §36.13 Skills Grupo 3b (Sessão 5B-β2b · 2026-05-06)

Info-only mercado + escalate — 4 skills sem geração de pending action.

**ITEM_UNAVAILABLE** (`read_only`)
- Activação: cliente pergunta sobre item não entregue ou substituído.
- Regras BR §3.x (reserva 15% anti-falta): cliente paga estimativa
  ×1.15; se item em falta, **estafeta substitui** por similar se cliente
  não responder no chat; cliente paga apenas o valor real.
- Tool: `agent_explain_event`.

**ITEM_ADDED** (`read_only`)
- Activação: cliente questiona item extra cobrado (➕ no app).
- Fórmula: `preço_base_mercado × 1.15 × qty` (15% =
  `_nonPartnerMarkupRate`); server aplica autoritativo em
  `finalize_storeshopping_purchase`.
- Tool: `agent_explain_event`.

**PRICE_DIFFERENCE** (`read_only`)
- Activação: diferença estimativa vs final.
- Regra: cobrança Stripe = estimativa ×1.15 (reserva 15%); cliente paga
  apenas o real comprado; extra é libertado automaticamente. NÃO
  prometer reembolso da diferença.
- Tool: `agent_explain_event`.

**PARTNER_REJECTED_ORDER** (`escalate`)
- Activação: parceiro rejeitou pedido (sem stock / encerrado /
  capacidade).
- Mecanismo: marker `[HANDOFF_HUMAN]` + `allowed_tools=[]`
  (consistência com `HUMAN_REQUEST` 5A-1).
- Sistema cria `support_tickets` automaticamente quando `escalated=true`.
- NÃO usa `agent_explain_event`. NÃO promete compensação (humano decide).

### §36.14 5B COMPLETO — total skills (após 5B-β2b)

- `read_only`: **11** (8 5A-2 + 3 Grupo 3b 5B-β2b)
- `write_shadow`: **7** (3 Grupo 1 5B-α + 2 Grupo 2 5B-β1 + 2 Grupo 3a 5B-β2a)
- `escalate`: **2** (HUMAN_REQUEST 5A-1 + PARTNER_REJECTED_ORDER 5B-β2b)
- **Total active: 20**

5B fechado. Próximas sessões: 5D (auto-suggest cron), 5E (auto-implement
zonas seguras), 5F (Robô A↔B), 5G (painel admin inbox), Sessão 6
(avaliações estrelas), Sessão 7 (validações finais + UUID refactor +
docs §12.3 / taxa cancel_during).

### §36.15 Tool `agent_explain_event` (Sessão 5B-β2b · 2026-05-06)

Tool read-only de logging em `support_agent_actions` (NÃO em
`support_pending_actions`). Não gera pending action; não requer
aprovação admin.

- **Whitelist:** `ITEM_UNAVAILABLE`, `ITEM_ADDED`, `PRICE_DIFFERENCE`.
- **shadow_status:** `'not_applicable'` (CHECK constraint da tabela
  aceita este valor).
- **Auth:** insert via `adminClient` (service_role) — bypass de RLS.
- **Falha silenciosa:** try/catch + console.warn; não bloqueia o fluxo
  conversacional.
- **Não usada por:** `PARTNER_REJECTED_ORDER` (essa skill usa
  `[HANDOFF_HUMAN]` marker que cria ticket automaticamente).

---

## §37 — AUTO-SUGGEST CRON SKILLS (Sessão 5D · 2026-05-06)

Sistema automático que analisa conversas chatbot e propõe novas skills
para cobrir padrões não cobertos por skills existentes.

### §37.1 Cron semanal

- `cron.job` `analyze-conversations-weekly`, schedule `0 4 * * 1`
  (segundas 04:00 UTC), active=true.
- Dispara `net.http_post` para Edge Fn `analyze-conversations` com
  `{ scheduled: true, days_back: 7, dry_run: false }`.
- ⚠️ Cron registado mas **inactivo em runtime** até config de
  `app.supabase_url` + `app.service_role_key` em prod (TODO histórico
  partilhado com PASSWORD_RESET / push admin trigger — ver §36.10).

### §37.2 Pipeline de análise

1. Lê mensagens `support_chatbot_messages` role='user' dos últimos 7
   dias (limit 200), prioridade para sessões `escalated=true`.
2. Threshold mínimo: `support_settings.skill_analysis_min_messages = 5`
   (default; admin pode editar). Abaixo → retorna
   `{ reason: 'below_threshold' }` sem chamar Gemini.
3. Anonimização PII regex: emails / phones (incluindo +351) /
   uuids / números 4+ dígitos → `[email]/[phone]/[id]/[number]`.
   Library GDPR (Microsoft Presidio) adiada (TODO 5D-β).
4. Pre-load anti-dedup: `skill_name` (active) + `pattern_summary`
   (pending) injectados no prompt como "NÃO duplicar".
5. Gemini 1.5 Flash (`gemini_model` setting). Output esperado:
   JSON array sem markdown fences. Parser robusto strip
   ```` ```json ``` ```` se modelo ignorar instrução.

### §37.3 Tabela `skill_suggestions`

```
id (uuid PK), suggested_at, status, pattern_summary,
sample_messages (jsonb), message_count, suggested_skill_name,
suggested_category, suggested_mode, suggested_playbook_md,
suggested_allowed_tools (jsonb), reviewed_at/by, rejection_reason,
implemented_skill_id (FK → support_skills.id ON DELETE SET NULL),
implemented_at, analysis_window_start/end, gemini_model,
pattern_hash, UNIQUE(pattern_hash, status)
```

- Status flow: `pending → implemented | rejected`.
- `pattern_hash = SHA256(pattern_summary.lowercase().trim())` —
  UNIQUE(pattern_hash, status) previne duplicatas em `pending`.
- RLS: admin_all (SELECT/INSERT/UPDATE/DELETE) + service_role_insert
  (Edge Fn).
- Realtime publication: `supabase_realtime` (badge admin actualiza ao
  vivo).

### §37.4 Admin workflow

`AdminSkillSuggestionsScreen` em `lib/screens/admin/`:

- Banner topo com cron status (próxima análise + última análise).
  Se `support_settings.last_skill_analysis_at IS NULL`, banner amber
  "Cron inactivo (config pendente)".
- Botão "🔄 Analisar Agora (7 dias)" — invoca Edge Fn directamente
  com JWT admin (não usa pg_net), rate-limited 1/h server-side.
- Lista cards filtrável: pending / approved / rejected / implemented /
  all.
- Aprovar → AlertDialog editor (skill_name + category + mode dropdown +
  playbook multiline 10 rows monospace) → `admin_approve_skill_suggestion`
  RPC cria skill activa + marca status=implemented.
- Rejeitar → motivo opcional → `admin_reject_skill_suggestion` RPC.
- Realtime badge contador pendentes no AppBar.

### §37.5 Regra de ouro

**Danilo aprova SEMPRE** antes de skill nova entrar em produção.
Sistema NÃO cria skills automaticamente. Editor de playbook
obrigatório no dialog.

### §37.6 Limitações conhecidas (5D)

- `pg_net` settings (`app.supabase_url`, `app.service_role_key`) NULL
  → cron inactivo em runtime; mitigação via botão manual.
- Anonimização PII regex simples — TODO library GDPR (5D-β).
- Dedup textual (SHA256 sobre `pattern_summary`) — TODO embeddar
  `support_skills.playbook_md` em `support_knowledge_chunks`
  (`source_type='skill'`) e usar `match_knowledge` semantic similarity
  ≥0.8 antes de INSERT (5D-β).
- Sem métricas: % aprovadas vs rejeitadas (5D-β).
- Sem editor markdown avançado: TextField multiline raw (5D-β).
- Sem re-análise inteligente (padrão N semanas consecutivas) — 5D-β.

---

## §38 — AUTO-IMPLEMENT ZONAS SEGURAS (Sessão 5E · 2026-05-06)

Estende §37: o pipeline de proposta passa a suportar 3 tipos com
classificação SAFE (1-clique) vs CRITICAL (manual). Regra ouro
`§37.5` mantém-se: **Danilo aprova SEMPRE** — 5E não cria
auto-approve sem intervenção humana.

### §38.1 Tipos de proposta

- `new_skill` (5D): criar skill nova.
- `playbook_update` (5E): actualizar `support_skills.playbook_md`
  de skill existente. Captura `previous_value` para rollback.
- `settings_update` (5E): actualizar coluna SAFE de
  `support_settings`. Captura `previous_value` para rollback.

### §38.2 Zonas

- **SAFE**: aprovação 1-clique → RPC executa imediatamente.
- **CRITICAL**: UI desactiva botão aprovar; mudança requer SQL
  manual via consola.

### §38.3 Skills CRITICAL (`playbook_update` zona crítica)

Hardcoded em `admin_approve_skill_suggestion` + Edge Fn
`analyze-conversations`:

- `CANCEL_PRE_PURCHASE`
- `CANCEL_DURING_PURCHASE`
- `RESERVATION_CANCEL`
- `PASSWORD_RESET`
- `ACCOUNT_UPDATE`
- `UPDATE_DELIVERY_INSTRUCTIONS`
- `UPDATE_DELIVERY_ADDRESS`
- `OTP_RESEND` *(defensivo — skill ainda não existe na DB,
  reservada CRITICAL se criada no futuro)*

### §38.4 SAFE settings whitelist (8 keys, validadas em A1)

Coluna real `support_settings`:

- `chatbot_welcome_text` *(text)*
- `sla_hours` *(integer)*
- `max_messages_per_session` *(integer)*
- `rate_limit_per_user_day` *(integer)*
- `max_output_tokens_per_call` *(integer)*
- `max_user_message_chars` *(integer)*
- `max_tool_iterations` *(integer)*
- `skill_analysis_min_messages` *(integer)*

Cast type-aware via `format('UPDATE %I = $1::%s', key, data_type)`
+ EXCEPTION wrapper `CAST_FAILED`.

### §38.5 CRITICAL settings (NÃO via proposta)

Mudança apenas via SQL directo:

- `gemini_model` *(impacto runtime chatbot)*
- `rag_enabled` *(toggle pipeline RAG)*
- `support_agent_enabled` *(kill switch global)*
- `shadow_mode` *(write_shadow vs effective)*
- `whatsapp_number`, `support_email` *(canais contacto)*

### §38.6 Rollback manual

`admin_rollback_suggestion(p_suggestion_id) RETURNS jsonb`:

- `playbook_update` → restaura `previous_value`,
  `version = GREATEST(version - 1, 1)`.
- `settings_update` → restaura `previous_value` com cast
  type-aware via `format()`.
- `new_skill` → `RAISE ROLLBACK_NOT_SUPPORTED_FOR_TYPE`
  (DELETE manual da skill criada).

Status final → `'rolled_back'` (CHECK constraint estendida em B1).

### §38.7 Defesas SQL injection

- `target_setting_key` CHECK constraint regex `^[a-z_]+$` (B1).
- Whitelist `v_safe_keys` validada **antes** de `format()` (B2).
- `format(%I::%s)` escape de identifier + `data_type` lookup
  em `information_schema.columns`.
- Edge Fn replica regex + whitelist client-side antes de INSERT.

### §38.8 BREAKING change RPC

`admin_approve_skill_suggestion` retorno mudou de `uuid` (5D) →
`jsonb` (5E) com fields:
`{type, skill_id, skill_name, setting_key, old_value, new_value, data_type}`.
Flutter 5D ignorava retorno → **sem regressão**.

### §38.9 UNIQUE constraint estendido

`(pattern_hash, status)` → `(pattern_hash, proposal_type, status)`.
Mesmo padrão pode ter propostas distintas por tipo
(ex: `new_skill` E `playbook_update` mesma summary).

### §38.10 Limitações conhecidas (5E)

- **Versioning frágil**: `version - 1` em rollback não é
  monotonic (ideal: tabela `support_skills_history`); TODO 5E-β.
- **Diff visual**: `TextField` simples; TODO biblioteca diff
  proper (5E-β).
- **`new_skill` rollback**: DELETE manual via SQL; aceitado.
- **Token output Gemini limit**: `maxOutputTokens=8192`; playbooks
  >8K tokens podem ser truncados.
- **Auto-approve threshold**: não implementado; sempre humano-in-loop.
- **Auditoria histórica**: aprovador (`reviewed_by`) capturado
  mas sem dashboard de métricas; TODO 5E-β.

### §38.11 Edge Fn `analyze-conversations` v2

Estendida para propor 3 tipos via Gemini. SHA `47949922bb…`
substituiu v1 `627d5c82…`. `maxOutputTokens` 4096 → 8192.
Lookup `target_skill_id` + `previous_value` em INSERT
(playbook_update e settings_update). `breakdown` no response.

---

## §39 — COMUNICAÇÃO ROBÔ A ↔ ROBÔ B (Sessão 5F · 2026-05-06)

Comunicação assíncrona entre os dois robôs do sistema:
- **Robô A** = `support-chatbot` Edge Fn (Gemini 1.5 Flash; cliente)
- **Robô B** = Claude Code com skill `ask-knowledge-base` + RAG

Cliente reporta problema técnico → Robô A escala via skill
`ASK_ROBOT_B` + tool `agent_ask_robot_b` → Claude Code consulta
RAG via `match_knowledge` (5C-α) e responde via
`robot_b_respond`. Admin observa em `AdminCrosstalkScreen` (5F)
ou no terminal via `scripts/crosstalk/check_pending.ts`.

### §39.1 Tabela `robot_crosstalk`

```
direction       text     ('a_to_b' | 'b_to_a')
status          text     ('pending' | 'answered' | 'ignored')
asked_by        text     ('robot_a' | 'robot_b' | 'admin')
answered_by     text     ('robot_a' | 'robot_b' | 'admin' | NULL)
question        text     (anonimizada server-side)
question_context jsonb   ({screen_name, error_message, …})
answer          text     (preenchida em b_to_a respond)
rag_chunks_used jsonb    (chunks consultados pelo Robô B)
session_id      uuid FK → support_chatbot_sessions
                          ON DELETE SET NULL  (preserva histórico)
skill_triggered text     ('ASK_ROBOT_B' default)
```

RLS: `admin_all` (`is_admin()`) + `service_role_all`. Realtime
publication ADD para `AdminCrosstalkScreen` badge live.

### §39.2 Helper `_anonymize_pii(text)` PostgreSQL

Função SQL `IMMUTABLE` reusable. Anonimiza email / phone PT
(`+351 9XX XXX XXX`) / phone genérico / UUID / números 4+
em ordem **UUID antes do phone genérico** (fix bug detectado
em smoke S2 — JS 5D `analyze-conversations` tem mesmo bug,
TODO 5F-β).

### §39.3 Robô A → B (`agent_ask_robot_b`)

- RPC SECURITY DEFINER, GRANT `authenticated + service_role`
- Check interno `auth.uid() IS NOT NULL`
- INSERT `direction='a_to_b'`, `status='pending'`,
  `asked_by='robot_a'`, anonimização automática via helper
- Tool `agent_ask_robot_b` no `support-chatbot v7`
  (TOOL_WHITELIST + buildFunctionDeclarations; segue padrão
  callRpc genérico, não branch shadow)
- Skill `ASK_ROBOT_B` mode='escalate', allowed_tools=
  `["agent_ask_robot_b"]`, category='technical_support',
  active=true (B2 seed)

Diferenciação vs `HUMAN_REQUEST` (escalate):
- `ASK_ROBOT_B`: bug técnico ou comportamento inesperado app
- `HUMAN_REQUEST`: cliente pede explicitamente humano

### §39.4 Robô B → A (`robot_b_respond`)

- RPC SECURITY DEFINER, GRANT **`service_role` only**
  (scripts crosstalk via `SUPABASE_SERVICE_ROLE_KEY`)
- UPDATE pending → `answered`, `answered_by='robot_b'`,
  preenche `answer`+`rag_chunks_used`+`answered_at`
- Falha `CROSSTALK_NOT_FOUND_OR_NOT_PENDING` se row
  inexistente OU já answered (evita double-respond)

### §39.5 Admin observador (`admin_list_crosstalk`)

- RPC SECURITY DEFINER, GRANT `authenticated`
- Check interno `is_admin()`; non-admin → `RAISE NOT_ADMIN`
- Filtros `p_status` (pending/answered/ignored/all) +
  `p_direction` (a_to_b/b_to_a/all)
- Returns table com `rag_chunks_count` agregado +
  `rag_chunks_used` JSON completo para drill-down

`AdminCrosstalkScreen`: cards com badge direcção (laranja A→B
/ verde B→A) + status amarelo/verde, tap chunks → JSON dialog.
Realtime subscription filtrada `status=eq.pending` para badge.
**Modo observador apenas** — sem botão reply em 5F.

### §39.6 Skill Claude Code `ask-knowledge-base`

`.claude/skills/ask-knowledge-base/SKILL.md` instrui workflow:

1. `scripts/crosstalk/check_pending.ts` — lista a_to_b pending
2. `scripts/crosstalk/query_knowledge.ts <termo>` — RAG via
   `match_knowledge` (Gemini embedding RETRIEVAL_QUERY dim=768,
   top-8 com min_similarity=0.5)
3. `scripts/crosstalk/respond.ts <id> <answer>` — submete via
   `robot_b_respond`

Scripts gate: se `SUPABASE_SERVICE_ROLE_KEY` ausente em
`scripts/rag/.env` → exit 1 com mensagem clara.

### §39.7 Fluxo end-to-end

```
[cliente]      "a app fecha ao abrir o mapa"
   ↓           (Robô A skill ASK_ROBOT_B)
[chatbot v7]   tool agent_ask_robot_b(question, context)
   ↓           anonimização _anonymize_pii server-side
[robot_crosstalk] INSERT direction=a_to_b status=pending
   ↓           realtime push
[Admin / CC]   AdminCrosstalkScreen badge OR check_pending.ts
   ↓           query_knowledge.ts <termo> → RAG chunks
[Robô B]       respond.ts <id> "answer" '[chunks]'
   ↓           robot_b_respond service_role
[robot_crosstalk] UPDATE status=answered answered_by=robot_b
   ↓
[Admin]        AdminCrosstalkScreen vê resposta
```

### §39.8 Limitações conhecidas (5F)

- **Comunicação manual**: Robô B responde manualmente via
  scripts; sem auto-resposta — TODO 5F-β.
- **Sem push admin**: realtime badge só na UI; sem
  notification — TODO 5F-β.
- **Admin observador apenas**: `admin_respond_to_crosstalk`
  RPC + UI reply são TODO 5F-β.
- **`SUPABASE_SERVICE_ROLE_KEY`**: requer `scripts/rag/.env`
  configurado pelo Danilo manualmente; sem fallback.
- **Anonymization PG vs JS drift**: PG (5F) corrigido com
  UUID antes phone genérico; JS 5D `analyze-conversations`
  mantém bug — TODO 5F-β.
- **Sem métricas**: rate respondido vs ignored — TODO 5F-β.

### §39.9 Defesas

- RLS `robot_crosstalk` admin + service_role only
- RPCs SECURITY DEFINER + check interno
- `robot_b_respond` GRANT exclusivo `service_role` (scripts)
- Anonimização automática server-side em INSERT (não confia
  em client)
- Skill `ASK_ROBOT_B` `requires_human_handoff=false` (não
  escala automaticamente para ticket — só regista crosstalk)

---

## §40 — NOTIFICAÇÕES URGÊNCIA ADMIN (Sessão 5F-α · 2026-05-06)

Estende §39 com classificação de urgência por Robô A no momento
da escalação para `robot_crosstalk`. Em 5F-α o canal é
**realtime apenas** (admin tem de ter `AdminCrosstalkScreen`
aberta para ver o badge live). Push real (FCM + email) fica
para 5F-β.

### §40.1 Coluna `robot_crosstalk.urgency`

- `text NOT NULL DEFAULT 'normal'`
- `CHECK (urgency IN ('critical','medium','normal'))`
- Index parcial `idx_crosstalk_urgency_critical` em
  `(urgency, status, created_at DESC) WHERE urgency='critical' AND status='pending'`
- Backfill ALTER ADD: rows existentes ficam `'normal'`
  (em 5F-α a tabela tinha 0 rows — backfill irrelevante)

### §40.2 Classificação no Robô A

`support_skills.ASK_ROBOT_B.playbook_md` v2 instrui Gemini a
classificar antes de chamar `agent_ask_robot_b`:

- 🔴 **critical** — bloqueia uso ou perde dinheiro
  (pagamento descontado sem pedido criado, conta bloqueada,
  app crash bloqueante no checkout, perda de dados/acesso indevido)
- 🟡 **medium** — atrapalha mas tem workaround
  (lentidão, botão intermitente, crashes não-bloqueantes)
- 🟢 **normal** — comportamento estranho mas não bloqueia
  (UI torta, ícone duplicado, notificação tardia)

Para `critical` o Robô A **NÃO** sugere soluções básicas
(reabrir/internet/reiniciar) — regista imediatamente para
análise técnica.

### §40.3 Tool `agent_ask_robot_b` (chatbot v8)

- Param novo `p_urgency` enum opcional (`critical|medium|normal`)
- Default `'normal'` se omitido
- **Sanitização server-side** RPC: valor inválido → fallback `'normal'`
  (não falha hard — Gemini pode mandar lixo sem partir o fluxo)
- GRANT preservado: `authenticated + service_role` (Opção A do
  audit 5F-α — chatbot chama via user JWT, anti-spam vem de
  `support_settings.rate_limit_per_user_day`)
- Dispatcher genérico do chatbot (`callRpc`) passa `p_urgency`
  ao RPC automaticamente — apenas 1 mudança no Edge Fn
  (`buildFunctionDeclarations` ganha prop `p_urgency`)

### §40.4 `admin_list_crosstalk`

- 4 args (added `p_urgency` 3º antes de `p_limit`):
  `(p_status, p_direction, p_urgency, p_limit)`
- Coluna `urgency` adicionada ao `RETURNS TABLE`
- ORDER BY `CASE urgency WHEN 'critical' THEN 1 WHEN 'medium' THEN 2 WHEN 'normal' THEN 3`
  então `created_at DESC` — críticas sempre no topo
- DROP+CREATE necessário porque `RETURNS TABLE` mudou — RE-GRANT
  explícito para `authenticated + service_role`
- Flutter `AdminCrosstalkScreen` já usa NAMED params → adicionar
  `'p_urgency'` é compatível sem migração extra

### §40.5 `AdminCrosstalkScreen`

- Estado `_urgencyFilter` (default `'all'`) + `_criticalCount`
- 3º `PopupMenuButton` urgência no AppBar
  (4 opções: all/critical/medium/normal com emojis)
- `_buildUrgencyBadge(String)` — Container colorido
  (vermelho/âmbar/cinza) + texto bold em cada card, ao lado
  do badge de status
- **Banner crítico (Opção 2)**: empilhado **acima** do banner
  observador 5F quando `_criticalCount > 0`
  (Card vermelho `#FFEBEE` com aviso "⚠️ N comunicação(ões)
  CRÍTICA(S) pendente(s)")
- `_refreshBadge` reusa o payload pendente (1 só RPC call)
  para computar `_pendingBadge` e `_criticalCount`
- Realtime preservado (5F filter `status=eq.pending`) —
  recarrega lista + recalcula contador crítico

### §40.6 Limitações 5F-α

- **Notificação só funciona com app aberta** — admin tem de
  estar com `AdminCrosstalkScreen` no ecrã para ver o badge live.
- **Push real (mesmo com app fechada)** requer 5F-β:
  `pg_net` settings (`app.supabase_url`, `app.service_role_key`),
  tabela `admin_push_tokens` com FCM tokens, Edge Fn
  `notify-admin-urgent`, trigger AFTER INSERT.
- **Email Resend** requer config 5F-β (Resend API key em secrets).
- **Sem WhatsApp** — decisão Danilo: zero custo extra, sem
  dependência terceira.
- **Sem reply UI** — admin continua a responder via
  `scripts/crosstalk/respond.ts`. `admin_respond_to_crosstalk`
  RPC + UI reply são TODO 5F-β.
- **Anonymization JS drift** (5D `analyze-conversations`) —
  TODO 5F-β.

### §40.7 Regra ouro 5F-α

> Robô A classifica → Robô B vê em tempo real (admin app aberta) →
> Danilo decide e responde manualmente via scripts/crosstalk.

Push notification real só em 5F-β. Em 5F-α o banner topo
vermelho garante visibilidade imediata em sessão admin activa.

---

## §41 — PUSH ADMIN URGENTE + REPLY UI + EMAIL (Sessão 5F-β · 2026-05-07)

### §41.1 Tabela `admin_push_tokens`

- 1 row por device admin (multi-device por admin) — `fcm_token UNIQUE`
- Schema: `id uuid pk`, `admin_id uuid FK auth.users ON DELETE CASCADE`,
  `fcm_token text NOT NULL UNIQUE`, `device_label text`,
  `platform text CHECK in (android,ios,web)`,
  `last_used_at timestamptz`, `created_at timestamptz`
- Indexes: `idx_admin_push_tokens_admin (admin_id)`,
  `idx_admin_push_tokens_last_used (last_used_at DESC)`
- RLS enabled + 2 policies:
  - `admin_own` — `admin_id = auth.uid() AND is_admin()` (FOR ALL)
  - `service_role_all` — `auth.role() = 'service_role'` (Edge Fn cleanup)

### §41.2 RPC `admin_register_push_token(p_fcm_token, p_device_label, p_platform)`

- SECURITY DEFINER; gate `is_admin()`; valida platform enum + token não-vazio
- UPSERT em conflict `fcm_token`:
  - `admin_id` actualizado para current admin (handles device sharing)
  - `device_label`/`platform` actualizam apenas se passados (COALESCE)
  - `last_used_at = now()` em cada registo
- Returns `uuid` (id da row)
- GRANT EXECUTE TO authenticated; REVOKE FROM public, anon
- Erros: `NOT_ADMIN`, `FCM_TOKEN_REQUIRED`, `INVALID_PLATFORM`

### §41.3 RPC `admin_respond_to_crosstalk(p_crosstalk_id, p_answer)`

- SECURITY DEFINER; gate `is_admin()`; valida `p_answer` não-vazio (trim)
- UPDATE robot_crosstalk SET `answer`, `answered_at=now()`,
  `answered_by='admin'`, `status='answered'`
  WHERE `id = p_crosstalk_id AND status = 'pending'`
- Erro `CROSSTALK_NOT_FOUND_OR_NOT_PENDING` se WHERE não bater
- Returns `jsonb { answered:true, crosstalk_id, answered_by:'admin' }`
- GRANT EXECUTE TO authenticated
- Distinção: `answered_by` agora pode ser `'b'` (Robô B via scripts) ou
  `'admin'` (Danilo via UI 5F-β) — UI mostra chips diferentes

### §41.4 Trigger `_notify_admin_urgent_trigger`

- AFTER INSERT em `robot_crosstalk` (`trg_robot_crosstalk_notify_urgent`)
- Filtro: só `direction='a_to_b' AND urgency='critical' AND status='pending'`
- Gate `pg_net` settings: skip silent (RAISE NOTICE) se
  `app.supabase_url` ou `app.service_role_key` em falta
- Chama `notify-admin-urgent` Edge Fn via `net.http_post`
- EXCEPTION WHEN OTHERS: nunca bloqueia INSERT; apenas RAISE NOTICE
- Body: `{ crosstalk_id, question, session_id, context }`

### §41.5 Edge Fn `notify-admin-urgent`

- `verify_jwt=false`; auth interna por match exacto
  `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>` → 403 caso contrário
- Pattern FCM **HTTP v1 + OAuth2 Service Account** (consistente com
  `notify-driver`/`notify-client`/`notify-partner`):
  - Endpoint `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`
  - JWT RS256 assertion → access_token (`getFirebaseAccessToken`)
- Push paralelo via `Promise.allSettled` para todos `admin_push_tokens`
- Cleanup automático: tokens com `errorCode IN (UNREGISTERED, INVALID_ARGUMENT)`
  → DELETE row em `admin_push_tokens`
- Email Resend **opcional**: skip silent se `RESEND_API_KEY` MISSING;
  HTML escapado em `escapeHtml()`
- Returns 200 sempre com `{ ok, crosstalk_id, push_attempted, push_success,
  push_cleaned, email_sent }`
- Graceful no-op quando Firebase env vars MISSING

### §41.6 Flutter `AdminPushService`

- Singleton private (static class) em `lib/services/admin_push_service.dart`
- `registerForAdmin()`:
  - Gate `AuthAdminService.isAdmin()` — no-op para não-admin
  - Reusa `NotificationService.instance.fcmToken` (não duplica permission)
  - Fallback `FirebaseMessaging.instance.getToken()` se singleton vazio
  - Listener `onTokenRefresh` registado uma vez (`_refreshSub ??= ...`)
  - Idempotente: guard `_registering` evita races
- `setupDeepLinks(context)`:
  - `onMessageOpenedApp` — push tap em foreground/background
  - `getInitialMessage()` — cold-start (app fechada quando push chegou)
  - Filtro `data.type == 'crosstalk_critical'` → `pushNamed('/admin/crosstalk')`
  - Idempotente: guard `_deepLinksWired`
- Device label via `Platform.operatingSystem` (sem `device_info_plus` dep)

### §41.7 AdminCrosstalkScreen reply UI (5F-β)

- Botão "💬 Responder" (verde Bora) em cards `status='pending' AND direction='a_to_b'`
- Dialog `_openReplyDialog`:
  - Preview pergunta (200 chars max) + TextField multiline 5-10 linhas
  - Validator não-vazio
  - Submit → RPC `admin_respond_to_crosstalk`
  - SnackBar verde sucesso / vermelho erro (mapeia NOT_ADMIN /
    ANSWER_REQUIRED / CROSSTALK_NOT_FOUND_OR_NOT_PENDING para PT)
  - Reload + refresh badge após sucesso
- Chip distintivo no bloco answer:
  - `answered_by='admin'` → "✋ Respondido por admin" (verde Bora)
  - `answered_by='b'/'a'` → "🤖 Respondido por Robô B/A" (azul)
- Banner topo actualizado: "Reply UI activa (5F-β)"
- Hookup dashboard: `WidgetsBinding.addPostFrameCallback` em
  `AdminDashboardScreen.initState` chama
  `AdminPushService.registerForAdmin() + setupDeepLinks(context)`
- Rota nomeada nova: `'/admin/crosstalk'` em `main.dart` para deep link

### §41.8 Activação manual Danilo (pós-deploy) — TODOs CRÍTICOS

#### 1. `pg_net` settings (BLOQUEANTE — trigger inactivo até config)

ALTER DATABASE via MCP falha por privilege. Configurar via Supabase
Dashboard SQL editor:

```sql
ALTER DATABASE postgres
  SET app.supabase_url = 'https://ojykpzwqrtusfeakzrna.supabase.co';
ALTER DATABASE postgres
  SET app.service_role_key = '<service_role_key do dashboard>';
SELECT pg_reload_conf();
```

Activa simultaneamente: 5D cron, 5B-β1 trigger,
`PASSWORD_RESET` real, **5F-β notify-admin-urgent trigger**.

#### 2. `RESEND_API_KEY` (opcional — só email)

```bash
supabase secrets set RESEND_API_KEY=<key> \
  --project-ref ojykpzwqrtusfeakzrna
```

Sem isto: push FCM funciona normalmente; email skip silent
(log: `RESEND_API_KEY missing — email skipped`).

#### 3. Domínio email Resend

Confirmar `noreply@boraapp.com` verificado no Resend Dashboard.
Caso seja outro, editar Edge Fn linha `EMAIL_FROM`.

#### 4. Admin abrir admin app uma vez pós-deploy

Sem isto: 0 tokens em `admin_push_tokens` → 1ª notificação não chega
(push_attempted=0). `AdminPushService.registerForAdmin()` corre
no `initState` do dashboard.

### §41.9 Limitações 5F-β

- **Trigger inactivo até `pg_net` config** (TODO §41.8 #1 BLOQUEANTE)
- **Email skip se Resend missing** — comportamento por design
- **1ª notificação só após admin abrir app** — registo FCM token no `initState`
- **WhatsApp não suportado** — decisão Danilo (zero custo extra)
- **Sem `device_info_plus`** — `device_label` é `os + version` (sem modelo)
- **Anonymization JS drift** (5D `analyze-conversations`) — continua TODO

### §41.10 Regra ouro 5F-β

> Cliente reporta crítico → trigger DB → Edge Fn → push FCM em todos
> devices admin + email opcional → admin abre app via deep link →
> responde via Reply UI → resposta vai para `answered_by='admin'`.

Push real **mesmo com app fechada** desde que `pg_net` settings
configurados e admin tenha aberto app pelo menos uma vez.

---

## §42 Activação pg_net via Supabase Vault (Sessão 5F-β-α)

### §42.1 Decisão arquitectural

`ALTER DATABASE postgres SET app.*` requer privilégio **superuser** que
**não está disponível em Supabase managed**. Tentativa anterior (5F-β
audit, §41.8) confirmou `permission denied`.

**Solução:** Supabase Vault (`supabase_vault` extension v0.3.1).
- Encrypted-at-rest (segurança superior a current_setting)
- Acessível via `vault.decrypted_secrets` em `SECURITY DEFINER` functions
- Permite rotação de keys sem alterar código (apenas UPDATE row)
- Padrão moderno recomendado pelos docs Supabase

### §42.2 Vault secrets registados

| name | propósito |
|---|---|
| `project_url` | `https://ojykpzwqrtusfeakzrna.supabase.co` |
| `service_role_key` | JWT service_role (nunca loggar valor; rotar periodicamente) |
| `dispatch_anon_jwt` | (pré-existente, S2 cutover 2026-04-30) |

### §42.3 Padrão para futuros triggers

```sql
DECLARE v_url text; v_key text;
BEGIN
  SELECT decrypted_secret INTO v_url
  FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url || '/functions/v1/<edge_fn>', ...);
END;
```

Para cron jobs: subqueries inline `(SELECT decrypted_secret FROM
vault.decrypted_secrets WHERE name = '...')`.

### §42.4 Rotação de keys

```sql
UPDATE vault.secrets SET secret = '<new>', updated_at = now()
WHERE name = 'service_role_key';
```

### §42.5 Componentes refactorizados (5F-β-α)

| Componente | Origem | Migration |
|---|---|---|
| `_notify_admin_urgent_trigger` | 5F-β | B2 |
| `admin_approve_action` (PASSWORD_RESET) | 5B-β1 | B3 |
| `fn_notify_admin_pending_action` | 5B-β1 | B3 |
| cron jobid 28 (analyze-conversations-weekly) | 5D | B4 |

### §42.6 Features activadas

- 5D cron auto-suggest skills (weekly)
- 5B-β1 push admin pending actions
- 5F-β push admin urgência crítica
- PASSWORD_RESET real

### §42.7 Migration B1 — Opção B (recomendada)

`.sql` **NÃO** committado ao repo (apenas apply_migration directo).
Zero exposição service_role_key em git history.

### §42.8 Limitações + fix1

- ~~Edge Fns com `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` fazem
  string-match exacto~~ → **5F-β-α-fix1**: Edge Fn `notify-admin-urgent`
  refactorizado para `verify_jwt=true` + JWT payload role check em vez
  de string-match contra env var. Padrão moderno Supabase, à prova de
  rotação de key. Aplicar mesmo padrão em qualquer nova Edge Fn que
  precise de auth service_role.
- `SECURITY DEFINER` owner deve ter acesso ao vault (default `postgres`)
- Sem auto-rotation; manual UPDATE

### §42.8.1 Padrão auth Edge Fn (5F-β-α-fix1)

```ts
// deploy com verify_jwt=true (platform valida signature)
const authHeader = req.headers.get('Authorization') ?? ''
if (!authHeader.startsWith('Bearer ')) return forbidden403
try {
  const token = authHeader.substring(7)
  const payload = JSON.parse(atob(token.split('.')[1]))
  if (payload.role !== 'service_role') return forbidden403
} catch { return forbidden403 }
```

### §42.9 Cron jobs `update-*` (legacy) — fora de escopo

7 jobs usam `current_setting('app.settings.service_role_key', true)`
(formato antigo). Sessão futura "5F-β-β cron cleanup".

### §42.10 Regra ouro

> Settings dinâmicas em Supabase managed → vault, nunca `ALTER
> DATABASE SET app.*`. Toda nova função com URL+key lê vault em
> variáveis locais com gate `IF NULL THEN RETURN`.

---

## §43 — Painel Admin Inbox Avançado (Sessão 5G)

### §43.1 Coluna `admin_notes` em `skill_suggestions`

- `text NULL DEFAULT NULL` (B1)
- Notas internas só visíveis ao admin
- Atualizada via `admin_update_skill_suggestion_note(p_id, p_note)`
- UI faz autosave 1s debounce
- `p_note` vazio ou só whitespace → guardado como `NULL`

### §43.2 Status enum estendido (B1)

`CHECK status IN (...)` com **6 valores**:

| valor | quando | origem |
|---|---|---|
| `pending` | sugestão acabada de criar | 5D |
| `approved` | aprovada (pré-implementação) | 5D |
| `rejected` | rejeitada manual | 5D |
| `implemented` | aprovada e aplicada | 5E |
| `rolled_back` | aplicada e depois revertida | 5E |
| `auto_archived` | >30 dias `pending` sem revisão | **5G novo** |

> 5E values **preservados sem mudança**. `ALTER CHECK` correu com 0 rows em prod.

### §43.3 4 RPCs novas (B2)

| RPC | Devolve | Notas |
|---|---|---|
| `admin_skill_suggestions_stats()` | jsonb 10 campos | total / pending / approved / implemented / rejected / rolled_back / auto_archived / with_notes / pct_approved / oldest_pending_days |
| `admin_skill_suggestions_metrics()` | jsonb 5 campos | avg_review_hours · top_categories (até 10) · by_month (6m) · by_type · by_zone |
| `admin_bulk_reject_skill_suggestions(p_ids uuid[], p_reason text)` | jsonb `{rejected_count, requested_count}` | max 50 ids · reason obrigatório · só rejeita rows com `status='pending'` |
| `admin_update_skill_suggestion_note(p_id uuid, p_note text)` | void | `RAISE EXCEPTION SUGGESTION_NOT_FOUND` se id inválido |

Todas com `is_admin()` gate, `SECURITY DEFINER`, `search_path=public`,
`REVOKE ALL ... FROM public, anon`, `GRANT EXECUTE TO authenticated`.

### §43.4 `admin_list_skill_suggestions` REPLACE (B3)

`(p_status, p_type, p_zone, p_category, p_search, p_limit)` — 6 params, todos com defaults backward-compat com a versão antiga (`p_status='pending'`, `p_limit=50`).

- `p_search` usa FTS portuguesa: `to_tsvector('portuguese', pattern_summary) @@ plainto_tsquery('portuguese', p_search)`
- ORDER BY status: `pending=1, implemented=2, approved=3, rejected=4, rolled_back=5, auto_archived=6`
- ORDER BY zone: `critical=1, safe=2`
- Tie-break: `suggested_at DESC`

### §43.5 Cron `auto-archive-old-suggestions` (B4)

- **Schedule:** `'0 3 * * *'` (diária 03:00 UTC)
- **Função:** `_auto_archive_old_suggestions()` — `UPDATE skill_suggestions SET status='auto_archived', reviewed_at=now() WHERE status='pending' AND suggested_at < now() - interval '30 days'`
- Idempotente (`DO $$ ... cron.unschedule ... $$`)

### §43.6 Indexes novos (B1)

| index | tipo |
|---|---|
| `idx_skill_suggestions_status_type` | btree (status, proposal_type, suggested_at DESC) |
| `idx_skill_suggestions_zone` | btree (zone_type) WHERE zone_type NOT NULL |
| `idx_skill_suggestions_category` | btree (suggested_category) |
| `idx_skill_suggestions_search` | GIN to_tsvector('portuguese', pattern_summary) |

Coexistem com 6 indexes existentes (5D + 5E) sem conflito.

### §43.7 UI Flutter — `AdminSkillSuggestionsScreen` (B5)

8 features adicionadas mantendo retrocompatibilidade:

1. **Stats card no topo** — 4 contadores (Pendentes/Implementadas/Rejeitadas/Arquivadas) + taxa aprovação + dias mais antigo pendente
2. **`ExpansionTile` filtros** — Estado / Tipo / Zona / Categoria (texto livre) + Pesquisa FTS-PT debounce 500ms + botão "Limpar filtros"
3. **Diff lado-a-lado** — para `playbook_update`: 2 colunas (Antes vermelho / Depois verde), linhas diferentes destacadas. Naive linha-a-linha; **LCS proper TODO 5G-β** (`diff_match_patch`)
4. **Bulk reject** — checkbox em cards `pending`, AppBar muda quando selecção activa (laranja + contador), dialog "Rejeitar N propostas" com razão obrigatória
5. **Notas internas** — TextField `maxLines=3, maxLength=500` por card; autosave 1s debounce via `_onNoteChanged(id, value)`
6. **FAB Métricas** — laranja, navega para `/admin/suggestions/metrics`
7. **Empty states PT-PT** — distingue "Sem propostas no momento" vs "Nenhum resultado para os filtros"
8. **Status enum estendido na UI** — 7 opções dropdown (Pendentes/Implementadas/Aprovadas/Rejeitadas/Revertidas/Arquivadas/Todas)

`_refreshBadge` agora usa `admin_skill_suggestions_stats` (1 RPC com 10 campos) em vez de `.length` da lista — mais eficiente.

### §43.8 UI Flutter — `AdminSkillSuggestionsMetricsScreen` (B6)

Novo ecrã `/admin/suggestions/metrics`. 4 gráficos `fl_chart 0.69.0`:

| Gráfico | Tipo | Cores Bora |
|---|---|---|
| Por tipo | Pie | verde · laranja · cinza |
| Por zona | Pie | verde · vermelho |
| Top categorias | Bar | verde |
| Por mês (6m) | Line | laranja |

Empty states "Sem dados ainda" para cada gráfico se RPC devolve vazio.

### §43.9 UI Flutter — `AdminDashboardScreen` (B7)

- `_NavCard` ganha param opcional `badgeCount: int = 0`
- "Sugestões Skills IA" mostra bolinha vermelha com contador pendentes (>99 → "99+")
- `RouteAware` mixin: `didPopNext` chama `_loadPendingSuggestionsCount()` — refresh quando admin volta do écran de propostas
- `routeObserver` global em `main.dart` (`navigatorObservers`)

### §43.10 Regra ouro

> Toda nova feature admin **não** entra na Launch Readiness Checklist a menos que afecte directamente Receita / UX cliente / Estabilidade core. 5G é Categoria 4 (Velocidade de Lançamento).

---

*Documento de regras de negócio — Bora App*
*Última atualização: 2026-05-07 (§43 — Sessão 5G Painel Admin Inbox Avançado)*
*Atualizar sempre que houver mudanças nas regras de negócio*
*Fonte de verdade usada por: todas as skills do sistema*
