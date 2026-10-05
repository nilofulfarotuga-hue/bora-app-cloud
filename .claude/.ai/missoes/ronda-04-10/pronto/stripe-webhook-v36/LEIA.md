# stripe-webhook v36 + finalize v14 + client-cancel v29 — PRONTO A APLICAR (só o Danilo)

> Ronda 04/10, Bloco A (dinheiro das entregas). Preparado a 05/10/2026 pelo Claude Code.
> ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
> A Trava proíbe o agente de editar ou publicar estas três funções; nada foi publicado.

## O que está nesta pasta

| Ficheiro | O que é |
|---|---|
| `ar-v35-index.ts` | o stripe-webhook **no ar** (v35), byte a byte (sha256 `84a94d70…85bb`). Serve para o repo ficar igual ao ar (A.9). |
| `index.v36.PROPOSTA.ts` | o v35 com as mudanças marcadas `// v36 (ronda 04/10 A.x)` (36 marcas). |
| `ar-v35-para-v36.diff` | diff -u do ar para a proposta. |
| `stripe_webhook_events.sql` | migração da tabela de idempotência (RLS ligada, sem políticas, sem anon/authenticated). |
| `finalize-order-from-intent-v14/` | `ar-v13-index.ts` (o ar), `index.v14.PROPOSTA.ts`, `ar-v13-para-v14.diff`. |
| `client-cancel-order-v29/` | `ar-v28-index.ts` (o ar), `index.v29.PROPOSTA.ts`, `ar-v28-para-v29.diff`. |
| `simular_webhook.ts` | guião de simulação (base falsa + Stripe falsa, assinatura HMAC verdadeira). |
| `simulacao.saida.txt` | saída: **v36 10/10 passam; v35 1/10** (só o cenário de controlo). |
| `deno-check.saida.txt` | `deno check` das 6 versões (ar e proposta): **0 erros em todas**, antes e depois. |

## O que muda, em palavras simples

**stripe-webhook v36**
- **A.1** Sempre que um pedido fica pago (cartão ou MB Way, pedido normal, pedido criado por rascunho/finalize, e o MB Way que reativa um pedido cancelado cedo demais), o webhook grava no pedido quanto a Stripe cobrou mesmo (`registar_cobranca_stripe` com `amount_received`). Até hoje esse número ficava sempre a 0 — e por isso os cancelamentos não sabiam que havia dinheiro a devolver.
- **A.3** O mesmo evento da Stripe já não é tratado duas vezes (tabela `stripe_webhook_events`, chave = id do evento). E quando uma gravação falha a sério (função do banco ou UPDATE com erro), o webhook responde **500** e a Stripe volta a tentar (até 3 dias). Antes respondia 200 e o pedido ficava por marcar para sempre. Eventos com dados desconhecidos continuam a responder 200 (só log).
- **A.7a Reserva TVDE paga** (`tvde_reservation` e `tvde_roundtrip_reservation`): o webhook chama as mesmas funções que a app chama ao confirmar (`tvde_reservation_mark_paid` / `tvde_roundtrip_reservation_mark_paid`). A reserva **nasce em `status='agendada'` + `reservation_status='aguarda_pagamento'`** (tvde-payment `charge_reservation`, comentário v10 e confirmado na função) e só procura motorista quando passa a `a_procurar`. Na v35 o webhook só punha `payment_status='succeeded'` e a reserva ficava parada em `aguarda_pagamento` até o cliente abrir a app. Reserva já morta (cancelada) continua a ir para o reembolso automático, nunca é ativada.
- **A.7b Plano TVDE**: passa os km pagos e a rota que estão nos metadados do pagamento (`distance_km`, `origin_label`, `dest_label` — postos pelo tvde-plan-payment). **A função `tvde_activate_paid_subscription` já aceita km** (`p_km_included`, `p_origin_label`, `p_dest_label`, com valor por defeito) — **não é preciso SQL novo**. Bug que isto fecha: se o webhook chegasse antes da app, o plano nascia sem km e a app já não o corrigia (a função devolve a subscrição existente pelo mesmo pagamento).
- **A.7c Lavagem** (`kind='carwash'`): marca a marcação como `held` pela mesma função do `mark_held` do carwash-checkout (`confirm_carwash_payment_webhook`, valida o valor, idempotente, procura lavador).
- **A.7d Gorjeta** (`kind='tip'`): grava na tabela `tips` exactamente como o `confirm` do charge-tip (mesmo mapeamento de estados, `paid_at`, `stripe_fee_cents`, `failure_reason`; nunca volta atrás de `succeeded`/`refunded`). Também no pagamento falhado/cancelado.

