// supabase/functions/payments-reconciler/index.ts — v2 (F8 MISSAO TOTAL 2026-08-16)
//
// RECONCILIADOR DE PAGAMENTOS — a "luz dos dados" pedida pelo Danilo.
// Cruza Stripe <-> banco e grava divergencias em payment_reconciliation_findings
// + alerta admin/Telegram (notify-admin-urgent kind=generic) quando ha achados
// NOVOS. READ-ONLY sobre dinheiro: NUNCA cobra, NUNCA reembolsa, NUNCA altera
// entidades — so observa, grava findings e avisa.
//
// v2: (a) o alerta reencaminha o MESMO Authorization recebido (o service key
// do runtime dava 403 no notify-admin-urgent); (b) sweep de orders sem
// updated_at (coluna nao existe -> 400 silencioso); (c) alerta falhado entra
// em `erros` com o status.
//
// Verifica:
//  A) PIs succeeded (48h) sem entidade confirmada no banco (por kind/purpose)
//  B) refunds prometidos no banco (tvde 7d + orders pending) sem refund Stripe
//  C) entidades presas a aguardar pagamento ha >1h (DB-only)
//
// Auth: verify_jwt=true + role service_role. Kill switch:
// platform_settings.payments_reconciler_enabled. Cron: run_payments_reconciler().

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const STRIPE_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const admin = createClient(SUPABASE_URL, SERVICE_KEY);

interface Finding {
  kind: string;
  severity: string;
  entity_type: string | null;
  entity_id: string | null;
  pi_id: string | null;
  amount_cents: number | null;
  details: Record<string, unknown>;
}

async function stripeGet(path: string): Promise<any> {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    headers: { Authorization: `Bearer ${STRIPE_KEY}` },
  });
  if (!res.ok) throw new Error(`stripe ${res.status} em ${path}`);
  return res.json();
}

