// Edge Fn support-password-reset
//
// Dispara o email de recuperação de palavra-passe para um utilizador.
//
// Dois chamadores, duas autenticações (verify_jwt=false — a guarda é feita
// aqui dentro, porque o caminho pg_net não traz JWT de utilizador nenhum):
//
//   1. `admin_approve_action` via pg_net — manda a service_role key na header.
//      Caminho original (Sessão 5B-β1 B3). Payload: { user_id, email }.
//   2. Painel admin (Flutter) — manda o JWT do Danilo. Exige
//      app_metadata.role='admin', a mesma guarda do resto do painel
//      (ver admin-payments). Payload: { user_id, email }.
//
// 2026-07-31 — acrescentado:
//   * `redirectTo` para a página web de redefinição (antes ia sem nenhum, o
//     que fazia o email apontar para o Site URL genérico do projecto);
//   * devolve `recovery_sent_at` (antes/depois) para o painel mostrar quando
//     foi o último envio;
//   * regista em `admin_audit_log` quem disparou.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
// CORS inline (em vez de ../_shared/cors.ts): esta funcao e' deployada
// isoladamente pelo MCP, que nao resolve dependencias relativas. Valores
// identicos aos de _shared/cors.ts.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ⚠️ URL CANÓNICA — tem de bater certo com lib/config/auth_links.dart e estar
// na allow-list "Redirect URLs" do Supabase Auth. Não alterar sem alterar lá.
const PASSWORD_RESET_REDIRECT =
  Deno.env.get('BORA_PASSWORD_RESET_REDIRECT') ??
  'https://bora-app-web.pages.dev/#/redefinir-palavra-passe';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'unauthorized' }, 401);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // ── Quem está a chamar ────────────────────────────────────────────────────
  let callerKind: 'service_role' | 'admin';
  let callerId: string | null = null;
  let callerEmail: string | null = null;

  if (token === SUPABASE_SERVICE_ROLE_KEY) {
    callerKind = 'service_role';
  } else {
    const { data: callerData, error: callerErr } =
      await adminClient.auth.getUser(token);
    if (callerErr || !callerData?.user) {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
    // deno-lint-ignore no-explicit-any
    const role = (callerData.user.app_metadata as any)?.role;
    if (role !== 'admin') {
      console.warn('[support-password-reset] nao-admin tentou aceder:', callerData.user.id);
      return jsonResponse({ error: 'forbidden: admin only' }, 403);
    }
    callerKind = 'admin';
    callerId = callerData.user.id;
    callerEmail = callerData.user.email ?? null;
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
  const { data: userData, error: userErr } =
    await adminClient.auth.admin.getUserById(userId);
  if (userErr || !userData?.user) {
    console.error('[support-password-reset] user not found:', userErr);
    return jsonResponse({ error: 'user_not_found' }, 404);
  }
  if (userData.user.email !== email) {
    console.error('[support-password-reset] email mismatch for user_id:', userId);
    return jsonResponse({ error: 'email_mismatch' }, 403);
  }

  // deno-lint-ignore no-explicit-any
  const previousSentAt = (userData.user as any)?.recovery_sent_at ?? null;

  // Trigger Supabase Auth recovery email via anon client
  // (resetPasswordForEmail requer anon key, não service_role)
  const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { error: resetErr } = await anonClient.auth.resetPasswordForEmail(email, {
    redirectTo: PASSWORD_RESET_REDIRECT,
  });

  if (resetErr) {
    console.error('[support-password-reset] resetPasswordForEmail failed:', resetErr);
    await logAudit(adminClient, {
      callerKind,
      callerId,
      callerEmail,
      userId,
      email,
      ok: false,
      detail: resetErr.message,
    });
    return jsonResponse({ error: 'reset_failed', detail: resetErr.message }, 500);
  }

  // Reler para devolver ao painel o instante do envio que acabou de acontecer.
  const { data: afterData } = await adminClient.auth.admin.getUserById(userId);
  // deno-lint-ignore no-explicit-any
  const recoverySentAt = (afterData?.user as any)?.recovery_sent_at ?? null;

  await logAudit(adminClient, {
    callerKind,
    callerId,
    callerEmail,
    userId,
    email,
    ok: true,
    detail: null,
  });

  console.log(`[support-password-reset] OK user_id=${userId} by=${callerKind}`);
  return jsonResponse({
    ok: true,
    user_id: userId,
    email_partial: email.substring(0, 3) + '***',
    redirect_to: PASSWORD_RESET_REDIRECT,
    previous_recovery_sent_at: previousSentAt,
    recovery_sent_at: recoverySentAt,
  });
});

// deno-lint-ignore no-explicit-any
async function logAudit(client: any, entry: {
  callerKind: string;
  callerId: string | null;
  callerEmail: string | null;
  userId: string;
  email: string;
  ok: boolean;
  detail: string | null;
}): Promise<void> {
  // A auditoria nunca pode derrubar o pedido principal, mas também não pode
  // desaparecer em silêncio — se falhar, fica no log da função.
  const { error } = await client.from('admin_audit_log').insert({
    admin_id: entry.callerId,
    admin_email: entry.callerEmail ?? entry.callerKind,
    action: 'password_reset_sent',
    entity_type: 'auth_user',
    entity_id: entry.userId,
    details: {
      target_email: entry.email,
      caller: entry.callerKind,
      ok: entry.ok,
      error: entry.detail,
    },
  });
  if (error) {
    console.error('[support-password-reset] audit log falhou:', error.message);
  }
}
