// supabase/functions/confirm-mbway-appointment-payment/index.ts — v1
//
// Endpoint de POLLING para confirmar o sinal MBWay de uma MARCAÇÃO.
// O cliente (AppointmentMBWayWaitingDialog) chama isto a cada ~3s.
// Verifica o PaymentIntent NO STRIPE (server-side, fonte de verdade) e,
// se succeeded, confirma a marcação via RPC client_confirm_appointment_payment
// (executada com o JWT do utilizador — mesma RPC do fluxo cartão, que também
// dispara as notificações a parceiro+cliente).
//
// Respostas: { status: 'confirmed' | 'pending' | 'canceled' }
// Idempotente: marcação já confirmada → 'confirmed' imediato.
// verify_jwt = true.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import { stripeDaLinha } from '../_shared/stripe_contas.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Duas contas Stripe (missão stripe-empresa-2026-11-01): o PI lê-se na conta gravada na
// marcação (appointments.stripe_account) — _shared/stripe_contas.ts.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const auth = req.headers.get('Authorization') ?? '';
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      secretKey() ?? '',
      { global: { headers: { Authorization: auth } } },
    );

    const { data: { user }, error: userErr } = await supabase.auth.getUser();
    if (userErr || !user) return json({ error: 'auth required' }, 401);

    const body = await req.json() as { appointment_id?: string };
    if (!body.appointment_id) return json({ error: 'missing appointment_id' }, 400);

    const { data: appt, error: apptErr } = await supabase
      .from('appointments')
      .select('id, client_user_id, status, deposit_pi, stripe_account')
      .eq('id', body.appointment_id)
      .single();

    if (apptErr || !appt) return json({ error: 'appointment not found' }, 404);
    if (appt.client_user_id !== user.id) return json({ error: 'not your appointment' }, 403);

    // Idempotente: já confirmada (por um poll anterior).
    if (appt.status === 'confirmed') return json({ status: 'confirmed' });
    if (appt.status === 'cancelled') return json({ status: 'canceled' });
    if (appt.status !== 'pending_payment') {
      return json({ status: 'pending', note: 'status=' + appt.status });
    }
    if (!appt.deposit_pi) return json({ status: 'pending', note: 'no deposit_pi yet' });

    const { stripe } = stripeDaLinha(appt); // duas contas: a conta onde o sinal foi pago
    const intent = await stripe.paymentIntents.retrieve(appt.deposit_pi);

    if (intent.status === 'succeeded') {
      // Mesma RPC do fluxo cartão (auth.uid() = user — o client já leva o JWT).
      const { error: rpcErr } = await supabase.rpc('client_confirm_appointment_payment', {
        p_appointment_id: appt.id,
      });
      if (rpcErr) {
        console.error('[confirm-mbway-appointment-payment] rpc failed:', rpcErr.message);
        return json({ error: 'confirm_failed: ' + rpcErr.message }, 500);
      }
      console.log('[confirm-mbway-appointment-payment] confirmed appointment=' + appt.id);
      return json({ status: 'confirmed' });
    }

    if (intent.status === 'canceled') {
      return json({ status: 'canceled' });
    }

    // requires_action / processing / requires_payment_method → continua à espera.
    return json({ status: 'pending', stripe_status: intent.status });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[confirm-mbway-appointment-payment] error:', message);
    return json({ error: message }, 500);
  }
});
