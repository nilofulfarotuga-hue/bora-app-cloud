# Stripe — duas contas (TVDE na pessoal, o resto na empresa)

> Missão `stripe-empresa-2026-11-01` (arrancada 02/11/2026 00:35, Claude Code / Fable).
> Autorização literal do Danilo: «Autorizo» — 01/11/2026 às 22:03 (ligar o app à Stripe da
> empresa: chaves, segredos, webhook, funções, app, painel, publicar nas 3 plataformas).
> Fora do âmbito: preços, comissões, taxas, tokens, Stripe Connect.

## 1. As contas

| Conta | Nome na Stripe | acct | Quem a usa |
|---|---|---|---|
| **PESSOAL** | "bora app" | `acct_1T8MFaGlT3R2jCYp` | TVDE / Bora Motorista (corridas, pacote ida-e-volta, paragens, planos, reservas TVDE, mudança de destino, cancelamentos/reembolsos TVDE, gorjeta de corrida) e **tudo o que já foi pago antes da mudança** |
| **EMPRESA** | "Bora" — Danilo Fulfaro da Silva - Unipessoal Lda, NIPC 519686233 | `acct_1UX67LGWwQxC9wR2` | entregas (restaurantes, mercados, lojas), Favores, limpeza, lavagem, Casa & Manutenção, marcações, reservas de mesa (3 €), gorjetas de entregas, dívida/carteira, diferença de peso, extras e acertos de pedido |

Regra de ouro: **o dinheiro mexe-se sempre na conta onde entrou.** Um pedido pago na pessoal
é reembolsado na pessoal, mesmo depois de a empresa passar a ser a conta ativa.

A conta da empresa começa do zero: não se copiam clientes, cartões, produtos nem histórico.
O cliente volta a guardar o cartão no primeiro pagamento na empresa
(`users.stripe_customer_id_empresa`; `users.stripe_customer_id` fica para a pessoal).

## 2. Segredos no servidor (Supabase Edge Functions)

| Segredo | Conta | Estado 02/11 00:50 |
|---|---|---|
| `STRIPE_SECRET_KEY` | pessoal (live) | existe (26/04) |
| `STRIPE_TEST_SECRET_KEY` + `BORA_STRIPE_MODE=test` | pessoal (teste) | não existe em produção (só usado em CI/QA) |
| `STRIPE_WEBHOOK_SECRET` | pessoal, destino `stripe-webhook` | existe (26/04) |
| `STRIPE_CONNECT_WEBHOOK_SECRET` | pessoal, Connect (fora da missão) | existe (06/08) |
| `STRIPE_SECRET_KEY_EMPRESA` | empresa (chave restrita `bora-app-servidor`) | **a criar na F1** |
| `STRIPE_PUBLISHABLE_KEY_EMPRESA` | empresa (pública) | **a criar na F1** (+ `.dart_defines` / `DART_DEFINES_FILE_B64` do CI) |
| `STRIPE_WEBHOOK_SECRET_EMPRESA` | empresa, destino `stripe-webhook-empresa` | **a criar na F2** |

A chave publicável da pessoal vive só no app (`STRIPE_PUBLISHABLE_KEY` em `.dart_defines`); o
servidor não a tinha. Passa a ter as duas (`STRIPE_PUBLISHABLE_KEY` e `_EMPRESA`) para as
devolver na resposta de criar pagamento (`publishable_key`).

## 3. Interruptor e compatibilidade

- `platform_settings.stripe_conta_nao_tvde` = `'pessoal'` (até as provas passarem) → `'empresa'`.
  Voltar a `'pessoal'` faz tudo regressar sem novo build.
- Apps antigas só conhecem a chave pessoal. O servidor só cria pagamentos na empresa quando o
  pedido traz `stripe_contas_v2: true` (apps a partir do build desta missão). Sem isso, pessoal.
- Forçar atualização: `app_min_supported_version_code = 0` e `_ios = 0` (02/11) → **não há
  versão mínima ativa**. Proposta no relatório: subir quando a maioria tiver a versão nova.
- Código defensivo: chave da empresa em falta / `stripePara('empresa')` a falhar → cai para
  pessoal, regista em `e2e_log` e alerta o admin. Nunca deixar o cliente sem pagar.

## 4. Mapa função → tipo de pagamento → conta (lido do código EM PRODUÇÃO, 02/11/2026)

Base de cada função = versão em produção (descarregada com `supabase functions download`,
guardada em `%TEMP%\claude\stripe-empresa-prod\per\<fn>`). Divergências repo ↔ produção:

