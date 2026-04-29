// supabase/functions/admin-force-driver-logout/index.ts
//
// FASE 3 · BUG 2 · M3 — Admin force-logout for drivers.
//
// Called by:
//   • Flutter admin → AdminDriverDetailScreen "Forçar logout" action.
//
// Behaviour:
//   1. Authenticates the caller via their JWT (anon client).
//   2. Validates `app_metadata.role = 'admin'` — same gate as the SQL RPCs
//      (see public._admin_op_guard / migration 20260428000003).
//   3. Resolves the driver (must exist; otherwise 404).
//   4. Revokes ALL of the driver's auth sessions globally
//      (`admin.auth.admin.signOut(user_id, 'global')`).
//   5. Clears `drivers.fcm_token`, sets `is_online=false`, and stamps
//      `last_forced_logout_at` / `last_forced_logout_by`.
//   6. Inserts a `driver_force_logout` row directly into `admin_audit_log`.
//      We DO NOT call `public.log_admin_action(...)` here: that RPC reads
//      `auth.uid()` from the JWT, but this function operates with the service
//      role (no JWT), so admin_id would arrive NULL. We supply admin_id /
//      admin_email explicitly from the caller JWT we validated in step 2.
//
// Environment:
//   - SUPABASE_URL
//   - SUPABASE_ANON_KEY                (for caller JWT verification)
//   - SUPABASE_SERVICE_ROLE_KEY        (for admin SDK calls)
//
// Pattern reference: supabase/functions/delete-account/index.ts

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.7';
import { corsHeaders } from '../_shared/cors.ts';

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
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  // ── Parse body ────────────────────────────────────────────────────────────
  let driverId: string | null = null;
  let reason: string = '';
  try {
    const body = await req.json();
    driverId = (body?.driver_id ?? '').toString().trim();
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

  // app_metadata.role is the canonical admin gate (migration 20260428215258_admin_gate_app_metadata).
  // Cannot be self-set by the user — only the service role / migrations can write to it.
  const callerRole = (caller.app_metadata as Record<string, unknown> | null)?.role;
  if (callerRole !== 'admin') {
    return jsonResponse({ error: 'admin_required' }, 403);
  }

  const adminId    = caller.id;
  const adminEmail = caller.email ?? null;

  // ── Service-role client for the actual work ──────────────────────────────
  const admin = createClient(supabaseUrl, serviceKey);

  // ── 1. Resolve driver ────────────────────────────────────────────────────
  const { data: driver, error: dErr } = await admin
    .from('drivers')
    .select('id, user_id, name, email, fcm_token, deleted_at')
    .eq('id', driverId)
    .maybeSingle();

  if (dErr) {
    console.error('[force-logout] driver lookup failed:', dErr);
    return jsonResponse({ error: 'lookup_failed', details: dErr.message }, 500);
  }
  if (!driver) {
    return jsonResponse({ error: 'driver_not_found' }, 404);
  }

  // user_id is the Supabase Auth UUID (added by migration 20260415060317).
  // Falls back to drivers.id for legacy rows where user_id is still NULL.
  const driverUserId = (driver.user_id ?? driver.id) as string;

  // ── 2. Revoke all auth sessions (global scope) ───────────────────────────
  let sessionsRevoked = false;
  try {
    const { error: signOutErr } = await admin.auth.admin.signOut(driverUserId, 'global');
    if (signOutErr) {
      console.error('[force-logout] signOut failed:', signOutErr);
    } else {
      sessionsRevoked = true;
    }
  } catch (e) {
    console.error('[force-logout] signOut threw:', e);
  }

  // ── 3. Update drivers row (FCM clear + audit columns + offline) ──────────
  const { error: updErr } = await admin
    .from('drivers')
    .update({
      fcm_token: null,
      is_online: false,
      last_forced_logout_at: new Date().toISOString(),
      last_forced_logout_by: adminId,
    })
    .eq('id', driverId);

  if (updErr) {
    console.error('[force-logout] drivers update failed:', updErr);
    return jsonResponse({ error: 'update_failed', details: updErr.message }, 500);
  }

  // ── 4. Audit log (direct INSERT — service role bypasses RLS) ─────────────
  // We pass admin_id/admin_email explicitly because log_admin_action() reads
  // auth.uid()/auth.jwt() which are NULL under the service role.
  const { error: auditErr } = await admin
    .from('admin_audit_log')
    .insert({
      admin_id:    adminId,
      admin_email: adminEmail,
      action:      'driver_force_logout',
      entity_type: 'driver',
      entity_id:   driverId,
      details: {
        driver_name:  driver.name,
        driver_email: driver.email,
        had_fcm_token: driver.fcm_token != null,
        sessions_revoked: sessionsRevoked,
        reason: reason || null,
      },
    });

  if (auditErr) {
    // Audit failure is non-fatal — the action already happened.
    console.error('[force-logout] audit insert failed:', auditErr);
  }

  return jsonResponse({
    success: true,
    driver_id: driverId,
    driver_name: driver.name,
    sessions_revoked: sessionsRevoked,
    fcm_cleared: true,
    last_forced_logout_at: new Date().toISOString(),
  });
});
