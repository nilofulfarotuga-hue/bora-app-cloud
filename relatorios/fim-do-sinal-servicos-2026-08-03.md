# Fim do sinal de €3 nas Marcações / Serviços — Flutter + painel admin

**Data:** 2026-08-03 · **Branch:** `autonomous-night-2026-04-29`
**Âmbito:** só Flutter (app cliente, app parceiro) + painel admin.
A base de dados já tinha sido alterada pelo Danilo via MCP — **nada foi refeito nem migrado**.

## Regra nova (a que o código passou a espelhar)

- O cliente paga o **valor cheio do serviço** no acto da marcação (Degradê €15 → paga €15).
- A Bora fica com **€0,50 por marcação** (`appointment_booking_fee_cents`) e repassa o resto
  ao parceiro no **acerto semanal**.
- **Walk-in** criado pelo parceiro também paga €0,50 (`appointment_walkin_fee_cents`).
- **No-show / cancelamento tardio** com dinheiro retido → fica 100% na Bora, fora do repasse.
- ⚠️ O pré-pagamento de **€3 das Reservas de mesa** continua igual — **não foi tocado**.

## Estado da base de dados confirmado (leitura, sem escrita)

Verificado por MCP antes de mexer no Flutter:

| Item | Estado |
|---|---|
| `appointment_booking_fee_cents` | `50` |
| `appointment_walkin_fee_cents` | `50` |
| `appointment_deposit_partner_cut_cents` | `0` |
| `appointment_deposit_bora_cut_cents` | `0` |
| `appointment_deposit_cents` | `300` — **órfã**, já ninguém a lê |
| `compute_provider_weekly_payout(text, timestamptz, boolean)` | devolve `revenue_recebida_cents`, `taxa_bora_cents`, `retido_no_show_cents`, `net_payout_cents`, `walkin_fees_cents`, `bora_revenue_cents`, `direction` |
| `admin_list_appointment_payouts` | devolve `ap.*` da tabela `appointment_payouts` (colunas com nomes antigos, significado novo) |

Mapa de nomes usado no Flutter (chave da RPC → coluna persistida em `appointment_payouts`):

| Coluna do painel | Chave da RPC | Coluna da tabela |
|---|---|---|
| Recebido | `revenue_recebida_cents` | `total_service_revenue_cents` |
| Taxa Bora | `taxa_bora_cents` | `bora_booking_fees_cents` |
| Retido (no-show) | `retido_no_show_cents` | `total_deposits_retained_cents` |
| A repassar | `net_payout_cents` | `net_payout_cents` |

---

## 1. App do cliente

| Ficheiro | O que mudou |
|---|---|
| `lib/models/service_provider_model.dart` | Default de `bookingPaymentMode` passou de `'deposit'` para `'full'` (construtor + `fromSupabase`). Removido o getter `isFullPaymentMode`, que ficou sem uso. |
| `lib/models/appointment_model.dart` | Removido o getter `isFullPaymentMode` (sem uso depois desta ronda). `providerPaymentMode` mantém-se — é coluna real e viaja no JOIN. |
| `lib/screens/client/services/booking_flow_screen.dart` | `_amountDueEur` deixou de ter o ramo do sinal: é sempre `price_cents` do serviço. Apagada a constante `_kDepositEur = 3.0`. Título da folha de pagamento é sempre **"Pagamento da marcação"** (já não alterna com "Sinal da marcação"). `_depositCard()` → `_paymentInfoCard()`, texto novo: **"Paga agora o valor total do serviço: €X,XX. / Não há mais nada a pagar na loja."** O texto de reagendamento ficou intacto. |
| `lib/screens/client/services/booking_success_screen.dart` | Novo parâmetro obrigatório `paidCents`. O texto **"Pagaste o sinal de €3,00. O restante é pago na barbearia."** foi substituído por **"Pago: €X,XX — valor total do serviço. Não há mais nada a pagar na loja."** Actualizados os 2 call-sites (cartão e MB Way). |
| `lib/screens/client/services/my_appointments_screen.dart` | `_depositLabel()` → `_paymentLabel()`, sem ramo "Sinal": mostra `Total €X,XX pago/pendente/reembolsado/retido`. `waived` → "Sem pagamento". No diálogo de cancelamento o substantivo é sempre "o valor pago". Linha do card deixou de repetir preço + sinal (`€15,00 • Sinal €3,00`) e mostra só o valor pago. Na folha de detalhe a linha passou a **"Pago pela app"** (a linha "Preço total" continua). |
| `lib/screens/client/services/appointment_mbway_waiting_dialog.dart` | Doc: "SINAL" → "PAGAMENTO". |
| `lib/stores/services_store.dart` | 3 comentários corrigidos (fluxo MBWay, criação do PaymentIntent, JOIN do parceiro). Sem mudança de lógica. A chave `deposit_cents` da RPC **não foi renomeada**, como pedido. |