- **Só comentários / caracteres de caixa**: a maioria (código igual).
- **Repo à frente, não publicado, só `secretKey()` de `_shared/keys.ts`** (missão
  chaves-varredura 31/10, sem efeito em runtime): admin-cancel-reservation, admin-payments,
  carwash-checkout, cleaning-checkout, confirm-mbway-appointment-payment,
  create-appointment-payment-intent, create-mbway-appointment-payment-intent,
  create-mbway-reservation-payment-intent, create-reservation-payment-intent, delete-account,
  list-saved-cards, manage-saved-cards, pay-debt-standalone, tvde-dest-change, tvde-plan-payment.
  → mantém-se a versão do repo (superset inofensivo).
- **Repo à frente com código autorizado mas NÃO publicado** (gorjeta devolvida no cancelamento,
  autorização 30/10 13:40 e 01/11 19:56; o classificador recusou o deploy a 01/11 — e2e_log
  zona-vermelha-2026-11-01): admin-cancel-order, cancel-order-with-choice, execute-cancellation,
  auto-refund-order. → base = repo; ao publicar nesta missão sobe também esse código (já autorizado).
- **Produção à frente do repo**: reprocess-refund (produção limita o reembolso ao que ainda
  está na Stripe e aceita MB Way). → repo ressincronizado a partir de produção
  (versão antiga do repo em `_arquivo/2026-11-02-repo-vs-prod/`).
- **`_shared/cobranca_stripe.ts` v3** (gorjeta cobrada junto) já está publicado via
  payments-reconciler e charge-tip; admin-cancel-order/cancel-order-with-choice/
  execute-cancellation em produção ainda carregam a v2 → ao republicar passam à v3.

| Função (prod vN) | O que faz na Stripe | Tipo / `kind` | Conta |
|---|---|---|---|
| create-payment-intent v36 | customers.create, paymentIntents.create/cancel, payment_drafts | pedido (cartão), draft_id | **fluxo** (empresa quando ligado) |
| create-mbway-payment-intent v32 | paymentIntents.create/retrieve (mb_way) | pedido (MB Way), order_id | **fluxo** |
| finalize-order-from-intent v16 | paymentIntents.retrieve | pedido (cria a ordem a partir do PI) | **gravada** no draft/PI |
| stripe-webhook v38 | constructEvent, PI retrieve, refunds.create | todos os eventos da PESSOAL | pessoal (fica intocado) |
| stripe-webhook-empresa (novo) | idem, código partilhado em `_shared/` | todos os eventos da EMPRESA; PI `tvde_*` → alerta urgente, não mexe | empresa |
| refund v28 | PI retrieve, refunds.create | reembolso admin/RPC (orders, appointments, reservations) | **gravada** |
| reprocess-refund v5 | PI retrieve, refunds.create | reembolso que falhou | **gravada** |
| auto-refund-order v6 | PI retrieve/cancel, refunds.create | cancelado pelo sistema | **gravada** |
| client-cancel-order v32 | PI retrieve, refunds.create | cancelamento pelo cliente | **gravada** |
| admin-cancel-order v16 | refunds.create | cancelamento admin | **gravada** |
| cancel-order-with-choice v20 | refunds.create | cancelamento com escolha (saldo/meio) | **gravada** |
| execute-cancellation v17 | refunds.create | pedido de cancelamento aprovado | **gravada** |
| charge-extra v21 | paymentIntents.create (off_session) | extra ao pedido | **gravada** (conta do pedido) |
| cobrar-diferenca-peso v1 | PI create/retrieve | diferença de peso | **gravada** (conta do pedido) |
| order-edit-settle v4 | PI create/retrieve, refunds.create | acerto de edição do pedido | **gravada** (conta do pedido) |
| pay-debt-standalone v9 | PI create/confirm | dívida / carteira | **fluxo** |
| list-saved-cards v8 | customers.retrieve, paymentMethods.list | cartões guardados | **conta pedida** (`stripe_account` no body; default fluxo) |
| manage-saved-cards v4 | paymentMethods.retrieve/detach | cartões guardados | **conta pedida** |
| create-reservation-payment-intent v18 | PI create | reserva de mesa 3 € | **fluxo** |
| create-mbway-reservation-payment-intent v9 | PI create (mb_way) | reserva de mesa | **fluxo** |
| admin-cancel-reservation v13 | refunds.create | reembolso de reserva | **gravada** |
| create-appointment-payment-intent v8 | PI create | marcação (barbearia/beleza) | **fluxo** |
| create-mbway-appointment-payment-intent v7 | PI create (mb_way) | marcação | **fluxo** |
| confirm-mbway-appointment-payment v4 | PI retrieve | marcação (confirmar MB Way) | **gravada** |
| cleaning-checkout v7 | customers.create, PI create/capture/cancel, refunds | limpeza | **fluxo** / gravada nos passos seguintes |
| cleaning-request-payment v3 | PI create (off_session) | limpeza (cobrar depois) | **gravada** (conta da reserva) |
| diag-pagamento-limpeza v2 | PI retrieve | diagnóstico limpeza | **gravada** |
| carwash-checkout v3 | customers.create, PI create/capture/cancel, refunds | lavagem | **fluxo** / gravada |
| charge-tip v3 | customers.create, PI create/retrieve, balance | gorjeta (`target` entrega ou tvde) | entrega → **fluxo**; TVDE → pessoal |
| payments-reconciler v9 | lê PIs via cobranca_stripe | conferência | **gravada** por linha |
| admin-payments v4 | customers.retrieve, paymentMethods.list | painel admin | **as duas** |
| stripe-relatorio-contabilista v1 | balance transactions | relatório contabilista | **separado por conta**; empresa ≥ 01/11/2026 |
| fecho-mensal-contabilista v1 | lê `stripe_extrato_contabilista` | fecho mensal | **separado por conta** |
| tvde-payment v21 | customers.create, PI create/update/cancel/retrieve, refunds | `tvde_ride`, `tvde_stop`, `tvde_roundtrip`, `tvde_reservation`, `tvde_roundtrip_reservation` | **pessoal** (sem alteração) |
| tvde-plan-payment v10 | customers.create, PI create/retrieve | `tvde_plan`, `tvde_roundtrip` | **pessoal** |
| tvde-dest-change v4 | não fala com a Stripe (cobrança é na tvde-payment) | — | pessoal |
| delete-account v26 | não fala com a Stripe (só texto) | — | — |
| stripe-connect-* | **não se toca** | Connect | — |

