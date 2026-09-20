# MAPA DO DINHEIRO — onde cada cêntimo vive, quem lá escreve, quem lê

> Missão `contas-claras-2026-09-20` · Bloco 0 · medido por SELECT em produção
> (`ojykpzwqrtusfeakzrna`) a 20/09/2026 entre as 18h50 e as 19h20 UTC. **Zero correcções
> neste bloco** — isto é só ler e medir. Cada número abaixo saiu de uma consulta; o SQL está
> em `.claude/.ai/provas/contas-claras-20260920/bloco0-*.sql`.
>
> Regra de leitura: **a negrito** está cada sítio onde duas arcas guardam o mesmo facto. São
> esses os pontos onde as contas se separam. As unidades estão sempre escritas, porque há
> tabelas em euros e tabelas em cêntimos lado a lado (cicatriz de 28/08, `PADRAO_BORA.md` §1.9).

---

## 0. Resumo em cinco linhas

1. Há **onze arcas** de dinheiro em produção, não cinco. Nenhuma função lê todas.
2. O cliente tem **duas verdades** (`wallet_transactions` × `client_wallets`) que não conversam.
   Uma função (`admin_mark_receipt_paid`) escreve numa e não na outra. Há uma **terceira**
   escondida: a coluna `balance_after_cents` dentro do próprio histórico.
3. O estafeta tem **quatro verdades** para o mesmo dinheiro (`driver_transactions` +
   `driver_balances`, `ledger_entries` + `user_balance_snapshots`, `orders` via
   `compute_driver_settlement`, e o ecrã de ganhos `driver_earnings_summary`), com **sinais
   trocados** entre tabelas: em `driver_transactions` um `cash_adjustment` positivo é dívida
   do estafeta; em `ledger_entries` o mesmo facto é negativo.
4. O motorista TVDE tem uma **quinta** arca só dele (`tvde_driver_balances`), com a convenção
   de sinal **ao contrário** de `driver_balances` (positivo = motorista deve à Bora), e **não
   entra em nenhum acerto semanal**.
5. Hoje, com a base pequena, quase tudo bate: só a Isabel Rebelo (fechado pelo Danilo), o
   TVDE do próprio Danilo (14,20 €) e três compensações de cancelamento de 1,50 € que vivem
   só no ledger. Mas bate **por sorte**, não por desenho — não há nada a impedir que separe amanhã.

---

## 1. As arcas, uma a uma

### 1.1 `wallet_transactions` — o histórico da carteira (cêntimos)

- **Guarda:** uma linha por movimento da carteira de **qualquer pessoa** (cliente OU
  estafeta — a chave é `user_id`, sem papel). Colunas: `amount_cents`, `kind`, `reason`,
  `related_order_id`, `idempotency_key`, **`balance_after_cents`**.
- **Unidade:** cêntimos inteiros.
- **Quem escreve (14 funções, todas em produção):** `create_order`, `wallet_credit_generic`,
  `wallet_credit_refund_full`, `wallet_credit_refund_split`, `wallet_debit_for_order`,
  `wallet_debit_cancel_fee`, `wallet_settle_debt`, `wallet_apply_post_delivery_adjustment`,
  `admin_grant_wallet_free`, `admin_revoke_wallet_free`, `admin_forgive_wallet_debt`,
  **`admin_mark_receipt_paid`**, `finalizar_talao_nao_parceiro`, `finalize_storeshopping_purchase_v2`.
- **Quem lê:** `wallet_get_balance` (só as últimas 20 linhas, para o ecrã da carteira),
  o painel admin da carteira, o vigia desta missão.
- **Tipos (`kind`) que existem hoje e o que valem:** `refund_credit_free` (saldo livre),
  **`refund_credit_tokens` (NÃO é saldo — é o valor em cêntimos dos tokens dados; somar isto
  ao saldo é a armadilha n.º 4 da ordem)**, `order_payment`, `cancel_fee_debit`, `settlement`,
  `admin_grant`, `forgive`, `adjustment`, `reimbursement_storeshopping` (reembolso de talão
  ao **estafeta**, na mesma tabela dos clientes).
- **O que se mediu:** 25 linhas, 8 pessoas. Sem `refund_credit_tokens`, o histórico soma
  **7,25 €**; a soma de todos os `client_wallets` é **4,16 €**; a diferença de 3,09 € é toda
  da Isabel (ver §2.1). Com as linhas de tokens somadas à toa daria 17,45 € — o número errado
  da armadilha n.º 4.