**finalize-order-from-intent v14** — depois de criar o pedido, grava a cobrança (`registar_cobranca_stripe` com o `amount_received` do PI que já lia). Se falhar só faz log (o pedido não se desfaz). Nota: no banco há **0 pedidos** criados por este caminho (payment_drafts usados = 0), por isso o efeito real hoje é preventivo.

**client-cancel-order v29** — lê o que foi pago com `lerPagoDoPedido` (se a coluna estiver a 0, pergunta à Stripe e grava) e reparte o reembolso com `repartirReembolso`: primeiro volta ao cartão/MB Way até ao que a Stripe cobrou, o resto vai à carteira com `wallet_credit_refund_split` (chave = id do pedido, não credita duas vezes). Se não conseguir ler a Stripe, responde 503 **antes** de cancelar (nada muda; o cliente tenta de novo). A opção "quero na carteira" continua a pôr tudo na carteira (agora com chave).

## Como aplicar (3 passos, pela ordem)

1. **Banco**: aplicar `stripe_webhook_events.sql` (e copiá-lo para `supabase/migrations/20261005xxxxxx_stripe_webhook_events.sql`). Prova: a query no fim do ficheiro tem de dar `rls=true, politicas=0, anon_le=false, auth_escreve=false`.
2. **Copiar e publicar** (Danilo, a Trava não deixa o agente):
   - `index.v36.PROPOSTA.ts` → `supabase/functions/stripe-webhook/index.ts` → publicar com **verify_jwt = false** (como o ar; a Stripe não manda JWT).
   - `finalize-order-from-intent-v14/index.v14.PROPOSTA.ts` → `supabase/functions/finalize-order-from-intent/index.ts` → **verify_jwt = true** (como o ar).
   - `client-cancel-order-v29/index.v29.PROPOSTA.ts` → `supabase/functions/client-cancel-order/index.ts` → **verify_jwt = true** (como o ar). Leva `_shared/cobranca_stripe.ts` (já no repo) — publicar a pasta com o `_shared`.
   - Ordem segura: webhook primeiro, depois finalize, depois client-cancel.
3. **Commit** dos três `index.ts` + a migração no ramo `autonomous-night-2026-04-29` (caminhos explícitos; ver o que viaja junto antes do push).

## Como provar no ar

- Versões: `list_edge_functions` → stripe-webhook **36** (verify_jwt false), finalize **14**, client-cancel **29** (verify_jwt true).
- Idempotência: no painel Stripe → Webhooks → um evento recente → "Reenviar". Depois:
  `select event_id, type, processed_at, last_error from stripe_webhook_events order by received_at desc limit 5;`
  e nos logs da função tem de aparecer `evento repetido, já processado`.
- Cobrança: no próximo pedido MB Way/cartão pago,
  `select id, payment_status, payment_intent_id, stripe_charge_cents from orders where payment_intent_id is not null order by created_at desc limit 5;` → `stripe_charge_cents` > 0.
- Falhas reais: `select * from stripe_webhook_events where processed_at is null and received_at < now() - interval '10 minutes';` deve ficar vazio (o que lá estiver é trabalho que a Stripe ainda está a repetir).
- Reserva TVDE com MB Way: depois de pagar, `select reservation_status, payment_status from tvde_rides where id = '<reserva>';` → `a_procurar` sem o cliente abrir a app.

## Como voltar atrás

