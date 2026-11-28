// supabase/functions/stripe-webhook-empresa/index.ts — v2 (PROPOSTA, missão limpeza-planos-fecho-2026-11-28)
// v1: missão stripe-empresa-2026-11-01, autorização do Danilo 01/11/2026 22:03.
//
// Webhook da conta Stripe da EMPRESA ("Bora", Danilo Fulfaro da Silva - Unipessoal Lda,
// acct_1UX67LGWwQxC9wR2). Destino na Stripe:
//   https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-webhook-empresa
// com EXATAMENTE os mesmos eventos que o webhook da conta pessoal escuta.
// v2 (planos de limpeza): na Stripe da EMPRESA é preciso JUNTAR a este webhook os eventos
//   setup_intent.succeeded e payment_intent.requires_action.
//
// verify_jwt = false (a Stripe não manda JWT): a autenticação é a assinatura `stripe-signature`,
// verificada com STRIPE_WEBHOOK_SECRET_EMPRESA dentro de _shared/stripe_webhook_core.ts.
// O tratamento é o MESMO do stripe-webhook (v38) — código partilhado, nada copiado — a falar
// com a Stripe da empresa (STRIPE_SECRET_KEY_EMPRESA). Um PaymentIntent tvde_* que chegue aqui
// não se toca: alerta urgente ao admin e 200.
//
// v2: os eventos dos PLANOS de limpeza (metadata kind 'cleaning_plan' / 'cleaning_plan_setup')
// tratam-se em planos.ts, ANTES do tratamento de sempre, depois de verificar a assinatura.
// Todos os outros eventos seguem para tratarWebhookStripe exatamente como antes (o corpo e os
// cabeçalhos originais, para a assinatura voltar a ser verificada lá). O _shared/stripe_webhook_core.ts
// não muda (é partilhado com o stripe-webhook da conta pessoal).
//
// O stripe-webhook antigo continua vivo e intocado para a conta pessoal (TVDE, pagamentos
// antigos, reembolsos atrasados).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { tratarWebhookStripe } from '../_shared/stripe_webhook_core.ts';
import { secretKey } from '../_shared/keys.ts';
import { segredoWebhook, stripePara } from '../_shared/stripe_contas.ts';
import { aplicarDecisao, decidirEventoPlano } from './planos.ts';

const JSON_H = { 'Content-Type': 'application/json' };

Deno.serve(async (req: Request) => {
  const corpo = await req.text();
  const assinatura = req.headers.get('stripe-signature');
  const segredo = segredoWebhook('empresa');

  if (assinatura && segredo) {
    try {
      const stripe = stripePara('empresa');
      const evento = await stripe.webhooks.constructEventAsync(corpo, assinatura, segredo);
      const decisao = decidirEventoPlano(evento as unknown as { type: string; data: { object: unknown } });
      if (decisao) {
        const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', secretKey());
        try {
          const r = await aplicarDecisao(admin, decisao, async (pmId) => {
            const pm = await stripe.paymentMethods.retrieve(pmId);
            return { brand: pm.card?.brand ?? null, last4: pm.card?.last4 ?? null, exp_month: pm.card?.exp_month ?? null, exp_year: pm.card?.exp_year ?? null };
          });
          console.log('[stripe-webhook-empresa] plano de limpeza:', evento.type, evento.id, JSON.stringify(r));
          return new Response(JSON.stringify({ received: true, plano: true }), { headers: JSON_H });
        } catch (e) {
          console.error('[stripe-webhook-empresa] plano de limpeza falhou (a Stripe repete):', evento.type, evento.id,
            e instanceof Error ? e.message : String(e));
          return new Response(JSON.stringify({ received: false }), { status: 500, headers: JSON_H });
        }
      }
    } catch (_) {
      // assinatura inválida ou sem chave: o tratamento de sempre responde como sempre (400/500)
    }
  }

  // Tudo o resto: o tratamento de sempre, com o pedido original.
  return tratarWebhookStripe(new Request(req.url, { method: req.method, headers: req.headers, body: corpo }), 'empresa');
});
