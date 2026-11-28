# O cliente cancela a reserva paga: o "reembolso em curso" é verdade? (fechar-tudo-15-11)

Pedido: revisão do Juiz da Claude.ai (15/11, 17:2x) ao commit `59e0bc95`, dentro do "Autorizo tudo"
do Danilo (15/11 15:15). Só leitura: SELECT no servidor, código da Edge `refund` lido com
`get_edge_function`, código do repo. Nada aplicado, nenhuma chamada à Stripe, nenhum código novo:
esta nota é a prova e a proposta.

## Resposta curta

O reembolso é **pedido, mas às cegas**. `client_cancel_reservation` põe o pedido de reembolso na
fila do pg_net (Edge `refund`) e, na mesma transação, marca a reserva `cancelled_refunded` e diz ao
cliente "Reserva cancelada — reembolso em curso / Reembolso de €3,00 em 5–10 dias úteis", sem
esperar pela resposta. Se a devolução falhar, ninguém sabe e ninguém tenta outra vez. E há pior: a
`refund` devolve qualquer pagamento que lhe mandem, e o cliente consegue gravar numa reserva o
pagamento que quiser (INSERT direto). Isso abre um caminho para reaver o dinheiro de um pedido já
entregue (ponto C, abaixo).

## Provas (15/11/2026)

1. **A função** `public.client_cancel_reservation(uuid, text)`: SECURITY DEFINER, EXECUTE para
   authenticated, md5(pg_get_functiondef) `64e04af0ca86cde88b99a83d7d947224`. Com direito a
   reembolso (faltam ≥ `reservation_cancel_window_hours` = 2 h), `prepayment_pi` não nulo e
   ≥ 0,50 €:
   - `net.http_post(project_url || '/functions/v1/refund', Authorization: Bearer <cofre
     service_role_key>, {paymentIntentId: prepayment_pi, amount: prepayment_cents/100, userId,
     orderId: <id da reserva>})` dentro de `BEGIN … EXCEPTION`, e logo a seguir
     `v_refund_ok := true`;
   - o pg_net é assíncrono: o pedido só entra em `net.http_request_queue` e sai depois do COMMIT.
     `v_refund_ok` quer dizer "pedido posto na fila", não "dinheiro devolvido";
   - `status = 'cancelled_refunded'` e o aviso in-app ao cliente saem na mesma transação;
   - o aviso à equipa (`notify_admin_event 'reservation_client_cancel_refund_manual'`, estado
     `cancelled_refund_pending`) só sai se o próprio `http_post` lançar ou faltar um segredo no
     cofre. Uma devolução recusada pela Stripe não dispara nada.
2. **A Edge `refund` no ar** (versão 36, `verify_jwt=true`, corpo "v29 duas contas Stripe"):
   - aceita a chamada do servidor (`chamadaDoServidor`). O cabeçalho que a função SQL manda é o
     mesmo do vigia das chaves (`_cron_saude_chaves_funcoes`, modo `legada_bearer` = `Bearer
     _service_role_key()`; sem `app.settings.service_role_key` definido em lado nenhum, é o cofre
     `service_role_key`, hoje uma `sb_secret`). Em `saude_chaves_pings`, a 15/11 às 07:00, a
     `refund` respondeu `200 {"pong":true}` a esse cabeçalho. **O pedido passa a porta**;
   - escolhe a conta Stripe pela linha que tem o PI (`contaDoPaymentIntent`: orders, tips,
     payment_drafts, pending_charges, reservations.prepayment_pi…). Uma reserva paga na empresa
     (`stripe_conta_nao_tvde` = "empresa" hoje) é devolvida pela empresa: certo;
   - **não confere a metadata do PaymentIntent** (`purpose`/`reservation_id`). Só confere que está
     `succeeded` e que o valor não passa do `amount_received`. Chave de idempotência:
     `refund-<pi>-<cêntimos>`;
   - a resposta (`refundId` ou erro) fica em `net._http_response`, que ninguém lê e que o pg_net
     apaga ao fim de poucas horas.
   - Achado pelo caminho: o repo está atrás do servidor. `supabase/functions/refund/index.ts` no
     repo é a v28 (só a conta pessoal); no ar corre a v29 das duas contas, publicada a partir de
     uma proposta (o cabeçalho diz "PROPOSTA — v29 … pronta a copiar para lá e publicar"). Convém
     trazer a versão do ar para o repo.
3. **Ninguém confere nem tenta outra vez**:
   - gatilhos em `reservations` (9, lidos em `pg_trigger`): campos protegidos, coming soon,
     convidado, aviso de nova reserva ao admin e ao parceiro, late cancel, no-show, seated,
     finished. Nenhum mexe em dinheiro;
   - `cron.job` com "reserv"/"refund": lembretes 24 h e 2 h, resumo da manhã, pendentes há muito,
     expirar listas, `auto_close_no_show_reservations`; o 7.º (`lote-minuto-despacho`) só apanha
     `tvde_reservations_sweep`, das corridas TVDE. Nenhum é de reembolso;
   - `payments-reconciler` (repo) só confere que um PI de reserva pago tem reserva fora de
     `pending_payment`. Não confere se uma `cancelled_refunded` foi mesmo devolvida;
   - só 3 funções SQL chamam `/functions/v1/refund`: `client_cancel_reservation`,
     `client_cancel_appointment` e `partner_cancel_appointment`. As duas das marcações têm o mesmo
     padrão às cegas; não foram lidas a fundo aqui;
   - `cancelled_refund_pending` só aparece em `client_cancel_reservation`: nenhuma função, cron ou
     Edge trata as reservas que ficam nesse estado. A Edge `admin-cancel-reservation` também não
     as trata: a RPC do admin responde `cannot_cancel_status`.
