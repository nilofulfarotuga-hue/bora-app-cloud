# AUDITORIA TOTAL DE PAGAMENTOS — BORA APP
**Data:** 2026-08-15 · **Modo:** SÓ LEITURA (Fase 2) · **Fonte da verdade:** PRODUÇÃO (Edge Functions lidas via MCP, não o repo) · Stripe **LIVE** — zero cobranças de teste nesta sessão.

> Projeto Supabase `ojykpzwqrtusfeakzrna`. App `1.0.1+523`. 15 Edge Functions de pagamento lidas na íntegra da versão *deployed*; 60 RPCs financeiras inventariadas; triggers, crons e dados vivos cruzados.

---

## 0. SUMÁRIO EXECUTIVO (o que interessa)

O sistema tem **dois desenhos de confirmação vivos e provados**: o do **delivery** (draft → paga → webhook cria a order) e o do **TVDE** (corrida nasce a aguardar, sem despachar → webhook marca paga → trigger despacha, com refund automático). **Os dois funcionam.** O problema não é falta de um padrão bom — é que **metade das verticais não usa nenhum dos dois**: confiam só no *poll* do cliente para confirmar o pagamento no servidor. Se o app fecha ou o MB Way demora, o dinheiro sai e a entidade (marcação/limpeza/plano/vale) nunca nasce ou nunca confirma.

**Os 5 riscos maiores (todos 🔴):**

1. **Reembolso-fantasma em Marcações e Reservas.** Quando o *cliente* cancela dentro da janela, a app chama `client_cancel_appointment` / `client_cancel_reservation` **diretamente** (RPC). A RPC marca `deposit_status='refunded'` / `status='cancelled_refunded'` e manda push *"Reembolso de €X em 5–10 dias"* — mas **nenhuma delas chama a Stripe.** O dinheiro nunca volta. O registo mente exatamente como o TVDE mentia antes do fix de 13/08.
2. **Marcações de Serviços sem confirmação no servidor.** `create-appointment-payment-intent` + versão MB Way confirmam **só por poll do cliente** (`client_confirm_appointment_payment` / `confirm-mbway-appointment-payment`). Sem ramo no `stripe-webhook`, sem cron de reconciliação. App fecha → cobrado, marcação fica `pending_payment`, parceiro nunca sabe. **É o mesmo buraco que fez o TVDE perder um cliente real.**
3. **Limpeza sem confirmação no servidor.** `cleaning-checkout` cobra na reserva mas o `held` depende do `mark_held` do cliente (poll 120s). Sem webhook, sem cron. App fecha → cobrado, reserva fica `unpaid`. Zero pagamentos online de limpeza na história — caminho por estrear. (Prova viva: limpeza `59bdcbcd` presa `in_progress/unpaid/cash` há 9 dias.)
4. **Planos TVDE e Vale ida-e-volta online sem confirmação no servidor.** `tvde-plan-payment` e o ramo `charge_roundtrip` dependem do cliente chamar `activate`/`confirm_roundtrip_payment`. O webhook v33 vê `kind=tvde_plan` / `tvde_roundtrip` mas **não cria nem a subscrição nem o vale** (só marcaria a corrida de ida). App fecha após pagar → dinheiro saiu, plano/vale nunca nasce. Zero subs pagas e zero vales online na história.
5. **Cartão morre no telemóvel antes de chegar ao servidor.** Zero pagamentos por cartão em qualquer vertical desde o reset de 31/07. Em 14/08 houve 6 chamadas a `list-saved-cards` sem um único PaymentIntent a seguir — o ecrã de cartão abre e morre no aparelho. Diagnóstico no §5.

**Contagem de células da matriz:** 🔴 **11** · 🟡 **9** · 🟢 **13** (detalhe no §2).

---

## 1. MATRIZ COMPLETA DE PAGAMENTOS (vertical × método)

Legenda de confirmação: **W**=webhook (garantia servidor) · **P**=poll do cliente (acelerador) · **T**=trigger DB · **A**=auto (trigger COD).

### 1.1 Quem cobra, com que metadata, quem confirma