## 2. App do parceiro

| Ficheiro | O que mudou |
|---|---|
| `lib/screens/partner/services/partner_agenda_screen.dart` | `_paymentLabel()` deixou de alternar: mostra sempre `€15,00 · Pago pela app: €15,00 (valor total)`. Sumiu o `· Sinal: €3,00`. |
| `lib/screens/partner/services/partner_appointments_finance_screen.dart` | **Corrigido bug real** (ver §5, BUG-1): os KPI liam `total_service_revenue_cents` e `total_deposits_retained_cents`, chaves que a RPC reescrita já não devolve → mostravam €0,00. Agora leem `revenue_recebida_cents`, `taxa_bora_cents`, `retido_no_show_cents`. KPIs renomeados: "Receita serviços" → **Recebido**; "Sinais retidos" → **Retido (faltas)**; "Taxa Bora" passou a usar `taxa_bora_cents` (antes usava `bora_revenue_cents`, que inclui o retido). Cartão do total: "A receber (estimado)" → **"A repassar (estimado)"** + subtítulo *"A Bora transfere no acerto semanal."* |
| `lib/stores/partner_appointments_store.dart` | Comentário do JOIN corrigido. |

Não foi encontrado nenhum texto a dizer que o parceiro recebe o sinal ou desconta ao cliente à chegada.

## 3. Painel admin (PT-BR)

| Ficheiro | O que mudou |
|---|---|
| `lib/screens/admin/admin_platform_settings_screen.dart` | Escondidas da lista as 3 chaves órfãs do sinal: `appointment_deposit_cents`, `appointment_deposit_partner_cut_cents`, `appointment_deposit_bora_cut_cents` (continuam na tabela, só não poluem o painel). `appointment_booking_fee_cents` e `appointment_walkin_fee_cents` passaram a **editáveis** — ver o aviso 🔴 no fim. |
| `lib/screens/admin/admin_appointments_payouts_screen.dart` | Cada linha passou a mostrar as 4 grandezas: **Recebido · Taxa Bora · Retido (no-show) · A repassar**. Cabeçalho: "Pendentes"/"Já pagos" → **"A repassar (pendente)"/"Já repassado"**. Gráfico "Receita Bora por semana" deixou de somar `bora_deposit_cut_cents` (hoje sempre 0) e passa a somar **Taxa Bora + Retido**. **Novo: exportação CSV** (ícone na barra) com as colunas do acerto novo, via `AdminExportService` — o mesmo padrão dos outros ecrãs admin. |
| `lib/screens/admin/admin_service_provider_detail_screen.dart` | Removidos os 2 rádios "Sinal (padrão) / Valor cheio" (a opção do sinal já não existe). No lugar, um bloco explicativo em PT-BR com a regra nova e onde editar as taxas. Removidos o campo `_paymentMode` e o parâmetro `paymentMode` de `_savePolicy` (ficaram órfãos). A política de cancelamento ficou intacta. |
| `lib/screens/admin/admin_appointments_screen.dart` | "Reembolsar o sinal ao cliente" → **"Reembolsar o valor pago ao cliente"**; "Reembolsar o sinal" → **"Reembolsar o valor pago"**. |
| `lib/screens/admin/admin_weekly_settlements_screen.dart` | "Sinais de marcações" (hint "reservas/serviços (€3)") → **"Marcações (recebido)"** (hint "valor total cobrado nas marcações"). O número já vinha certo: `admin_weekly_bora_totals` soma `deposit_cents`, que hoje é o valor cheio. |
| `lib/screens/admin/admin_settlements_screen.dart` | "Sinais de marcações €X" → **"Marcações — recebido €X"**. |