Funções SQL: nenhuma fala com a API da Stripe diretamente (verificado em `pg_proc`, 02/11);
as que precisam chamam as Edge Functions acima (`refund`, `auto-refund-order`, `charge-tip`,
`finalize-order-from-intent`). O cofre (`vault.secrets`) não tem chaves Stripe.

## 5. Tabelas com pagamentos Stripe (coluna nova `stripe_account`)

`'pessoal' | 'empresa'`, default `'pessoal'`, gravada no momento em que o PaymentIntent é criado.
Tudo o que já existe = `'pessoal'`.

| Tabela | Coluna do PI | Linhas com PI (02/11) |
|---|---|---|
| orders | payment_intent_id, refund_id, stripe_charge_cents | 29 |
| payment_drafts | payment_intent_id | 1 |
| pending_charges | stripe_payment_intent_id | 0 |
| tips | stripe_payment_intent_id | 1 |
| cleaning_bookings | stripe_payment_intent_id | 1 |
| carwash_bookings | stripe_payment_intent_id | 0 |
| reservations | prepayment_pi | 0 |
| appointments | deposit_pi, full_payment_pi | 3 |
| pedido_morada_trocada | payment_intent_id (rascunho do pedido) | — |
| stripe_webhook_events | event_id (recebe também os da empresa) | 153 |
| stripe_extrato_contabilista | payment_intent, bt_id | — |
| users | `stripe_customer_id` (pessoal) + **`stripe_customer_id_empresa`** (nova) | 21 clientes |
| tvde_rides, tvde_ride_stops, tvde_roundtrip_credits, tvde_subscriptions, tvde_destination_changes | payment_intent_id | ficam sempre `'pessoal'` (não levam coluna) |
| casa_pedidos (Casa & Manutenção) | **não tem PaymentIntent** (02/11) — sem Stripe ainda | — |

## 6. App (Flutter) — onde a chave entra

- `lib/main.dart` ~L644: `Stripe.publishableKey` = `STRIPE_PUBLISHABLE_KEY` (ou `STRIPE_TEST_…`
  com `BORA_STRIPE_MODE=test`) + `applySettings()` no arranque.
- Porta única da folha de cartão: `lib/services/folha_cartao.dart` → `apresentarFolhaCartao(...)`,
  chamada por payment_service (pedidos, dívida, cartão guardado), services_store (marcações),
  reservation_flow_screen e reservation_checkout_screen.
- Web: `lib/services/web_checkout_web.dart` → `startWebCardCheckout(publishableKey: …)` →
  `web/pay.html` (Stripe.js lê `pk` do fragmento).
- Cartões guardados: `list-saved-cards` (payment_service.fetchSavedCards) e `manage-saved-cards`
  (card_wallet_service).
- MB Way: só client_secret/PI, sem chave publicável no app.

