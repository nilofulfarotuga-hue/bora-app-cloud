// =============================================================================
// stripe-connect-admin — ações do painel "Pagamentos Connect" (2026-08-06).
// Só admin (is_admin() no Postgres). verify_jwt=true.
//
// body.action:
//   onboard_link { role, row_id } → (re)gera Account Link de onboarding
//   login_link   { role, row_id } → link do Express Dashboard da conta
//   resync       { role, row_id } → accounts.retrieve + reescreve o espelho
//   disconnect   { role, row_id } → volta a acerto manual (status 'disabled')
//
// Todas as ações ficam em admin_audit_log.
// =============================================================================

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const STRIPE_MODE = (Deno.env.get('BORA_STRIPE_MODE') ?? 'live').toLowerCase();
const stripeSecretKey =
  STRIPE_MODE === 'test'
    ? (Deno.env.get('STRIPE_TEST_SECRET_KEY') ?? '')
    : (Deno.env.get('STRIPE_SECRET_KEY') ?? '');
const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const admin = createClient(SUPABASE_URL, SERVICE_KEY);

const RETURN_BASE = 'https://bora-app-web.pages.dev';

type Role = 'partner' | 'provider' | 'driver' | 'cleaner';
const ROLE_TABLES: Record<Role, string> = {
  partner: 'restaurants',
  provider: 'service_providers',
  driver: 'drivers',
  cleaner: 'cleaners',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    // 1. Só admin.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'not_authenticated' }, 401);
    const { data: isAdmin, error: adminErr } = await userClient.rpc('is_admin');
    if (adminErr || isAdmin !== true) return json({ error: 'forbidden' }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');
    const role = String(body.role ?? '') as Role;
    const rowId = String(body.row_id ?? '');
    if (!(role in ROLE_TABLES) || !rowId) {
      return json({ error: 'role e row_id obrigatórios' }, 400);
    }
    const table = ROLE_TABLES[role];

    const { data: row, error: rowErr } = await admin
      .from(table)
      .select('id, name, stripe_account_id, stripe_account_status')
      .eq('id', rowId)
      .maybeSingle();
    if (rowErr) return json({ error: rowErr.message }, 500);
    if (!row) return json({ error: 'row_not_found' }, 404);

    const audit = async (details: Record<string, unknown>) => {
      await admin.from('admin_audit_log').insert({
        admin_id: user.id,
        admin_email: user.email,
        action: `stripe_connect_${action}`,
        entity_type: role,
        entity_id_text: rowId,
        details,
      });
    };

    switch (action) {
      case 'onboard_link': {
        let accountId: string | null = row.stripe_account_id;
        if (!accountId) {
          const account = await stripe.accounts.create({
            type: 'express',
            country: 'PT',
            default_currency: 'eur',
            capabilities: { transfers: { requested: true } },
            metadata: { bora_role: role, bora_row_id: String(row.id), bora_admin: 'true' },
          });
          accountId = account.id;
          await admin.from(table)
            .update({ stripe_account_id: accountId, stripe_account_status: 'pending' })
            .eq('id', row.id);
        }
        const link = await stripe.accountLinks.create({
          account: accountId,
          type: 'account_onboarding',
          refresh_url: `${RETURN_BASE}/connect/refresh`,
          return_url: `${RETURN_BASE}/connect/return`,
        });
        await audit({ account_id: accountId });
        return json({ url: link.url, account_id: accountId });
      }

      case 'login_link': {
        if (!row.stripe_account_id) return json({ error: 'sem_conta_connect' }, 400);
        const login = await stripe.accounts.createLoginLink(row.stripe_account_id);
        await audit({ account_id: row.stripe_account_id });
        return json({ url: login.url });
      }

      case 'resync': {
        if (!row.stripe_account_id) return json({ error: 'sem_conta_connect' }, 400);
        const acct = await stripe.accounts.retrieve(row.stripe_account_id);
        const { data, error } = await admin.rpc('apply_stripe_account_update', {
          p_account_id: acct.id,
          p_charges_enabled: acct.charges_enabled ?? false,
          p_payouts_enabled: acct.payouts_enabled ?? false,
          p_currently_due: acct.requirements?.currently_due ?? [],
          p_disabled_reason: acct.requirements?.disabled_reason ?? null,
        });
        if (error) return json({ error: error.message }, 500);
        await audit({ account_id: acct.id, result: data });
        return json({ ok: true, result: data });
      }

      case 'disconnect': {
        // Fase 1: não há transferências automáticas — "desligar" = marcar
        // disabled no espelho; o acerto volta a ser 100% manual.
        const { error } = await admin.from(table)
          .update({
            stripe_account_status: 'disabled',
            stripe_charges_enabled: false,
            stripe_payouts_enabled: false,
            stripe_requirements: { disabled_reason: 'disconnected_by_admin' },
          })
          .eq('id', row.id);
        if (error) return json({ error: error.message }, 500);
        await audit({ account_id: row.stripe_account_id, note: 'volta a acerto manual' });
        return json({ ok: true });
      }

      default:
        return json({ error: 'action inválida (onboard_link|login_link|resync|disconnect)' }, 400);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[stripe-connect-admin] error:', message);
    return json({ error: message }, 500);
  }
});