- **Onde se separa:**
  - **`balance_after_cents` é um saldo guardado dentro do histórico**, preenchido por umas
    funções e não por outras (Isabel: 4 linhas, todas a `NULL`; Dayane: todas preenchidas).
    É uma terceira verdade que ninguém lê.
  - `wallet_credit_refund_split` **não tem chave de idempotência**: a 12/09 a Dayane recebeu
    o mesmo reembolso **7 vezes em 4 minutos** (7 × 5,66 € livre + 7 × 282 tokens). O saldo
    livre foi corrigido à mão (`adjustment` −35,10 €, chave `admin-fix-full-refund-bba0f503`),
    mas as **7 linhas de tokens ficaram**: o histórico diz 1 015 cêntimos em tokens e a
    `bora_tokens` só tem 282 tokens (= 141 cêntimos) para esse pedido.

### 1.2 `client_wallets` — o saldo que a app mostra (cêntimos)

- **Guarda:** `free_balance_cents` por `user_id`. Uma linha por pessoa.
- **Unidade:** cêntimos inteiros.
- **Quem escreve:** as mesmas funções de 1.1 **menos** `admin_mark_receipt_paid`,
  `finalizar_talao_nao_parceiro` e `finalize_storeshopping_purchase_v2` (estas três escrevem
  o histórico e **não** tocam o saldo). Não há trigger a ligar as duas tabelas.
- **Quem lê:** `wallet_get_balance` → app cliente e app estafeta (carteira), `create_order`
  (para abater saldo no checkout), trigger `_trg_admin_notif_wallet_debt_high`.
- **O que se mediu:** 11 linhas. Positivos: 2 (6,66 €); negativo: 1 (−2,50 €, Letícia,
  taxa de cancelamento); zero: 8. **O Valdemir não tem linha nenhuma** — a app lê 0 por
  ausência, não por registo.
- **Onde se separa:** **é o gémeo directo de 1.1.** É a causa-raiz apurada pela Claude.ai a
  20/09: o histórico promete o que o saldo não tem. Hoje só a Isabel diverge (4,09 € no
  histórico contra 1,00 € no saldo, **caso fechado pelo Danilo — não se toca**).

### 1.3 `driver_transactions` — o histórico do estafeta nas entregas (euros)

- **Guarda:** `amount` numérico em **euros**, `type` ∈ `delivery_earning`, `cash_adjustment`,
  `token_conversion` (o view antigo `v_driver_weekly_earnings` ainda procura um tipo
  `withdrawal` que **não existe**), `status`, `order_id`, `driver_id` = **`user_id` do auth**
  (não `drivers.id`).
- **Unidade:** euros com 2 casas.
- **Quem escreve (só triggers/RPC de servidor):** `fn_credit_driver_on_delivery` (ganho ao
  entregar), `apply_driver_cash_settlement` (acerto de dinheiro em mão ao entregar a cash),
  `fn_apply_client_debt_settlement_on_cash_delivery` (dívida do cliente cobrada em mão),
  `driver_convert_tokens`.
- **Quem lê:** `driver_balances` é actualizado pelas mesmas funções; `compute_driver_settlement`
  lê só `token_conversion`; o view `v_driver_weekly_earnings`.
- **Convenção de sinal — a armadilha:** `delivery_earning` positivo = a Bora deve ao
  estafeta; **`cash_adjustment` positivo = o estafeta deve à Bora** (é o que ele ficou com a
  mais na mão: `total − ganho − talão`). Somar a coluna `amount` às cegas dá lixo.
  A conta certa é `ganhos + tokens − cash_adjustment`.
- **O que se mediu:** 35 linhas, 4 estafetas. Ganhos 100,85 €, `cash_adjustment` 44,31 €,
  tokens 0,48 €.

### 1.4 `driver_balances` — o saldo do estafeta nas entregas (euros)

- **Guarda:** `balance` por `driver_id` (= `user_id`).
- **Unidade:** euros.
- **Quem escreve:** as mesmas 4 funções de 1.3, na mesma transacção. **É o gémeo directo de
  1.3, mas aqui os gémeos concordam** (verificado: 4 em 4 batem ao cêntimo com
  `ganhos + tokens − cash_adjustment`).
