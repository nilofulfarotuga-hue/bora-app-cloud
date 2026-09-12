# TVDE — Card + MB Way nas corridas (implementação) — 2026-07-07

Branch: `autonomous-night-2026-04-29` · Scope: **Edge Function + Flutter** (backend já aplicado via
MCP pelo Danilo). **Kill switch `tvde_card_payments_enabled` = OFF** — nada cobra em produção.

## ⚠️ O que fica para o Danilo (passos de dinheiro — NÃO fiz)

1. **Deploy da Edge Function `tvde-payment`** (escrita + commitada, **NÃO deployada** nesta sessão —
   é código de dinheiro por testar). Deploy com `verify_jwt=true`. Comando MCP/CLI:
   `supabase functions deploy tvde-payment` (ou MCP `deploy_edge_function`).
2. **Ligar o switch** `tvde_card_payments_enabled=true` — **só depois** do deploy + teste com cartão
   real. Enquanto OFF, a UI esconde card/mbway e a RPC/Edge Function rejeitam.
3. **Wiring da captura no fim** (ver §"Falta ligar"): hoje a Edge Function TEM as ações
   `capture`/`settle`, mas ninguém as chama ainda no fim da corrida. Sem isto, o cartão fica
   autorizado mas não capturado.

## Backend já no ar (confirmado via MCP — não recriei/alterei)

- `tvde_request_ride(...)` tem `p_payment_method text DEFAULT 'cash'` (assinatura única, sem overload).
- `tvde_finish_ride` liquida por método (cash = deve `bora_cut`; card/mbway = saldo −`driver_earn`).
- `tvde_card_payments_enabled=false`, `tvde_auth_margin_pct=20`.
- `admin_tvde_rides_list` devolve `payment_method`.
- Arquivei a proposta antiga: `relatorios/proposta-tvde-card-mbway.APLICADO-VIA-MCP.sql.bak` (NÃO correr).

## O que implementei

### Migration (aplicada via MCP — colunas nullable, NÃO mexe em valores)
`tvde_rides` ganhou `payment_intent_id text` + `payment_status text` (ligam o Stripe PI à corrida).

### A) Edge Function `supabase/functions/tvde-payment/index.ts` (NOVA, isolada)
Não toca no `stripe-webhook`. Padrão copiado das functions Stripe existentes (inline CORS, Stripe
`apiVersion 2023-10-16`, toggle test/live, cliente JWT p/ criar a ride como o utilizador). Ações:
- **`authorize` (cartão):** PaymentIntent `capture_method=manual`, hold = **estimado × (1+20%)**
  (`tvde_calculate_fare` server-side — nunca confia no cliente), cria a corrida (JWT), liga o PI.
  Devolve `clientSecret` p/ o cliente confirmar o hold. Se a criação da ride falhar → **void** do PI.
- **`charge` (MB Way):** PaymentIntent `mb_way` `confirm:true` com telefone E.164 → push MB WAY.
- **`capture` (fim):** captura **`final_fare_cents`** (≤ autorizado).
- **`settle` (MB Way, fim):** `final < estimado` → refund da diferença; `final > estimado` → Bora
  absorve (política aprovada).
- **`cancel`:** sem taxa → **void**; com taxa → captura só a taxa (cartão) / refund parcial (MB Way).
- **Gate #1:** primeira coisa que faz é ler `tvde_card_payments_enabled` — OFF → `403 card_payments_not_enabled`.
- Mínimo Stripe €0,50 e `idempotencyKey` em todas as chamadas.

### B) Flutter cliente (`tvde_request_ride_screen` + `TvdeStore` + `TvdeRide`)
- **Secção "Pagamento"** nova (`TvdePaymentSelector`, widget partilhado): **Dinheiro sempre visível
  (default)**; **Cartão + MB Way só com o switch ligado** (lido via `getSettingBool`). Hoje (OFF)
  mostra "Pagamento: Dinheiro" → **resolve o "ia direto sem pedir pagamento"**.
- `requestRide` ganhou `paymentMethod` (default 'cash' → tudo igual). Corrida coberta pelo plano ou
  switch off → força 'cash'.
- `requestRidePaid` (card/mbway): invoca a Edge Function ANTES de criar a ride; cartão confirma o
  `clientSecret` via `PaymentService`.
- `TvdeRide` lê `payment_method` (+ helper `isPaidOnline`).

