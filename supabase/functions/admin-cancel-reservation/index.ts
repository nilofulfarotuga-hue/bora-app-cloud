// supabase/functions/admin-cancel-reservation/index.ts
// Sessao 5B-beta2a B0.2 — Admin reservation cancellation orchestrator (espelha admin-cancel-order).
// v22 PROPOSTA (fechar-tudo-15-11, 15/11/2026): o valor e o pagamento da devolução passam a vir da
// Stripe (como em partner-reject-reservation) e uma nova chamada sobre uma reserva já
// 'cancelled_refunded' devolve o que ainda faltar. A lógica (e o porquê de cada mudança face à v21)
// está em logica.ts, testada em logica_test.ts.
//
// Fluxo:
//  1. Corpo { reservation_id, reason } (400 invalid_body / invalid_reservation_id).
//  2. Token confirmado no Auth (auth.getUser); só app_metadata.role='admin' (403 admin_required).
//  3. RPC admin_cancel_reservation_on_behalf_of com o token do admin: muda o estado, avisa o
//     cliente (in-app) e regista a ação. Já cancelada → idempotent=true.
//  4. Com direito a devolução (>= janela, ou nova tentativa de uma 'cancelled_refunded'): reserva lida
//     com a chave do servidor → PaymentIntent conferido na Stripe (metadata desta reserva,
//     succeeded) → refunds.create do que falta, idempotencyKey admin-cancel-rsv-<id>-<n> (n =
//     devoluções que a Stripe já lista para o pagamento: uma chave por tentativa, ver logica.ts),
//     na conta onde entrou (reservations.stripe_account, _shared/stripe_contas.ts).
//  5. admin_audit_log 'reservation_cancel_complete'; se a devolução não saiu, aviso urgente à
//     equipa (notify_admin_urgent_push 'reservation_refund_failed': linha no painel + push).
//  6. Resposta como na v21: { success, idempotent, reservation_id, new_status | previous_status,
//     message?, refund: { result, stripe_id, amount, error, amount_cents, reason, stripe_status } }.
//
// Segredos, só por Deno.env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SECRET_KEYS ou
// SUPABASE_SERVICE_ROLE_KEY (secretKey), STRIPE_SECRET_KEY e STRIPE_SECRET_KEY_EMPRESA
// (_shared/stripe_contas.ts; em modo teste, BORA_STRIPE_MODE=test e as STRIPE_TEST_*).

// @ts-nocheck: só a ligação ao supabase-js e à Stripe (como na v21); logica.ts tem tipos.
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

  // Token do admin: a RPC corre como ele (auth.uid() = admin; is_admin() confere de novo).
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  // Chave do servidor: ler a reserva, registar e avisar a equipa.
  const admin = createClient(supabaseUrl, serviceKey);

  const deps = {
    async utilizador() {
      const { data, error } = await userClient.auth.getUser(token);
      const u = data?.user;
      if (error || !u) return null;
      return { id: u.id, email: u.email ?? null, papel: u.app_metadata?.role ?? null };
    },
    async cancelarPelaRpc(id, motivo) {
      const { data, error } = await userClient.rpc('admin_cancel_reservation_on_behalf_of', {
        p_reservation_id: id,
        p_reason: motivo,
      });
      if (error) return { ok: false, mensagem: error.message ?? 'rpc_failed' };
      return { ok: true, dados: data ?? null };
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
      // notify_admin_urgent_push(p_event_type, p_summary, p_entity_type, p_entity_id, p_payload,
      // p_deep_link) — lida no servidor a 15/11: grava a linha pelo notify_admin_event (sempre
      // 'high') e manda o push urgente (notify-admin-urgent, agrupado por payload.push_ref).
      const { error } = await admin.rpc('notify_admin_urgent_push', {
        p_event_type: TIPO_AVISO,
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
    const r = await tratar(body, token, deps);
    return jsonResponse(r.body, r.status);
  } catch (e) {
    console.error('[admin-cancel-reservation] erro:', e);
    return jsonResponse({ error: 'internal_error' }, 500);
  }
});