- **Quem lê:** ninguém no lado do estafeta. O ecrã de ganhos não lê daqui. O acerto semanal
  não lê daqui. Só o view `v_driver_weekly_earnings` — e esse **junta por `drivers.id` em vez
  de `user_id`** (cicatriz da identidade, 28/08): mostra saldo errado para toda a gente.
- **O que se mediu:** Danilo 37,59 €, Danilo Fulfaro −2,10 €, Estafeta Demo 20,25 €,
  Valdemir 1,28 €.

### 1.5 `ledger_entries` — o livro-razão (euros, só acrescenta)

- **Guarda:** lançamentos por `user_type` ∈ driver/restaurant/platform e `type` ∈ earning /
  cash_adjustment / payout / commission. `user_id` é **texto** (uuid do estafeta ou slug da
  loja). Triggers `ledger_no_update`/`ledger_no_delete` tornam-no imutável.
- **Unidade:** euros.
- **Quem escreve:** `post_order_to_ledger` (trigger ao entregar **pago**), `create_payout`,
  `fn_apply_client_debt_settlement_on_cash_delivery`, e a compensação de cancelamento
  (linhas `earning` de 1,50 € em pedidos cancelados depois de aceites).
- **Quem lê:** **`driver_earnings_summary` (o ecrã "Ganhos" do estafeta lê daqui, não de
  1.3/1.4)**, `recompute_user_balance` → `user_balance_snapshots`, `compute_partner_weekly_settlement`,
  `admin_weekly_bora_totals`, `v_ledger_reconciliation`, `reconcile_dia1_checks`.
- **Convenção de sinal:** aqui `cash_adjustment` é **negativo** quando o estafeta deve
  (o oposto de 1.3). `payout` negativo.
- **O que se mediu:** 75 linhas. Estafetas: ganhos 105,35 €, cash −63,87 €, payout −15,90 €.
  Lojas: ganhos 62,79 €, payouts −51,89 €. Plataforma: comissão 41,91 €.
- **Onde se separa de 1.3:** três pedidos **cancelados** têm um `earning` de 1,50 € no ledger
  (compensação ao estafeta) que **não existe** em `driver_transactions`, logo não está em
  `driver_balances`, e como o acerto semanal só conta pedidos entregues, **também não está no
  acerto**. O estafeta vê 1,50 € no ecrã de ganhos e nunca o recebe. Um deles é do Valdemir
  (pedido `bba0f503`, 12/09).

### 1.6 `user_balance_snapshots` — o saldo do ledger (euros)

- **Guarda:** `sum(ledger_entries)` por (`user_id`, `user_type`), recalculado pelo trigger
  `ledger_recompute_on_insert`.
- **Quem lê:** ninguém encontrado em `pg_proc` além de quem o escreve.
- **É o gémeo de 1.5, e concorda com ele por construção.** Mas **é um quarto saldo do
  estafeta** ao lado de 1.4 e de `tvde_driver_balances`, e os três dizem números diferentes
  para a mesma pessoa (Danilo: 37,59 € em 1.4, 12,95 € aqui, −79,10 € no TVDE).

### 1.7 `orders` — as colunas de dinheiro do pedido (euros; `*_cents` em cêntimos)

- **Guarda:** `price`, `subtotal`, `delivery_fee`, `service_fee`, `platform_commission`,
  `driver_earnings`, `partner_commission_visible`, `partner_markup_hidden`,
  `partner_service_fee_client`, `final_total`, `customer_total`, `cash_total_due`,
  `refund_amount`, `tip_amount_cents`, `wallet_applied_cents`, `tokens_applied_value_cents`,
  `stripe_charge_cents`, `debt_collected_cents`, `small_order_fee`, `bag_fee`.
- **Unidade:** mista — euros nas colunas antigas, cêntimos nas `*_cents`.
- **Quem escreve:** `create_order`, `finalize_*`, triggers de preço; o trigger
  `orders_financial_lock` impede mudar o dinheiro depois de criado.
- **Quem lê:** **`compute_driver_settlement` calcula o acerto semanal directamente daqui**
  (ganhos, cash recebido, talões), sem passar por 1.3, 1.4 ou 1.5. `compute_partner_weekly_settlement`
  também. `weekly_closeout_compile` idem.
- **O que se mediu (entregues, sem testes):** cash 13 pedidos 266,41 € (estafeta 71,79 €,
  comissão 28,28 €); MB Way 4 pedidos 63,47 € (estafeta 17,68 €); cartão 0 entregues.