**Autoridade total nesta área — estado:** ver ✅ · editar ✅ (taxas em Configurações, política de cancelamento na ficha do parceiro, cancelar/reembolsar em Marcações) · exportar ✅ (CSV dos repasses, criado nesta ronda) · auditar ✅ (`admin_audit_log` via `admin_update_setting` e as ações de cancelamento/marcar-pago, que mantêm a dupla confirmação).

---

## 4. Validação

- `flutter analyze`: **0 erros** · 221 issues, todas `info`/`warning` pré-existentes
  (`prefer_const_constructors`, `deprecated_member_use` dos `RadioListTile`, imports por usar
  noutros ecrãs). Corrida completa em 186,5 s. Nenhuma issue nova nos ficheiros desta ronda —
  o único erro que apareceu a meio (`missing_required_argument` do `paidCents` no caminho MB Way
  do `booking_flow_screen.dart`) foi corrigido e a corrida final ficou limpa.
- Nenhuma zona protegida tocada: `pricing_service`, `dispatch_engine`, `finalizePurchase`,
  `bora_tokens`, Stripe webhook, RLS — nada. As Edge Functions de pagamento **não** foram alteradas.
- `versionCode` **não** foi incrementado (o CI faz isso).
- Design system intacto: verde `#16A34A`, laranja `#F97316`, Inter. Nenhuma foto alterada.
- Reservas de mesa: **zero alterações** (nem código nem texto).

---

## 5. Varredura global — bugs e pontas soltas encontradas

### 🔴 BUG-1 (crítico, DINHEIRO) — fallback de €3 nas Edge Functions — ✅ **CORRIGIDO E DEPLOYADO**

**Aprovado pelo Danilo ("vai no BUG-1") e aplicado a 2026-08-03.**

`supabase/functions/create-appointment-payment-intent/index.ts`
`supabase/functions/create-mbway-appointment-payment-intent/index.ts`

Antes:

```ts
const cents = parseInt(String(appt.deposit_cents ?? 300), 10);
if (cents < 50) { ...400 'deposit too small'... }
```

Com `deposit_cents` a `NULL` a função **cobrava €3,00** em vez do valor do serviço, em silêncio
— e a diferença nunca aparecia no acerto. No fluxo MB Way, o cliente chegava a receber o push
de €3 no telemóvel.

Depois (v3 nas duas funções):

```ts
const rawCents = appt.deposit_cents;
const cents = typeof rawCents === 'number'
  ? rawCents
  : Number.parseInt(String(rawCents ?? ''), 10);
if (!Number.isInteger(cents) || cents < 50) {
  console.error('[<fn>] invalid_charge_amount:',
    `appointment=${appt.id}`, `deposit_cents=${JSON.stringify(rawCents)}`);
  return json({
    error: 'invalid_charge_amount',
    message: 'A marcação não tem um valor válido para cobrar.',
    appointment_id: appt.id,
  }, 400);
}
```

- **Zero valor por omissão.** `null`, `undefined`, não-numérico, não-inteiro e `< 50`
  (mínimo Stripe) caem todos no mesmo ramo — `Number.isInteger(NaN)` é `false`, por isso
  `null`/`undefined`/lixo ficam cobertos pela mesma condição.
- **Nada chega ao Stripe** nesse caminho: a verificação corre antes de
  `paymentIntents.create`, logo no MB Way também não há push.
- **Log explícito** com `appointment_id` e o valor cru recebido, para dar para investigar.
- A marcação fica em `pending_payment` — nada é cobrado, o cliente pode tentar outra vez.
- Cabeçalhos das duas funções actualizados: já não dizem "SINAL … (€3 default)".

Complemento no Flutter (`lib/stores/services_store.dart`): `invalid_charge_amount` foi
adicionado ao `_mapErrorPtPt`, para o cliente ver *"Não foi possível apurar o valor deste
serviço. Não te cobrámos nada — tenta de novo ou fala com o suporte."* em vez do código cru.

