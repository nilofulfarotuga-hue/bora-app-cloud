// Sessão 5B-β1 B3 — Edge Fn support-password-reset
// Chamada por admin_approve_action via pg_net (service_role auth).
// Faz fire-and-forget Supabase Auth resetPasswordForEmail.
// verify_jwt: false — autenticação por service_role na header.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders } from '../_shared/cors.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method not allowed' }, 405);

  // Auth: aceita só service_role key na Authorization header
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token || token !== SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: 'service_role_required' }, 401);
  }

  let payload: { user_id?: string; email?: string };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const userId = payload.user_id;
  const email = payload.email;
  if (!userId || !email) {
    return jsonResponse({ error: 'user_id and email required' }, 400);
  }

  // Verificar que email corresponde de facto ao user_id em auth.users
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: userData, error: userErr } = await adminClient.auth.admin.getUserById(userId);
  if (userErr || !userData?.user) {
    console.error('[support-password-reset] user not found:', userErr);
    return jsonResponse({ error: 'user_not_found' }, 404);
  }
  if (userData.user.email !== email) {
    console.error('[support-password-reset] email mismatch for user_id:', userId);
    return jsonResponse({ error: 'email_mismatch' }, 403);
  }

  // Trigger Supabase Auth recovery email via anon client
  // (resetPasswordForEmail requer anon key, não service_role)
  const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { error: resetErr } = await anonClient.auth.resetPasswordForEmail(email);

  if (resetErr) {
    console.error('[support-password-reset] resetPasswordForEmail failed:', resetErr);
    return jsonResponse({ error: 'reset_failed', detail: resetErr.message }, 500);
  }

  console.log(`[support-password-reset] OK user_id=${userId}`);
  return jsonResponse({
    ok: true,
    user_id: userId,
    email_partial: email.substring(0, 3) + '***',
  });
});