- **Onde se separa:** é a **fonte** de 1.3 e 1.5, mas cada trigger copia o que quer: o acerto
  de cash copia `total − ganho − talão`; o ledger copia `ganho` só se o pedido estiver **pago**
  (`payment_status='paid'`) — um cash entregue mas não marcado pago fica fora do ledger e
  dentro de `driver_transactions`.

### 1.8 `driver_weekly_settlements` — o acerto semanal do estafeta (euros)

- **Guarda:** uma linha por (`driver_id`, semana): `total_earnings`, `total_cash_received`,
  `cash_adjustments_due`, `tokens_converted_value`, `net_balance`, `direction`, `status`,
  `payment_method`, `payment_reference`, `paid_at`.
- **Unidade:** **euros** (as gémeas `cleaner_weekly_settlements` e `washer_weekly_settlements`
  estão em **cêntimos** — cicatriz de 28/08).
- **Quem escreve:** `compute_driver_settlement` (a partir de `orders`, ver 1.7),
  `admin_list_settlements_for_week`, `admin_marcar_acerto_pago`, `admin_set_settlement_state`,
  `admin_set_settlement_status`, `admin_unmark_settlement`. Comprovativo por email via
  `_settlement_receipt_enqueue` → `settlement_receipts` (6 enviados, 28,42 €).
- **Quem lê:** `driver_earnings_summary` (o último acerto), `v_acerto_semanal_unificado`,
  `weekly_closeout_*`, o painel admin.
- **O que se mediu:** 10 linhas.
- **Onde se separa:** **o acerto não inclui o TVDE** (nenhuma função de acerto lê
  `tvde_rides`), não inclui as compensações de cancelamento (1.5), e a fórmula
  `ganhos − cash + talões + tokens` é recalculada a partir de `orders` de cada vez, sem
  deixar as linhas que a compõem — a pessoa vê um número, não as parcelas.

### 1.9 `order_receipts_v2` — os talões (cêntimos)

- **Guarda:** por pedido de compra: `driver_typed_total_cents`, `ocr_extracted_total_cents`,
  `reimbursement_status` ∈ `cash_settled` / `pending_admin` / `admin_paid` / rejeitado,
  `reimbursement_amount_cents`, `reimbursement_processed_at`, `reimbursement_admin_notes`.
  **Não existe** em produção a coluna `reimbursement_method` (a migration
  `20260920103000_admin_talao_pago_externamente_mbway.sql` está no repo mas **não foi aplicada**;
  `admin_mark_receipt_paid_external` também não existe no ar — confirmado por `pg_proc`).
- **Unidade:** cêntimos.
- **Quem escreve:** `finalizar_talao_nao_parceiro`, `finalize_errand_purchase`,
  `finalize_storeshopping_purchase_v2`, `registar_talao_nao_parceiro`; `admin_mark_receipt_paid`,
  `admin_reject_receipt`, `admin_corrigir_talao`.
- **Quem lê:** `order_driver_reimbursement(order_id)` — que é lido por
  `apply_driver_cash_settlement` (1.3) e por `compute_driver_settlement` (1.8).
