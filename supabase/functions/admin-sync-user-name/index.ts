// supabase/functions/admin-sync-user-name/index.ts
//
// manha-15-11 bloco B1 (ordem do Danilo 15/11/2026 08:50): o nome do cliente
// só muda pelo suporte. Quando o admin aprova um ACCOUNT_UPDATE ou edita o nome
// no painel, só `public.users.name` mudava; a app e o painel (admin_list_clients)
// mostram `user_metadata.bora_name` do login, que ficava antigo (caso de 15/11).
//
// Esta função copia o nome de `public.users` para `user_metadata.bora_name`
// (auth.admin.updateUserById, nunca SQL no auth). Só admins
// (app_metadata.role = 'admin', o mesmo portão do _admin_op_guard).
// Não recebe o nome do chamador: lê-o da base, a fonte da verdade.

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import { corsHeaders } from '../_shared/cors.ts';
import { secretKey } from '../_shared/keys.ts';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method_not_allowed' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = secretKey() ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) return jsonResponse({ error: 'server_misconfigured' }, 500);

  // user_id direto (editar contacto) OU action_id de um ACCOUNT_UPDATE aprovado
  // (support_pending_actions não chega ao painel com o user_id).
  let userId = '';
  let actionId = '';
  try {
    const body = await req.json();
    userId = (body?.user_id ?? '').toString().trim();
    actionId = (body?.action_id ?? '').toString().trim();
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }
  if (!UUID_RE.test(userId) && !UUID_RE.test(actionId)) {
    return jsonResponse({ error: 'invalid_user_id' }, 400);
  }

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const caller = userData?.user;
  if (authError || !caller) return jsonResponse({ error: 'unauthorized' }, 401);
  if (caller.app_metadata?.role !== 'admin') return jsonResponse({ error: 'admin_required' }, 403);

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  if (!UUID_RE.test(userId)) {
    const { data: acao, error: acaoErr } = await admin
      .from('support_pending_actions').select('user_id, action_type, status')
      .eq('id', actionId).maybeSingle();
    if (acaoErr || !acao) return jsonResponse({ error: 'action_not_found' }, 404);
    if (acao.action_type !== 'ACCOUNT_UPDATE') return jsonResponse({ error: 'not_account_update' }, 400);
    userId = (acao.user_id ?? '').toString();
    if (!UUID_RE.test(userId)) return jsonResponse({ error: 'action_without_user' }, 404);
  }

  const { data: row, error: rowErr } = await admin
    .from('users').select('name').eq('id', userId).maybeSingle();
  if (rowErr) return jsonResponse({ error: 'read_failed', details: rowErr.message }, 500);
  const nome = (row?.name ?? '').toString().trim();
  if (!row || nome.length < 2) return jsonResponse({ error: 'name_not_found' }, 404);

  const { data: alvo, error: getErr } = await admin.auth.admin.getUserById(userId);
  if (getErr || !alvo?.user) return jsonResponse({ error: 'auth_user_not_found' }, 404);
  const antes = (alvo.user.user_metadata?.bora_name ?? '').toString();
  if (antes === nome) return jsonResponse({ ok: true, unchanged: true, name: nome });

  const { error: updErr } = await admin.auth.admin.updateUserById(userId, {
    user_metadata: { ...(alvo.user.user_metadata ?? {}), bora_name: nome },
  });
  if (updErr) return jsonResponse({ error: 'auth_update_failed', details: updErr.message }, 500);

  // Auditoria com quem fez (o service role não tem auth.uid()).
  await admin.from('admin_audit_log').insert({
    admin_id: caller.id,
    admin_email: caller.email ?? null,
    action: 'sync_user_name_auth',
    entity_type: 'user',
    entity_id: userId,
    details: { antes, depois: nome },
  }).then(({ error }) => { if (error) console.error('[admin-sync-user-name] audit failed:', error.message); });

  return jsonResponse({ ok: true, name: nome, before: antes });
});