| Vertical | Edge/RPC que cobra (ficheiro Flutter) | Metadata do PI | Confirma no SERVIDOR | Métodos |
|---|---|---|---|---|
| **Delivery restaurante parceiro** | `create-payment-intent` modo B (draft) · `create-mbway-payment-intent` (`order_store.dart:633`, `payment_service.dart:258`) | `draft_id`+`user_id` / `order_id` | **W** `finalize-order-from-intent` (draft) ou Mode A (order) → notify parceiro | cartão, MB Way, dinheiro, tokens, wallet |
| **Delivery mercado / não-parceiro** | idem (mesmo funil `payment_method_screen.dart`) | `draft_id` | **W** idem + `callingDriver`+dispatch | idem |
| **Favores (errand/sendPackage/carry)** | idem (mesmo funil) | `draft_id` | **W** idem | cartão, MB Way, dinheiro, tokens |
| **TVDE corrida** | `tvde-payment` `charge` (`tvde_store.dart:266`) | `kind=tvde_ride`, `ride_id`, `user_id` | **W** v33 `tvdeHandleSucceeded` → `payment_status=succeeded` → **T** `tr_tvde_dispatch_on_paid` · **P** `confirm_ride_payment` | cartão, MB Way, dinheiro, tokens |
| **TVDE paradas** | `tvde-payment` `charge_stop` (`tvde_store.dart:545`) | `kind=tvde_stop`, `ride_id` | **P** só `confirm_stop_payment` (webhook = **no-op** por desenho) | cartão, MB Way |
| **TVDE vale ida-e-volta** | `tvde-payment` `charge_roundtrip` / `tvde-plan-payment` `create_roundtrip*` (`tvde_store.dart:827+`) | `kind=tvde_roundtrip`, (ride_id no charge_roundtrip; **sem ride_id** no plan) | **P** `confirm_roundtrip_payment`/`activate_roundtrip` cria o vale; webhook **não cria vale** | cartão, MB Way, dinheiro |
| **TVDE planos** | `tvde-plan-payment` `create`/`create_mbway` (`tvde_store.dart:760+`) | `kind=tvde_plan`, `plan`, `user_id` (**sem ride_id**) | **P** só `activate`; webhook vê `tvde_` mas **"nada a marcar"** | cartão, MB Way |
| **Limpeza** | `cleaning-checkout` `create`/`create_mbway` (`cleaning_store.dart:319+`) | `kind=cleaning`, `booking_id`, `user_id` | **P** só `mark_held`; sem webhook, sem cron | cartão, MB Way, dinheiro |
| **Reservas de mesa** | `create-reservation-payment-intent` · `-mbway-` (`reservation_store.dart:349`, flow legacy `reservation_flow_screen.dart:134`) | `purpose=reservation_prepayment`, `reservation_id` | **W** `confirm_reservation_payment_webhook` + limpeza de órfã no failed · **P** `client_confirm_reservation_payment` | cartão, MB Way |
| **Marcações de Serviços** | `create-appointment-payment-intent` · `-mbway-` (`services_store.dart:409/341`) | `purpose=appointment_deposit`, `appointment_id`, `provider_id` | **P** só `client_confirm_appointment_payment` / `confirm-mbway-appointment-payment`; **sem webhook** | cartão, MB Way |
| **Dívida / wallet** | `pay-debt-standalone` (`payment_service.dart:305`, `wallet_service.dart:113`) | `standalone_debt_settle`, `debt_settle_cents`, `user_id` | **W** ramo `wallet_settle_debt` | cartão, MB Way |
| **Carregamento de wallet** | **NÃO EXISTE** (só grants de admin + excedente de pagamento de dívida) | — | — | — |

> **Valor da marcação:** o modelo "sinal €3" foi removido a 03/08 — `appointments.deposit_cents` guarda agora o **valor total** do serviço (a coluna manteve o nome antigo). As Edge v3 recusam cobrar valor por omissão (fim do `?? 300`). ✅

### 1.2 Teste mental obrigatório (cliente paga MB Way, fecha o app, aprova 5 min depois)

| Vertical | O que acontece com o app fechado | Veredicto |
|---|---|---|
| Delivery (todos) | Webhook marca `paid`, cria/despacha a order. **Nasce sozinho.** | 🟢 |
| TVDE corrida | Webhook v33 marca `succeeded` → trigger despacha; refund automático se corrida já morta. **Nasce sozinho.** | 🟢 |
| TVDE parada | `confirm_stop_payment` nunca corre → **€2 cobrados, parada nunca adicionada, sem refund** (webhook é no-op) | 🔴 |
| TVDE vale ida-e-volta | Webhook marca a corrida de ida paga (e despacha-a!) mas **o vale nunca nasce** (depende do `confirm_roundtrip_payment`) | 🔴 |
| TVDE plano | Webhook não faz nada → **cobrado, subscrição nunca ativada** | 🔴 |
| Limpeza | **Cobrado, reserva fica `unpaid`** até reabrir o app | 🔴 |
| Reservas | Webhook `reservation_prepayment` confirma → `pending`. **Nasce sozinho.** | 🟢 |
| Marcações | **Cobrado, marcação fica `pending_payment`, parceiro nunca sabe** | 🔴 |
| Dívida/wallet | Webhook `debt_settle_cents` liquida. **Nasce sozinho.** | 🟢 (ver ⚠️ §2) |

