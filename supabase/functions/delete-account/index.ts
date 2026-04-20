// supabase/functions/delete-account/index.ts
//
// GDPR account deletion (BR §20.2).
//
// Called by:
//   • Flutter client → profile_screen.dart "Apagar conta" button
//
// Behaviour:
//   1. Authenticates the caller via their JWT.
//   2. Anonymises past orders (sets user_name = 'Utilizador apagado')
//      — preserves fiscal data (order totals, Stripe references) for 10 years.
//   3. Deletes chat messages authored by the user.
//   4. Deletes unused Bora tokens belonging to the user (best-effort).
//   5. Deletes the auth.users row — cascades to public.drivers
//      via the ON DELETE CASCADE foreign key (see supabase/schema.sql §3).
//
// Never touches:
//   • orders rows (only anonymises user_name)
//   • driver_transactions / driver_balances / ledger_entries / payouts
//     / order_financials — fiscal trail kept for 10 years (BR §20.2).
//
// This function only ADDS deletion/anonymisation logic. It does not modify
// any existing table structure or business rule.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

// deno-lint-ignore no-explicit-any
const jsonResponse = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!supabaseUrl || !serviceKey || !anonKey) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  // ── Authenticate the caller ─────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) {
    return jsonResponse({ error: 'missing_token' }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (authError || !user) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  const uid = user.id;
  const admin = createClient(supabaseUrl, serviceKey);

  // ── 1. Anonymise past orders (preserve fiscal fields) ───────────────────
  try {
    await admin
      .from('orders')
      .update({ user_name: 'Utilizador apagado' })
      .eq('user_id', uid);
  } catch (e) {
    console.error('[delete-account] anonymise orders failed:', e);
  }

  // ── 2. Delete chat messages authored by this user ───────────────────────
  //     messages.sender_id is TEXT (see supabase/schema.sql §5).
  try {
    await admin.from('messages').delete().eq('sender_id', uid);
  } catch (e) {
    console.error('[delete-account] delete messages failed:', e);
  }

  // ── 3. Delete unused tokens (best-effort — table may not exist yet) ─────
  try {
    await admin.from('bora_tokens').delete().eq('user_id', uid);
  } catch (e) {
    console.warn('[delete-account] delete bora_tokens skipped:', e);
  }

  // ── 4. Delete the auth user — cascades drivers via ON DELETE CASCADE ────
  const { error: delError } = await admin.auth.admin.deleteUser(uid);
  if (delError) {
    console.error('[delete-account] auth.admin.deleteUser failed:', delError);
    return jsonResponse(
      { error: 'delete_failed', details: delError.message },
      500,
    );
  }

  return jsonResponse({ ok: true, anonymised_past_orders: true });
});