Mudança (F4): antes de cada folha / confirmação / web checkout, a chave passa a ser a que o
servidor devolveu (`publishable_key`), com `applySettings()` se mudou; TVDE continua na pessoal.
Pedidos de criação de pagamento levam `stripe_contas_v2: true`.

## 7. Estado por fase (02/11/2026 ~03:00) e o que falta, passo a passo

A sessão de 02/11 (Claude Code, Fable) correu **sem o Danilo presente**: a tranca do repo
(bora-tranca) pergunta-lhe antes de migrações, deploys de Edge Functions e push, e nega as 8
funções da zona vermelha. Por isso o servidor ficou **preparado no repo**, não publicado.

| Fase | Estado | O que falta |
|---|---|---|
| F0 inventário | feito | — |
| F1 chaves da empresa | **bloqueado** | a Stripe pede a palavra-passe da Stripe para ligar a conta Google boraappbora (só o Danilo). Depois: criar a chave restrita `bora-app-servidor` e gravar os segredos (§7.1) |
| F2 webhook da empresa | código feito; destino por criar | criar o destino na Stripe da empresa (§7.2); gravar o segredo do webhook da empresa; publicar `stripe-webhook-empresa` |
| F3 servidor | código feito no repo | aplicar as propostas SQL (docs/propostas/stripe-duas-contas/01–03, 05) e publicar as funções (§7.3) |
| F4 app | feito no repo (menos `order_store`) | aplicar a proposta 04 (2 linhas em `lib/stores/order_store.dart`) |
| F5 painel admin | feito no repo | aplicar a proposta SQL 05 para a coluna "Conta Stripe" vir do banco |
| F6 provas | por fazer | só depois de F1–F3 (§7.4) |
| F7 publicar | por fazer | `git push origin autonomous-night-2026-04-29` (CI publica Play + web; Apple pelo caminho de sempre) e acrescentar a chave publicável da empresa ao segredo `DART_DEFINES_FILE_B64` do GitHub |

### 7.1 Chaves da empresa (Chrome perfil Bora, deviceId d9e862e0…)
1. `https://dashboard.stripe.com/acct_1UX67LGWwQxC9wR2/apikeys` → "Criar chave restrita",
   nome `bora-app-servidor`, permissões de **escrita**: PaymentIntents, SetupIntents, Customers,
   PaymentMethods, Refunds, Charges; **leitura**: Balance, Balance transactions, Payouts, Events.
   (Se a Stripe recusar alguma, usar a chave secreta padrão e dizer porquê no relatório.)
2. Gravar os três segredos com `npx -y supabase@2 secrets set … --project-ref ojykpzwqrtusfeakzrna`
   (o CLI do PC vive em `npx -y supabase@2`; o token está em `.supabase-token.env` na raiz do
   repo do PC): a chave restrita da empresa em `STRIPE_SECRET_KEY_EMPRESA`, a chave publicável
   da empresa em `STRIPE_PUBLISHABLE_KEY_EMPRESA` e a chave publicável da pessoal em
   `STRIPE_PUBLISHABLE_KEY` (o servidor passa a devolvê-las ao app). Os valores NUNCA vão para
   o chat, git, Córtex, e2e_log ou Obsidian.
3. `.dart_defines` local: linha `STRIPE_PUBLISHABLE_KEY_EMPRESA` com a chave publicável da
   empresa; CI: refazer o segredo `DART_DEFINES_FILE_B64` (decodificar o atual, acrescentar a
   linha, voltar a codificar em base64).
4. Métodos de pagamento da empresa: ligar os mesmos da pessoal (cartão, MB Way, Google Pay; Apple
   Pay está desligado na v1 iOS). MB Way "em análise" = registar e seguir.

### 7.2 Webhook da empresa
1. Ler na conta PESSOAL (`https://dashboard.stripe.com/acct_1T8MFaGlT3R2jCYp/webhooks`) a lista
   de eventos do destino `…/functions/v1/stripe-webhook` (o código trata
   `payment_intent.succeeded`, `payment_intent.processing`, `payment_intent.payment_failed`,
   `payment_intent.canceled`, `charge.refunded`; copiar EXATAMENTE a lista configurada).
2. Na EMPRESA: destino `https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-webhook-empresa`
   com os mesmos eventos. O segredo de assinatura vai para `STRIPE_WEBHOOK_SECRET_EMPRESA`
   (mesmo comando `secrets set`).
3. Publicar: `npx -y supabase@2 functions deploy stripe-webhook-empresa --no-verify-jwt --project-ref ojykpzwqrtusfeakzrna`.