### 1.3 Coluna 6 — REFUND (regra do adendo: cancelamento nas regras devolve automático, registo nunca mente)

| Vertical / caminho | Emite refund Stripe automático? | Registo honesto? | Veredicto |
|---|---|---|---|
| **Delivery — cliente cancela** (`client-cancel-order`) | Sim (cartão) ou wallet, capado ao pago menos taxa; `refund_status='pending'` até `charge.refunded` | Sim — `refunded` só quando dinheiro sai; senão `cancelled_no_charge` | 🟢 |
| **TVDE — cliente cancela** (`tvde-payment refund`) | Sim, capado ao pago menos taxa | Sim — v9: `kept_cancel_fee` quando 0 devolvido, nunca `refunded` a seco | 🟢 |
| **Reservas — ADMIN cancela** (`admin-cancel-reservation`) | Sim, síncrono, com idempotency key, audita resultado | Sim | 🟢 |
| **Marcações — PARCEIRO cancela** (`partner_cancel_appointment`) | Sim, mas via `net.http_post` **fire-and-forget** (pg_net não espera resposta) | **Parcial** — marca `refunded` se a chamada foi *enfileirada*, não se *concluiu*; se a `refund` falhar depois (ex. `charge_missing`), fica a mentir | 🟡 |
| **Reservas — CLIENTE cancela** (`client_cancel_reservation`, RPC direta `client_reservations_screen.dart:91`) | **NÃO** — RPC não toca na Stripe | **NÃO** — marca `cancelled_refunded` + push "reembolso em 5–10 dias" sem devolver nada | 🔴 |
| **Marcações — CLIENTE cancela** (`client_cancel_appointment`, RPC direta `services_store.dart:506`) | **NÃO** — o próprio comentário admite (`services_store.dart:503`) | **NÃO** — marca `deposit_status='refunded'` sem devolver nada | 🔴 |
| **Limpeza — cancelamento** (`cleaning-checkout reverse`) | Sim *se* o fluxo de cancelamento chamar `reverse` (estorna total menos taxa) | Depende de a app disparar a ação; não há garantia servidor | 🟡 |
| **TVDE parada / vale / plano** | Sem caminho de refund dedicado (parada refunda só se `confirm` falhar após pagar) | n/a | 🔴 parada · 🟡 vale/plano |

**Conclusão da coluna 6:** o padrão honesto (refund automático + registo que não mente) existe e está provado em **delivery** e **TVDE corrida**. Falta portá-lo para **cliente-cancela-reserva** e **cliente-cancela-marcação** (hoje são reembolso-fantasma), tornar o **parceiro-cancela-marcação** síncrono/verificado, e dar caminho de refund a **parada/vale/plano TVDE**.

### 1.4 Colunas 7–9 (ledger, tokens/wallet, acerto semanal) — resumo

- **Ledger/extrato (7):** delivery entra em `ledger_entries` + `order_financials` + split via triggers (`orders_post_to_ledger`, `orders_financial_split`). TVDE/limpeza/marcações/reservas alimentam `driver_weekly_settlements`, `cleaner_weekly_settlements`, `appointment_payouts`, `partner_reservation_payouts` respetivamente. `admin_list_payments` unifica as 6 verticais para leitura. 🟢 estrutura existe.
- **Tokens/wallet (8):** ⚠️ **`token_value_cents_x100` (=50, i.e. €0,005) NÃO é lido no checkout** — o valor está **cravado em 4 sítios** no Flutter (`business_rules.dart:50`, `tvde_request_ride_screen.dart:1323/1332`, `client_promo_code_screen.dart:61`). Só `token_payment_max_pct` (=50) é lido da BD. Hoje bate certo por coincidência (0,005 = 50/10000); no dia em que o Danilo mudar o setting, o app cobra pela regra antiga. 🟡 dívida técnica séria. A contagem de tokens é recalculada server-side pela RPC (bom), mas o desconto mostrado ao cliente usa o literal.
- **Acerto semanal (9):** crons existem e correm (`appt-weekly-payout` seg 08h, `cleaning-weekly-settlement` seg 08h, `bora_weekly_auto_payout` seg 03h, settlements de parceiro/estafeta). 🟢 estrutura; execução real de transferências continua manual/Stripe Connect (Connect em Fase 1, ainda espelho).

---

## 2. LISTA DE CÉLULAS 🔴🟡🟢