/** Confere a entidade do PI no banco; divergencia -> push em `out`. */
async function entityConfirmed(pi: any, out: Finding[]): Promise<void> {
  const md = pi.metadata ?? {};
  const amount = Number(pi.amount_received ?? pi.amount ?? 0);
  const add = (kind: string, severity: string, entity_type: string | null, entity_id: string | null, details: Record<string, unknown>) =>
    out.push({ kind, severity, entity_type, entity_id, pi_id: pi.id, amount_cents: amount, details });

  const k = String(md.kind ?? '');
  const purpose = String(md.purpose ?? '');

  if (k === 'tvde_stop') {
    if (md.applied !== '1') add('pi_sem_entidade', 'warn', 'tvde_stop', String(md.ride_id ?? ''), { nota: 'parada paga sem applied=1' });
    return;
  }
  if (k === 'tvde_ride') {
    const rideId = String(md.ride_id ?? '');
    const { data } = await admin.from('tvde_rides').select('payment_status').eq('id', rideId).maybeSingle();
    const ok = data && ['succeeded', 'refunded', 'partial_refund', 'kept_cancel_fee'].includes(String(data.payment_status));
    if (!ok) add('pi_sem_entidade', 'critical', 'tvde_ride', rideId, { payment_status: data?.payment_status ?? 'ride_nao_encontrada' });
    return;
  }
  if (k === 'tvde_roundtrip') {
    const { data } = await admin.from('tvde_roundtrip_credits').select('id').eq('payment_intent_id', pi.id).maybeSingle();
    if (!data) add('pi_sem_entidade', 'critical', 'roundtrip_credit', String(md.ride_id ?? '') || null, { nota: 'pacote pago sem vale criado' });
    return;
  }
  if (k === 'tvde_plan') {
    const { data } = await admin.from('tvde_subscriptions').select('id').eq('stripe_payment_intent_id', pi.id).maybeSingle();
    if (!data) add('pi_sem_entidade', 'critical', 'tvde_subscription', String(md.user_id ?? ''), { plan: md.plan ?? null });
    return;
  }
  if (k === 'cleaning') {
    const bid = String(md.booking_id ?? '');
    const { data } = await admin.from('cleaning_bookings').select('payment_status').eq('id', bid).maybeSingle();
    const ok = data && String(data.payment_status) !== 'unpaid';
    if (!ok) add('pi_sem_entidade', 'critical', 'cleaning_booking', bid, { payment_status: data?.payment_status ?? 'booking_nao_encontrada' });
    return;
  }
  if (k === 'appointment' || purpose === 'appointment_deposit') {
    const aid = String(md.appointment_id ?? '');
    const { data } = await admin.from('appointments').select('status').eq('id', aid).maybeSingle();
    const ok = data && String(data.status) !== 'pending_payment';
    if (!ok) add('pi_sem_entidade', 'critical', 'appointment', aid, { status: data?.status ?? 'nao_encontrada' });
    return;
  }
  if (purpose === 'reservation_prepayment') {
    const rid = String(md.reservation_id ?? '');
    const { data } = await admin.from('reservations').select('status').eq('id', rid).maybeSingle();
    const ok = data && String(data.status) !== 'pending_payment';
    if (!ok) add('pi_sem_entidade', 'critical', 'reservation', rid, { status: data?.status ?? 'nao_encontrada' });
    return;
  }
  if (md.standalone_debt_settle === 'true') return; // settle idempotente no webhook
  if (md.draft_id) {
    const { data } = await admin.from('payment_drafts').select('used_at').eq('id', String(md.draft_id)).maybeSingle();
    const ok = data && data.used_at != null;
    if (!ok) add('pi_sem_entidade', 'critical', 'order', String(md.draft_id), { nota: 'draft pago sem pedido criado', used_at: data?.used_at ?? null });
    return;
  }
  if (md.order_id) {
    const { data } = await admin.from('orders').select('payment_status').eq('id', String(md.order_id)).maybeSingle();
    const ok = data && ['paid', 'refunded', 'refundPending', 'partial_refund'].includes(String(data.payment_status));
    if (!ok) add('pi_sem_entidade', 'critical', 'order', String(md.order_id), { payment_status: data?.payment_status ?? 'order_nao_encontrada' });
    return;
  }
  add('pi_metadata_desconhecida', 'info', null, null, { metadata: md });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  // Auth: service_role apenas (mesmo padrao do notify-admin-urgent).
  const auth = req.headers.get('Authorization') ?? '';
  try {
    const payload = JSON.parse(atob(auth.replace(/^Bearer\s+/i, '').split('.')[1]));
    if (payload.role !== 'service_role') return json({ ok: false, error: 'forbidden' }, 403);
  } catch (_) {
    return json({ ok: false, error: 'forbidden' }, 403);
  }

  // Kill switch (fail-closed: setting em falta/false = nao corre).
  const { data: ks } = await admin.from('platform_settings').select('value').eq('key', 'payments_reconciler_enabled').maybeSingle();
  const enabled = ks && (ks.value === true || String(ks.value).replace(/"/g, '') === 'true');
  if (!enabled) return json({ ok: true, skipped: 'kill_switch_off' });

  const findings: Finding[] = [];
  const errors: string[] = [];

  // ── A) PIs succeeded das ultimas 48h sem entidade confirmada ─────────────
  try {
    const since = Math.floor(Date.now() / 1000) - 48 * 3600;
    let url = `/payment_intents?limit=100&created[gte]=${since}`;
    let pages = 0;
    while (url && pages < 5) {
      const page = await stripeGet(url);
      for (const pi of page.data ?? []) {
        if (pi.status !== 'succeeded') continue;
        try { await entityConfirmed(pi, findings); } catch (e) { errors.push(`pi ${pi.id}: ${e}`); }
      }
      pages++;
      url = page.has_more && page.data?.length
        ? `/payment_intents?limit=100&created[gte]=${since}&starting_after=${page.data[page.data.length - 1].id}`
        : '';
    }
  } catch (e) { errors.push(`sweep_stripe: ${e}`); }

  // ── B) refunds prometidos sem refund na Stripe ──────────────────────────────
  try {
    const { data: rides, error } = await admin.from('tvde_rides')
      .select('id, payment_intent_id, payment_status, updated_at')
      .in('payment_status', ['refunded', 'partial_refund'])
      .gte('updated_at', new Date(Date.now() - 7 * 86400_000).toISOString())
      .not('payment_intent_id', 'is', null)
      .limit(50);
    if (error) errors.push(`sweep_refunds_q: ${error.message}`);
    for (const r of rides ?? []) {
      try {
        const refunds = await stripeGet(`/refunds?payment_intent=${r.payment_intent_id}&limit=1`);
        if (!(refunds.data ?? []).length) {
          findings.push({ kind: 'refund_prometido_sem_refund', severity: 'critical', entity_type: 'tvde_ride', entity_id: String(r.id), pi_id: String(r.payment_intent_id), amount_cents: null, details: { payment_status: r.payment_status } });
        }
      } catch (e) { errors.push(`refund ${r.id}: ${e}`); }
    }
  } catch (e) { errors.push(`sweep_refunds: ${e}`); }

  try {
    // v2: orders nao tem updated_at — filtro so por refund_status (poucas linhas).
    const { data: ords, error } = await admin.from('orders')
      .select('id, refund_status')
      .eq('refund_status', 'pending')
      .limit(50);
    if (error) errors.push(`sweep_order_refunds_q: ${error.message}`);
    for (const o of ords ?? []) {
      findings.push({ kind: 'refund_prometido_sem_refund', severity: 'warn', entity_type: 'order', entity_id: String(o.id), pi_id: null, amount_cents: null, details: { refund_status: 'pending' } });
    }
  } catch (e) { errors.push(`sweep_order_refunds: ${e}`); }

  // ── C) presos a aguardar pagamento ha >1h (DB-only) ──────────────────────────
  const hourAgo = new Date(Date.now() - 3600_000).toISOString();
  try {
    const { data: stuck, error } = await admin.from('tvde_rides')
      .select('id, payment_status, status, updated_at')
      .in('payment_status', ['processing', 'requires_action', 'requires_payment_method'])
      .lte('updated_at', hourAgo)
      .not('status', 'in', '(cancelada_cliente,cancelada_motorista,no_show,concluida)')
      .limit(50);
    if (error) errors.push(`sweep_stuck_tvde_q: ${error.message}`);
    for (const r of stuck ?? []) {
      findings.push({ kind: 'preso_aguarda_pagamento', severity: 'warn', entity_type: 'tvde_ride', entity_id: String(r.id), pi_id: null, amount_cents: null, details: { payment_status: r.payment_status, status: r.status } });
    }
  } catch (e) { errors.push(`sweep_stuck_tvde: ${e}`); }

  try {
    const { data: resv, error } = await admin.from('reservations')
      .select('id, created_at').eq('status', 'pending_payment').lte('created_at', hourAgo).limit(50);
    if (error) errors.push(`sweep_stuck_resv_q: ${error.message}`);
    for (const r of resv ?? []) {
      findings.push({ kind: 'preso_aguarda_pagamento', severity: 'warn', entity_type: 'reservation', entity_id: String(r.id), pi_id: null, amount_cents: null, details: {} });
    }
  } catch (e) { errors.push(`sweep_stuck_resv: ${e}`); }

  try {
    const { data: cln, error } = await admin.from('cleaning_bookings')
      .select('id, created_at, payment_method, status')
      .eq('payment_status', 'unpaid').neq('payment_method', 'cash')
      .lte('created_at', hourAgo)
      .not('status', 'in', '(cancelled_client,cancelled_cleaner,expired)')
      .limit(50);
    if (error) errors.push(`sweep_stuck_cleaning_q: ${error.message}`);
    for (const c of cln ?? []) {
      findings.push({ kind: 'preso_aguarda_pagamento', severity: 'warn', entity_type: 'cleaning_booking', entity_id: String(c.id), pi_id: null, amount_cents: null, details: { payment_method: c.payment_method, status: c.status } });
    }
  } catch (e) { errors.push(`sweep_stuck_cleaning: ${e}`); }

  // ── Gravar (idempotente) e contar SO os novos ────────────────────────────────
  let novos = 0;
  for (const f of findings) {
    const { data, error } = await admin.from('payment_reconciliation_findings')
      .upsert({ ...f, run_at: new Date().toISOString() }, { onConflict: 'kind,pi_id,entity_id', ignoreDuplicates: true })
      .select('id');
    if (error) { errors.push(`upsert: ${error.message}`); continue; }
    if (data && data.length > 0) novos++;
  }

  // ── Alerta admin/Telegram so quando ha achados NOVOS ─────────────────────────
  let alerted = false;
  if (novos > 0) {
    try {
      const porKind: Record<string, number> = {};
      for (const f of findings) porKind[f.kind] = (porKind[f.kind] ?? 0) + 1;
      const resumo = Object.entries(porKind).map(([k, n]) => `${k}: ${n}`).join(' · ');
      // v2: reencaminha o MESMO Authorization que passou o nosso check — a
      // mesma credencial passa o check identico do notify-admin-urgent.
      const res = await fetch(`${SUPABASE_URL}/functions/v1/notify-admin-urgent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: auth },
        body: JSON.stringify({
          kind: 'generic',
          title: `\u{1F4B0} Reconciliador: ${novos} divergencia(s) nova(s)`,
          body: `${resumo}. Ver payment_reconciliation_findings.`,
          route: '/admin',
          ref: 'payments-reconciler',
        }),
      });
      alerted = res.ok;
      if (!res.ok) errors.push(`alerta_status_${res.status}`);
    } catch (e) { errors.push(`alerta: ${e}`); }
  }

  console.log('[payments-reconciler] achados:', findings.length, 'novos:', novos, 'alerted:', alerted, 'erros:', errors.length);
  return json({ ok: true, achados: findings.length, novos, alerted, erros: errors });
});