### 7.3 Servidor — ordem de aplicação (Claude.ai por MCP ou sessão com o Danilo na caixa da tranca)
1. SQL: `docs/propostas/stripe-duas-contas/01_colunas_stripe_account.sql` →
   `02_interruptor_stripe_conta_nao_tvde.sql` → `03_stripe_extrato_resumo_por_conta.sql` →
   `05_admin_list_payments_conta.sql`. Copiar cada uma para `supabase/migrations/` com o nome indicado.
2. Zonas vermelhas: copiar cada `supabase/functions/_propostas/stripe-duas-contas/<fn>/index.ts`
   para `supabase/functions/<fn>/index.ts` (create-payment-intent, create-mbway-payment-intent,
   finalize-order-from-intent, stripe-webhook, refund, reprocess-refund, charge-extra,
   client-cancel-order) e `docs/propostas/stripe-duas-contas/04_order_store_duas_linhas.md`.
3. Publicar as funções (todas lêem `_shared/stripe_contas.ts`): as 8 acima + stripe-webhook-empresa
   + admin-cancel-order, cancel-order-with-choice, execute-cancellation, auto-refund-order
   (estas 4 levam também o código das gorjetas autorizado a 30/10 e 01/11 que o classificador
   recusou publicar a 01/11), create-reservation-payment-intent, create-mbway-reservation-payment-intent,
   admin-cancel-reservation, create-appointment-payment-intent, create-mbway-appointment-payment-intent,
   confirm-mbway-appointment-payment, list-saved-cards, manage-saved-cards, pay-debt-standalone,
   diag-pagamento-limpeza, cleaning-request-payment, cobrar-diferenca-peso, order-edit-settle,
   cleaning-checkout, carwash-checkout, charge-tip, payments-reconciler, admin-payments,
   stripe-relatorio-contabilista, fecho-mensal-contabilista. `verify_jwt` igual ao que cada uma tem hoje
   (`supabase functions list`).
   **Enquanto `stripe_conta_nao_tvde` = 'pessoal' e os segredos da empresa não existirem, tudo
   continua a funcionar exatamente como hoje** (a conta decidida é sempre 'pessoal').

### 7.4 Provas (F6) e interruptor
1. Modo teste da empresa (BORA_STRIPE_MODE=test + chave de teste da empresa) num emulador:
   cartão 4242 numa entrega de mercado → pedido criado, `stripe-webhook-empresa` 200,
   `orders.stripe_account='empresa'`; reembolso sai na empresa; cartão guardado aparece só na
   empresa; MB Way de teste; corrida TVDE de teste continua na pessoal.
2. Pedido antigo (pessoal) → reembolso em teste vai à pessoal.
3. Produção sem cobrar: PaymentIntent de 0,50 € criado e cancelado logo na empresa pelo servidor;
   o evento `payment_intent.canceled` chega ao `stripe-webhook-empresa` com 200
   (`stripe_webhook_events.stripe_account='empresa'`).
4. Só então: `update platform_settings set value='"empresa"'::jsonb where key='stripe_conta_nao_tvde';`
   (ou no painel admin → "Stripe — duas contas"). Provar por SELECT. Voltar a 'pessoal' desfaz tudo.
5. Android (emulador), iPhone (simulador/TestFlight) e web (app.boraguarda.com): a folha abre com a
   conta certa (o log da app diz `[StripeContas] chave publicável aplicada: empresa (…)`).

### 7.5 Erros encontrados pelo caminho (reportados, não escondidos)
- O commit cb134328 (chaves, 31/10) deixou **4 funções com o bloco de imports partido** no repo
  (create-reservation-payment-intent, create-mbway-reservation-payment-intent,
  create-appointment-payment-intent, create-mbway-appointment-payment-intent): `import { secretKey }`
  ficou dentro de outro `import {`. Nunca foi publicado (o ar continua com a versão anterior);
  corrigido nesta missão.
- `reprocess-refund` no repo estava atrás da produção (v5): ressincronizado.
- As 4 funções de cancelamento com a devolução de gorjetas (autorizadas 30/10 e 01/11) continuam
  por publicar desde 01/11 (o classificador recusou); seguem com esta missão.
- `app_min_supported_version_code` = 0 (Android e iOS): não há versão mínima a forçar atualização.
  Proposta: só depois de a versão desta missão estar na maioria dos aparelhos, subir para esse
  `versionCode`; até lá os apps antigos ficam na pessoal e continuam a pagar.
- `deno check` acusa 2 erros de tipos **já existentes em produção** (`list-saved-cards` e
  `cleaning-checkout`, "implicit any"); o bundler da Supabase não verifica tipos, por isso nunca
  partiram nada. Não se tocou.
