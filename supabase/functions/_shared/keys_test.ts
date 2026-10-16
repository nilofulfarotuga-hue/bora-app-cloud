// deno test --allow-env --allow-net=127.0.0.1 supabase/functions/_shared/keys_test.ts
// Tokens de brincar construídos em tempo de execução (nada com cara de JWT no ficheiro).
import { callerOk, isSecretApikey, secretKey } from './keys.ts';

const b64u = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwtDeBrincar = (role: string, sub?: string) =>
  ['cabecalho', b64u(JSON.stringify(sub ? { role, sub } : { role })), 'assinatura'].join('.');

const NOVA = 'sb_secret_abcdefghijklmnopqrstuvwxyz0123456789';
const BACKEND = 'sb_secret_backend2026100000000000000000000';
const PUBLICAVEL = 'sb_publishable_0123456789abcdefghijklmnopqrstuv';

function preparar(opcoes: { novas?: Record<string, string>; srk?: string; url?: string; publicaveis?: Record<string, string> } = {}) {
  for (const n of ['SUPABASE_SECRET_KEYS', 'SUPABASE_SECRET_KEY', 'SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_URL']) {
    Deno.env.delete(n);
  }
  if (opcoes.novas) Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify(opcoes.novas));
  if (opcoes.publicaveis) Deno.env.set('SUPABASE_PUBLISHABLE_KEYS', JSON.stringify(opcoes.publicaveis));
  if (opcoes.srk) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', opcoes.srk);
  if (opcoes.url) Deno.env.set('SUPABASE_URL', opcoes.url);
}
const pedido = (h: Record<string, string>) => new Request('https://x.test/f', { headers: h });

/** Auth de brincar: /auth/v1/user responde 200 só ao token de utilizador dado; admin/users só à legada dada. */
function authDeBrincar(utilizador: string, legada: string) {
  const servidor = Deno.serve({ port: 0, hostname: '127.0.0.1', onListen() {} }, (req) => {
    const u = new URL(req.url);
    const bearer = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (u.pathname === '/auth/v1/user' && bearer === utilizador) return new Response(JSON.stringify({ id: 'u-1', email: 'x@y.z', app_metadata: {} }), { status: 200 });
    if (u.pathname === '/auth/v1/admin/users' && (req.headers.get('apikey') ?? '') === legada) return new Response('{"users":[]}', { status: 200 });
    return new Response('{"message":"invalid"}', { status: 401 });
  });
  const porta = (servidor.addr as Deno.NetAddr).port;
  return { url: `http://127.0.0.1:${porta}`, parar: () => servidor.shutdown() };
}

Deno.test('secretKey prefere backend-2026-10, depois default, depois a variavel antiga', () => {
  preparar({ novas: { default: NOVA, 'backend-2026-10': BACKEND }, srk: 'sb_secret_zzz' });
  if (secretKey() !== BACKEND) throw new Error('devia dar a backend-2026-10');
  preparar({ novas: { default: NOVA }, srk: 'sb_secret_zzz' });
  if (secretKey() !== NOVA) throw new Error('devia dar a default');
  preparar({ srk: 'sb_secret_zzz' });
  if (secretKey() !== 'sb_secret_zzz') throw new Error('devia recuar para a variavel antiga');
});

Deno.test('isSecretApikey so com chave secreta conhecida', async () => {
  preparar({ novas: { default: NOVA, 'backend-2026-10': BACKEND }, publicaveis: { default: PUBLICAVEL } });
  if (!(await isSecretApikey(pedido({ apikey: NOVA })))) throw new Error('default');
  if (!(await isSecretApikey(pedido({ apikey: BACKEND })))) throw new Error('backend');
  if (await isSecretApikey(pedido({ apikey: PUBLICAVEL }))) throw new Error('publicavel nao e secreta');
  if (await isSecretApikey(pedido({ Authorization: `Bearer ${NOVA}` }))) throw new Error('so o cabecalho apikey conta aqui');
  if (await isSecretApikey(pedido({}))) throw new Error('sem apikey');
});

Deno.test('callerOk: apikey nova, Bearer nova, legada confirmada, utilizador valido; recusa o resto', async () => {
  const utilizador = jwtDeBrincar('authenticated', 'u-1');
  const legada = jwtDeBrincar('service_role');
  const auth = authDeBrincar(utilizador, legada);
  try {
    preparar({ novas: { default: NOVA }, url: auth.url, publicaveis: { default: PUBLICAVEL } });
    if (!(await callerOk(pedido({ apikey: NOVA })))) throw new Error('apikey nova');
    if (!(await callerOk(pedido({ Authorization: `Bearer ${NOVA}` })))) throw new Error('Bearer nova');
    if (!(await callerOk(pedido({ Authorization: `Bearer ${legada}` })))) throw new Error('legada confirmada no Auth');
    if (!(await callerOk(pedido({ Authorization: `Bearer ${utilizador}` })))) throw new Error('utilizador valido');
    if (await callerOk(pedido({ Authorization: `Bearer ${jwtDeBrincar('authenticated', 'u-2')}` }))) throw new Error('utilizador desconhecido passou');
    if (await callerOk(pedido({ Authorization: `Bearer ${legada}x` }))) throw new Error('legada forjada passou');
    if (await callerOk(pedido({ apikey: PUBLICAVEL }))) throw new Error('publicavel passou');
    if (await callerOk(pedido({}))) throw new Error('sem nada passou');
  } finally {
    await auth.parar();
  }
});
