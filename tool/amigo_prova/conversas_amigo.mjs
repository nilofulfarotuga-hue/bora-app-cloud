// Prova do adendo 4 da M11 (09/11/2026): o Amigo conversa como amigo, nunca fala "do cliente" na 3.ª pessoa,
// nunca se diz "de compras", e a deixa muda de conversa para conversa (uma linha nova em assistant_deixas).
//
// Corre-se DEPOIS de publicar o client-assistant, numa sessão com as travas abertas para publicar:
//   node tool/amigo_prova/conversas_amigo.mjs <saida.json>
// Sessão das CONTAS DE TESTE e2e_client_*@boraapp.test por link mágico gerado com a chave de servidor
// (método da memória "prova-do-robo-de-suporte-com-conta-de-teste"): nenhuma senha, nenhum email enviado.
// As chaves leem-se de backend/.env e .dart_defines do checkout principal e NUNCA se escrevem em lado nenhum.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const RAIZ = 'C:/BoraLocal/projetosflutter/bora_app';
const saida = process.argv[2] ?? 'C:/BoraLocal/missoes/m11-amigo-rosto-2026-11-09/prova-conversas-adendo4.json';

function lerChaves(caminho) {
  if (!existsSync(caminho)) return {};
  const t = readFileSync(caminho, 'utf8').trim();
  if (t.startsWith('{')) return JSON.parse(t);
  const o = {};
  for (const l of t.split(/\r?\n/)) {
    const m = l.match(/^\s*([A-Za-z0-9_]+)\s*=\s*"?([^"\r\n]*)"?\s*$/);
    if (m) o[m[1]] = m[2];
  }
  return o;
}
const env = { ...lerChaves(`${RAIZ}/backend/.env`), ...lerChaves(`${RAIZ}/.dart_defines`) };
const url = Object.entries(env).find(([k, v]) => /SUPABASE_URL/i.test(k) && /^https:/.test(v))?.[1];
const servidor = Object.entries(env).find(([k, v]) => /SERVICE_ROLE|SECRET_KEY|SERVICE_KEY/i.test(k) && /^(eyJ|sb_secret_)/.test(v))?.[1];
const publica = Object.entries(env).find(([k, v]) => /ANON|PUBLISHABLE/i.test(k) && /^(eyJ|sb_publishable_)/.test(v))?.[1];
if (!url || !servidor || !publica) { console.log('FALTAM CHAVES (url/servidor/publicavel):', !!url, !!servidor, !!publica); process.exit(2); }

async function sessao(email) {
  const g = await fetch(`${url}/auth/v1/admin/generate_link`, {
    method: 'POST', headers: { apikey: servidor, Authorization: `Bearer ${servidor}`, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email }),
  }).then((r) => r.json());
  const h = g?.properties?.hashed_token ?? g?.hashed_token;
  const v = await fetch(`${url}/auth/v1/verify`, {
    method: 'POST', headers: { apikey: publica, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: h }),
  }).then((r) => r.json());
  if (!v.access_token) throw new Error(`sessão falhou para ${email}`);
  return { token: v.access_token, uid: v.user?.id };
}

