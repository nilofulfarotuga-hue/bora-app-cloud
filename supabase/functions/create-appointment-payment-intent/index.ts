// supabase/functions/create-appointment-payment-intent/index.ts — v5
//
// v5 (2026-11-15, conserto P0 do Juiz da Claude.ai, "Autorizo tudo" do Danilo 15:15): a escrita
// do deposit_pi passa a ir por um cliente com a chave do servidor SEM o Authorization do
// cliente; quem chama é identificado por admin.auth.getUser(token); se gravar falhar, o
// PaymentIntent é cancelado e a resposta é erro; nova tentativa depois de um PI cancelado já não
// recebe o PI cancelado da Stripe. Lógica em logica.ts. Nenhum valor cobrado foi alterado.
// v4 (2026-08-16): F3a MISSAO TOTAL — metadata ganha `kind: 'appointment'`
// (padronizacao do router por kind no stripe-webhook, que passa a ser a
// GARANTIA do pagamento; o poll do cliente fica como acelerador). Nenhum
// valor cobrado foi alterado.
// v3 (2026-08-03): FIM DO SINAL. Removido o fallback `?? 300`: se
// `deposit_cents` vier null/undefined/inválido/<50, a função NÃO cria o
// PaymentIntent — devolve 400 `invalid_charge_amount` com log. Nunca se cobra
// um valor por omissão. Nenhum valor cobrado foi alterado.
// v2 (2026-07-31): guarda "Em breve" (STORE_COMING_SOON) antes do Stripe.
//
// PaymentIntent Stripe para o PAGAMENTO de uma MARCAÇÃO de barbearia, via
// cartão. Clone de create-reservation-payment-intent (v9).
// `appointments.deposit_cents` mantém o nome antigo mas guarda o valor TOTAL do
// serviço, escrito por `client_book_appointment`.
//
// Fluxo: a marcação já foi criada por `client_book_appointment` (RPC, que valida
// disponibilidade/colisão com auth.uid() do cliente). Esta função recebe o
// appointment_id, valida ownership + estado, e cria o PaymentIntent.
//
// Card-only (PaymentSheet ainda mostra Apple Pay / Google Pay como wallets de cartão).
// A confirmação client-side é feita por `client_confirm_appointment_payment` (RPC).
// verify_jwt = true.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { isProviderComingSoon } from '../_shared/coming_soon.ts';
import { secretKey } from '../_shared/keys.ts';
import { respostaConta, stripeParaNovoPagamento } from '../_shared/stripe_contas.ts';
import { type CorpoMarcacao, type Dependencias, tratar } from './logica.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const ORIGEM = 'create-appointment-payment-intent';

// Duas contas Stripe (missão stripe-empresa-2026-11-01): a conta decide-se por pagamento em
// _shared/stripe_contas.ts (marcações = NÃO TVDE; app antiga → pessoal; interruptor → empresa).

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const url = Deno.env.get('SUPABASE_URL') ?? '';
    const auth = req.headers.get('Authorization') ?? '';
    // Leitura em nome do cliente (RLS ap_select), como na v4.
    const leitura = createClient(url, secretKey() ?? '', { global: { headers: { Authorization: auth } } });
    // Chave do servidor, SEM o Authorization do cliente: escreve como service_role.
    const admin = createClient(url, secretKey() ?? '');

    const body = await req.json() as CorpoMarcacao;

    const deps: Dependencias = {
      async utilizadorDoToken(token) {
        const { data, error } = await admin.auth.getUser(token);
        return error || !data?.user ? null : { id: data.user.id };
      },
      async lerMarcacao(id) {
        const { data, error } = await leitura
          .from('appointments')
          .select('id, client_user_id, provider_id, deposit_cents, status, deposit_pi')
          .eq('id', id)
          .single();
        return error || !data ? null : data;
      },
      parceiroEmBreve: (providerId) => isProviderComingSoon(admin, providerId),
      async prepararStripe(b) {
        // Duas contas: a conta deste sinal.
        const { stripe, conta } = await stripeParaNovoPagamento(admin, { body: b, origem: ORIGEM });
        return {
          conta,
          async criarIntent(params, chave) {
            // deno-lint-ignore no-explicit-any
            const pi = await stripe.paymentIntents.create(params as any, { idempotencyKey: chave });
            // deno-lint-ignore no-explicit-any
            const cab = (pi as any).lastResponse?.headers ?? {};
            const repetido = String(cab['idempotent-replayed'] ?? cab['Idempotent-Replayed'] ?? '') === 'true';
            return { id: pi.id, client_secret: pi.client_secret, status: pi.status, repetido };
          },
          estadoIntent: async (id) => (await stripe.paymentIntents.retrieve(id)).status,
          cancelarIntent: async (id) => {
            await stripe.paymentIntents.cancel(id);
          },
        };
      },
      async gravarPi(marcacaoId, clienteId, piId, conta) {
        const { data, error } = await admin
          .from('appointments')
          .update({ deposit_pi: piId, stripe_account: conta })
          .eq('id', marcacaoId)
          .eq('client_user_id', clienteId)
          .eq('status', 'pending_payment')
          .select('id');
        if (error) return error.message;
        return (data ?? []).length === 1 ? null : `linhas gravadas: ${(data ?? []).length}`;
      },
      respostaConta: (conta) => respostaConta(conta as 'pessoal' | 'empresa'),
      async avisarEquipa(resumo, detalhes) {
        const { error } = await admin.rpc('notify_admin_urgent_push', {
          p_event_type: 'appointment_payment_not_saved',
          p_summary: resumo.slice(0, 300),
          p_entity_type: 'appointment',
          p_entity_id: detalhes.appointment_id ?? null,
          p_payload: detalhes,
          p_deep_link: '/admin/appointments',
        });
        if (error) throw new Error(error.message);
      },
      agora: () => Date.now(),
    };

    const r = await tratar(auth, body, deps);
    return new Response(JSON.stringify(r.corpo),
      { status: r.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    // O detalhe fica no log; o cliente só recebe um código genérico (revisão do Juiz 15/11 19:27).
    // Inclui erros da Stripe ao criar o PaymentIntent (a marcação fica pending_payment).
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[${ORIGEM}] error:`, msg);
    return new Response(JSON.stringify({ error: 'internal_error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