### C) Flutter motorista (`TvdePayBadge`)
3.º estado: card/mbway → **"💳 Pago no app — NÃO cobrar o passageiro"** (verde), a par de
"Coberta pelo plano" e "Dinheiro · cobrar €X".

### D) Admin (`admin_tvde_drivers_screen`)
O saldo do motorista agora lê o **sinal**: `>0` "Deve ao Bora"; `<0` **"Bora deve: €X"** (crédito,
card/mbway); `0` "Saldo quitado". Antes dizia sempre "Deve ao Bora" (enganava com saldo negativo).

## Testes (com o switch OFF)
- **`flutter analyze`** nos 7 ficheiros: **0 erros, 0 warnings** (só `info` pré-existentes).
- **Widget test** `test/tvde_payment_selector_test.dart` — **3/3 verde**: OFF → só Dinheiro;
  ON → Dinheiro+Cartão+MB Way; tocar chama `onChanged`.
- **Fluxo dinheiro inalterado** (default 'cash') — nada quebra. Teste cash no Redmi: ver na próxima
  build do CI (device na 370, build local OOM).
- **Teste com cartão real:** só depois do Danilo deployar a function + ligar o switch (fora desta sessão).

## Falta ligar (para a captura funcionar quando o switch abrir)
No fim da corrida (lado do motorista, após `tvde_finish_ride`) e no cancelamento, chamar a Edge
Function: `card` → `capture`; `mbway` → `settle`; cancelamento → `cancel` com `cancel_fee_cents`.
Deixei as ações prontas na function; falta o gatilho no `TvdeDriverStore.finish/cancel`. Não o
adicionei porque é código de dinheiro por testar — melhor ligar junto com o teste real do Danilo.

## 💡 Sugestão de melhoria (o que pediste — cruzei delivery × motorista × limpeza)

As três verticais **reinventaram** o aviso de "quanto cobrar", com divergências perigosas:
- **Delivery** (`driver_home_screen`): **4 cópias inline** do badge de dinheiro (uma vermelha, três
  laranja; só 1 mostra o valor), e para **card/MB Way não mostra NADA** → o estafeta não distingue
  "já pago no app" de "o badge falhou" e pode **cobrar dinheiro num pedido já pago**.
- **TVDE** (`TvdePayBadge`): o melhor — 1 widget, 3 estados — mas o histórico usa outra redação.
- **Limpeza** (`cleaner_home`): "COBRAR EM DINHEIRO: €X" sem ícone/caixa; card = "Pago na app".

**Proposta:** um único **`CollectBadge`** partilhado (delivery, TVDE, limpeza e futuras verticais),
com 3 estados fixos e **valor obrigatório** por construção:
- `collectCash` → laranja, 💰, "COBRAR EM DINHEIRO: €X" (o €X é argumento obrigatório → impossível
  enviar um badge sem valor).
- `paidOnline` → **verde**, ✓, "JÁ PAGO NA APP — não cobrar".
- `coveredByPlan` → verde, "COBERTO PELO PLANO — não cobrar".

**Porquê:** elimina estruturalmente os 2 erros de hoje — (a) cobrar dinheiro num pedido já pago
(o delivery passa a mostrar um estado verde explícito em vez de nada) e (b) não saber o valor (o
valor passa a ser obrigatório). Colapsa ~6 cópias numa só e mata a deriva de cor/caixa/maiúsculas.
O **maior ganho é no delivery** (é o único que hoje não mostra sinal nenhum no card/MB Way).
Estimativa: ~3-4h (widget + substituir os call sites). Fica como proposta — não implementei para
não mexer no `driver_home_screen` fora do scope desta tarefa.

## Ficheiros
**Novos:** `supabase/functions/tvde-payment/index.ts`, `lib/widgets/tvde/tvde_payment_selector.dart`,
`test/tvde_payment_selector_test.dart`. **Alterados:** `lib/models/tvde_ride.dart`,
`lib/stores/tvde_store.dart`, `lib/widgets/tvde/tvde_pay_badge.dart`,
`lib/screens/client/tvde/tvde_request_ride_screen.dart`,
`lib/screens/admin/admin_tvde_drivers_screen.dart`. **Migration:** `tvde_rides_payment_intent_columns`
(aplicada). **Arquivado:** `relatorios/proposta-tvde-card-mbway.APLICADO-VIA-MCP.sql.bak`.