**🔴 Buraco real (11):**
1. Marcações — confirmação servidor (sem webhook)
2. Marcações — cliente-cancela = refund-fantasma
3. Limpeza — confirmação servidor (sem webhook/cron)
4. Planos TVDE — confirmação servidor (webhook não ativa)
5. Vale ida-e-volta TVDE — vale nunca nasce com app fechado
6. TVDE parada MB Way — €2 sem parada nem refund com app fechado
7. Reservas — cliente-cancela = refund-fantasma
8. Cartão — morre no telemóvel antes do servidor (todas as verticais; §5)
9. Carregamento de wallet — inexistente (gap de produto)
10. Vale/plano TVDE — sem caminho de refund no cancelamento
11. Limpeza `59bdcbcd` presa `in_progress/unpaid/cash` há 9 dias (fluxo de finalizar não fecha; §6/BUG-06)

**🟡 Funciona por sorte / só poll / desalinhado (9):**
1. `token_value_cents_x100` cravado no cliente (4 sítios)
2. Parceiro-cancela-marcação: refund fire-and-forget pode mentir
3. Limpeza refund depende de a app chamar `reverse`
4. `pay-debt-standalone` MB Way usa `payment_method_types:['multibanco']` (não `mb_way`) — método diferente do resto da app
5. Duas implementações vivas de pagamento de **reservas** (nova + legacy) alcançáveis por entradas diferentes
6. Dois wrappers de `pay-debt-standalone` com contratos de erro diferentes (`payment_service` devolve null; `wallet_service` faz throw)
7. TVDE `SavedCardCheckout.authorize()` chamado sem `amountEur` (prompt biométrico sem contexto de valor)
8. Vale ida-e-volta online **não aplica tokens** (desarmado de propósito até o backend honrar)
9. `charge-extra` cria PI sem validar dono/valor contra entidade (uso genérico)

**🟢 Sólido (13):** delivery cartão (draft→webhook) · delivery MB Way (Mode A) · delivery dinheiro (auto-confirm) · delivery cliente-cancela-refund · storeShopping/mercado draft→webhook · favores draft→webhook · TVDE corrida cartão/MB Way (webhook v33+trigger) · TVDE corrida refund honesto v9 · reservas cartão (webhook) · reservas MB Way (webhook) · reservas órfã-cleanup no failed · dívida/wallet (webhook settle) · admin-cancela-reserva refund síncrono.

---

## 3. TAREFA 2 — O DESENHO ÚNICO (comparar os dois vivos e escolher)

Os dois padrões provados, de frente:

| Critério | **Delivery** (draft → paga → webhook cria) | **TVDE** (entidade nasce a aguardar → webhook marca → trigger despacha) |
|---|---|---|
| App fecha depois de pagar | Entidade nem existe até o webhook a criar — **nada órfão** | Entidade já existe `solicitada`+`payment_status≠succeeded`; webhook completa; **fica visível "a aguardar pagamento"** |
| Idempotência | `payment_drafts.used_at`+`order_id` (uma order por draft) | `payment_status` guard + `neq('succeeded')`; trigger só dispara na transição |
| Reembolso honesto | `client-cancel-order` capa ao pago, `refunded` só com dinheiro fora | `tvde-payment` v9 idem + `kept_cancel_fee`; **refund automático no webhook** se dinheiro entra numa corrida já morta |
| Registos órfãos | Zero (sem paga, sem order) | Possíveis: corrida `solicitada` que nunca paga (mas é limpável e visível ao admin) |
| Simplicidade | Precisa de `payment_drafts` + `finalize-order-from-intent` (2 peças) | Uma tabela, um trigger, um ramo no webhook |
| O que a vertical precisa | Ideal quando **não deve existir nada** antes de pagar (delivery, favores) | Ideal quando a entidade **precisa de existir já** para o cliente ver estado, o parceiro reservar o slot, ou dar para cancelar (marcação, reserva, limpeza, plano) |

**Escolha: HÍBRIDO, com o padrão TVDE como base para tudo o que reserva um recurso.**

Porquê: marcações, reservas e limpeza **têm de existir antes de pagar** (o slot/dia fica reservado, o parceiro vê, o cliente acompanha). Para essas, o padrão delivery (não existe nada até pagar) não serve — e é por isso que hoje improvisaram com poll. O padrão **TVDE é o molde certo**: a entidade nasce `pending_payment`, **o `stripe-webhook` ganha UM router por `kind`** que marca paga + dispara o efeito (notificar parceiro / confirmar marcação / libertar limpeza / ativar plano / criar vale), e **o poll do cliente passa a mero acelerador**. O delivery mantém o seu padrão draft (é o melhor para "nada antes de pagar") — não se mexe no que já é 🟢.

