// supabase/functions/create-mbway-reservation-payment-intent/index.ts — v7
//
// MBWay payment intent para PRÉ-PAGAMENTO de RESERVA (€3 default).
// Server-confirm com billing_details.phone (mesmo padrão que orders v21).
//
// v7 (2026-11-15, conserto P0 do Juiz da Claude.ai, "Autorizo tudo" do Danilo 15:15): as
// escritas passam a ir por um cliente com a chave do servidor SEM o Authorization do cliente
// (o gatilho trg_00_reservas_campos_protegidos recusava gravar o prepayment_pi como
// `authenticated` e a v6 respondia ok:true na mesma); quem chama é identificado por
// admin.auth.getUser(token); se gravar o prepayment_pi falhar, o PaymentIntent é cancelado e a
// resposta é erro. Lógica em logica.ts. Nenhum valor cobrado foi alterado.
//
// v6 (2026-07-31): guarda "Em breve" (STORE_COMING_SOON) antes do Stripe e
// antes de inserir a reserva. Nenhum valor cobrado foi alterado.
//
// verify_jwt = true — mantém paridade com create-reservation-payment-intent.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { isRestaurantComingSoon } from '../_shared/coming_soon.ts';
import { secretKey } from '../_shared/keys.ts';
import { STRIPE_MODE, stripeParaNovoPagamento } from '../_shared/stripe_contas.ts';
import { type CorpoReservaMbway, type Dependencias, tratar } from './logica.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const ORIGEM = 'create-mbway-reservation-payment-intent';

// Duas contas Stripe (missão stripe-empresa-2026-11-01): a conta decide-se por pagamento em
// _shared/stripe_contas.ts (STRIPE_MODE vem de lá; TVDE nunca passa aqui).

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    // Chave do servidor, SEM o Authorization do cliente: escreve como service_role.
    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', secretKey() ?? '');

    const body = await req.json() as CorpoReservaMbway;

    const deps: Dependencias = {
      async utilizadorDoToken(token) {
        const { data, error } = await admin.auth.getUser(token);
        return error || !data?.user ? null : { id: data.user.id };
      },
      restauranteEmBreve: (id) => isRestaurantComingSoon(admin, id),
      async lerValorPrepagamento() {
        const { data } = await admin
          .from('platform_settings').select('value')
          .eq('key', 'reservation_prepayment_cents').maybeSingle();
        return data?.value ?? null;
      },
      async prepararStripe(b) {
        // Duas contas: a conta deste pré-pagamento (reserva de mesa = NÃO TVDE).
        const { stripe, conta } = await stripeParaNovoPagamento(admin, { body: b, origem: ORIGEM });
        return {
          conta,
          modo: STRIPE_MODE,
          // deno-lint-ignore no-explicit-any
          criarIntent: (params, chave) => stripe.paymentIntents.create(params as any, { idempotencyKey: chave }),
          cancelarIntent: async (id) => {
            await stripe.paymentIntents.cancel(id);
          },
        };
      },
      async inserirReserva(linha) {
        const { data, error } = await admin.from('reservations').insert(linha).select('id').single();
        if (error || !data) return { erro: error?.message ?? 'sem linha' };
        return { id: data.id as string };
      },
      async gravarPi(reservaId, piId) {
        const { data, error } = await admin
          .from('reservations').update({ prepayment_pi: piId }).eq('id', reservaId).select('id');
        if (error) return error.message;
        return (data ?? []).length === 1 ? null : `linhas gravadas: ${(data ?? []).length}`;
      },
      async apagarReserva(reservaId) {
        // Só a reserva que este pedido criou e que ficou sem pagamento.
        const { error } = await admin.from('reservations').delete()
          .eq('id', reservaId).eq('status', 'pending_payment').is('prepayment_pi', null);
        if (error) throw new Error(error.message);
      },
      async avisarEquipa(resumo, detalhes) {
        const { error } = await admin.rpc('notify_admin_urgent_push', {
          p_event_type: 'reservation_payment_not_saved',
          p_summary: resumo.slice(0, 300),
          p_entity_type: 'reservation',
          p_entity_id: detalhes.reservation_id ?? null,
          p_payload: detalhes,
          p_deep_link: '/admin/reservations',
        });
        if (error) throw new Error(error.message);
      },
    };

    const r = await tratar(req.headers.get('Authorization'), body, deps);
    return json(r.corpo, r.status);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[${ORIGEM}] error:`, message);
    // O detalhe fica no log; o cliente só recebe um código genérico (revisão do Juiz 15/11 19:27).
    return json({ error: 'internal_error' }, 500);
  }
});