async function amigo(s, mensagem, conversa) {
  const r = await fetch(`${url}/functions/v1/client-assistant`, {
    method: 'POST', headers: { apikey: publica, Authorization: `Bearer ${s.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ message: mensagem, conversation_id: conversa ?? null, platform: 'web' }),
  });
  const j = await r.json().catch(() => ({}));
  return { status: r.status, j };
}

const TERCEIRA = /\b(o|a|ao|à|do|da|pelo|pela)\s+client[ea]s?\b|\bSISTEMA\b|\bnota (do sistema|interna)\b|\bas minhas (regras|instru)|\bn[aã]o vou (empurrar|for[cç]ar)\b/i;
const DE_COMPRAS = /(assistente|amigo|ajudante)\s+(de|das)\s+compras/i;

const CONVERSAS = [
  ['olá!'], ['bom dia Amigo'], ['como estás?'], ['tudo bem contigo?'],
  ['está um frio de rachar na Guarda hoje'], ['achas que vai chover amanhã?'],
  ['viste o jogo do Benfica ontem?'], ['o meu dia está a ser difícil'],
  ['estou cansado do trabalho'], ['conta-me uma piada'],
  ['não quero comprar nada, só conversar'], ['estou só a ver a app'],
  ['obrigado pela ajuda de ontem'], ['o que gostas de fazer?'],
  ['estou aborrecido'], ['gosto muito da Guarda'], ['boa noite Amigo'],
  ['só queria dizer olá'],
  ['chamo-me Rui e hoje fiz anos', 'lembras-te do meu nome?'],
  ['hoje corri 5 km', 'achas que amanhã devia descansar?'],
];
const QUEM_ES = ['quem és tu?', 'o que fazes?', 'apresenta-te', 'és o assistente de compras?', 'para que serves?'];

const contas = ['e2e_client_a@boraapp.test', 'e2e_client_b@boraapp.test', 'e2e_client_test_explore@boraapp.test'];
const sessoes = [];
for (const c of contas) { try { sessoes.push({ email: c, ...(await sessao(c)) }); } catch (e) { console.log(e.message); } }
let k = 0;
const proxima = () => sessoes[(k++) % sessoes.length];
const resultado = { conversas: [], quem_es: [], deixas: [] };

for (const passos of CONVERSAS) {
  const s = proxima();
  let conv = null;
  const linhas = [];
  for (const m of passos) {
    const { status, j } = await amigo(s, m, conv);
    conv = j.conversation_id ?? conv;
    linhas.push({ eu: m, amigo: j.texto ?? `(${status} ${j.error ?? ''})`, emocao: j.emocao ?? null, deixa: j.deixa?.texto ?? null,
      terceira_pessoa: TERCEIRA.test(j.texto ?? ''), de_compras: DE_COMPRAS.test(j.texto ?? '') });
    if (j.deixa?.id) resultado.deixas.push({ conta: s.email, id: j.deixa.id, tipo: j.deixa.tipo, texto: j.deixa.texto });
  }
  resultado.conversas.push(linhas);
}
for (const m of QUEM_ES) {
  const s = proxima();
  const { status, j } = await amigo(s, m, null);
  resultado.quem_es.push({ eu: m, amigo: j.texto ?? `(${status})`, de_compras: DE_COMPRAS.test(j.texto ?? ''), terceira_pessoa: TERCEIRA.test(j.texto ?? '') });
}
// linhas novas em assistant_deixas (só contagem e tipos, das contas de teste)
const uids = sessoes.map((s) => s.uid).filter(Boolean);
const dx = await fetch(`${url}/rest/v1/assistant_deixas?select=id,tipo,user_id,mostrada_em&user_id=in.(${uids.join(',')})&mostrada_em=gte.${new Date(Date.now() - 3600e3).toISOString()}`, {
  headers: { apikey: servidor, Authorization: `Bearer ${servidor}` },
}).then((r) => r.json()).catch(() => []);
resultado.assistant_deixas_ultima_hora = Array.isArray(dx) ? dx.map((d) => ({ id: d.id, tipo: d.tipo })) : dx;
const todas = resultado.conversas.flat();
resultado.resumo = {
  respostas: todas.length,
  terceira_pessoa: todas.filter((x) => x.terceira_pessoa).length + resultado.quem_es.filter((x) => x.terceira_pessoa).length,
  de_compras: todas.filter((x) => x.de_compras).length + resultado.quem_es.filter((x) => x.de_compras).length,
  deixas_ditas: resultado.deixas.length,
  deixas_diferentes: new Set(resultado.deixas.map((d) => d.texto)).size,
  linhas_assistant_deixas: Array.isArray(dx) ? dx.length : '?',
};
writeFileSync(saida, JSON.stringify(resultado, null, 2));
console.log('PROVA', JSON.stringify(resultado.resumo));