**Regra única de metadata (nova cobrança nasce sempre assim):**
`metadata = { kind, entity_id, user_id }` com `kind ∈ {delivery_draft, delivery_order, tvde_ride, tvde_stop, tvde_roundtrip, tvde_plan, reservation, appointment, cleaning, debt}`. O webhook faz `switch(kind)` — um ramo por família, todos presentes.

**Ramos que faltam no `stripe-webhook` v33** (hoje só cobre reservation_prepayment, tvde_*, debt, draft/order):
- `appointment` (marcar `confirmed`/`deposit_status='paid'` + `client_confirm_appointment_payment` server-side + notify parceiro)
- `cleaning` (marcar `held` + notify)
- `tvde_plan` (ativar subscrição via `tvde_activate_paid_subscription`)
- `tvde_roundtrip` (criar o vale via `tvde_create_roundtrip_credit`, idempotente pelo PI)

**Plano de migração (ordens pequenas <15 min, por ordem de risco crescente; cada uma com FEITO):**

| # | Ordem | FEITO quando |
|---|---|---|
| O1 | **Refund honesto cliente-cancela-marcação:** `client_cancel_appointment` passa a chamar a Edge `refund` (net.http_post como `partner_cancel_appointment`) e só marca `refunded` no sucesso | cancelar marcação paga devolve dinheiro; `deposit_status` nunca `refunded` sem refund |
| O2 | **Refund honesto cliente-cancela-reserva:** igual para `client_cancel_reservation` | idem reservas |
| O3 | **Webhook ramo `appointment`** (confirma marcação server-side) | pagar marcação com app fechado confirma-a; parceiro é notificado |
| O4 | **Webhook ramo `cleaning`** (marca held) | limpeza online confirma sem o app |
| O5 | **Webhook ramo `tvde_plan`** (ativa subscrição) | plano pago ativa sem o app |
| O6 | **Webhook ramo `tvde_roundtrip`** (cria vale idempotente) | vale nasce sem o app |
| O7 | **`token_value_cents_x100` lido no checkout** (1 fonte, apaga os 4 literais) | mudar o setting muda o desconto no app |
| O8 | **Parceiro-cancela-marcação síncrono** (ler resposta da `refund` antes de marcar `refunded`) | status reflete o refund real |
| O9 | **Consolidar reservas** numa só implementação (retirar a legacy) | uma só entrada de pagamento de reserva |
| O10 | **Carregamento de wallet** (top-up) — decisão de produto | cliente carrega saldo |

> Todas estas ordens são 🔴 LISTA VERMELHA (mexem em dinheiro/webhook). **Nesta sessão não se aplica nenhuma** — ficam prontas para o Danilo dizer "vai", uma a uma.

---

## 4. TAREFA 3 — BUG DO CARTÃO NO TELEMÓVEL (hipóteses ordenadas)

Facto: **zero pagamentos por cartão desde 31/07** em qualquer vertical; 14/08 10:46 = 6 chamadas a `list-saved-cards` **sem nenhum PaymentIntent a seguir**; `payment_drafts` vazia de tentativas. Ou seja, o ecrã de cartão abre (chega a listar cartões guardados) e **morre no aparelho antes de chamar `create-payment-intent`**. Hipóteses, da mais provável à menos:

1. **`Stripe.publishableKey` vazia/errada no build instalado (mais provável).** `main.dart:345-351` faz `throw StateError` no arranque se a key vier vazia — mas se o build no telemóvel foi compilado **sem** `--dart-define-from-file=.dart_defines` (ou com `STRIPE_PUBLISHABLE_KEY` em branco), o PaymentSheet nunca inicializa. Casa com "abre e morre". **Pedir:** confirmar que o APK instalado é de um CI que injeta os dart-defines (o histórico do projeto tem exatamente este bug — splash hang por CI não injetar `.dart_defines`).
2. **Versão instalada ≠ código atual.** App `1.0.1+523`; muita correção de cartão (Carteira Única, saved cards, draft mode) é recente. Se o telemóvel tem um build antigo, chama endpoints/fluxos que já mudaram. **Pedir:** `versionCode` no telemóvel (Definições → Apps → Bora) vs último build do Play.
3. **`initPaymentSheet` / `presentPaymentSheet` a lançar exceção engolida.** No delivery o erro é mapeado (`payment_method_screen.dart:961-993`), mas **em reservas os dois ecrãs não têm guarda `kIsWeb`** e o dialog de MB Way engole tudo (`catch (_) {}`). **Pedir:** o texto exato do erro no ecrã (screenshot) — hoje falta e é o que fecha o diagnóstico.
4. **Google Pay/Apple Pay merchant mal configurado** (`main.dart:329-363` aplica `merchantIdentifier`+GooglePay PT). Um `applySettings()` a falhar pode abortar a folha. **Pedir:** testar com cartão manual (não wallet).
5. **3DS/SCA a devolver `requires_action` e a app não reabrir a folha** (`confirmSavedCardPayment` devolve `false` em `StripeException` — `payment_service.dart:353-383`). Menos provável dado que nem chega a criar PI.

