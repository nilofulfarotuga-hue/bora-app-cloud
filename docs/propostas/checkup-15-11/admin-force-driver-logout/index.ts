// supabase/functions/admin-force-driver-logout/index.ts
//
// PROPOSTA checkup-geral-15-11 (B2.1, caixa 64 refeita): ficheiro INTEIRO para substituir o atual.
// NÃO PUBLICADO. Já NÃO precisa da função SQL admin_revogar_sessoes (P5.3 fica de fora: a ordem é
// fechar as sessões só pela API oficial do Auth, nunca por SQL). Publicar com a skill
// deploy-edge-function (mantém verify_jwt=true) e com ../_shared/cors.ts e keys.ts do mesmo commit.
//
// FASE 3 · BUG 2 · M3 — Admin force-logout for drivers.
//
// O erro de antes (15/11/2026): `admin.auth.admin.signOut(user_id, 'global')`. No supabase-js o 1.º
// argumento de signOut é o TOKEN DE ACESSO (JWT) do utilizador, não o id: o Auth recusava e as sessões
// nunca eram apagadas (admin_audit_log: sessions_revoked=false). Agora o Auth apaga-as ele próprio
// (logout global com uma sessão de uso único criada pela API de admin — ver passo 2).
//
// Behaviour:
//   1. Authenticates the caller via their JWT (anon client).
//   2. Validates `app_metadata.role = 'admin'` — same gate as the SQL RPCs
//      (see public._admin_op_guard / migration 20260428000003).
//   3. Resolves the driver by drivers.id OR user_id (must exist; otherwise 404).
//   4. Revokes ALL of the driver's auth sessions through the official Auth API (generate_link →
//      verify → logout?scope=global). No SQL on auth.*.
//      `sessions_revoked` is true ONLY when that call succeeded.
//   5. Clears `drivers.fcm_token`, sets `is_online=false`, stamps `last_forced_logout_at` /
//      `last_forced_logout_by`, deactivates his rows in driver_push_tokens and provider_push_tokens
//      (role 'driver') and mirrors offline in driver_locations (both ids). The app registers the tokens
//      again at the next login (register_push_token sets active=true).
//   6. Inserts a `driver_force_logout` row directly into `admin_audit_log`.
//      We DO NOT call `public.log_admin_action(...)` here: that RPC reads `auth.uid()` from the JWT, but
//      this function operates with the service role (no JWT), so admin_id would arrive NULL. We supply
//      admin_id / admin_email explicitly from the caller JWT we validated in step 2.
//
// LIMITE (não se resolve aqui): o token de acesso que o telemóvel já tem continua válido até expirar
// (tempo do token do projeto; por defeito 1 hora). A app já não consegue renovar a entrada (a sessão
// deixou de existir) e sai da conta nessa altura; até lá ele fica offline e sem notificações.
//
// Pattern reference: supabase/functions/delete-account/index.ts

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
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey    = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = secretKey() ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  // ── Parse body ────────────────────────────────────────────────────────────
  // driver_id: drivers.id OU user_id (15 dos 19 estafetas ativos têm os dois diferentes).
  let driverId: string | null = null;
  let reason: string = '';
  try {
    const body = await req.json();
    driverId = (body?.driver_id ?? '').toString().trim().toLowerCase();
    reason   = (body?.reason ?? '').toString().trim();
  } catch (_) {
    return jsonResponse({ error: 'invalid_body' }, 400);
  }
  if (!driverId || !UUID_RE.test(driverId)) {
    return jsonResponse({ error: 'invalid_driver_id' }, 400);
  }

  // ── Authenticate caller and check admin role ─────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: userData, error: authError } = await userClient.auth.getUser();
  const caller = userData?.user;
  if (authError || !caller) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  // app_metadata.role is the canonical admin gate (migration 20260428215258).
  // Cannot be self-set by the user — only the service role / migrations write it.
  const callerRole = (caller.app_metadata as Record<string, unknown> | null)?.role;
  if (callerRole !== 'admin') {
    return jsonResponse({ error: 'admin_required' }, 403);
  }

  const adminId    = caller.id;
  const adminEmail = caller.email ?? null;

  // ── Service-role client for the actual work ──────────────────────────────
  const admin = createClient(supabaseUrl, serviceKey);

  // ── 1. Resolve driver (drivers.id OR user_id; user_id wins) ──────────────
  // driverId already passed UUID_RE, so it is safe inside the filter string.
  const { data: rows, error: dErr } = await admin
    .from('drivers')
    .select('id, user_id, name, email, fcm_token, deleted_at, is_online')
    .or(`id.eq.${driverId},user_id.eq.${driverId}`)
    .limit(2);

  if (dErr) {
    console.error('[force-logout] driver lookup failed:', dErr);
    return jsonResponse({ error: 'lookup_failed', details: dErr.message }, 500);
  }
  const lista = (rows ?? []) as Array<Record<string, unknown>>;
  const driver = lista.find((r) => r.user_id === driverId) ?? lista[0] ?? null;
  if (!driver) {
    return jsonResponse({ error: 'driver_not_found' }, 404);
  }

  // user_id = Supabase Auth UUID (user_id manda). Falls back to drivers.id for legacy rows.
  const driverRowId  = driver.id as string;
  const driverUserId = (driver.user_id ?? driver.id) as string;
  const agora = new Date().toISOString();

  // ── 2. Revoke all auth sessions — SÓ pela API oficial do Auth (checkup 15/11, nunca SQL) ──
  // O Auth não tem rota de admin "sair de todos os aparelhos de X" e o ban não apaga sessões
  // (supabase/auth internal/models/user.go: Ban só grava banned_until). Caminho oficial:
  //   a) GET  /auth/v1/admin/users/{id}          → email do estafeta (sintético {tel}@driver.bora.app)
  //   b) POST /auth/v1/admin/generate_link        → hashed_token de um link mágico (NÃO envia email)
  //   c) POST /auth/v1/verify (type magiclink)    → sessão de uso único em nome dele
  //   d) POST /auth/v1/logout?scope=global        → o Auth apaga TODAS as sessões dele (e esta).
  let sessionsRevoked = false;
  let sessoesApagadas: number | null = null;
  let sessionsError: string | null = null;
  try {
    const { data: au, error: auErr } = await admin.auth.admin.getUserById(driverUserId);
    const emailAuth = au?.user?.email ?? null;
    if (auErr || !emailAuth) throw new Error('sem_email_auth: ' + (auErr?.message ?? 'utilizador sem email'));

    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
      type: 'magiclink',
      email: emailAuth,
    });
    const hashed = link?.properties?.hashed_token ?? null;
    if (linkErr || !hashed) throw new Error('generate_link: ' + (linkErr?.message ?? 'sem hashed_token'));

    const vr = await fetch(`${supabaseUrl}/auth/v1/verify`, {
      method: 'POST',
      headers: { apikey: anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'magiclink', token_hash: hashed }),
    });
    const sess = await vr.json().catch(() => ({}));
    const acesso = sess?.access_token ?? null;
    if (!vr.ok || !acesso) throw new Error(`verify ${vr.status}: ${sess?.msg ?? sess?.error_description ?? ''}`);
    if (sess?.user?.id && sess.user.id !== driverUserId) throw new Error('verify devolveu outro utilizador');

    const lo = await fetch(`${supabaseUrl}/auth/v1/logout?scope=global`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: `Bearer ${acesso}` },
    });
    if (lo.status !== 204 && !lo.ok) throw new Error(`logout ${lo.status}: ${(await lo.text()).slice(0, 200)}`);
    sessionsRevoked = true;
  } catch (e) {
    sessionsError = String((e as Error)?.message ?? e);
    console.error('[force-logout] revogar sessoes falhou:', sessionsError);
  }

  // ── 3. Update drivers row ────────────────────────────────────────────────
  const { error: updErr } = await admin
    .from('drivers')
    .update({
      fcm_token: null,
      is_online: false,
      last_forced_logout_at: agora,
      last_forced_logout_by: adminId,
    })
    .eq('id', driverRowId);

  if (updErr) {
    console.error('[force-logout] drivers update failed:', updErr);
    return jsonResponse({
      error: 'update_failed',
      details: updErr.message,
      sessions_revoked: sessionsRevoked,
    }, 500);
  }

  // ── 4. Push cleanup + offline mirror (non-fatal) ─────────────────────────
  let pushDesativados = 0;
  const { data: dpt, error: dptErr } = await admin
    .from('driver_push_tokens')
    .update({ active: false, updated_at: agora })
    .eq('user_id', driverUserId)
    .eq('active', true)
    .select('id');
  if (dptErr) console.error('[force-logout] driver_push_tokens cleanup failed:', dptErr);
  else pushDesativados += dpt?.length ?? 0;

  const { data: ppt, error: pptErr } = await admin
    .from('provider_push_tokens')
    .update({ active: false, updated_at: agora })
    .eq('user_id', driverUserId)
    .eq('role', 'driver')
    .eq('active', true)
    .select('id');
  if (pptErr) console.error('[force-logout] provider_push_tokens cleanup failed:', pptErr);
  else pushDesativados += ppt?.length ?? 0;

  // The drivers trigger mirrors the drivers.id row; the app mirrors the user_id row. Do both.
  const { error: locErr } = await admin
    .from('driver_locations')
    .update({ is_online: false })
    .in('driver_id', [driverRowId, driverUserId])
    .eq('is_online', true);
  if (locErr) console.error('[force-logout] driver_locations offline failed:', locErr);

  // ── 5. Audit log (direct INSERT — service role bypasses RLS) ─────────────
  const { error: auditErr } = await admin
    .from('admin_audit_log')
    .insert({
      admin_id:       adminId,
      admin_email:    adminEmail,
      action:         'driver_force_logout',
      entity_type:    'driver',
      entity_id:      driverRowId,
      entity_id_text: driverRowId,
      details: {
        user_id:                 driverUserId,
        driver_name:             driver.name,
        driver_email:            driver.email,
        had_fcm_token:           driver.fcm_token != null,
        was_online:              driver.is_online === true,
        sessions_revoked:        sessionsRevoked,
        sessoes_apagadas:        sessoesApagadas,
        sessions_error:          sessionsError,
        push_tokens_desativados: pushDesativados,
        reason:                  reason || null,
      },
    });

  if (auditErr) {
    // Audit failure is non-fatal — the action already happened.
    console.error('[force-logout] audit insert failed:', auditErr);
  }

  return jsonResponse({
    success: true,
    driver_id: driverRowId,
    user_id: driverUserId,
    driver_name: driver.name,
    sessions_revoked: sessionsRevoked,
    sessoes_apagadas: sessoesApagadas,
    sessions_error: sessionsRevoked ? null : sessionsError,
    push_tokens_desativados: pushDesativados,
    fcm_cleared: true,
    is_online: false,
    last_forced_logout_at: agora,
    aviso: sessionsRevoked
      ? 'Sessões apagadas: o app dele não consegue mais renovar a entrada. O acesso que ele já tem vale até expirar (no máximo cerca de 1 hora); até lá ele fica offline e sem notificações.'
      : 'As sessões NÃO foram apagadas (veja sessions_error): ele continua com o app logado. Offline e notificações foram desligados.',
  });
});
