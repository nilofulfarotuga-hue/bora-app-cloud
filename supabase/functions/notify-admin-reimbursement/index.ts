// notify-admin-reimbursement v7 — try/catch global + debug logs
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TG_TOKEN    = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
const TG_CHAT_ID  = Deno.env.get('TELEGRAM_CHAT_ID') ?? '';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

async function sendTelegram(msg: string): Promise<{ok:boolean;error?:string}> {
  if (!TG_TOKEN || !TG_CHAT_ID) return { ok: false, error: 'secrets missing' };
  try {
    const res = await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: TG_CHAT_ID, text: msg, parse_mode: 'Markdown' }),
    });
    const data = await res.json();
    if (!res.ok || !data.ok) return { ok: false, error: JSON.stringify(data) };
    return { ok: true };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  
  try {
    console.log('[notify-reimbursement] START');
    console.log('[notify-reimbursement] TG_TOKEN set:', !!TG_TOKEN);
    console.log('[notify-reimbursement] TG_CHAT_ID set:', !!TG_CHAT_ID);

    const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
    const body = await req.json().catch(() => ({}));
    const receiptId: string = body?.receipt_id ?? '';
    const orderId:   string = body?.order_id   ?? '';
    console.log('[notify-reimbursement] receipt_id:', receiptId, 'order_id:', orderId);

    if (!receiptId && !orderId) {
      return new Response(JSON.stringify({ ok: false, error: 'receipt_id or order_id required' }),
        { status: 400, headers: { ...cors, 'content-type': 'application/json' } });
    }

    // Buscar talão
    let q = sb.from('order_receipts_v2').select('*');
    if (receiptId) q = q.eq('id', receiptId);
    else q = q.eq('order_id', orderId);
    const { data: receipts, error: rErr } = await q.limit(1);
    console.log('[notify-reimbursement] receipt query error:', rErr);
    const receipt = receipts?.[0];
    if (!receipt) {
      return new Response(JSON.stringify({ ok: false, error: 'receipt not found', db_error: rErr }),
        { status: 404, headers: { ...cors, 'content-type': 'application/json' } });
    }
    console.log('[notify-reimbursement] receipt found:', receipt.id, 'order_id:', receipt.order_id);

    // Buscar pedido
    const { data: order, error: oErr } = await sb.from('orders')
      .select('id, vendor_name, payment_method, assigned_driver_id')
      .eq('id', receipt.order_id)
      .maybeSingle();
    console.log('[notify-reimbursement] order error:', oErr, 'found:', !!order);

    // Buscar driver (com cast seguro)
    let driverName = 'Desconhecido', driverPhone = '', driverIban = '';
    if (order?.assigned_driver_id) {
      try {
        const { data: driver, error: dErr } = await sb.from('drivers')
          .select('name, phone, iban')
          .eq('id', order.assigned_driver_id)
          .maybeSingle();
        console.log('[notify-reimbursement] driver error:', dErr, 'found:', !!driver);
        if (driver) {
          driverName  = driver.name  ?? 'Desconhecido';
          driverPhone = driver.phone ?? '';
          driverIban  = driver.iban  ?? '';
        }
      } catch (e) {
        console.warn('[notify-reimbursement] driver fetch failed:', e);
      }
    }

    // Signed URL da foto (best effort)
    let photoUrl = '';
    if (receipt.photo_url) {
      try {
        const { data: s1 } = await sb.storage.from('receipts').createSignedUrl(receipt.photo_url, 3600);
        if (s1?.signedUrl) photoUrl = s1.signedUrl;
      } catch (_) {}
      if (!photoUrl) {
        try {
          const { data: s2 } = await sb.storage.from('order-photos').createSignedUrl(receipt.photo_url, 3600);
          if (s2?.signedUrl) photoUrl = s2.signedUrl;
        } catch (_) {}
      }
    }
    console.log('[notify-reimbursement] photoUrl generated:', !!photoUrl);

    const valorEur = ((receipt.driver_typed_total_cents ?? receipt.reimbursement_amount_cents ?? 0) / 100).toFixed(2);
    const mercado  = order?.vendor_name ?? 'Mercado';
    const metodo   = order?.payment_method === 'mbway' ? 'MBWay' : 'Cartão';

    const msg = [
      `🛒 *REEMBOLSO PENDENTE — Bora App*`,
      ``,
      `💰 Valor: *€${valorEur}*`,
      `🏪 Mercado: ${mercado}`,
      `💳 Pagamento cliente: ${metodo}`,
      ``,
      `👤 Estafeta: *${driverName}*`,
      `📱 Telemóvel: ${driverPhone || 'Ver no admin'}`,
      `🏦 IBAN: ${driverIban || 'Sem IBAN — ver no admin'}`,
      ``,
      photoUrl ? `📸 [Ver foto do talão](${photoUrl})` : `📸 Sem foto`,
      ``,
      `👉 Envia *€${valorEur}* via MBWay para ${driverPhone || '[ver no admin]'}`,
      `Depois marca como pago em: Painel Admin → Reembolsos/Talões`,
    ].join('\n');

    console.log('[notify-reimbursement] sending Telegram...');
    const tgResult = await sendTelegram(msg);
    console.log('[notify-reimbursement] Telegram result:', JSON.stringify(tgResult));

    // Notificação no admin inbox (best effort)
    try {
      await sb.rpc('notify_admin_event', {
        p_event_type: 'reimbursement_pending',
        p_severity: 'high',
        p_summary: `Reembolso pendente €${valorEur} — ${driverName} (${mercado})`,
        p_entity_type: 'order_receipt',
        p_entity_id: receipt.id,
        p_payload: { driver_name: driverName, driver_phone: driverPhone, driver_iban: driverIban, valor_eur: valorEur, mercado, metodo_pagamento: metodo, photo_url: photoUrl, receipt_id: receipt.id },
        p_deep_link: '/admin/receipts',
      });
    } catch (e) {
      console.warn('[notify-reimbursement] notify_admin_event error:', e);
    }

    return new Response(JSON.stringify({
      ok: true,
      telegram_sent: tgResult.ok,
      telegram_error: tgResult.error ?? null,
      photo_url_generated: !!photoUrl,
      driver_name: driverName,
      valor_eur: valorEur,
    }), { headers: { ...cors, 'content-type': 'application/json' } });

  } catch (e: any) {
    console.error('[notify-reimbursement] FATAL:', e?.stack ?? e);
    return new Response(JSON.stringify({ ok: false, error: String(e?.message ?? e) }),
      { status: 500, headers: { ...cors, 'content-type': 'application/json' } });
  }
});
