// =============================================================================
// stripe-connect-onboard — Stripe Connect Express, Fase 1 (2026-08-06).
// Abre (ou retoma) o onboarding Express do utilizador autenticado.
// NÃO move dinheiro: só cria a conta Connect e devolve o link.
//
// Entrada (JWT obrigatório — verify_jwt=true):
//   { role: 'partner' | 'provider' | 'driver' | 'cleaner' }
// A linha correspondente é resolvida pelo user_id do JWT — NUNCA aceita
// id vindo do cliente.
//
// Saída:
//   { url, account_id, status, kind: 'onboarding' | 'login' }
//   - conta já 'enabled' → login link do Express Dashboard (ver pagamentos)
//   - caso contrário     → Account Link de onboarding
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

// Mesmo interruptor test/live do tvde-payment.
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

// A Stripe só aceita http(s) nos Account Links — o deep link nativo
// (pt.boraapp.bora://) é recusado, por isso o retorno é sempre o web app.
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
    // 1. Utilizador do JWT (verify_jwt=true já rejeitou anónimos).
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    const user = userData?.user;
    if (userErr || !user) return json({ error: 'not_authenticated' }, 401);

    const body = await req.json().catch(() => ({}));
    const role = String(body.role ?? '') as Role;
    if (!(role in ROLE_TABLES)) {
      return json({ error: 'invalid_role (partner|provider|driver|cleaner)' }, 400);
    }
    const table = ROLE_TABLES[role];

    // 2. Linha do próprio utilizador (restaurants tem 2 colunas de dono).
    const select = 'id, name, stripe_account_id, stripe_account_status';
    let query = admin.from(table).select(select).limit(1);
    if (role === 'partner') {
      query = query.or(`user_.eq.${user.id},user_id.eq.${user.id}`);
    } else if (role === 'provider') {
      query = query.eq('user_id', user.id);
    } else {
      query = query.or(`user_id.eq.${user.id},id.eq.${user.id}`);
    }
    const { data: row, error: rowErr } = await query.maybeSingle();
    if (rowErr) return json({ error: `lookup_failed: ${rowErr.message}` }, 500);
    if (!row) return json({ error: 'row_not_found_for_user' }, 404);

    let accountId: string | null = row.stripe_account_id;

    // 3. Conta já ativa → link do Express Dashboard (ver os próprios pagamentos).
    if (accountId && row.stripe_account_status === 'enabled') {
      const login = await stripe.accounts.createLoginLink(accountId);
      return json({
        url: login.url,
        account_id: accountId,
        status: 'enabled',
        kind: 'login',
      });
    }

    // 4. Sem conta → cria a conta Connect Express (PT, EUR, transfers).
    if (!accountId) {
      const account = await stripe.accounts.create({
        type: 'express',
        country: 'PT',
        default_currency: 'eur',
        capabilities: { transfers: { requested: true } },
        // Inferido pelo papel; o dono pode corrigir no próprio onboarding.
        business_type: role === 'partner' || role === 'provider' ? 'company' : 'individual',
        metadata: {
          bora_role: role,
          bora_row_id: String(row.id),
          bora_user_id: user.id,
        },
      });
      accountId = account.id;
      const { error: updErr } = await admin
        .from(table)
        .update({ stripe_account_id: accountId, stripe_account_status: 'pending' })
        .eq('id', row.id);
      if (updErr) {
        console.error('[stripe-connect-onboard] update failed:', updErr.message);
        return json({ error: `persist_failed: ${updErr.message}` }, 500);
      }
    }

    // 5. Account Link de onboarding (retomável — a Stripe continua onde ficou).
    const link = await stripe.accountLinks.create({
      account: accountId,
      type: 'account_onboarding',
      refresh_url: `${RETURN_BASE}/connect/refresh`,
      return_url: `${RETURN_BASE}/connect/return`,
    });

    console.log('[stripe-connect-onboard]', role, row.id, '->', accountId);
    return json({
      url: link.url,
      account_id: accountId,
      status: row.stripe_account_status === 'none' || !row.stripe_account_status
        ? 'pending'
        : row.stripe_account_status,
      kind: 'onboarding',
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[stripe-connect-onboard] error:', message);
    return json({ error: message }, 500);
  }
});
