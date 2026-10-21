// deno test --allow-env --allow-net=127.0.0.1 supabase/functions/_shared/servidor_ou_admin_test.ts
//
// Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4).
// Prova com DEFEITO PLANTADO: o portão antigo (exigirCallerOk) deixa passar uma conta normal
// — é o ataque "qualquer cliente manda um push com texto livre a qualquer pessoa" —, e o
// portão novo (exigirServidorOuAdmin) recusa-a com 403, sem partir o banco (chave de
// servidor) nem o admin.
// Tokens de brincar construídos em tempo de execução (nada com cara de JWT no ficheiro).
import { exigirCallerOk } from './keys.ts';
import { exigirServidorOuAdmin } from './chaves.ts';

const b64u = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenDeBrincar = (role: string, sub: string) =>
  ['cabecalho', b64u(JSON.stringify({ role, sub })), 'assinatura'].join('.');

const NOVA = 'sb_secret_abcdefghijklmnopqrstuvwxyz0123456789';
const PUBLICAVEL = 'sb_publishable_0123456789abcdefghijklmnopqrstuv';
const CLIENTE = tokenDeBrincar('authenticated', 'cliente-normal');
const ADMIN = tokenDeBrincar('authenticated', 'admin-do-painel');
const LEGADA = tokenDeBrincar('service_role', 'servidor');
const ANON = tokenDeBrincar('anon', 'ninguem');

function preparar(url: string) {
  for (const n of ['SUPABASE_SECRET_KEYS', 'SUPABASE_SECRET_KEY', 'SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_URL']) {
    Deno.env.delete(n);
  }
  Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify({ default: NOVA }));
  Deno.env.set('SUPABASE_PUBLISHABLE_KEYS', JSON.stringify({ default: PUBLICAVEL }));
  Deno.env.set('SUPABASE_URL', url);
}

/** Auth de brincar: /auth/v1/user conhece um cliente normal e um admin; admin/users só aceita a legada. */
function authDeBrincar() {
  const servidor = Deno.serve({ port: 0, hostname: '127.0.0.1', onListen() {} }, (req) => {
    const u = new URL(req.url);
    const bearer = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (u.pathname === '/auth/v1/user' && bearer === CLIENTE) {
      return new Response(JSON.stringify({ id: 'u-cliente', email: 'cliente@x.test', app_metadata: {} }), { status: 200 });
    }
    if (u.pathname === '/auth/v1/user' && bearer === ADMIN) {
      return new Response(JSON.stringify({ id: 'u-admin', email: 'admin@x.test', app_metadata: { role: 'admin' } }), { status: 200 });
    }
    if (u.pathname === '/auth/v1/admin/users' && (req.headers.get('apikey') ?? '') === LEGADA) {
      return new Response('{"users":[]}', { status: 200 });
    }
    return new Response('{"message":"invalid"}', { status: 401 });
  });
  const porta = (servidor.addr as Deno.NetAddr).port;
  return { url: `http://127.0.0.1:${porta}`, parar: () => servidor.shutdown() };
}

const pedido = (h: Record<string, string>) => new Request('https://x.test/f', { method: 'POST', headers: h });
const comBearer = (t: string) => pedido({ authorization: `Bearer ${t}`, apikey: PUBLICAVEL });

Deno.test('DEFEITO (portão antigo): exigirCallerOk deixa uma conta normal passar', async () => {
  const auth = authDeBrincar();
  try {
    preparar(auth.url);
    const r = await exigirCallerOk(comBearer(CLIENTE));
    if (r !== null) throw new Error(`esperava que o portão antigo deixasse passar (é o defeito), veio ${r.status}`);
  } finally {
    await auth.parar();
  }
});

Deno.test('CORRIGIDO: exigirServidorOuAdmin recusa a mesma conta normal com 403', async () => {
  const auth = authDeBrincar();
  try {
    preparar(auth.url);
    const r = await exigirServidorOuAdmin(comBearer(CLIENTE));
    if (!r || r.status !== 403) throw new Error(`esperava 403, veio ${r?.status ?? 'null (passou)'}`);
    const corpo = await r.json();
    if (corpo.error !== 'forbidden') throw new Error(`corpo inesperado ${JSON.stringify(corpo)}`);
  } finally {
    await auth.parar();
  }
});

Deno.test('o admin do painel continua a passar', async () => {
  const auth = authDeBrincar();
  try {
    preparar(auth.url);
    const r = await exigirServidorOuAdmin(comBearer(ADMIN));
    if (r !== null) throw new Error(`admin devia passar, veio ${r.status}`);
  } finally {
    await auth.parar();
  }
});

Deno.test('o banco continua a passar: chave nova em apikey/Bearer e legada confirmada no Auth', async () => {
  const auth = authDeBrincar();
  try {
    preparar(auth.url);
    if ((await exigirServidorOuAdmin(pedido({ apikey: NOVA }))) !== null) throw new Error('chave nova em apikey devia passar');
    if ((await exigirServidorOuAdmin(pedido({ authorization: `Bearer ${NOVA}` }))) !== null) throw new Error('chave nova em Bearer devia passar');
    if ((await exigirServidorOuAdmin(pedido({ authorization: `Bearer ${LEGADA}` }))) !== null) throw new Error('legada confirmada devia passar');
  } finally {
    await auth.parar();
  }
});

Deno.test('sem credencial, chave publicável ou anon: 403', async () => {
  const auth = authDeBrincar();
  try {
    preparar(auth.url);
    for (const [nome, req] of [
      ['nada', pedido({})],
      ['publicavel', pedido({ apikey: PUBLICAVEL, authorization: `Bearer ${PUBLICAVEL}` })],
      ['anon', comBearer(ANON)],
      ['token desconhecido', comBearer(tokenDeBrincar('authenticated', 'forjado'))],
    ] as const) {
      const r = await exigirServidorOuAdmin(req);
      if (!r || r.status !== 403) throw new Error(`${nome}: esperava 403, veio ${r?.status ?? 'null (passou)'}`);
    }
  } finally {
    await auth.parar();
  }
});