**Log a pedir ao Danilo (fecha o diagnóstico):** com o telemóvel ligado por USB, `adb logcat | grep -i "flutter\|stripe\|bora"` enquanto tenta pagar por cartão; + screenshot do ecrã no momento do erro; + confirmar `versionCode` instalado. **Não corrigir** — só diagnóstico. *(Nesta sessão `adb devices` = nenhum aparelho ligado.)*

---

## 5. TAREFA 4 — PAINEL ADMIN DE PAGAMENTOS (o que há e o que falta)

**Existe:** `admin-payments` v3 (`list_cards`, `stuck_intents` — PIs em `requires_action`/`requires_confirmation`, `refund` delegado na Edge `refund` blindada com auditoria) · `admin_list_payments` (RPC unifica as 6 verticais para leitura) · `admin_tvde_stuck_payments` + ecrã "Corridas presas" (reconferir na Stripe / confirmar) · `reprocess-refund` (recupera refund falhado, idempotente) · `admin-cancel-order` / `admin-cancel-reservation` (refund síncrono) · família `stripe-connect-admin` (onboard/login/resync/disconnect) · settlements/payouts por vertical.

**Falta para autoridade total (só listar):**
1. **"Pagamentos presos" além do TVDE** — o `admin_tvde_stuck_payments` só vê corridas. Não há equivalente para **marcações/limpeza/reservas** paradas (é onde estão os buracos 🔴). Falta um painel "pagamentos presos" transversal que leia `stuck_intents` da Stripe e cruze com a entidade.
2. **Reprocessar/forçar confirmação por vertical** — o `reprocess-refund` é só de refund de order. Falta "reconfirmar pagamento" (reler PI da Stripe e completar a entidade) para marcação/limpeza/plano/vale — hoje só o cliente o faz por poll.
3. **Corrigir estado à mão** — não há ação admin para mover uma marcação/limpeza presa para `confirmed`/`held` depois de verificar o dinheiro na Stripe.
4. **Exportar** — `admin_list_payments` lista mas não há export CSV de pagamentos/refunds para contabilidade.
5. **Auditar refund-fantasma** — não há alerta quando uma entidade fica `refunded`/`cancelled_refunded` sem refund Stripe correspondente (os casos 🔴 do §1.3 passam despercebidos).

---

## 6. TAREFA 5 — BUGS FORA DO SCOPE (regra da casa)

- **BUG-01 (🔴):** reembolso-fantasma cliente-cancela em **marcações e reservas** (detalhe §1.3) — dinheiro nunca volta, push diz que volta.
- **BUG-02 (🔴):** `pay-debt-standalone` MB Way cria PI com `payment_method_types:['multibanco']` (Multibanco referência), não `mb_way` — método diferente do resto da app; provável falha ou UX inconsistente ao liquidar dívida por "MB Way".
- **BUG-03 (🟡):** duas implementações vivas de pagamento de reservas (`reservation_flow_screen.dart` legacy vs `client/reservation/*` nova) alcançáveis por entradas diferentes — risco de divergência e de manter bugs só num lado.
- **BUG-04 (🟡):** `token_value_cents_x100` não lido no checkout; valor €0,005 cravado em 4 sítios (§1.4).
- **BUG-05 (🟡):** guardas `kIsWeb` de cartão são por-ecrã e inconsistentes — **os dois ecrãs de reservas não têm guarda**, então no web o utilizador chega ao `initPaymentSheet` em vez do Payment Element web.
- **BUG-06 (🔴 dados):** limpeza `59bdcbcd` presa `in_progress/unpaid/cash` desde 06/08 (9 dias) — o fluxo de finalizar limpeza não fecha o pagamento em dinheiro; provável falta de trigger/ação equivalente ao `orders_cash_settlement` do delivery.
- **BUG-07 (🟡):** 7 corridas TVDE MB Way em `requires_action` (bug antigo de MB Way preso); a cadeia nova (webhook v33 + trigger) tem prova SQL mas pouca prova real em telemóvel — validar num teste real.
- **BUG-08 (🟡):** `charge-extra` cria PaymentIntent a partir de `amount`+`customerId` do corpo sem validar dono nem entidade — cobrança genérica autenticada, sem amarra a uma order.
- **BUG-09 (🟢 nota):** `cleaning-checkout reverse` e `admin-cancel-*` são sólidos; registar como referência do padrão bom.

