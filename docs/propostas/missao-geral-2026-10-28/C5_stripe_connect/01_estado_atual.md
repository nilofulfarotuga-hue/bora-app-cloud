# C5 — Stripe Connect fase 2 · 01 · Estado atual (29/10/2026)

Missão `final-app-2026-10-29`, Bloco 7 C5. Agente `pagamentos-wallet` (PROPOSE-ONLY).
Tudo abaixo foi lido por SELECT, por `list_edge_functions` / `get_edge_function` e no repo
`C:\BoraLocal\wt-missao-geral-28-10` (só leitura). Nada foi aplicado, deployado, nem escrito
no banco ou na Stripe. Projeto Supabase `ojykpzwqrtusfeakzrna`.

## 0. Em cinco linhas

1. A fase 1 do Connect está feita e no ar: 3 Edge Functions, 4 tabelas com colunas `stripe_*`, extrato, ecrãs do parceiro e do admin, webhook do Connect a receber `account.updated`.
2. A fase 2 não existe: não há `transfers.create` em lado nenhum (grep a `supabase/functions` e `lib`: zero), nem tabela que ligue acerto a transferência.
3. O interruptor `stripe_connect_enabled` está `false` e hoje só muda o texto do extrato (lido em duas RPCs de leitura); não trava nenhum pagamento porque não há pagamento Connect.
4. O fecho semanal corre sozinho (cron 26, segunda 00:05) e cria os acertos dos parceiros; quem os paga é o Danilo, à mão, no ecrã "Acertos da semana", com referência escrita. Há 2 parceiros com conta Connect ativa (Sabores de Casa Açaí e Goola Açaí) de 29 restaurantes.
5. O "Roll secret" do webhook do Connect continua por fazer (o `whsec_` passou pelo chat a 06/08); passo a passo em `03_roll_secret_webhook.md`.

## 1. Fase 1 — o que já existe

### 1.1 Edge Functions (estado vivo, `list_edge_functions` de hoje)

| Função | Versão | verify_jwt | O que faz | Repo |
|---|---|---|---|---|
| `stripe-connect-onboard` | v3 | true | Cria a conta Express (PT, EUR, só capacidade `transfers`) e devolve o link de registo; conta `enabled` → link do painel Express. Resolve a linha pelo JWT, nunca por id vindo do cliente. | `supabase/functions/stripe-connect-onboard/index.ts:107-113` (criação), `:35` (interruptor de modo) |
| `stripe-connect-webhook` | v3 | false (assinatura própria) | `account.updated` → espelho do estado; `account.application.deauthorized` → `disabled`; `payout.paid/failed` → auditoria (+ aviso ao admin no `failed`). Idempotente por `event_id`. | `supabase/functions/stripe-connect-webhook/index.ts:36` (nome do secret), `:83`, `:97`, `:111-112` (eventos) |
| `stripe-connect-admin` | v3 | true + `is_admin()` | `onboard_link`, `login_link`, `resync`, `disconnect`. Tudo em `admin_audit_log`. | `supabase/functions/stripe-connect-admin/index.ts:9` (ações), `:144-152` (disconnect = "volta a acerto manual", comentário "Fase 1: não há transferências automáticas") |

Nota: o `stripe-webhook` dos pagamentos (zona protegida) é outro endpoint e não foi tocado.

### 1.2 Webhook do Connect (só o nome do secret, nunca o valor)

- Endpoint na Stripe: `we_1U1ROvGlT3R2jCYpG8qnQ1zW`, modo live, escopo "contas conectadas", 4 eventos: `account.updated`, `account.application.deauthorized`, `payout.paid`, `payout.failed` (página `livro-areas-stripe-connect` do livro, 06/08).
- URL: `https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-connect-webhook`.
- Nome do secret no Supabase: **`STRIPE_CONNECT_WEBHOOK_SECRET`** (lido em `index.ts:36`; se faltar, a função responde 400 a tudo — falha fechada por desenho).
- Prova de uso real: `stripe_connect_events` tem 30 eventos, todos `account.updated`, de 06/08 a 28/09, 4 contas. Zero eventos `payout.*` (nunca houve transferência nem payout Connect).

### 1.3 Base de dados