- **O que se mediu:** 12 talões: 11 `cash_settled` (172,34 €, o estafeta ficou com o valor
  do dinheiro do cliente), 1 `admin_paid` (8,20 €, Valdemir, 19/09 23h53, nota "Pago via
  MBWay (painel admin)").
- **Onde se separa:** **`admin_mark_receipt_paid` marca aqui E insere em 1.1 sem tocar 1.2.**
  Foi o que aconteceu com o Valdemir: o painel diz "pago via MB Way", a função creditou 8,20 €
  no histórico da carteira, o saldo ficou a 0, e a 20/09 a Claude.ai teve de pôr uma linha de
  estorno (−8,20 €, chave `estorno_mbway_reimb_b89e66d2`) só para o histórico deixar de mentir.

### 1.10 `bora_tokens` — os tokens (tokens, não euros)

- **Guarda:** uma linha por atribuição: `amount` (tokens), `role`, `source_order_id`,
  `expires_at`, `is_used`.
- **Unidade:** tokens. O valor em euros vem **só** de `platform_settings.token_value_cents_x100`
  (cicatriz de 13/08).
- **Quem escreve:** `add_tokens`, `admin_grant_tokens`, `consume_tokens`,
  `admin_revoke_token_grant`; `repor_demo_apagar` apaga os de demo.
- **Quem lê:** `get_user_tokens` (soma dos não usados e não expirados — **uma verdade só,
  bem feito**), `driver_earnings_summary`, `reconcile_dia1_checks`.
- **O que se mediu:** clientes 619,40 tokens por usar (65 pessoas) + 36,65 usados; estafetas
  6,15 por usar + 4,95 usados.
- **Onde se separa:** as linhas `refund_credit_tokens` de 1.1 são uma **cópia em cêntimos**
  do que aqui está em tokens — e já divergem (Dayane: 7 cópias para 1 atribuição).
  `driver_token_transactions` existe com **0 linhas e nenhuma função a escrever** — tabela
  morta (lei do §1.20: tabela de dinheiro sempre vazia é suspeita).

### 1.11 `tvde_rides` + `tvde_ride_events` + `tvde_driver_balances` — o TVDE (cêntimos; saldo em euros)

- **Guarda:** por corrida: `final_fare_cents`, `driver_earn_cents`, `bora_cut_cents`,
  `payment_method`, `cancel_fee_cents`, tokens e crédito promocional aplicados. Ao terminar,
  `tvde_finish_ride` escreve o evento `finalizada` em `tvde_ride_events` com
  `meta.settle_cents` (o delta aplicado ao saldo) e soma-o a `tvde_driver_balances.balance`.
- **Unidade:** cêntimos nas corridas e nos eventos; **euros** no saldo.
- **Convenção de sinal do saldo:** **positivo = o motorista deve à Bora** (corrida a dinheiro:
  fica com a tarifa, deve a parte da Bora); negativo = a Bora deve ao motorista (corrida
  online: a Bora recebeu, deve-lhe o ganho). **É o contrário de `driver_balances`.**
- **Quem escreve:** só `tvde_finish_ride`.
- **Quem lê:** `driver_earnings_summary` lê `tvde_rides` (ganho por corrida, sem o sentido
  cash/online); `v_ganho_diario_por_pessoa`, `socio_kpi_tvde`. **Nenhum acerto semanal lê o
  TVDE.** O saldo `tvde_driver_balances` não é lido por ecrã nenhum encontrado.
- **O que se mediu:** 63 corridas terminadas: cash 40 (tarifa 179,80 €, motorista 178,20 €,
  Bora 43,10 €), MB Way 21 (88,00 € / 84,00 € / 18,50 €), cartão 2 (30,00 € / 24,00 € / 6,00 €).
  Saldos: Valdemir −31,50 € (a Bora deve-lhe 31,50 €: 48,00 € de corridas online menos
  16,50 € de parte da Bora nas corridas a dinheiro — **bate ao cêntimo** com a soma dos
  `settle_cents`), Erika −4,00 €, Rui Teste +2,40 €, Danilo −79,10 € contra −93,30 € nos
  eventos (**desacerto de 14,20 €** na conta do próprio Danilo; não corrigido).

### 1.12 `partner_weekly_settlements` + `payouts` + `partner_statement_lines` — o parceiro (euros)

- **Guarda:** por (loja, semana): `gross_sales`, `commission_total`, `partner_share`,
  `cash_kept_by_partner`, `net_balance`, `direction`, `status`, `paid_at`.
- **Quem escreve:** `compute_partner_weekly_settlement` (de `orders` + `ledger_entries`),
  `admin_set_partner_settlement_status`, `admin_set_settlement_state`, `admin_unmark_settlement`.
- **Quem lê:** `partner_my_weekly_closeout` (app parceiro), `admin_list_partner_settlements_for_week`,
  `weekly_closeout_*`, `stripe-connect` (Edge).
- **O que se mediu (Goola Açaí, única loja com acertos):** 3 semanas: 19,80 € pago 06/09,
  21,80 € pago 14/09, 10,90 € pendente. Soma 52,50 € = ganhos no ledger 52,50 € ✓. Pedidos
  entregues 4, bruto 77,04 €, comissão visível 6,62 €.
- **Onde se separa:**
  - **`payouts` é um gémeo parado:** tem 2 payouts da Goola (41,60 €) e 1 da Sabores do
    Brasil (10,29 €) todos em `pending`, enquanto os acertos correspondentes estão `paid`.
    Ninguém actualiza `payouts` depois de criado.
  - **`partner_statement_lines` existe (0 linhas) e nenhuma função escreve nela** — o extrato
    do parceiro linha a linha foi desenhado e nunca ligado.
  - A Sabores do Brasil tem ganho 10,29 € no ledger e payout pendente **sem nenhuma linha de
    acerto semanal**.

### 1.13 `cleaner_weekly_settlements` / `washer_weekly_settlements` / `appointment_payouts` (cêntimos)

- Limpeza, lavagem e marcações: em **cêntimos**, chave pela **linha do prestador**
  (`cleaners.id`, `washers.id`, `provider_id`), não pela pessoa. Hoje: 0 / 0 / 1 linhas.
  Entram no `v_acerto_semanal_unificado` já convertidos para a pessoa (`user_id`). Não se
  mede mais nada aqui nesta missão; ficam no mapa para o vigia os incluir.

### 1.14 `payment_reconciliation_findings` — um vigia que já existe

- Escrito por `reconcile_dia1_checks` (kinds: `pi_metadata_desconhecida` 18 abertos,
  `driver_snapshot_longe_do_dropoff` 3 abertos, `refund_prometido_sem_refund` 1 resolvido,
  `ganho_sem_lancamento_no_ledger`). Compara Stripe × pedidos × ledger. **Não compara
  histórico × saldo em arca nenhuma.** O Bloco 5 desta missão escreve aqui, no mesmo formato,
  em vez de criar uma segunda tabela de achados.

### 1.15 `order_financials` + `order_financial_transactions` — a repartição do pedido do parceiro (euros)

- **Guarda:** por pedido de parceiro entregue e pago: `base_amount` (produtos), `total_paid`,
  `restaurant_amount` (= `partner_store_share(base)`), `platform_amount`.
- **Quem escreve:** `apply_order_financial_split` (trigger ao entregar pago). **Quem lê:** o
  `extrato_parceiro` (Bloco 3) e o vigia (par `vigia_parceiro_arcas`).
- **O que se mediu (Goola, 4 pedidos):** `restaurant_amount` = ledger `restaurant/earning` =
  `partner_store_share`, ao cêntimo (10,90 € em 12,72 €). **Descoberto no Bloco 3:** o ecrã do
  parceiro calculava em Dart `subtotal − partner_commission_visible` (11,45 €) — a coluna
  `partner_commission_visible` (1,27 €) **não é** a parte da Bora (1,82 €). É um gémeo de rótulo
  (PADRAO §2.7) que já não é lido pelo ecrã.

---

## 2. O que cada arca diz hoje, por ponta, e onde discordam

### 2.1 Cliente (carteira)

| Pessoa | histórico livre (1.1, sem tokens) | saldo app (1.2) | desacerto |
|---|---:|---:|---:|
| Isabel Rebelo | 4,09 € | 1,00 € | **3,09 €** — fechado pelo Danilo, não se toca |
| Dayane Camila | 5,66 € | 5,66 € | 0 |
| Letícia Cosmo | −2,50 € | −2,50 € | 0 |
| mjogos7b | 0 | 0 | 0 |
| Danilo (cliente) | 0 | 0 | 0 |
| Valdemir (como pessoa) | 0 (8,20 − 8,20) | **sem linha** | 0 por ausência |
| outros 5 | sem histórico | 0 | 0 |

Tokens no histórico (1.1 `refund_credit_tokens`) × tokens reais (1.10): Dayane 1 015 cêntimos
no histórico contra 282 tokens (141 cêntimos) — **7 linhas a mais**; mjogos7b 5 contra 10 tokens ✓.

### 2.2 Estafeta (entregas)

| Estafeta | 1.3 ganhos+tokens−cash | 1.4 saldo | 1.5 ledger (ganhos+cash+payout) | 1.6 snapshot | acertos 1.8 |
|---|---:|---:|---:|---:|---:|
| Danilo | 37,59 € | 37,59 € ✓ | 12,95 € | 12,95 € | 10 linhas no total |
| Danilo Fulfaro | −2,10 € | −2,10 € ✓ | −6,95 € | — | |
| Estafeta Demo | 20,25 € | 20,25 € ✓ | 20,25 € ✓ | — | ignorado pelo trigger de demo |
| Valdemir | 1,28 € | 1,28 € ✓ | −0,67 € | — | |

1.3/1.4 concordam. 1.5 discorda de 1.3 em: (a) 3 compensações de cancelamento de 1,50 €
que só o ledger tem; (b) o `cash_adjustment` do ledger inclui a dívida do cliente cobrada em
mão (`fn_apply_client_debt_settlement_on_cash_delivery`) com outro sinal; (c) o ledger só
lança pedidos `paid`. Ninguém hoje consegue dizer, com uma consulta, quanto a Bora deve ao
Valdemir pelas entregas: o acerto semanal recalcula de `orders` e dá um número por semana.

### 2.3 Motorista (TVDE)

| Motorista | corridas | online (Bora deve) | cash (deve à Bora) | 1.11 saldo | soma dos eventos | desacerto |
|---|---:|---:|---:|---:|---:|---:|
| Valdemir | 21 | 48,00 € | 16,50 € | −31,50 € | −31,50 € | 0 ✓ |
| Erika | 1 | 4,00 € | 0 | −4,00 € | −4,00 € | 0 ✓ |
| Rui Teste E2E | 1 | 0 | 2,40 € | +2,40 € | +2,40 € | 0 ✓ |
| Danilo | 40 | 56,00 € | 24,20 € | −79,10 € | −93,30 € | **14,20 €** |

O TVDE não entra em `driver_weekly_settlements` nem em `v_acerto_semanal_unificado`:
**a Bora deve 31,50 € ao Valdemir de TVDE e nenhum acerto o sabe.**

### 2.4 Parceiro

| Loja | pedidos entregues | ganhos ledger | acertos (soma) | acertos pagos | payouts (estado) |
|---|---:|---:|---:|---:|---|
| Goola Açaí | 4 (77,04 €) | 52,50 € | 52,50 € ✓ | 41,60 € | 41,60 € **pending** (gémeo parado) |
| Sabores do Brasil | — | 10,29 € | **sem acerto** | — | 10,29 € pending |

### 2.5 Dono (Danilo)

Não existe hoje nenhuma arca que responda "quanto entrou, por que meio, quanto saiu, quanto
está retido". Os pedaços: `orders` (entradas por método), `tvde_rides` (idem), `ledger_entries`
tipo `commission` (41,91 € — só de pedidos pagos), `stripe_connect_events` (13),
`platform_settings` (comissões), Stripe (fora da base). O Bloco 4 constrói a folha a partir
destes, sem inventar nenhum.

---

## 3. Os gémeos, em lista fechada (o que o Bloco 1 e o Bloco 5 têm de vigiar)

1. **`wallet_transactions` × `client_wallets`** — saldo da carteira. Causa-raiz da ordem.
2. **`wallet_transactions.balance_after_cents` × `client_wallets.free_balance_cents`** — o
   mesmo saldo guardado duas vezes, uma delas às vezes.
3. **`wallet_transactions` (`refund_credit_tokens`) × `bora_tokens`** — tokens em cêntimos
   contra tokens em tokens.
4. **`driver_transactions` × `driver_balances`** — concordam, com sinal invertido no
   `cash_adjustment`.
5. **`driver_transactions` × `ledger_entries`** — dois históricos do mesmo ganho, escritos por
   triggers diferentes com regras diferentes (pago/não pago; cancelamentos).
6. **`ledger_entries` × `user_balance_snapshots`** — concordam por trigger.
7. **`orders.driver_earnings` × 1.3 × 1.5 × `driver_weekly_settlements.total_earnings`** — o
   mesmo ganho lido de quatro maneiras.
8. **`tvde_ride_events.meta.settle_cents` × `tvde_driver_balances`** — concordam em 4 de 5.
9. **`order_receipts_v2.reimbursement_status` × `wallet_transactions` (`reimbursement_storeshopping`)** —
   o talão pago e o crédito da carteira.
10. **`partner_weekly_settlements` × `payouts` × `ledger_entries` (restaurant)** — três registos
    do mesmo pagamento à loja; `payouts` fica parado.
11. **`driver_weekly_settlements` (euros) × `cleaner/washer_weekly_settlements` (cêntimos)** —
    unidades diferentes na mesma família.
12. **`drivers.id` × `drivers.user_id`** como chave de dinheiro — `v_driver_weekly_earnings`
    junta pelo errado.

---

## 4. O que NÃO se fez neste bloco (de propósito)

- Não se corrigiu nada. Nem a Isabel (ordem do Danilo), nem os 14,20 € do TVDE do Danilo,
  nem os 1,50 € de cancelamento, nem os `payouts` parados, nem as 7 linhas de tokens da Dayane.
- Não se leu a Stripe (fora da base). Os totais "por meio" de §2.5 são os da base.
- Não se mediram limpeza/lavagem/marcações além de contar linhas (0/0/1).