- Republicar `ar-v35-index.ts` (verify_jwt false), `ar-v13-index.ts` (verify_jwt true) e `ar-v28-index.ts` (verify_jwt true) — são cópias exactas do ar.
- A tabela pode ficar (o v35 não a usa). Só se quiser: `drop table public.stripe_webhook_events;` **depois** de repor o v35.

## Riscos (lidos, não escondidos)

1. **500 faz a Stripe repetir até 3 dias.** Um erro permanente (não transitório) numa função do banco fica a repetir e a Stripe envia aviso por email se o endpoint falhar muito. Excepções já tratadas como recusa definitiva (200): `paid_below_plan_price` do plano, `ride_already_terminal` do TVDE, `ok:false` da lavagem. Ver `last_error` na tabela.
2. **Repetição depois de falha a meio**: o evento volta a correr do início. Os passos são idempotentes (pedido só passa a pago se estava `pending`; RPCs por PI; refunds com idempotencyKey), mas o aviso ao parceiro do MB Way pode sair 2x nesse caso raro (como já acontecia na v35 em toda a repetição).
3. **Duas entregas do mesmo evento ao mesmo tempo** ainda podem correr as duas (a tabela só trava depois de `processed_at`). As funções de dinheiro são idempotentes; não há duplicação de dinheiro, só de log.
4. **Se a tabela não existir**, o v36 segue sem idempotência (como o v35) e escreve o erro no log — não bloqueia pagamentos. Por isso aplicar a migração primeiro.
5. **Lavagem paga por cartão** é pré-autorizada (`requires_capture`): não gera `payment_intent.succeeded` até ser capturada, por isso esse caso continua a depender do `mark_held` da app. O MB Way (que chega como succeeded) fica coberto. Cobrir o cartão exigiria tratar `payment_intent.amount_capturable_updated` e subscrevê-lo no painel da Stripe — não incluído (decisão tua).
6. **client-cancel v29 muda o caminho do MB Way**: antes o reembolso de MB Way ia todo para a carteira; agora a parte paga por MB Way volta ao MB Way pela Stripe (o resto à carteira). E a parte da carteira passa a ir pelo split 80% saldo / 20% tokens também na "graça" (antes, na graça com destino carteira, era 100% saldo — isso continua igual quando o cliente escolhe carteira). Confirma se é isto que queres.
7. `refund_method` só aceita `stripe|wallet|none`: um reembolso misto fica gravado como `stripe` com `refund_amount` = total movido; a resposta à app traz `refund_card_eur` e `refund_wallet_eur`.

## O que a simulação prova (e o que não prova)

`deno run -A --config deno.json simular_webhook.ts <index.ts>` (deno.json = `{"nodeModulesDir":"auto"}`). Corre o código verdadeiro com stripe@14.21.0 e supabase-js@2 verdadeiros; só a rede é falsa.

| Cenário | v35 (ar) | v36 |
|---|---|---|
| A.1 pedido pago grava stripe_charge_cents | FALHA (0) | PASSA (1850) |
| A.1 pedido por finalize grava stripe_charge_cents | FALHA (0) | PASSA (990) |
| A.3 evento repetido não processa 2x | FALHA (parceiro avisado 2x) | PASSA (1x) |
| A.3 falha de RPC → 500 + last_error; repetição acaba | FALHA (200, perdido) | PASSA |
| A.3 falha do UPDATE do pedido → 500 | FALHA (200, pedido por marcar) | PASSA |
| A.7d gorjeta fica succeeded | FALHA (fica requires_action) | PASSA |
| A.7c lavagem fica held | FALHA (fica unpaid) | PASSA |
| A.7a reserva TVDE fica a_procurar | FALHA (fica aguarda_pagamento) | PASSA |
| A.7b plano grava km | FALHA (km vazio) | PASSA (12.5) |
| controlo: metadata desconhecida → 200 | PASSA | PASSA |

Não prova: o comportamento das funções reais do banco (as RPCs falsas imitam o essencial das definições lidas a 05/10), nem o finalize v14 / client-cancel v29 (só `deno check`, sem simulação).
