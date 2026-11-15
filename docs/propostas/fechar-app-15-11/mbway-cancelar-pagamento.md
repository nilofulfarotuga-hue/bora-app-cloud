# Proposta — cancelar o pagamento MB WAY na Stripe quando o pedido é cancelado por falha (15/11/2026)

> ZONA DE DINHEIRO. Isto é só proposta: nada aplicado. Precisa do "autorizo" do Danilo
> com data para esta tarefa. Ficheiros envolvidos: `supabase/functions/client-cancel-order`
> (e, se se escolher a opção B, `supabase/functions/stripe-webhook`).

## O problema (achado 1 da revisão do Juiz e Refinador, 15/11)

Quando o MB WAY falha ou o cliente não confirma a tempo (120 s), a app chama
`client-cancel-order` com `reason: 'payment_failed'`. Essa função muda o pedido para
cancelado (`payment_status = cancelled_no_charge`), mas **não cancela o PaymentIntent na
Stripe**: o pedido de pagamento continua vivo na app MB WAY do banco. Se o cliente o
aprovar depois, o `stripe-webhook` (função de reativação, linhas ~391-455) vê que o
cancelamento foi automático por `payment_failed` e **reativa** o pedido.

Desde o commit ea1e450a o cliente fica no ecrã de pagamento com o carrinho e é convidado
a tentar outra vez. Se aprovar os dois pedidos na app MB WAY, paga duas vezes.

## O que já foi feito do lado da app (só fluxo, sem dinheiro) — ramo `ai/2026-11-15-fechar-app`

- O carrinho guarda o id do último pedido MB WAY à espera.
- Antes de criar outro pedido (qualquer meio), ao abrir o ecrã de pagamento e ao voltar à
  app, a app lê esse pedido: se está pago ou já não está cancelado, limpa o carrinho e abre
  os Pedidos em vez de criar outro. Sem rede para confirmar, não cria outro.
- A frase da falha diz: "Se o pedido antigo ainda aparecer na app MB WAY, recusa-o lá."

Isto fecha a janela enquanto a app está aberta, mas não a fecha toda: se o cliente cria o
2.º pedido e só depois aprova o 1.º na app do banco, entram os dois. Só o servidor pode
fechar isso.

## Correção de raiz proposta

**Opção A (recomendada) — `client-cancel-order` cancela o PaymentIntent.**
Quando `reason === 'payment_failed'`, `payment_method === 'mbway'`, o pedido tem
`payment_intent_id` a começar por `pi_` e nada foi cobrado (`paidCents === 0`):

1. `stripe.paymentIntents.retrieve(pi)`;
2. se o estado for `requires_action`, `requires_payment_method` ou `requires_confirmation`:
   `stripe.paymentIntents.cancel(pi, { cancellation_reason: 'abandoned' }, { idempotencyKey: 'cancel-' + pi })`.
   Em `processing` não se cancela (a Stripe não deixa): segue como hoje e o webhook trata;
3. se a Stripe disser `succeeded` entretanto: NÃO cancelar o pedido; devolver
   `{ ok: false, error: 'already_paid' }` para a app abrir o pedido pago;
4. falha a falar com a Stripe: cancelar o pedido na mesma (como hoje) e registar no
   `e2e_log`/eventos, para o webhook continuar a ser a rede de segurança.

Com o PI cancelado, a app MB WAY deixa de mostrar o pedido de pagamento (a Stripe cancela
a ação pendente), e o webhook nunca reativa porque não há pagamento.

**Opção B (complementar) — o webhook não reativa se o cliente já tem outro pedido pago
com o mesmo carrinho nos últimos minutos**: reembolsa automaticamente em vez de reativar.
É mais frágil (o "mesmo carrinho" é uma heurística) e mexe no `stripe-webhook`; só vale
se a opção A não chegar.

## Como provar (quando houver "autorizo")

- `deno test` com Stripe falsa: `payment_failed` + PI `requires_action` → `cancel` chamado
  uma vez com a chave de idempotência; PI `succeeded` → pedido não cancelado e
  `already_paid` devolvido; Stripe em erro → pedido cancelado como hoje.
- Em produção, um pedido MB WAY de teste deixado expirar: o PI fica `canceled` na Stripe e
  o pedido some da app MB WAY.

## O que esta proposta NÃO muda

Nenhum valor, taxa, comissão nem regra de reembolso. A função de reembolso
(`repartirReembolso`) não é tocada: o caso só se aplica quando nada foi cobrado.