4. **Em produção:** 0 linhas em `reservations` e 0 linhas `client_cancel_reservation` no
   `admin_audit_log`. Este caminho nunca correu com dinheiro real e não há clientes por
   reembolsar.
5. **O INSERT direto está aberto:** authenticated tem INSERT em `reservations`, também nas colunas
   `status`, `prepayment_cents`, `prepayment_pi` e `stripe_account`
   (`information_schema.column_privileges`). A RLS `reservations_client_owner` (FOR ALL, with check
   `client_user_id = auth.uid()`) deixa passar. Os gatilhos de INSERT (coming soon, convidado,
   avisos) não conferem esses campos. O gatilho novo `trg_00_reservas_campos_protegidos` só corre
   no UPDATE.

## O que isto quer dizer

- **A. Uma devolução falhada não faz barulho.** Casos reais: MB WAY ainda `processing`
  (`charge_missing`, 409), Stripe em baixo, chave da conta em falta (`stripe_key_missing`, 500),
  valor acima do recebido. Em todos, o cliente leu "reembolso em curso", a reserva diz
  `cancelled_refunded` e a equipa não foi avisada.
- **B. A recuperação existe, mas ninguém sabe quando a usar.** A Edge `admin-cancel-reservation`
  (v22, desta missão) trata uma `cancelled_refunded` como nova tentativa: lê a Stripe e devolve o que
  faltar, com chave nova por tentativa. Só que nada diz à equipa que é preciso carregar nela.
- **C. Buraco de dinheiro.** Juntando as provas 1, 2 e 5, sem teste (só leitura):
  1. o cliente insere uma reserva `pending` para amanhã, com `prepayment_pi` = o PaymentIntent de
     um pedido seu já entregue e `prepayment_cents` = o valor desse pedido;
  2. chama `client_cancel_reservation`;
  3. a `refund` encontra o PI em `orders`, vê-o `succeeded` e devolve o pedido inteiro, na conta
     certa.

  A `admin-cancel-reservation` e a `partner-reject-reservation` não caem nisto: exigem
  `metadata.purpose='reservation_prepayment'` e `metadata.reservation_id` = a reserva.

## Proposta mínima (sem código; para a Claude.ai decidir e mandar fazer)

1. **Urgente — fechar o INSERT.** Um BEFORE INSERT em `reservations` que, para authenticated/anon
   não-admin, obrigue `status='pending_payment'`, `prepayment_cents=0`, `prepayment_pi=null` e
   `stripe_account` por defeito. É o ACHADO 1 de `reservas_pagamento.PROPOSTA.sql`. As Edge
   `create-*-reservation-payment-intent` inserem com a chave do servidor e não são afetadas. Só isto
   já fecha o ponto C. Também fecha o "reservar sem pagar" pela porta do lado.
2. **O reembolso do cliente feito como o do admin, com resposta verdadeira.** Uma Edge
   `client-cancel-reservation` (sessão do cliente confirmada no Auth) que:
   1. muda o estado por uma RPC igual à `client_cancel_reservation`, mas sem o `net.http_post`;
   2. devolve com a lógica de `admin-cancel-reservation/logica.ts`: PI lido na Stripe com a
      metadata desta reserva, valor = recebido − já devolvido, chave por tentativa, conta da linha;
   3. se não sair, avisa a equipa (`notify_admin_urgent_push`) e diz ao cliente a verdade
      ("reembolso pedido" ou "a nossa equipa vai tratar").

   A app (`lib/screens/client_reservations_screen.dart`, `_cancel`) passa a chamar a Edge. Lógica
   partilhada, para não haver um terceiro "gémeo" a divergir de `partner-reject-reservation` e
   `admin-cancel-reservation`.
   - Alternativa mais pequena: a função SQL deixa de marcar `cancelled_refunded` antes da resposta
     (fica `cancelled_refund_pending`, com o aviso "a processar"). Um robô de minuto a minuto (Edge
     com a chave do servidor e a mesma lógica de devolução) faz a devolução e só depois muda para
     `cancelled_refunded`; se falhar, `notify_admin_urgent_push`.
3. **Conferência diária** no `payments-reconciler`: cada reserva `cancelled_refunded` /
   `rejected_refunded` dos últimos 30 dias tem de ter na Stripe devoluções feitas ou a caminho que
   cubram o recebido. Senão, um achado `critical`. Serve para os três caminhos (cliente, parceiro,
   admin).

Hoje há 0 reservas, por isso o risco presente é só o do ponto C. O passo 1 é o que não pode esperar.
