// PROPOSTA — supabase/functions/stripe-webhook/index.ts — v39 (duas contas Stripe)
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03). A tranca do repo
// não deixa esta sessão escrever em supabase/functions/stripe-webhook/; este ficheiro é a versão
// completa pronta a copiar para lá e publicar (verify_jwt=false, como hoje).
//
// O tratamento dos eventos (v38, intacto) passou para _shared/stripe_webhook_core.ts, parametrizado
// pela conta. Esta função é a da conta PESSOAL ("bora app", acct_1T8MFaGlT3R2jCYp): TVDE / Bora
// Motorista e todos os pagamentos feitos antes da mudança. Assinatura: STRIPE_WEBHOOK_SECRET;
// Stripe: STRIPE_SECRET_KEY. Nada muda para a Stripe pessoal (mesmo URL, mesmos eventos).
// A função irmã stripe-webhook-empresa faz o mesmo para a conta da empresa.

import { tratarWebhookStripe } from '../_shared/stripe_webhook_core.ts';

Deno.serve((req: Request) => tratarWebhookStripe(req, 'pessoal'));
