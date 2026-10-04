// execute-broadcast v8 — 2026-10-04 (missão de correção, agente admin-geral).
// Parte da v7 que estava no ar (ronda-fecho D3: comunicação comercial só a quem
// deu opt-in separado — push_broadcasts.only_marketing_opt_in -> users.marketing_opt_in).
//
// O que muda na v8 (provado em produção a 04/10):
//  1. A v7 gravava status 'completed', que o CHECK de push_broadcasts não aceita
//     (pending/sending/sent/failed) — o update falhava calado e a linha ficava
//     presa em 'sending' para sempre (as 3 de 21/05). Agora: 'sent' ou 'failed',
//     com status_note a explicar em português.
//  2. Só pega no que já venceu (scheduled_at <= agora). Sem isto, a tarefa agendada
//     mandava logo as notificações agendadas para amanhã.
//  3. Reserva atómica: só envia quem conseguir passar a linha de 'pending' a
//     'sending' (a tarefa agendada e o painel podem chamar ao mesmo tempo).
//  4. target_user_ids: quando o painel escolhe um segmento ("Clientes activos 30d",
//     "Drivers online"), o push vai só a essas pessoas — antes ia ao segmento inteiro.
//  5. O mesmo aparelho (token) só recebe uma vez, mesmo que esteja em duas tabelas.
// Chamada por: tarefa agendada `execute-broadcast-queue` (public.broadcasts_processar_fila)
// e pelo painel admin logo depois de criar um envio. verify_jwt=false (como a v7).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FB_PROJECT = Deno.env.get('FIREBASE_PROJECT_ID')!;
const FB_SA = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!;
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...cors, 'content-type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });
  const body = await req.json().catch(() => ({}));
  const broadcastId: string | null = body?.broadcast_id ?? null;
  const agora = new Date().toISOString();

  let query = sb.from('push_broadcasts').select('*').eq('status', 'pending').lte('scheduled_at', agora)
    .order('scheduled_at', { ascending: true }).limit(20);
  if (broadcastId) query = query.eq('id', broadcastId);
  const { data: broadcasts, error: bErr } = await query;
  if (bErr) return json({ ok: false, error: bErr.message }, 500);
  if (!broadcasts?.length) return json({ ok: true, message: 'no pending broadcasts' });

  let accessToken: string;
  try { accessToken = await getFirebaseToken(JSON.parse(FB_SA)); }
  catch (e) { return json({ ok: false, error: `firebase auth: ${e}` }, 500); }

  const results = [];
  for (const broadcast of broadcasts) {
    // Reserva atómica: se outra chamada já a apanhou, salta.
    const { data: claimed, error: cErr } = await sb.from('push_broadcasts')
      .update({ status: 'sending', claimed_at: new Date().toISOString() })
      .eq('id', broadcast.id).eq('status', 'pending').select('id');
    if (cErr || !claimed?.length) {
      results.push({ broadcast_id: broadcast.id, skipped: true, reason: cErr?.message ?? 'já reservada' });
      continue;
    }

    try {
      const onlyOptIn = broadcast.only_marketing_opt_in === true;
      const alvos: string[] | null = Array.isArray(broadcast.target_user_ids) ? broadcast.target_user_ids : null;
      const tokens = await getTokens(sb, broadcast.segment, onlyOptIn, alvos);
      console.log(`[execute-broadcast] id=${broadcast.id} segment=${broadcast.segment} only_opt_in=${onlyOptIn} alvos=${alvos?.length ?? 'segmento'} tokens=${tokens.length}`);

      if (tokens.length === 0) {
        await finish(sb, broadcast.id, 'sent', 0, 0,
          'Nenhum telemóvel registado para push neste grupo (o aviso no sininho, quando existe, já foi entregue).');
        results.push({ broadcast_id: broadcast.id, sent: 0, failed: 0 });
        continue;
      }

      let sent = 0, failed = 0;
      const BATCH = 50;
      for (let i = 0; i < tokens.length; i += BATCH) {
        const batch = tokens.slice(i, i + BATCH);
        const res = await Promise.allSettled(batch.map((t) =>
          sendFcm(accessToken, t, broadcast.title, broadcast.body, broadcast.segment)));
        for (const r of res) { if (r.status === 'fulfilled' && r.value.ok) sent++; else failed++; }
      }
      const estado = sent === 0 && failed > 0 ? 'failed' : 'sent';
      const nota = estado === 'failed'
        ? `Nenhum aparelho aceitou o push (${failed} recusaram — tokens antigos ou app desinstalada).`
        : `Entregue a ${sent} aparelho(s)` + (failed ? `; ${failed} recusaram (tokens antigos).` : '.');
      await finish(sb, broadcast.id, estado, sent, failed, nota);
      console.log(`[execute-broadcast] done id=${broadcast.id} sent=${sent} failed=${failed}`);
      results.push({ broadcast_id: broadcast.id, sent, failed });
    } catch (e) {
      console.error(`[execute-broadcast] erro id=${broadcast.id}: ${e}`);
      await finish(sb, broadcast.id, 'failed', 0, 0, `Erro no envio: ${String(e).slice(0, 180)}`);
      results.push({ broadcast_id: broadcast.id, error: String(e) });
    }
  }
  return json({ ok: true, results });
});

