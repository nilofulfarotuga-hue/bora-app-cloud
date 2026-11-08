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

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';
import {
  garantirContaConnect,
  linkConnect,
  TABELAS_CONNECT,
  type PapelConnect,
} from '../_shared/connect_conta.ts';

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

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = secretKey() ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const admin = createClient(SUPABASE_URL, SERVICE_KEY);

// Chaves Stripe (pessoal/empresa, live/test) e retorno http(s): ver _shared/connect_conta.ts.
type Role = PapelConnect;
const ROLE_TABLES = TABELAS_CONNECT;

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
    //    select('*') para ler stripe_account_owner quando a migração M7 já estiver aplicada.
    let query = admin.from(table).select('*').limit(1);
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

    // 3. Conta na plataforma certa (M7: pessoal ou empresa, pelo interruptor
    //    stripe_connect_conta_nova). Cria se faltar; troca de plataforma se for preciso.
    const { stripe, conta, accountId, criada } = await garantirContaConnect(admin, role, row, {
      bora_user_id: user.id,
    });
    const ativa = !criada && row.stripe_account_status === 'enabled';

    // 4. Ativa → painel Express (ver os próprios pagamentos); senão → link de cadastro.
    const link = await linkConnect(stripe, accountId, ativa);

    console.log('[stripe-connect-onboard]', role, row.id, '->', accountId, 'plataforma:', conta);
    return json({
      url: link.url,
      account_id: accountId,
      status: ativa
        ? 'enabled'
        : (criada || !row.stripe_account_status || row.stripe_account_status === 'none'
          ? 'pending'
          : row.stripe_account_status),
      kind: link.kind,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[stripe-connect-onboard] error:', message);
    return json({ error: message }, 500);
  }
});
