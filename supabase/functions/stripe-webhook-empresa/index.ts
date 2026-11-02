// supabase/functions/stripe-webhook-empresa/index.ts — v1 (missão stripe-empresa-2026-11-01,
// autorização do Danilo 01/11/2026 22:03).
//
// Webhook da conta Stripe da EMPRESA ("Bora", Danilo Fulfaro da Silva - Unipessoal Lda,
// acct_1UX67LGWwQxC9wR2). Destino na Stripe:
//   https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-webhook-empresa
// com EXATAMENTE os mesmos eventos que o webhook da conta pessoal escuta.
//
// verify_jwt = false (a Stripe não manda JWT): a autenticação é a assinatura `stripe-signature`,
// verificada com STRIPE_WEBHOOK_SECRET_EMPRESA dentro de _shared/stripe_webhook_core.ts.
// O tratamento é o MESMO do stripe-webhook (v38) — código partilhado, nada copiado — a falar
// com a Stripe da empresa (STRIPE_SECRET_KEY_EMPRESA). Um PaymentIntent tvde_* que chegue aqui
// não se toca: alerta urgente ao admin e 200.
//
// O stripe-webhook antigo continua vivo e intocado para a conta pessoal (TVDE, pagamentos
// antigos, reembolsos atrasados).

import { tratarWebhookStripe } from '../_shared/stripe_webhook_core.ts';

Deno.serve((req: Request) => tratarWebhookStripe(req, 'empresa'));
