// supabase/functions/sessao-convidado/index.ts
//
// SESSÃO DE CONVIDADO SEM PALAVRA-PASSE NA APP — missão melhorias-paridade-2026-10-26 (item 2).
//
// Até 01/09/2026 a app entrava como guest@bora.com com uma palavra-passe escrita no código
// (repo público, bundle web legível). A 31/08 viu-se que essa conta pedia corridas TVDE reais e
// a palavra-passe foi mudada no servidor: desde aí a entrada dava 400 e o signUp 422, e quem
// chegava sem conta ficava sem sessão nenhuma.
//
// Agora a palavra-passe NUNCA sai do servidor: é derivada da chave secreta (HMAC) e esta função
// devolve só os tokens da sessão. Se a chave secreta mudar, a primeira chamada repõe a
// palavra-passe derivada (auto-cura) e segue. Nada é escrito em log.
//
// O que o convidado pode fazer é decidido no BANCO, não aqui: a migração
// 20261026090000_convidado_so_ve.sql recusa-lhe escrever ou ler dados de clientes e criar
// corridas/marcações/reservas; o pedido (orders/create_order) fica guardado no pacote da
// publicação (pendente_create_order.sql). Por isso a função só responde com a definição
// `sessao_convidado_ativa` = true — desligada até esse pacote estar aplicado.
//
// CONTRATO: { ok: true, refresh_token, access_token, expires_at } ou { ok: false, motivo }.
//
// PUBLICAR COM verify_jwt = false (supabase/config.toml). Pelo MCP/painel é preciso
// marcá-lo à mão, senão quem ainda não tem sessão leva 401.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { secretKey } from '../_shared/keys.ts';

const EMAIL_CONVIDADO = 'guest@bora.com';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// deno-lint-ignore no-explicit-any
const json = (body: any, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });

/** Palavra-passe derivada: HMAC-SHA256(chave secreta, rótulo fixo), em base64url. */
async function palavraDerivada(chave: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(chave), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('HMAC', k, new TextEncoder().encode('bora-sessao-convidado-v1')),
  );
  return btoa(String.fromCharCode(...sig)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, motivo: 'metodo' }, 405);

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const chave = secretKey();
  const admin = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });

  // Interruptor no banco: só há sessão de convidado quando as guardas estão todas aplicadas.
  const { data: ativa } = await admin.rpc('get_setting', { p_key: 'sessao_convidado_ativa' });
  if (ativa !== true) return json({ ok: false, motivo: 'desligada' });

  const senha = await palavraDerivada(chave);
  const entrar = () =>
    createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } })
      .auth.signInWithPassword({ email: EMAIL_CONVIDADO, password: senha });

  let { data, error } = await entrar();
  // Auto-cura SÓ quando a palavra-passe não bate (a chave secreta mudou, ou é a
  // primeira vez). Um 429 (limite por IP) ou rede em baixo não repõe nada.
  const credenciaisErradas = !!error &&
    ((error as { code?: string }).code === 'invalid_credentials' ||
      /invalid login credentials/i.test(error.message));
  if (error && !credenciaisErradas) {
    return json({ ok: false, motivo: 'auth_indisponivel' }, 503);
  }
  if (error) {
    let conta: { id: string } | undefined;
    for (let page = 1; page <= 50 && !conta; page++) {
      const { data: lista, error: eLista } = await admin.auth.admin.listUsers({ page, perPage: 200 });
      if (eLista) return json({ ok: false, motivo: 'auth_indisponivel' }, 503);
      conta = lista.users.find((u) => (u.email ?? '').toLowerCase() === EMAIL_CONVIDADO);
      if (lista.users.length < 200) break;
    }
    if (!conta) return json({ ok: false, motivo: 'conta_inexistente' }, 503);
    const { error: eUpd } = await admin.auth.admin.updateUserById(conta.id, { password: senha });
    if (eUpd) return json({ ok: false, motivo: 'repor_falhou' }, 503);
    ({ data, error } = await entrar());
  }
  if (error || !data.session) return json({ ok: false, motivo: 'entrada_falhou' }, 503);

  return json({
    ok: true,
    refresh_token: data.session.refresh_token,
    access_token: data.session.access_token,
    expires_at: data.session.expires_at,
  });
});
