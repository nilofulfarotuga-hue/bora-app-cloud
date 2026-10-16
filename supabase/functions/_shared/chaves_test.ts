// deno test --allow-env --allow-net=127.0.0.1 supabase/functions/_shared/chaves_test.ts
//
// Os tokens aqui são de BRINCAR e constroem-se em tempo de execução (nada com cara de
// JWT escrito no ficheiro): a tranca do repositório recusa, e bem, segredos em texto claro.
import {
  chamadaDoServidor,
  chavePublicavel,
  chaveSecreta,
  chavesSecretas,
  iguais,
  papelNoJwtSemValidar,
  tokenBearer,
  utilizadorDoPedido,
} from './chaves.ts';

const b64u = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwtDeBrincar = (role: string) => ['cabecalho', b64u(JSON.stringify({ role })), 'assinatura'].join('.');

const NOVA = 'sb_secret_abcdefghijklmnopqrstuvwxyz0123456789';
const OUTRA = 'sb_secret_zyxwvutsrqponmlkjihgfedcba9876543210';
const PUBLICAVEL = 'sb_publishable_0123456789abcdefghijklmnopqrstuv';
const LEGADA = jwtDeBrincar('service_role');
const ANON = jwtDeBrincar('anon');
const FORJADO = jwtDeBrincar('service_role') + 'x';

function preparar(
  opcoes: { novas?: Record<string, string>; publicaveis?: Record<string, string>; srk?: string; anon?: string; url?: string } = {},
) {
  for (const n of ['SUPABASE_SECRET_KEYS', 'SUPABASE_SECRET_KEY', 'SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_URL']) {
    Deno.env.delete(n);
  }
  if (opcoes.novas) Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify(opcoes.novas));
  if (opcoes.publicaveis) Deno.env.set('SUPABASE_PUBLISHABLE_KEYS', JSON.stringify(opcoes.publicaveis));
  if (opcoes.srk) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', opcoes.srk);
  if (opcoes.anon) Deno.env.set('SUPABASE_ANON_KEY', opcoes.anon);
  if (opcoes.url) Deno.env.set('SUPABASE_URL', opcoes.url);
}

const pedido = (h: Record<string, string>) => new Request('https://x.test/f', { headers: h });

/** Um Auth de brincar: diz 200 em /auth/v1/admin/users só para a credencial dada. */
function authDeBrincar(aceita: string): { url: string; parar: () => Promise<void>; chamadas: () => number } {
  let n = 0;
  const servidor = Deno.serve({ port: 0, hostname: '127.0.0.1', onListen() {} }, (req) => {
    n++;
    const u = new URL(req.url);
    const cred = req.headers.get('apikey') ?? '';
    if (u.pathname === '/auth/v1/admin/users' && cred === aceita) return new Response('{"users":[]}', { status: 200 });
    return new Response('{"message":"invalid"}', { status: 401 });
  });
  const porta = (servidor.addr as Deno.NetAddr).port;
  return { url: `http://127.0.0.1:${porta}`, parar: () => servidor.shutdown(), chamadas: () => n };
}

Deno.test('chave nova em apikey e aceite', async () => {
  preparar({ novas: { default: NOVA } });
  if (!(await chamadaDoServidor(pedido({ apikey: NOVA })))) throw new Error('devia aceitar apikey nova');
});

Deno.test('chave nova em Bearer e aceite (o banco manda assim)', async () => {
  preparar({ novas: { default: NOVA } });
  if (!(await chamadaDoServidor(pedido({ Authorization: `Bearer ${NOVA}` })))) throw new Error('devia aceitar Bearer nova');
});

Deno.test('a chave nova que vem na variavel antiga tambem conta', async () => {
  preparar({ srk: OUTRA });
  if (!(await chamadaDoServidor(pedido({ Authorization: `Bearer ${OUTRA}` })))) throw new Error('devia aceitar a sb_secret da variavel antiga');
  if (chavesSecretas().length !== 1) throw new Error('devia conhecer 1 chave');
});

Deno.test('segunda chave secreta com outro nome tambem e aceite', async () => {
  preparar({ novas: { default: NOVA, vps: OUTRA } });
  if (!(await chamadaDoServidor(pedido({ apikey: OUTRA })))) throw new Error('devia aceitar a chave "vps"');
  if (chavesSecretas().length !== 2) throw new Error('devia conhecer 2 chaves');
});