---

## 7. TAREFA 6 — REFINAMENTO VISUAL

> **Método:** análise 100% pelo código (dois agentes de varredura sobre `lib/`). **Sem prints reais** — `adb devices` não mostrou nenhum telemóvel ligado por USB nesta sessão, por isso o `juiz_capture.py` não correu. Tokens reais confirmados em `lib/config/app_colors.dart` + `app_theme.dart` (TextTheme Inter completo) + `app_spacing.dart` (`Spacing`/`Radii`) — **não existe `lib/theme/`**.

### 7.1 Fase A — diagnóstico (o que o código mostra)

**Achado sistémico (toda a app):** o `TextTheme` existe e é bom, mas **quase nenhum ecrã o usa** — ~240 `TextStyle(fontSize: N)` cravados, 8+ tamanhos por ecrã, sem escala. Migrar para `Theme.of(context).textTheme.*` é o maior ganho de consistência, mas é **GRANDE** (por ecrã) → lista priorizada.

**Ranking de alinhamento (melhor → pior):**
- 🟢 **Serviços** (`provider_detail`, `booking_flow`, `services_category`) e **Limpeza** (`cleaning_wizard`, `cleaning_tracking`) — referências de ouro: 1 laranja, estados loading/vazio/erro completos, `errorBuilder`+`loadingBuilder`, `Bora*` components, `Spacing`/`Radii`. **`provider_detail_screen` e `cleaning_wizard_screen` são o padrão a replicar.**
- 🟡 **Delivery/Mercados** — funcionais mas com muito `Colors.*` cru, títulos fora do theme, e vários "empty antes de loading".
- 🔴 **Wallet/Histórico** (`wallet_history`, `pay_debt_modal`, `refund_choice_dialog`) — **a zona mais desalinhada**: exceptions cruas a ecrã inteiro, `€` com ponto, paleta de cor ad-hoc, quase zero tokens.
- 🔴 **Reservas** — **duas implementações vivas**: a legacy (`reservation_flow_screen`, CTA laranja, sem slots reais, viola 1-laranja) e a nova (`client/reservation/*`, verde, slots reais, estados). Alcançáveis pelo mesmo utilizador (tile da home → legacy; ficha do restaurante → nova).

**Defeitos [A] "visivelmente quebrado" mais graves:**
1. **Exceptions técnicas em inglês a ecrã inteiro** nos ecrãs de dinheiro (`wallet_history:40`, `refund_choice_dialog:121`, `pay_debt_modal:108`, `my_appointments:170`, `client_reservations:105/119`).
2. **Visto verde `check_circle` nas linhas de penalização** dos termos €3 (`reservation_checkout:510-514`) — comunica benefício onde é penalização; risco de disputa.
3. **Status cru da BD como texto visível** (`reservation_card:293 default: return status`, `my_appointments:567`).
4. **Regra "1 laranja" quebrada** em vários ecrãs de alto tráfego: `order_tracking_screen` (9 tons laranja/amber no "código de entrega"), `payment_method_screen` (3 zonas quentes), `reservation_flow_screen` (CTA+aviso+ícone laranja), `wallet_history` (card âmbar + ícone laranja), `store_products` (categoria "Animais" laranja + CTA).
5. **`€` com ponto decimal** (não PT-PT) em quase todos os ecrãs de dinheiro; a lógica correta já existe em `CleaningLabels.euro()`.
6. **Alvos de toque ~20-22px** (corações de favorito em `restaurants_screen:318`, `restaurant_menu:1467`; "+" de produto; "reenviar código" no tracking).
7. **`Image.network` sem `errorBuilder`** (pesquisa de menu `restaurant_menu:461`; 2 imagens em `store_products`; avatares de limpeza).
8. **Zero estados** em widgets grandes (`market_store_tab` 754L sem loading/vazio/erro).

**Nota 🔒:** todos os ecrãs TVDE (`tvde_request_ride`, `tvde_ride_tracking`, `tvde_plans`, `ride_mbway_waiting_dialog`, `tvde_rides_history`) têm achados registados mas **NÃO foram tocados** — estão bloqueados pelo cherry-pick pendente. Destaque para `tvde_plans_screen:64` ("A carregar…" eterno se o preço falhar, com botão de aderir ativo) e o mapa-miniatura de 220px de `tvde_request_ride` (divergência estrutural face a Uber/Bolt) — ficam para depois do cherry-pick fechar.

### 7.2 Fase B — fixes aplicados nesta sessão (só UI, seguros)

**7 ficheiros, ~24 fixes** — todos pura-UI, nenhum ficheiro TVDE/bloqueado, nenhuma mudança em stores/lógica:

| Ficheiro | Fixes |
|---|---|
| `cart_screen.dart` | switch "Usar saldo Bora" `Colors.green` → `AppColors.primary` (fim de dois verdes lado a lado no checkout) |
| `payment_method_screen.dart` | banner "brevemente" `Color(0xFFF97316)` ×3 → `AppColors.accent` (token em vez de hex à mão) |
| `refund_choice_dialog.dart` | +import AppColors · exception crua → PT-PT · moeda `€` com vírgula ×3 · `Colors.red/black54/black45` → tokens · "App — instantâneo" → "Saldo Bora — instantâneo" · CTA "Confirmar cancelamento" → "Confirmar" |
| `reservation_flow_screen.dart` | CTA "Confirmar reserva" `AppColors.accent` → `AppColors.primary` (elimina a única violação 1-laranja num ecrã de pagamento) |
| `reservation_card.dart` | badge de estado com `maxLines:1`+`ellipsis` · `default: return status` → `'Estado desconhecido'` · `Colors.red/grey` → `AppColors.error/textSubtle` |
| `reservation_checkout_screen.dart` | `_TermLine` ganha `isWarning` → ícone neutro `info_outline` nas 2 linhas de penalização €3 (fim do visto verde na letra pequena) |
| `wallet_history_screen.dart` | exception crua → PT-PT · `Colors.red` → `AppColors.error` · copy "regularize para fazer" → "regulariza para fazeres" |

**Verificação:** `flutter analyze` nos 7 ficheiros — resultado no fecho (§7.4).

### 7.3 Fica para a lista priorizada (GRANDE / precisa de store / decisão de produto — NÃO feito nesta sessão)

1. **[GRANDE]** Apontar `restaurants_screen.dart:182` (tile "Reservar Mesa") para `ReservationAvailabilityScreen` e **arquivar `reservation_flow_screen.dart`** — resolve de uma vez a divergência de UI, a regra 1-laranja, a falta de slots reais e de estados.
2. **[store]** "Loading antes do empty" nas listas (`restaurants_screen`, `stores_screen`, `market_store_tab`, `tvde_rides_history`) — exige flag `isLoading` que os stores não expõem (fora do âmbito só-UI).
3. **[GRANDE]** Migrar títulos/corpo para `Theme.of(context).textTheme.*` (~240 sítios).
4. **[GRANDE]** Consolidar o laranja do `order_tracking_screen` "código de entrega" (9 tons → 1 accent).
5. **[GRANDE]** Helper global `euro(cents)` PT-PT e aplicar aos ~16 `toStringAsFixed(2)` restantes.
6. **[GRANDE]** Extrair paleta de 22 categorias de `store_products_screen` (26 hex crus) para `AppColors`.
7. **[decisão]** Consolidar `ClientReservationsScreen` vs `MyReservationListsScreen` (dois "sítios de reservas" no perfil).
8. **[MÉD]** Componente `MbwayWaitingDialog` partilhado (3 diálogos MB WAY divergentes hoje).
9. Alvos de toque (corações/“+”) para 44px — mecânico mas altera layout; fazer com print real por perto.

### 7.4 Resultado do `flutter analyze`

`flutter analyze` nos 7 ficheiros editados: **`19 issues found` — 0 erros, 0 warnings, 19 `info`.** Todos os 19 são lints de estilo/deprecação **pré-existentes** no codebase (`deprecated_member_use` de `activeColor`/`groupValue`/`onChanged` do Material 3, `prefer_const_*`, `use_build_context_synchronously`) — **nenhum foi introduzido pelas edições desta sessão**. Critério "0 erros" cumprido. Os lints `info` de RadioListTile/activeColor são dívida transversal da app (migração Material 3) e ficam para uma limpeza dedicada, fora do âmbito de dinheiro desta missão.

---

## 8. NOTAS DE PROTECÇÃO E MÉTODO

- **Nada foi alterado em pagamentos/dados nesta sessão.** Todas as leituras de Edge Functions foram da versão *deployed* (MCP `get_edge_function`), não do repo. Confirmado que o repo está atrás da produção (ex.: `tvde-payment` v9 em prod).
- **Cherry-pick TVDE pendente NÃO tocado** (be13c8e, 1ec200c, bd9517d, b7d2d94, 1c0a420, 44d8a5f, a74a321, +a404c90). Ficheiros bloqueados listados e respeitados na Fase B.
- **Stripe LIVE:** nenhuma cobrança/refund de teste emitido. A conta Stripe acessível por MCP nesta sessão é *sandbox* (não vê os PIs LIVE de produção) — por isso os PIs foram cruzados pelo estado da BD, não pela API Stripe live.
