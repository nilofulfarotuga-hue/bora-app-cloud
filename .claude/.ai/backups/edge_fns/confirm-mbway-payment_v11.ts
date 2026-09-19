// BACKUP — confirm-mbway-payment v11 (Sessão 4 — A1)
// Snapshot date: 2026-05-04
// Status before delete: ACTIVE, verify_jwt=true, version=11
// Project: ojykpzwqrtusfeakzrna
// Reason for delete: obsoleto — substituído por stripe-webhook + create-mbway-payment-intent (LIVE 2026-04-24).
// Comments from Edge Fn header: "Server-trusted MBWay confirmation (temporary manual stub)."

// Server-trusted MBWay confirmation (temporary manual stub).
// Real flow will be replaced by a bank/MBWay webhook. Until then, this
// function is the ONLY authorised path to flip orders.payment_status to
// 'paid' for MBWay orders — the client is never trusted to do it.
//
// Auth: uses SUPABASE_SERVICE_ROLE_KEY so it bypasses RLS, matching the
// Stripe webhook pattern.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { orderId } = await req.json();
    if (!orderId || typeof orderId !== 'string') {
      return new Response(JSON.stringify({ error: 'orderId required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Only promote pending → paid. Never overwrite failed/refunded.
    const { data, error } = await supabase
      .from('orders')
      .update({ payment_status: 'paid' })
      .eq('id', orderId)
      .eq('payment_method', 'mbway')
      .eq('payment_status', 'pending')
      .select('id, payment_status')
      .maybeSingle();

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!data) {
      return new Response(
        JSON.stringify({ error: 'order not found or not in pending mbway state' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    return new Response(
      JSON.stringify({ ok: true, orderId: data.id, paymentStatus: data.payment_status }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