**Contexto da coluna:** o Danilo já mudou por MCP o default de `appointments.deposit_cents`
de `300` para `0` (confirmado: `column_default = 0`, `is_nullable = NO`). Com default `0`, uma
marcação inserida sem valor cai em `0 < 50` → 400. Sem migration, como instruído.

**Prova do deploy** (MCP `deploy_edge_function`, projecto `ojykpzwqrtusfeakzrna`):

| Função | Versão | Estado | `verify_jwt` | `ezbr_sha256` |
|---|---|---|---|---|
| `create-appointment-payment-intent` | 3 → **4** | ACTIVE | `true` (preservado) | `87963de7429239018d74ee542bcd653e3c38b6d230ba3e345046e52a0ed5bd94` |
| `create-mbway-appointment-payment-intent` | 2 → **3** | ACTIVE | `true` (preservado) | `e985a654c9f9e793c7516d5f12fd74f7032b3bdcbe44fb54fa6a0b9e77eb9a6c` |

`verify_jwt` foi lido do deployed **antes** do deploy (`get_edge_function` → `true` nas duas) e
reenviado igual — não houve alteração de superfície de autenticação.

Smoke test pós-deploy (não custa dinheiro, não cria PaymentIntent):

```
create-appointment-payment-intent -> OPTIONS=200
create-mbway-appointment-payment-intent -> OPTIONS=200
```

### 🟡 BUG-2 (médio, já corrigido nesta ronda) — KPIs do parceiro a zero

O ecrã financeiro do parceiro lia `total_service_revenue_cents` / `total_deposits_retained_cents`
do `compute_provider_weekly_payout`. A RPC reescrita deixou de devolver essas chaves, por isso
"Receita serviços" e "Sinais retidos" mostravam **€0,00** desde a alteração da DB.
Corrigido — passa a ler `revenue_recebida_cents` / `taxa_bora_cents` / `retido_no_show_cents`.

### 🟡 BUG-3 (médio) — `appointment_payouts.bora_deposit_cut_cents` ficou morta

A RPC persiste sempre `0` nesta coluna. Ficou a poluir o schema e estava a ser somada no
gráfico de receita do admin (já retirada daí). Nada urgente; se quiseres, dropa-se a coluna
numa migration futura.

### 🟡 BUG-4 (médio) — `appointment_deposit_cents = 300` continua em `platform_settings`

Chave órfã: ninguém a lê. Escondida do painel nesta ronda, mas continua na tabela.
Vale um `DELETE` quando decidires — é uma linha de settings, não afecta cobranças.

### 🟢 BUG-5 (baixo) — drift entre `supabase/migrations/` e produção

A alteração de 2026-08-03 (default `'full'`, `client_book_appointment`,
`compute_provider_weekly_payout`, os 4 `platform_settings`) foi aplicada por MCP e **não tem
ficheiro de migration**. Quem ler `supabase/migrations/20260728120000_appointment_booking_payment_mode.sql`
ou `20260608000003_appointments_platform_settings.sql` vê a regra antiga. Conforme instruído,
**não foi criada migration**. Fica registado para quando quiseres consolidar.

### 🟢 BUG-6 (baixo) — comentário stale na RPC `admin_weekly_bora_totals`

Declara `v_appt_deposits numeric := 0; -- sinais €3 pagos em marcações da semana`.
O valor está certo (soma `deposit_cents`, hoje o valor cheio); só o comentário mente.

### 🟢 BUG-7 (baixo) — parceiro não vê que o walk-in custa €0,50

`lib/screens/partner/services/partner_add_walk_in_screen.dart` não menciona a taxa em lado
nenhum. O parceiro só descobre no ecrã financeiro, na linha de walk-ins. Sugestão (fora do
âmbito desta tarefa): uma linha discreta no ecrã de criar walk-in.

### Reservas de mesa — só reportado, não tocado

`prepayment_cents=300` / `€3` / split €2 parceiro + €1 Bora continuam em
`docs/contexto/03-regras-de-negocio.md:43`, `docs/contexto/04-verticais.md:30`,
`lib/screens/client/reservation/reservation_payment_method_sheet.dart` e nas Edge Functions
`create-reservation-payment-intent` / `create-mbway-reservation-payment-intent`.
**Correcto e intocado** — é outra vertical.

