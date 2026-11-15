// supabase/functions/partner-reject-reservation/index.ts
// fechar-tudo-15-11 (15/11/2026) — o PARCEIRO rejeita uma reserva e, se o cliente já tinha pago o
// pré-pagamento, a Bora devolve-o na Stripe. Espelha admin-cancel-reservation; a lógica (e o
// porquê de cada diferença) está em logica.ts, testada em logica_test.ts.
//
// Fluxo:
//  1. Token do parceiro confirmado no Auth (auth.getUser).
//  2. Reserva lida com a chave do servidor; o dono do restaurante (restaurants.user_) é
//     verificado aqui, nunca pela palavra da app.
//  3. Reserva 'pending' → RPC partner_decide_reservation(p_accept=false) com o token do parceiro
//     (muda o estado e avisa o cliente). Já 'rejected_refunded' → nova tentativa, sem repetir a RPC.
//  4. Pagamento conferido na Stripe (metadata da reserva) → stripe.refunds.create com
//     idempotencyKey reserva-recusa-<id>, na conta onde entrou (reservations.stripe_account).
//  5. admin_audit_log; se a devolução não saiu, aviso no painel (notify_admin_event).
//  6. Resposta { success, idempotent, reservation_id, new_status, refund: { result, amount_cents, amount } }.
//
// Segredos, só por Deno.env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SECRET_KEYS ou
// SUPABASE_SERVICE_ROLE_KEY (secretKey), STRIPE_SECRET_KEY e STRIPE_SECRET_KEY_EMPRESA
// (_shared/stripe_contas.ts; em modo teste, BORA_STRIPE_MODE=test e as STRIPE_TEST_*).

// @ts-nocheck: só a ligação ao supabase-js e à Stripe (como no admin-cancel-reservation); logica.ts tem tipos.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import { secretKey } from '../_shared/keys.ts';
import { stripeDaLinha } from '../_shared/stripe_contas.ts';
import { TIPO_AVISO, tratar } from './logica.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = secretKey() ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  let body = null;
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  // Token do parceiro: a RPC corre como ele (auth.uid() = parceiro), como o admin no admin-cancel.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  // Chave do servidor: ler a reserva e o restaurante, registar e avisar a equipa.
  const admin = createClient(supabaseUrl, serviceKey);

  const deps = {
    async utilizador() {
      const { data, error } = await userClient.auth.getUser(token);
      return error || !data?.user ? null : { id: data.user.id };
    },
    async lerReserva(id) {
      const { data, error } = await admin
        .from('reservations')
        .select('id, restaurant_id, status, prepayment_pi, prepayment_cents, stripe_account')
        .eq('id', id)
        .maybeSingle();
      if (error) throw new Error(`ler_reserva: ${error.message}`);
      return data ?? null;
    },
    async eDono(restaurantId, userId) {
      const { data, error } = await admin
        .from('restaurants')
        .select('id')
        .eq('id', restaurantId)
        .eq('user_', userId)
        .maybeSingle();
      if (error) throw new Error(`ler_restaurante: ${error.message}`);
      return !!data;
    },
    async rejeitarPelaRpc(id, motivo) {
      const { data, error } = await userClient.rpc('partner_decide_reservation', {
        p_reservation_id: id,
        p_accept: false,
        p_reason: motivo,
      });
      if (error) return { ok: false, mensagem: error.message ?? 'rpc_failed' };
      if (!data || data.success !== true) return { ok: false, mensagem: 'rpc_unexpected' };
      return { ok: true, status: String(data.status ?? '') };
    },
    stripe(reserva) {
      // Duas contas: o reembolso sai pela conta onde o pré-pagamento entrou.
      const { stripe, conta } = stripeDaLinha(reserva);
      return {
        conta,
        lerPagamento: (pi) => stripe.paymentIntents.retrieve(pi),
        listarDevolucoes: async (pi) =>
          (await stripe.refunds.list({ payment_intent: pi, limit: 100 })).data,
        devolver: (pi, cents, chave, metadata) =>
          stripe.refunds.create(
            { payment_intent: pi, amount: cents, metadata },
            { idempotencyKey: chave },
          ),
      };
    },
    async registar(linha) {
      const { error } = await admin.from('admin_audit_log').insert(linha);
      if (error) throw new Error(error.message);
    },
    async avisarEquipa(aviso) {
      const { error } = await admin.rpc('notify_admin_event', {
        p_event_type: TIPO_AVISO,
        p_severity: 'high',
        p_summary: aviso.resumo,
        p_entity_type: 'reservation',
        p_entity_id: aviso.reservaId,
        p_payload: aviso.detalhes,
        p_deep_link: '/admin/reservations',
      });
      if (error) throw new Error(error.message);
    },
  };

  try {
    const r = await tratar(body, deps);
    return jsonResponse(r.body, r.status);
  } catch (e) {
    console.error('[partner-reject-reservation] erro:', e);
    return jsonResponse({ error: 'internal_error' }, 500);
  }
});