Deno.test('service_role legada em Bearer so e aceite quando o Auth a confirma', async () => {
  const auth = authDeBrincar(LEGADA);
  try {
    preparar({ novas: { default: NOVA }, url: auth.url });
    if (!(await chamadaDoServidor(pedido({ Authorization: `Bearer ${LEGADA}` })))) throw new Error('devia aceitar a legada confirmada');
    const antes = auth.chamadas();
    if (!(await chamadaDoServidor(pedido({ Authorization: `Bearer ${LEGADA}` })))) throw new Error('devia aceitar outra vez');
    if (auth.chamadas() !== antes) throw new Error('a segunda vez devia vir da memoria, sem ir ao Auth');
    if (await chamadaDoServidor(pedido({ Authorization: `Bearer ${FORJADO}` }))) throw new Error('aceitou um JWT forjado');
    if (await chamadaDoServidor(pedido({ Authorization: `Bearer ${ANON}` }))) throw new Error('aceitou a anon (nem devia ir ao Auth)');
  } finally {
    await auth.parar();
  }
});

Deno.test('sem Auth ao alcance, a legada e recusada (fecha, nao abre)', async () => {
  preparar({ novas: { default: NOVA } });
  const token = jwtDeBrincar('service_role') + 'outra';
  if (await chamadaDoServidor(pedido({ Authorization: `Bearer ${token}` }))) throw new Error('aceitou sem confirmar');
});

Deno.test('chave publicavel, anon e lixo nunca passam por servidor', async () => {
  preparar({ novas: { default: NOVA }, anon: ANON, publicaveis: { default: PUBLICAVEL } });
  if (await chamadaDoServidor(pedido({ apikey: PUBLICAVEL }))) throw new Error('aceitou a publicavel');
  if (await chamadaDoServidor(pedido({ Authorization: `Bearer ${PUBLICAVEL}` }))) throw new Error('aceitou a publicavel em Bearer');
  if (await chamadaDoServidor(pedido({}))) throw new Error('aceitou sem cabecalhos');
  if (await chamadaDoServidor(pedido({ apikey: '' }))) throw new Error('aceitou apikey vazia');
  if (await chamadaDoServidor(pedido({ Authorization: 'Bearer lixo' }))) throw new Error('aceitou lixo');
});

Deno.test('chaveSecreta prefere a nova e recua para a variavel antiga', () => {
  preparar({ novas: { default: NOVA }, srk: OUTRA });
  if (chaveSecreta() !== NOVA) throw new Error('devia dar a nova');
  preparar({ srk: OUTRA });
  if (chaveSecreta() !== OUTRA) throw new Error('devia recuar para a variavel antiga');
  preparar({ novas: { producao: OUTRA } });
  if (chaveSecreta() !== OUTRA) throw new Error('sem "default" devia dar a primeira que existe');
  preparar({});
  if (chaveSecreta() !== '') throw new Error('sem nada devia dar vazio');
});

Deno.test('chavePublicavel prefere a publicavel e recua para a anon', () => {
  preparar({ publicaveis: { default: PUBLICAVEL }, anon: ANON });
  if (chavePublicavel() !== PUBLICAVEL) throw new Error('devia dar a publicavel');
  preparar({ anon: ANON });
  if (chavePublicavel() !== ANON) throw new Error('devia recuar para a anon');
});

Deno.test('SUPABASE_SECRET_KEYS mal formado nao rebenta', async () => {
  preparar({ srk: NOVA });
  Deno.env.set('SUPABASE_SECRET_KEYS', 'isto nao e json');
  if (chavesSecretas().length !== 1) throw new Error('devia ignorar o JSON invalido e ficar com a variavel antiga');
  if (!(await chamadaDoServidor(pedido({ apikey: NOVA })))) throw new Error('a nova devia continuar a valer');
});

Deno.test('tokenBearer, iguais e papelNoJwtSemValidar', async () => {
  if (tokenBearer(pedido({ Authorization: 'bearer   abc ' })) !== 'abc') throw new Error('tokenBearer');
  if (tokenBearer(pedido({ Authorization: 'Basic abc' })) !== '') throw new Error('Basic nao e bearer');
  if (!(await iguais('a', 'a')) || (await iguais('a', 'b')) || (await iguais('', ''))) throw new Error('iguais');
  if (papelNoJwtSemValidar(LEGADA) !== 'service_role') throw new Error('papel');
  if (papelNoJwtSemValidar(NOVA) !== null) throw new Error('sb_ nao tem papel');
  if (papelNoJwtSemValidar('a.b') !== null) throw new Error('duas partes');
});

Deno.test('utilizadorDoPedido recusa chaves e tokens de servico sem ir a rede', async () => {
  preparar({ novas: { default: NOVA } });
  if ((await utilizadorDoPedido(pedido({ Authorization: `Bearer ${NOVA}` }))) !== null) throw new Error('sb_ nao e utilizador');
  if ((await utilizadorDoPedido(pedido({ Authorization: `Bearer ${LEGADA}` }))) !== null) throw new Error('service_role nao e utilizador');
  if ((await utilizadorDoPedido(pedido({ Authorization: 'Bearer so-um-token' }))) !== null) throw new Error('nao-JWT nao e utilizador');
  if ((await utilizadorDoPedido(pedido({}))) !== null) throw new Error('sem token nao e utilizador');
});
