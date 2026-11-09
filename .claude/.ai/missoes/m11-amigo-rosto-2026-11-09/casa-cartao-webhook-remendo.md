# PROPOSTA — remendo do stripe-webhook para a Casa (m11, 09/11/2026)

⚠️ ZONA PROTEGIDA (stripe-webhook) e DINHEIRO. Só se aplica com o "autorizo" do Danilo, junto com a
proposta `casa-cartao-mbway-proposta.md` (o SQL) e a Edge `supabase/functions/casa-checkout`.

## Porquê

Na Limpeza e na Lavagem, o webhook da Stripe é a GARANTIA de que um pagamento feito fica registado
mesmo que a app feche a meio (o caso típico: o cliente aprova o MB Way no telemóvel e a app já não está
aberta para ver). O `mark_held` da app é só o acelerador. Sem este remendo, um MB Way aprovado com a app
fechada não fica registado: o pedido cai aos 30 minutos e o dinheiro fica na Stripe até alguém devolver
à mão pelo painel. Com o remendo, o pedido segue sozinho para os profissionais (ou, se já tinha caído,
fica marcado para devolver e a app/painel devolvem).

## Onde

`supabase/functions/stripe-webhook/index.ts`, no `case 'payment_intent.succeeded'`, logo DEPOIS do bloco
da Limpeza que acaba assim (âncora, igual nas versões lidas a 09/11):

```ts
        } else {
          console.error('[stripe-webhook] cleaning PI missing booking_id:', intent.id);
        }
        break;
      }
```

## O que entra (só isto; nada mais muda)

```ts
      // ⭐ m11 (09/11/2026) — CASA & MANUTENÇÃO (kind='casa'). O webhook GARANTE o 'held'
      // (MB Way aprovado com a app fechada); o mark_held do cliente (casa-checkout) é o acelerador.
      // RPC idempotente: confere o valor contra total_cents; pedido já caído → marcado para devolver.
      if (intent.metadata?.kind === 'casa') {
        const pedidoId = intent.metadata?.pedido_id;
        if (pedidoId) {
          const { data, error } = await supabase.rpc('casa_pagamento_confirmado', {
            p_pedido_id: pedidoId,
            p_payment_intent_id: intent.id,
            p_amount_cents: Number(intent.amount_received ?? intent.amount ?? 0),
            p_stripe_account: intent.metadata?.bora_conta ?? null,
            p_origem: 'stripe-webhook',
          });
          if (error) {
            console.error('[stripe-webhook] casa held failed:', error.message, intent.id);
            falha(`casa_pagamento_confirmado: ${error.message}`);
          } else {
            console.log('[stripe-webhook] casa held:', JSON.stringify(data), intent.id);
          }
        } else {
          console.error('[stripe-webhook] casa PI missing pedido_id:', intent.id);
        }
        break;
      }
```

## Antes de aplicar (regra da memória "repo pode estar atrás do ar")

1. Descarregar a versão NO AR do stripe-webhook (e do `_shared` que ela leva) e comparar com o repo;
   o remendo aplica-se por cima da versão do ar, pela âncora acima.
2. `deno check` fora do repo (cópia numa pasta do %TEMP%) e o teste do webhook, se existir.
3. Publicar o webhook DEPOIS de a migração estar aplicada (a função `casa_pagamento_confirmado` tem de
   existir) e ANTES de ligar `casa_pagamento_app_ativo`.
