// Sessão 5A-1 B10 — Edge Fn support-submit-ticket
// Tracking only (DB). Outbound email/WhatsApp em 5B (Resend/SMTP).
// verify_jwt: true. POST { channel, subject, body, order_id? }.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders } from '../_shared/cors.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const ALLOWED_CHANNELS = new Set(['whatsapp', 'email']);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return jsonResponse({ error: 'no jwt' }, 401);
  const userJwt = authHeader.replace('Bearer ', '');

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: 'invalid jwt' }, 401);
  const userId = userData.user.id;
  const userRole = (userData.user.user_metadata?.bora_role as string | undefined) ?? 'client';

  let payload: { channel?: string; subject?: string; body?: string; order_id?: string };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid json' }, 400);
  }

  const channel = (payload.channel ?? '').trim().toLowerCase();
  if (!ALLOWED_CHANNELS.has(channel)) {
    return jsonResponse({
      error: 'channel must be whatsapp or email (chatbot is created via support-chatbot only)',
    }, 400);
  }

  const subject = (payload.subject ?? '').trim();
  const body = (payload.body ?? '').trim();
  if (subject.length < 1 || subject.length > 200) {
    return jsonResponse({ error: 'subject must be 1..200 chars' }, 400);
  }
  if (body.length < 1 || body.length > 5000) {
    return jsonResponse({ error: 'body must be 1..5000 chars' }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Validate order ownership if provided
  if (payload.order_id) {
    const { data: ord } = await adminClient
      .from('orders').select('user_id').eq('id', payload.order_id).maybeSingle();
    if (!ord || ord.user_id !== userId) {
      return jsonResponse({ error: 'order not found or not owner' }, 404);
    }
  }

  // INSERT — preserve question NOT NULL legacy by replicating subject+body.
  const questionLegacy = subject || body.slice(0, 500);

  const { data: tk, error: insErr } = await adminClient.from('support_tickets').insert({
    user_id: userId,
    user_role: userRole,
    channel,
    subject,
    body,
    question: questionLegacy,
    order_id: payload.order_id ?? null,
    status: 'open',
  }).select('id').single();

  if (insErr || !tk) {
    return jsonResponse({ error: insErr?.message ?? 'insert fail' }, 500);
  }

  const { data: settingsRow } = await adminClient
    .from('support_settings').select('sla_hours').eq('id', 1).single();
  const slaHours = (settingsRow?.sla_hours as number | undefined) ?? 24;

  return jsonResponse({ ticket_id: tk.id, sla_hours: slaHours });
});
