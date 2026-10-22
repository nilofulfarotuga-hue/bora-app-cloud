// chaves-semear — leva a chave secreta nova (sb_secret "default", que a plataforma injeta nesta
// função) para o cofre do banco (vault.bora_server_secret), sem passar por nenhuma pessoa nem
// por nenhuma conversa. Missão chave-nova-16-10 (16/10/2026). Ver docs/SEGURANCA-CHAVES.md.
//
// Quem pode chamar: só o servidor (chamadaDoServidor): o banco com a service_role legada do
// cofre (confirmada no Auth) ou uma chave secreta nova. O verify_jwt fica LIGADO — o portão
// valida a legada; a nova passa porque o portão a reconhece (medido a 16/10/2026).
// Nunca devolve a chave: só o prefixo (10 caracteres) e o tamanho.
import { chamadaDoServidor, chaveSecreta } from '../_shared/chaves.ts';

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405);
  if (!(await chamadaDoServidor(req))) return json({ ok: false, error: 'forbidden' }, 403);

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const chave = chaveSecreta();
  if (!url || !chave.startsWith('sb_secret_')) {
    return json({ ok: false, error: 'sem_chave_nova', prefixo: chave.slice(0, 10), tamanho: chave.length }, 500);
  }

  // A própria chave secreta serve de credencial (apikey) para chamar a RPC do cofre.
  const r = await fetch(`${url}/rest/v1/rpc/vault_semear_chave_servidor`, {
    method: 'POST',
    headers: { apikey: chave, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_valor: chave, p_origem: 'chaves-semear' }),
  });
  const texto = await r.text();
  return json({ ok: r.ok, status: r.status, resultado: texto.slice(0, 300) }, r.ok ? 200 : 502);
});
