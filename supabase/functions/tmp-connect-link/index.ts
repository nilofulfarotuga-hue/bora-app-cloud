// tmp-connect-link — convite de cadastro Stripe Connect.
//
// GET  ?a=<acct_...>&k=<chave>  -> gera Account Link FRESCO e redireciona (302).
//      A chave e derivada de SHA-256(account_id|SEGREDO); sem ela devolve 403.
//      Serve para enviar ao parceiro por mensagem: o link da Stripe dura 5 min,
//      este nao, porque e gerado no momento do clique.
// POST { secret, account_id, update?, external_account? }
//      -> pre-preenche a conta (accounts.update / external_account) e devolve
//         o link imediato + a chave do convite.

import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';

const SECRET = 'bora-cnt-9f3a71c4e58b';
const RETURN_BASE = 'https://bora-app-web.pages.dev';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });

async function keyFor(accountId: string): Promise<string> {
  const data = new TextEncoder().encode(accountId + '|' + SECRET);
  const buf = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, 16);
}

async function makeLink(accountId: string) {
  return await stripe.accountLinks.create({
    account: accountId,
    type: 'account_onboarding',
    refresh_url: `${RETURN_BASE}/connect/refresh`,
    return_url: `${RETURN_BASE}/connect/return`,
  });
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const a = url.searchParams.get('a') ?? '';
    const k = url.searchParams.get('k') ?? '';
    if (!a.startsWith('acct_') || k !== (await keyFor(a))) {
      return new Response('Link invalido ou expirado. Pede um novo ao Bora.', { status: 403 });
    }
    try {
      const link = await makeLink(a);
      return new Response(null, { status: 302, headers: { Location: link.url } });
    } catch (err) {
      return new Response('Erro a abrir o cadastro: ' + String(err), { status: 500 });
    }
  }

  const body = await req.json().catch(() => ({}));
  if (String(body.secret ?? '') !== SECRET) return json({ error: 'forbidden' }, 403);
  const accountId = String(body.account_id ?? '');
  if (!accountId.startsWith('acct_')) return json({ error: 'account_id invalido' }, 400);

  const done: string[] = [];
  const falhou: string[] = [];
  try {
    if (body.update) {
      try {
        await stripe.accounts.update(accountId, body.update);
        done.push('update');
      } catch (e) {
        falhou.push('update: ' + (e instanceof Error ? e.message : String(e)));
      }
    }
    if (body.external_account) {
      try {
        await stripe.accounts.createExternalAccount(accountId, {
          external_account: body.external_account,
        });
        done.push('iban');
      } catch (e) {
        falhou.push('iban: ' + (e instanceof Error ? e.message : String(e)));
      }
    }
    const link = await makeLink(accountId);
    return json({
      url: link.url,
      expires_at: link.expires_at,
      convite_key: await keyFor(accountId),
      account_id: accountId,
      done,
      falhou,
    });
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err), done, falhou }, 500);
  }
});