- Colunas (6 por tabela) em `restaurants`, `service_providers`, `drivers`, `cleaners`: `stripe_account_id`, `stripe_account_status` (default `'none'`), `stripe_charges_enabled`, `stripe_payouts_enabled`, `stripe_requirements` (jsonb), `stripe_onboarded_at`.
- Funções (migrations `20260806120000_stripe_connect_statement.sql` e `20260806121000_stripe_connect_status_rpc.sql`): `apply_stripe_account_update` (só service_role; é o que o webhook chama), `stripe_connect_fee_cents(p_gross_cents, p_kind)` (função única da taxa, `:65`), `admin_list_connect_accounts`, `get_my_connect_status`, `get_statement`.
- Tabelas: `stripe_connect_events` (PK `event_id`), `partner_statement_lines` (`kind` ∈ sale/commission/stripe_fee/payout/adjustment; RLS: dono lê o seu, admin lê tudo, só service_role escreve).
- Settings (`platform_settings`, categoria `stripe_connect`), valores de hoje: `stripe_connect_enabled=false`, `stripe_fee_bearer="partner"`, `stripe_processing_fee_pct=0.015`, `stripe_processing_fee_fixed_cents=25`, `stripe_payout_fee_pct=0.0025`, `stripe_payout_fee_fixed_cents=25`, `stripe_connect_monthly_account_cents=200`.
- Onde `stripe_connect_enabled` é lido no servidor: só `get_my_connect_status` (`20260806121000...sql:71`) e `get_statement` (`:129`). Nada mais.

### 1.4 Dados reais (hoje)

| Tabela | Linhas com conta Connect | Estado |
|---|---|---|
| `restaurants` (29) | 2: Sabores de Casa Açaí, Goola Açaí | ambas `enabled`, `charges` e `payouts` ligados, `currently_due` vazio |
| `drivers` | 1 | (a conta de teste do Danilo, ativa desde 14/09 segundo o livro) |
| `service_providers` | 1 | por confirmar o estado |
| `cleaners` | 0 | — |

### 1.5 O que o painel admin e as apps já mostram

- Admin (PT-BR) `lib/screens/admin/admin_connect_payments_screen.dart` ("Pagamentos Connect"): lista de contas (`:55` `admin_list_connect_accounts`), ações por conta (`:102` invoca `stripe-connect-admin`), edição das 7 chaves (`:306-345`; o diálogo de `stripe_connect_enabled` está em `:312` e o de `stripe_fee_bearer` em `:337`), extrato de qualquer conta, trilha de auditoria (`:63`, ações `stripe_connect%`). **Não tem nada de transferências.**
- Admin "Acertos da semana" `lib/screens/admin/admin_acertos_semana_screen.dart`: o botão que paga é `_marcar` (`:208-220`): abre `confirmarDinheiro(...)` e chama `admin_set_settlement_state`. Botão "Pagar" no cartão: `:974`. Rota `/admin/acertos-semana` em `lib/main.dart:1022`.
- Admin "Acertos" (parceiros, estado manual) `lib/screens/admin/admin_settlements_screen.dart:188` chama `admin_set_partner_settlement_status` com referência livre.
- Parceiro (PT-PT) `lib/screens/connect/connect_payments_screen.dart` (`:44` `get_my_connect_status`, `:66` `stripe-connect-onboard`) e `connect_statement_screen.dart` (`:73` lê `connect_enabled`; `:271` mostra "Pago pela Stripe ✅ a DD/MM" quando existe linha `payout`; `:275-279` mostra "Pagamento ainda por transferência bancária." enquanto `connect_enabled=false`).

## 2. O fecho semanal — a máquina que a fase 2 tem de respeitar

### 2.1 Quem cria os acertos dos parceiros

- Cron 26 `close-weekly-settlements`, `5 0 * * 1`, ativo → `run_weekly_closeout()` → `close_partner_week_settlements()` → `compute_partner_weekly_settlement(parceiro, âncora, true)` (grava). Definições lidas por `pg_get_functiondef`; a migration de origem mais recente da função está em `supabase/migrations/20261004214000_parceiro_extrato_sem_markup_ganhos.sql`.
- Conta do acerto: `partner_share` = soma das linhas `earning` do `ledger_entries` desse parceiro nas encomendas entregues da semana (segunda a domingo, hora de Lisboa); `cash_kept_by_partner` = o que o parceiro cobrou em dinheiro; **`net_balance = ROUND(partner_share − cash_kept_by_partner, 2)`**. `direction`: `bora_pays_partner` (net > 0), `partner_pays_bora` (net < 0) ou `zero`.
- Tabela `partner_weekly_settlements`: única por `(partner_id, week_start_at)`; `status` ∈ pending/closed/paid/received/disputed; o upsert do fecho não reescreve linhas `paid`/`received`. Gatilhos: `trg_acerto_pago_congelado` (linha paga não muda de valor), `trg_receipt_partner` (ao mudar o estado, põe o comprovativo na fila), `trg_acerto_ignora_demo`.
- Histórico real: 6 acertos de 2 parceiros, todos `paid` (9,90 + 30,28 + 10,90 + 21,80 + 19,80 a favor do parceiro; 1 acerto de −5,41 em que o parceiro pagou à Bora). Nenhum pendente hoje. O próximo fecho é segunda 02/11 às 00:05.