### Ocorrências de "sinal" que NÃO são dinheiro

`admin_ratings_screen.dart` ("sinalizar avaliação"), `admin_driver_approval_screen.dart`,
`admin_cleaning_cleaners_screen.dart`, `admin_tvde_drivers_screen.dart`,
`notification_service.dart`, os ecrãs de login. Sentido diferente da palavra — deixados como estão.

---

## 6. Zona 🔴 (dinheiro) — o que foi aprovado e aplicado

**Nenhum valor cobrado foi alterado** em nenhum momento desta ronda. Preços, taxas, comissões
e splits ficaram exactamente onde estavam.

**(a) `appointment_booking_fee_cents` e `appointment_walkin_fee_cents` editáveis no painel** —
pedido explícito do Danilo, mesmo precedente do `tvde_roundtrip_discount_pct` (01/08): o painel
admin é onde o **dono** mexe no preço do próprio produto; um agente continua sem poder alterar
isto sozinho. **Confirmado por ele para ficar como está.** Os valores continuam em €0,50.

**(b) BUG-1 — fallback `?? 300` nas duas Edge Functions de pagamento** — apresentado em relatório,
**aprovado pelo Danilo ("vai no BUG-1")** e aplicado. Detalhe técnico, código antes/depois e prova
do deploy em §5. Resumo do que ele pediu e do que foi feito, ponto a ponto:

| Pedido | Estado |
|---|---|
| Tirar o `?? 300` nos dois ficheiros | ✅ removido |
| `null` / `undefined` / `< 50` → não criar o PaymentIntent | ✅ (mais `NaN` e não-inteiro, pela mesma condição) |
| Erro explícito `invalid_charge_amount` | ✅ literal, mais `message` PT-PT e `appointment_id` |
| Devolver 400 com log | ✅ `console.error` com `appointment_id` + valor cru |
| Nunca cobrar um valor por omissão | ✅ não há caminho que chegue ao Stripe sem valor válido |
| Deploy das duas Edge Functions | ✅ v4 e v3, ACTIVE, `verify_jwt` preservado |
| Taxas editáveis ficam como estão | ✅ não mexi |
| Sem migration para o default da coluna | ✅ nenhuma criada (confirmado por leitura: `column_default = 0`) |

**Nada fica pendente de aprovação nesta área.** Os restantes achados da varredura (BUG-3 a BUG-7)
são de limpeza/cosmética e nenhum cobra dinheiro — ficam registados, não bloqueiam.

---

## 7. Ficheiros tocados (20)

```
lib/models/appointment_model.dart
lib/models/service_provider_model.dart
lib/screens/admin/admin_appointments_payouts_screen.dart
lib/screens/admin/admin_appointments_screen.dart
lib/screens/admin/admin_platform_settings_screen.dart
lib/screens/admin/admin_service_provider_detail_screen.dart
lib/screens/admin/admin_settlements_screen.dart
lib/screens/admin/admin_weekly_settlements_screen.dart
lib/screens/client/services/appointment_mbway_waiting_dialog.dart
lib/screens/client/services/booking_flow_screen.dart
lib/screens/client/services/booking_success_screen.dart
lib/screens/client/services/my_appointments_screen.dart
lib/screens/partner/services/partner_agenda_screen.dart
lib/screens/partner/services/partner_appointments_finance_screen.dart
lib/stores/partner_appointments_store.dart
lib/stores/services_store.dart
supabase/functions/create-appointment-payment-intent/index.ts          (BUG-1, v3)
supabase/functions/create-mbway-appointment-payment-intent/index.ts    (BUG-1, v3)
relatorios/fim-do-sinal-servicos-2026-08-03.md  (este ficheiro)
```

Commits: `d2d4ee2` (Flutter + admin) e o commit do BUG-1 (Edge Functions + `_mapErrorPtPt`).

Nenhum ficheiro de outra tarefa foi incluído no commit (havia trabalho TVDE por commitar na
árvore — `tvde_request_ride_screen.dart`, `tvde_store.dart`, `tvde-payment`, `tvde-plan-payment`
— ficou de fora, `git add` explícito por ficheiro).