async function finish(sb: any, id: string, status: 'sent' | 'failed', sent: number, failed: number, nota: string) {
  const { error } = await sb.from('push_broadcasts').update({
    status, sent_count: sent, failed_count: failed, completed_at: new Date().toISOString(), status_note: nota,
  }).eq('id', id);
  if (error) console.error(`[execute-broadcast] não gravou o estado final id=${id}: ${error.message}`);
}

// D3 (2026-09-23): com onlyOptIn só entram aparelhos de utilizadores com
// users.marketing_opt_in = true (parceiros pelo dono da loja: restaurants.user_id).
// v8: com `alvos` (target_user_ids) só entram essas pessoas.
async function getTokens(sb: any, segment: string, onlyOptIn: boolean, alvos: string[] | null): Promise<string[]> {
  let optIn: Set<string> | null = null;
  if (onlyOptIn) {
    const { data } = await sb.from('users').select('id').eq('marketing_opt_in', true);
    optIn = new Set((data ?? []).map((u: any) => String(u.id)));
  }
  const alvoSet = alvos ? new Set(alvos.map(String)) : null;
  const aceita = (uid: unknown) => {
    const k = String(uid);
    if (onlyOptIn && !optIn!.has(k)) return false;
    if (alvoSet && !alvoSet.has(k)) return false;
    return true;
  };
  const porUser = async (tabela: string) => {
    const { data } = await sb.from(tabela).select('fcm_token,user_id').eq('active', true);
    return (data ?? []).filter((r: any) => aceita(r.user_id)).map((r: any) => String(r.fcm_token));
  };
  const clients = () => porUser('client_push_tokens');
  const drivers = () => porUser('driver_push_tokens');
  const partners = async () => {
    const { data } = await sb.from('partner_push_tokens').select('fcm_token,partner_id').eq('active', true);
    if (!onlyOptIn && !alvoSet) return (data ?? []).map((t: any) => String(t.fcm_token));
    const { data: rs } = await sb.from('restaurants').select('id,user_id').not('user_id', 'is', null);
    const ok = new Set((rs ?? []).filter((r: any) => aceita(r.user_id)).map((r: any) => String(r.id)));
    return (data ?? []).filter((t: any) => ok.has(String(t.partner_id))).map((t: any) => String(t.fcm_token));
  };
  let lista: string[] = [];
  if (segment === 'all') {
    const [c, d, p] = await Promise.all([clients(), drivers(), partners()]);
    lista = [...c, ...d, ...p];
  } else if (segment === 'clients') lista = await clients();
  else if (segment === 'drivers') lista = await drivers();
  else if (segment === 'partners') lista = await partners();
  // o mesmo aparelho só recebe uma vez
  return [...new Set(lista.filter((t) => t && t !== 'null'))];
}

async function sendFcm(accessToken: string, fcmToken: string, title: string, body: string, segment: string): Promise<{ ok: boolean }> {
  const url = `https://fcm.googleapis.com/v1/projects/${FB_PROJECT}/messages:send`;
  const msg = { message: { token: fcmToken, notification: { title, body }, data: { type: 'admin_broadcast', segment }, android: { priority: 'high', notification: { channel_id: 'bora_general', sound: 'default' } }, apns: { headers: { 'apns-priority': '10' }, payload: { aps: { sound: 'default' } } } } };
  try {
    const res = await fetch(url, { method: 'POST', headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(msg) });
    if (!res.ok) { const t = await res.text(); console.error(`[execute-broadcast] FCM error ${res.status}: ${t.slice(0, 200)}`); }
    return { ok: res.ok };
  } catch { return { ok: false }; }
}

async function getFirebaseToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const b64u = (s: string) => btoa(unescape(encodeURIComponent(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  const b64uB = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  const sigIn = `${b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64u(JSON.stringify({ iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', exp: now + 3600, iat: now }))}`;
  const kb = Uint8Array.from(atob(sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', kb, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = b64uB(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(sigIn))));
  const res = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${sigIn}.${sig}` }) });
  const data = await res.json();
  if (!data.access_token) throw new Error(JSON.stringify(data));
  return data.access_token;
}