### 2.2 Como se paga hoje (manual)

- Ecrã "Acertos da semana" → `admin_set_settlement_state('partner', <id>, <segunda>, 'paid', <referência>)`: só faz `status='paid'`, `paid_at`, `paid_by`, `payment_reference` e escreve `admin_audit_log`. Exige `is_admin()` (utilizador autenticado admin; **com a chave de serviço falha com `admin_required`**, porque `auth.uid()` é nulo).
- Esse caminho **não escreve** em `ledger_entries` nem em `payouts`. Prova: o saldo do `ledger` dos 3 restaurantes é 122,37 € = soma exata das 8 linhas `earning` (nunca foi abatido pelos 5 pagamentos manuais).
- Reabrir: `admin_reabrir_acerto` (só a semana em curso ou a última fechada, motivo obrigatório) e `admin_unmark_settlement` (sem limite de semana). Ambos põem o acerto outra vez `pending`. **É o buraco do pagamento em duplicado** se houver uma transferência Stripe já feita (ver `02_proposta_fase2.md`, secção 6).

### 2.3 O caminho antigo de payouts — não reativar

- Cron 2 `bora_weekly_auto_payout` (segunda 03:00): **inativo**. A função `auto_payout_pending` → `create_payout` (cria linha em `payouts` pendente + linha negativa `payout` no `ledger_entries`).
- `payouts` tem 10 linhas, **todas `failed`** (07/09 a 05/10), e o `ledger` tem 20 linhas `payout` que somam 0,00 (cada saída foi anulada por uma linha "estorno fantasma 2026-10-05"). Conclusão: o caminho de payouts por saldo do ledger nunca pagou ninguém; reativá-lo ao lado da fase 2 pagaria duas vezes.
- Duas contabilidades em paralelo: o acerto semanal (verdade do dinheiro a pagar) e o saldo do ledger (acumula ganhos, não abatido). A fase 2 segue o acerto semanal.

## 3. O que falta (a fase 2)

| # | Falta | Evidência |
|---|---|---|
| 1 | Nenhuma criação de transferência Stripe | grep `transfers.create` / `createReversal` em `supabase/functions` e `lib`: 0 resultados |
| 2 | Nenhuma tabela liga acerto ↔ transferência (idempotência, estado, erro) | consulta a `pg_class` por nomes `%connect%`/`%transfer%`: só `stripe_connect_events` |
| 3 | Nenhum botão/ecrã admin para pagar via Stripe nem para ver transferências | `admin_connect_payments_screen.dart` não tem transferências |
| 4 | O extrato dos parceiros não tem linhas de `partner_statement_lines` (owner_type `partner`): o backfill de 06/08 correu antes de existirem acertos de parceiros | SELECT: 0 linhas `partner` |
| 5 | O acordo de taxas é por parceiro (Goola: nenhuma taxa Stripe; Ouro e Prata: só a taxa de transferência) mas `stripe_fee_bearer` é global | página `livro-areas-stripe-connect-parte3` |
| 6 | O modo de teste usa `BORA_STRIPE_MODE`, um interruptor **global** que também muda o TVDE; não há prova de que `STRIPE_TEST_SECRET_KEY` exista (os secrets não se leem por MCP) | `GUIA_DANILO_STRIPE_CONNECT.md:62-69` |
| 7 | O webhook do Connect não tem eventos de transferência (os eventos `transfer.*` são da plataforma, não das contas conectadas; o único endpoint de plataforma é o `stripe-webhook`, zona protegida, onde eventos não tratados só ficam no log). A proposta não depende deles: a criação da transferência é síncrona. | `index.ts:111-112`; `stripe-webhook` `default:` |
| 8 | Roll secret do webhook pendente | `03_roll_secret_webhook.md` |
| 9 | Ligar `stripe_connect_enabled` muda o texto do extrato de **todos** os parceiros (os 27 sem conta passariam a não ver "Pagamento ainda por transferência bancária.") | `connect_statement_screen.dart:73,275-279`; RPC `get_statement` `:129` |

## 4. Números de apoio (para a proposta)

- Custo Stripe do modelo "a Bora cobra" (livro, 06/08): 2,00 € por conta ativa por mês + 0,25 % + 0,25 € por payout enviado. Com os 2 parceiros de hoje: 4,00 €/mês fixos + ~0,27–0,33 € por semana e parceiro (9,90 € → 27 cêntimos; 30,28 € → 33 cêntimos), isto é, 2,7 % a 1,1 % do valor pago.
- Os pagamentos semanais reais andam entre 9,90 € e 30,28 €. Pagar por pedido seria ruinoso (o fixo de 0,25 € por payout come a margem); fica semanal.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — à espera de autorizo. (Este ficheiro é só diagnóstico; nada foi aplicado.)
