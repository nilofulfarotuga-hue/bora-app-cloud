#!/usr/bin/env node
// Cortex MCP server — a PONTE: Claude.ai <-> Hermes sobre o MESMO Cortex.
// MCP (JSON-RPC) sobre HTTP + OAuth 2.1 (PKCE + DCR) para o conector web do claude.ai.
// Mantém também auth por token estático (Claude Desktop/API). SÓ mexe no Cortex (.md).
// NUNCA DB / dinheiro / shell arbitrário. Zona 🔴 = recusa e manda propor. Dial cauteloso.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const PORT = parseInt(process.env.PORT || '4870', 10);
const BRAIN = process.env.CORTEX_BRAIN || '/brain/.claude/.ai/knowledge';
const TOKEN = process.env.CORTEX_TOKEN || '';                       // token estático (paralelo ao OAuth)
const ISSUER = (process.env.CORTEX_ISSUER || 'https://cortex.srv1786862.hstgr.cloud').replace(/\/$/, '');
const WRITE_ENABLED = process.env.CORTEX_WRITE_ENABLED === 'true';  // dial: começa false
const GIT_PUSH = process.env.CORTEX_GIT_PUSH === 'true';
const LOG = path.join(BRAIN, 'log.md');
const PROPOSALS = path.join(BRAIN, 'inbox', '_reports', 'proposals.jsonl');
const RED = /dispatch|pricing|finalizepurchase|bora_tokens|stripe|\brls\b|wallet|ledger|refund|comiss|markup|service_fee/i;
const FILA = process.env.CORTEX_FILA || path.join(BRAIN.replace(/[\\/]\.claude[\\/]\.ai[\\/]knowledge$/, ''), 'orquestracao'); // fila do loop (o MESMO dir que a campainha inotify observa)
const RED_ORDER = /dispatch_engine|dispatch|pricing|finalizepurchase|bora_tokens|stripe|payment|webhook|wallet|ledger|refund|payout|comiss|commission|markup|service_fee|platform_settings|\brls\b|force.?push/i; // zona vermelha p/ ordens novas (>= cobertura do carteiro T3)

// ---- OAuth state (memória; single-user) ----
const clients = new Map();   // client_id -> {redirect_uris:[]}
const codes = new Map();     // code -> {client_id, redirect_uri, challenge, exp}
const tokens = new Map();    // access_token -> {exp}
const refresh = new Map();   // refresh_token -> {exp}
const ACCESS_TTL = 2592000;  // 30d (era 3600=1h — causava "cai de hora em hora"; agora igual ao refresh)
const REFRESH_TTL = 2592000; // 30d

// ---- Persistência do estado OAuth (Parte 8 da missao sistema-redondo-2026-08-01) ----
// Problema: clients/tokens/refresh viviam SO em memoria. server.mjs esta baked na imagem
// (Dockerfile: COPY server.mjs), portanto qualquer deploy obriga a `docker build` + recriar o
// container -> o estado evaporava e o conector do claude.ai ficava deslogado a cada redeploy.
// Volume dedicado de proposito: /opt/data/.secrets esta montado READ-ONLY, e /brain e' um clone
// git (reset --hard de madrugada + risco de um `git add -A` alheio arrastar tokens para um commit).
// Falha a escrever = degrada para so-memoria; nunca derruba o servidor.
const STATE_FILE = process.env.CORTEX_OAUTH_STATE || '/state/oauth.json';
let stateDirty = false, stateTimer = null;
function loadState() {
  let raw; try { raw = fs.readFileSync(STATE_FILE, 'utf8'); } catch { return; }
  let d; try { d = JSON.parse(raw); } catch { console.error('[oauth] estado ilegivel — recomeco vazio'); return; }
  const t = now(); let nc = 0, nt = 0, nr = 0;
  for (const [k, v] of Object.entries(d.clients || {})) { clients.set(k, v); nc++; }
  for (const [k, v] of Object.entries(d.tokens || {})) { if (v && v.exp > t) { tokens.set(k, v); nt++; } }
  for (const [k, v] of Object.entries(d.refresh || {})) { if (v && v.exp > t) { refresh.set(k, v); nr++; } }
  console.error(`[oauth] estado restaurado: ${nc} cliente(s), ${nt} access, ${nr} refresh (expirados descartados)`);
}
function saveStateNow() {
  stateDirty = false;
  const t = now();
  const pick = (m) => Object.fromEntries([...m.entries()].filter(([, v]) => v && v.exp > t));
  const body = JSON.stringify({ v: 1, gravado: new Date().toISOString(), clients: Object.fromEntries(clients), tokens: pick(tokens), refresh: pick(refresh) });
  try {
    fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
    const tmp = STATE_FILE + '.tmp';
    fs.writeFileSync(tmp, body, { mode: 0o600 });   // escrita atomica: nunca deixa ficheiro meio-escrito
    fs.renameSync(tmp, STATE_FILE);
  } catch (e) { console.error('[oauth] NAO consegui gravar o estado (' + String(e.code || e).slice(0, 40) + ') — sigo so em memoria'); }
}
function saveState() { // agrupa rajadas (o fluxo OAuth escreve varias vezes seguidas)
  stateDirty = true;
  if (stateTimer) return;
  stateTimer = setTimeout(() => { stateTimer = null; if (stateDirty) saveStateNow(); }, 500);
  if (stateTimer.unref) stateTimer.unref();
}
const b64url = (b) => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const rand = (n = 32) => b64url(crypto.randomBytes(n));
const sha256 = (s) => crypto.createHash('sha256').update(s).digest();
const now = () => Math.floor(Date.now() / 1000);
function validToken(tok) { if (TOKEN && tok === TOKEN) return true; const t = tokens.get(tok); return !!(t && t.exp > now()); }
loadState(); // só aqui: loadState() usa now(), que é `const` e estaria na zona morta temporal acima.

// ---- rate limit por IP ----
const buckets = new Map();
const rateOk = (ip) => { const n = Date.now(); const b = buckets.get(ip) || { n: 0, t: n }; if (n - b.t > 60000) { b.n = 0; b.t = n; } b.n++; buckets.set(ip, b); return b.n <= 120; };

// ---- Cortex (leitura no BRAIN + orquestracao/ — a fila do loop) ----
function walk(dir) { const out = []; (function r(d) { let it; try { it = fs.readdirSync(d, { withFileTypes: true }); } catch { return; } for (const e of it) { if (e.isDirectory()) { if (['_descartado', '.git', '__pycache__', '.obsidian'].includes(e.name)) continue; r(path.join(d, e.name)); } else if (e.name.endsWith('.md')) out.push(path.join(d, e.name)); } })(dir); return out; }
const READ_ROOTS = [BRAIN, FILA]; // escopo de leitura = cérebro (knowledge) + fila de orquestração
function walkRoots() { const out = []; for (const r of READ_ROOTS) { try { out.push(...walk(r)); } catch {} } return out; }
function relPath(p) { const b = path.relative(BRAIN, p); if (!b.startsWith('..')) return b; const fp = path.relative(FILA, p); if (!fp.startsWith('..')) return 'orquestracao/' + fp; return b; }
const readf = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
function frontmatter(txt) { const fm = {}; if (!txt || !txt.startsWith('---')) return fm; const end = txt.indexOf('\n---', 3); if (end < 0) return fm; for (const line of txt.slice(3, end).split('\n')) { const m = line.match(/^([a-zA-Z_]+):\s*(.*)$/); if (m) fm[m[1]] = m[2].trim(); } return fm; }
function findById(id) { for (const p of walkRoots()) { const t = readf(p); if (frontmatter(t).id === id) return { p, t }; } return null; }
function logWrite(who, what) { try { fs.appendFileSync(LOG, `| ${new Date().toISOString().slice(0, 10)} | vps-mcp | ${who} | ${what} |\n`); } catch { } }

function t_buscar({ query }) { const q = (query || '').toLowerCase(); const res = []; for (const p of walkRoots()) { const t = readf(p) || ''; const fm = frontmatter(t); if ((path.basename(p) + ' ' + t).toLowerCase().includes(q)) { const i = t.toLowerCase().indexOf(q); res.push({ id: fm.id || null, path: relPath(p), tipo: fm.tipo, zona: fm.zona, snippet: i >= 0 ? t.slice(Math.max(0, i - 40), i + 90).replace(/\s+/g, ' ') : '' }); } if (res.length >= 20) break; } return { total: res.length, resultados: res }; }
function t_ler({ id }) { const f = findById(id); return f ? { id, path: relPath(f.p), conteudo: f.t } : { error: `id '${id}' não encontrado` }; }
function t_listar({ filtro }) { const res = []; for (const p of walkRoots()) { const fm = frontmatter(readf(p)); if (!fm.id) continue; const folder = relPath(p).split('/')[0]; if (filtro && fm.tipo !== filtro && fm.zona !== filtro && folder !== filtro) continue; res.push({ id: fm.id, tipo: fm.tipo, zona: fm.zona, path: relPath(p) }); } return { total: res.length, paginas: res }; }
function t_debt() { const t = readf(path.join(BRAIN, '_debt.md')); return t ? { conteudo: t } : { error: '_debt.md ausente' }; }
function t_propor({ id, conteudo }, who) { const pid = 'prop-' + crypto.randomBytes(4).toString('hex'); const f = findById(id); const rec = { pid, id, zona: f ? frontmatter(f.t).zona : '?', who, ts: new Date().toISOString(), conteudo: String(conteudo || '') }; try { fs.mkdirSync(path.dirname(PROPOSALS), { recursive: true }); fs.appendFileSync(PROPOSALS, JSON.stringify(rec) + '\n'); } catch (e) { return { error: String(e).slice(0, 200) }; } logWrite(who, `PROPOSTA ${pid} p/ ${id} (${rec.zona})`); return { pid, status: 'na fila de aprovação do admin (Central do Córtex)' }; }
function t_escrever({ id, conteudo }, who) {
  if (!WRITE_ENABLED) return { refused: 'escrita DESLIGADA (CORTEX_WRITE_ENABLED=false, dial cauteloso). Usa cortex_propor.' };
  const f = findById(id); if (!f) return { refused: `id '${id}' não encontrado — não crio páginas novas por MCP. Usa cortex_propor.` };
  if (frontmatter(f.t).zona === 'vermelha' || RED.test(String(conteudo))) return { refused: 'ZONA VERMELHA — recusado no servidor. Usa cortex_propor.', redirect: 'cortex_propor' };
  try { fs.writeFileSync(f.p, String(conteudo)); } catch (e) { return { error: String(e).slice(0, 200) }; }
  logWrite(who, `ESCREVEU ${id}`); let pushed = false;
  if (GIT_PUSH) { try { const repo = path.resolve(BRAIN, '..', '..', '..'); execFileSync('git', ['-C', repo, 'add', path.relative(repo, f.p)]); execFileSync('git', ['-C', repo, 'commit', '-m', `cortex(mcp): ${who} atualizou ${id} [skip ci]`]); execFileSync('git', ['-C', repo, 'push']); pushed = true; } catch (e) { return { written: true, pushed: false, gitError: String(e).slice(0, 160) }; } }
  return { written: true, pushed };
}
function t_nova_ordem({ tarefa, zona }, who) {
  const task1 = String(tarefa || '').replace(/\r?\n/g, ' ').trim();
  if (!task1) return { error: 'tarefa vazia — nada a fazer.' };
  // zona: auto-deteta por palavra-chave; override manual só ESCALA p/ vermelha, nunca desce (segurança).
  const vermelha = zona === 'vermelha' || RED_ORDER.test(task1);
  const id = 'ordem-' + new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14) + '-' + crypto.randomBytes(2).toString('hex');
  const criada = new Date().toISOString();
  if (vermelha) {
    // 🔴 NUNCA entra no loop — vai p/ a fila de aprovação do admin (como cortex_propor).
    const pid = 'prop-' + crypto.randomBytes(4).toString('hex');
    const rec = { pid, id, tipo: 'ordem_orquestracao', zona: 'vermelha', tarefa: task1, who, ts: criada };
    try { fs.mkdirSync(path.dirname(PROPOSALS), { recursive: true }); fs.appendFileSync(PROPOSALS, JSON.stringify(rec) + '\n'); } catch (e) { return { error: String(e).slice(0, 200) }; }
    logWrite(who, `NOVA ORDEM 🔴 ${id} -> aprovacao admin (${pid})`);
    return { id: null, roteado: 'aprovacao_admin', zona: 'vermelha', pid, aviso: '🔴 ZONA VERMELHA — a ordem NAO entra no loop automatico; foi p/ a fila de aprovação do admin (Central do Córtex). So corre depois de o Danilo aprovar a mao.' };
  }
  // 🟢 verde — cria a ordem na fila; a escrita do ficheiro dispara a campainha (inotify).
  const md = `--- ordem ---\nid: ${id}\nestado: aberta\nautor: ${who || 'claude.ai'}\ncriada: ${criada}\nzona: verde\ntentativa: 0\nteto_tentativas: 5\ntarefa: ${task1}\n--- fim ---\n`;
  const dest = path.join(FILA, id + '.md');
  try { fs.mkdirSync(FILA, { recursive: true }); fs.writeFileSync(dest, md); } catch (e) { return { error: 'falha a escrever na fila: ' + String(e).slice(0, 180) }; }
  logWrite(who, `NOVA ORDEM 🟢 ${id} (aberta) na fila`);
  return { id, estado: 'aberta', zona: 'verde', path: 'orquestracao/' + id + '.md', teto_tentativas: 5, campainha: 'disparada — o watcher inotify acorda o carteiro (se orquestracao_enabled=false a ordem espera aberta).', acompanhar: `cortex_ler('${id}') p/ ver o estado evoluir: aberta->executando->respondida->aprovada|corrigir.` };
}
// ---- Fila 🔴: LISTAR pendentes + APROVAR por pid (Parte 2 da missao sistema-redondo-2026-08-01) ----
// Porque existe: uma proposta criada por cortex_propor/cortex_nova_ordem(vermelha) so era visivel
// na Central (painel admin). Do lado do chat ficava so uma linha no log.md — sem forma de a LER
// nem de lhe dar destino. Estas duas ferramentas dao destino ao "vai" do Danilo sem abrir a Central.
//
// BARREIRA DELIBERADA (nao e' um esquecimento): aprovar por aqui NAO emite audit_id.
// O passo 2 do hermes-cortex-proposals-sync.sh so escreve autorizado_por_admin/audit_id a partir
// de uma aprovacao AUTENTICADA na Central (RPC cortex_proposal_approve + _admin_op_guard), e so
// COM esse trilho o carteiro salta o T3. Uma ordem nascida aqui vai SEM trilho => o carteiro
// re-avalia zona_vermelha() sobre o TEXTO no pickup e conteudo de dinheiro real volta a esperar
// o humano (Telegram "vai <id>"). Ou seja: isto desbloqueia os falsos-positivos (que sao a maioria)
// sem abrir uma porta lateral ao gate do dinheiro.
function readProposals() {
  const txt = readf(PROPOSALS); if (!txt) return [];
  const out = [];
  for (const line of txt.split('\n')) { const s = line.trim(); if (!s) continue; try { const r = JSON.parse(s); if (r && r.pid) out.push(r); } catch { } }
  return out;
}
function ordemPathsFor(rec) {
  const oid = String(rec.id || ('ordem-' + rec.pid)).replace(/[^a-zA-Z0-9_-]/g, '-').slice(0, 80);
  return { oid, central: path.join(FILA, oid + '-aprovado.md'), chat: path.join(FILA, oid + '-aprovado-chat.md') };
}
function t_propostas_pendentes({ limite } = {}) {
  const recs = readProposals();
  const n = Math.min(Math.max(parseInt(limite, 10) || 20, 1), 100);
  const pendentes = [], encaminhadas = [];
  for (const r of recs.slice().reverse()) {                       // mais recentes primeiro
    const f = ordemPathsFor(r);
    const via = fs.existsSync(f.central) ? 'central' : (fs.existsSync(f.chat) ? 'chat' : null);
    const item = {
      pid: r.pid, ordem_id: r.id || null, zona: r.zona || '?', tipo: r.tipo || 'edicao_cortex',
      who: r.who || '?', criada: r.ts || null,
      tarefa: String(r.tarefa || r.conteudo || '').replace(/\s+/g, ' ').slice(0, 400),
    };
    if (via) { if (encaminhadas.length < n) encaminhadas.push({ ...item, encaminhada_via: via }); }
    else if (pendentes.length < n) pendentes.push(item);
  }
  return {
    total_no_ficheiro: recs.length, total_pendentes: pendentes.length, propostas: pendentes,
    ja_encaminhadas: encaminhadas,
    nota: 'Para dar destino a uma: cortex_aprovar_proposta(pid). Aprovar por aqui NAO emite audit_id — '
      + 'a ordem nasce sem trilho de admin, logo o carteiro re-avalia a zona sobre o texto e conteudo de '
      + 'dinheiro real continua a exigir o "vai" humano. Aprovacao com trilho so na Central.',
  };
}
function t_aprovar_proposta({ pid }, who) {
  const alvo = String(pid || '').trim();
  if (!/^prop-[a-f0-9]{6,16}$/i.test(alvo)) return { error: `pid invalido: '${alvo}'. Formato esperado: prop-xxxxxxxx (ve com cortex_propostas_pendentes).` };
  const rec = readProposals().find((r) => r.pid === alvo);
  if (!rec) return { error: `pid '${alvo}' nao encontrado em proposals.jsonl.` };
  const tarefa = String(rec.tarefa || rec.conteudo || '').replace(/\r?\n/g, ' ').trim();
  if (!tarefa) return { error: `pid '${alvo}' nao tem texto de tarefa — nada para encaminhar.` };
  const f = ordemPathsFor(rec);
  if (fs.existsSync(f.central)) return { ja_encaminhada: true, via: 'central', path: 'orquestracao/' + path.basename(f.central), aviso: 'Esta proposta ja foi aprovada na Central (com trilho de auditoria). Nao crio segunda ordem.' };
  if (fs.existsSync(f.chat)) return { ja_encaminhada: true, via: 'chat', path: 'orquestracao/' + path.basename(f.chat), aviso: 'Ja aprovada por aqui antes. Idempotente — nao crio segunda ordem.' };
  const ts = new Date().toISOString();
  const md = `--- ordem ---\nid: ${f.oid}-aprovado-chat\nestado: aberta\nautor: cortex-mcp-chat (${who || 'claude.ai'})\ncriada: ${ts}\nzona: verde\ntentativa: 0\nteto_tentativas: 5\naprovada_via: chat\npid_original: ${alvo}\ntarefa: ${tarefa}\n--- fim ---\nnota: encaminhada pelo Danilo via chat (cortex_aprovar_proposta) em ${ts}, pid original ${alvo}.\nNasce DE PROPOSITO sem trilho de autorizacao de admin — o carteiro RE-AVALIA zona_vermelha() sobre\no texto no pickup. Se o conteudo tocar dinheiro real, volta a esperar o "vai" humano no Telegram.\n(Esta nota nao nomeia os campos do trilho para nao dar falso-positivo a quem faca grep no ficheiro.)\n`;
  try { fs.mkdirSync(FILA, { recursive: true }); fs.writeFileSync(f.chat, md); } catch (e) { return { error: 'falha a escrever na fila: ' + String(e).slice(0, 180) }; }
  logWrite(who, `APROVOU (chat, sem audit_id) ${alvo} -> ordem ${f.oid}-aprovado-chat`);
  return {
    aprovada: alvo, ordem_id: `${f.oid}-aprovado-chat`, estado: 'aberta',
    path: 'orquestracao/' + path.basename(f.chat),
    campainha: 'disparada — o watcher inotify acorda o carteiro (se orquestracao_enabled=false a ordem espera aberta).',
    barreira: 'sem audit_id: se o texto tocar dinheiro real, o carteiro devolve-a ao humano em vez de a correr.',
    acompanhar: `cortex_ler('${f.oid}-aprovado-chat')`,
  };
}
const TOOL_DEFS = [
  { name: 'cortex_buscar', description: 'Procura no Córtex (nome+conteúdo). id/tipo/zona/snippet.', inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
  { name: 'cortex_ler', description: 'Página do Córtex pelo id do frontmatter.', inputSchema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] } },
  { name: 'cortex_listar', description: 'Lista páginas; filtro por tipo ou zona.', inputSchema: { type: 'object', properties: { filtro: { type: 'string' } } } },
  { name: 'cortex_debt', description: 'Devolve o _debt.md.', inputSchema: { type: 'object', properties: {} } },
  { name: 'cortex_escrever', description: 'Atualiza página EXISTENTE — só zona verde. 🔴 recusada. Pode estar desligado.', inputSchema: { type: 'object', properties: { id: { type: 'string' }, conteudo: { type: 'string' } }, required: ['id', 'conteudo'] } },
  { name: 'cortex_propor', description: 'Zona 🔴 / write off: cria proposta na fila do admin (não escreve).', inputSchema: { type: 'object', properties: { id: { type: 'string' }, conteudo: { type: 'string' } }, required: ['id', 'conteudo'] } },
  { name: 'cortex_propostas_pendentes', description: 'Lista as propostas 🔴 que ficaram à espera de decisão (cortex_propor / cortex_nova_ordem em zona vermelha) e que ainda NÃO foram encaminhadas. Devolve pid, zona, quem propôs, quando e o texto da tarefa. Read-only.', inputSchema: { type: 'object', properties: { limite: { type: 'integer', description: 'Máximo de propostas a devolver (1-100, default 20).' } } } },
  { name: 'cortex_aprovar_proposta', description: 'Dá destino a uma proposta 🔴 pelo pid: cria a ordem real na fila do loop. NÃO emite audit_id — a ordem nasce sem trilho de admin, portanto o carteiro re-avalia a zona sobre o texto e conteúdo de dinheiro real continua a exigir o "vai" humano no Telegram. Idempotente. Aprovação COM trilho só na Central.', inputSchema: { type: 'object', properties: { pid: { type: 'string', description: 'O pid da proposta (formato prop-xxxxxxxx), obtido em cortex_propostas_pendentes.' } }, required: ['pid'] } },
  { name: 'cortex_nova_ordem', description: 'Cria uma ORDEM NOVA no loop de orquestração (id novo, estado aberta) e dispara a campainha. Zona verde entra no loop automatico; zona vermelha vai p/ aprovação do admin (NUNCA no loop). Teto de tentativas fixo em 5. Devolve o id p/ acompanhar com cortex_ler.', inputSchema: { type: 'object', properties: { tarefa: { type: 'string', description: 'O comando exato p/ o Claude Code executor (uma linha).' }, zona: { type: 'string', enum: ['verde', 'vermelha'], description: 'Opcional. Auto-detetada por palavras-chave das zonas protegidas; podes forçar vermelha. Nunca desce vermelha->verde.' }, teto_tentativas: { type: 'integer', description: 'IGNORADO — o sistema fixa sempre 5.' } }, required: ['tarefa'] } },
];
function dispatch(name, a, who) { switch (name) { case 'cortex_buscar': return t_buscar(a); case 'cortex_ler': return t_ler(a); case 'cortex_listar': return t_listar(a); case 'cortex_debt': return t_debt(a); case 'cortex_propor': return t_propor(a, who); case 'cortex_escrever': return t_escrever(a, who); case 'cortex_nova_ordem': return t_nova_ordem(a, who); case 'cortex_propostas_pendentes': return t_propostas_pendentes(a); case 'cortex_aprovar_proposta': return t_aprovar_proposta(a, who); default: return { error: 'ferramenta desconhecida: ' + name }; } }

function handleRpc(m, who) {
  if (!m || m.id === undefined || m.id === null) return null;
  const ok = (result) => ({ jsonrpc: '2.0', id: m.id, result });
  if (m.method === 'initialize') return ok({ protocolVersion: (m.params && m.params.protocolVersion) || '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'cortex-bora', version: '1.1.0' } });
  if (m.method === 'ping') return ok({});
  if (m.method === 'tools/list') return ok({ tools: TOOL_DEFS });
  if (m.method === 'tools/call') { const p = m.params || {}; let out; try { out = dispatch(p.name, p.arguments || {}, who); } catch (e) { out = { error: String(e).slice(0, 200) }; } return ok({ content: [{ type: 'text', text: JSON.stringify(out) }] }); }
  return { jsonrpc: '2.0', id: m.id, error: { code: -32601, message: 'method not found: ' + m.method } };
}

// ---- helpers HTTP ----
const json = (res, code, obj, extra = {}) => { res.writeHead(code, { 'content-type': 'application/json', ...extra }); res.end(JSON.stringify(obj)); };
const readBody = (req) => new Promise((r) => { let b = ''; req.on('data', (c) => { b += c; if (b.length > 1e6) req.destroy(); }); req.on('end', () => r(b)); });
const form = (s) => { const o = {}; for (const kv of (s || '').split('&')) { const i = kv.indexOf('='); if (i > 0) o[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1).replace(/\+/g, ' ')); } return o; };

const server = http.createServer(async (req, res) => {
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '?').toString().split(',')[0];
  if (!rateOk(ip)) return json(res, 429, { error: 'rate_limited' });
  const u = new URL(req.url, ISSUER); const p = u.pathname;

  // --- OAuth discovery (sem auth) ---
  if (req.method === 'GET' && (p === '/.well-known/oauth-authorization-server' || p === '/.well-known/openid-configuration'))
    return json(res, 200, { issuer: ISSUER, authorization_endpoint: ISSUER + '/authorize', token_endpoint: ISSUER + '/token', registration_endpoint: ISSUER + '/register', response_types_supported: ['code'], grant_types_supported: ['authorization_code', 'refresh_token'], code_challenge_methods_supported: ['S256'], token_endpoint_auth_methods_supported: ['none'], scopes_supported: ['cortex'] });
  if (req.method === 'GET' && (p === '/.well-known/oauth-protected-resource' || p === '/.well-known/oauth-protected-resource/'))
    return json(res, 200, { resource: ISSUER, authorization_servers: [ISSUER] });

  // --- DCR: registo dinâmico de cliente (o claude.ai regista-se) ---
  if (req.method === 'POST' && p === '/register') {
    const body = await readBody(req); let meta = {}; try { meta = JSON.parse(body || '{}'); } catch { }
    const cid = 'cli_' + rand(12); const uris = Array.isArray(meta.redirect_uris) ? meta.redirect_uris : [];
    clients.set(cid, { redirect_uris: uris }); saveState();
    return json(res, 201, { client_id: cid, redirect_uris: uris, token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] });
  }

  // --- Authorize (single-user auto-consent) ---
  if (req.method === 'GET' && p === '/authorize') {
    const q = Object.fromEntries(u.searchParams);
    const c = clients.get(q.client_id);
    const redir = q.redirect_uri;
    if (!c) return json(res, 400, { error: 'invalid_client' });
    if (c.redirect_uris.length && redir && !c.redirect_uris.includes(redir)) return json(res, 400, { error: 'invalid_redirect_uri' });
    if (q.response_type !== 'code' || !q.code_challenge || q.code_challenge_method !== 'S256') return json(res, 400, { error: 'invalid_request', detail: 'code+S256 obrigatório' });
    const code = rand(24); codes.set(code, { client_id: q.client_id, redirect_uri: redir, challenge: q.code_challenge, exp: now() + 300 });
    const back = new URL(redir); back.searchParams.set('code', code); if (q.state) back.searchParams.set('state', q.state);
    res.writeHead(302, { location: back.toString() }); return res.end();
  }

  // --- Token (authorization_code + refresh_token, PKCE) ---
  if (req.method === 'POST' && p === '/token') {
    const b = form(await readBody(req));
    if (b.grant_type === 'authorization_code') {
      const rec = codes.get(b.code); codes.delete(b.code);
      if (!rec || rec.exp < now()) return json(res, 400, { error: 'invalid_grant' });
      if (rec.redirect_uri && b.redirect_uri && rec.redirect_uri !== b.redirect_uri) return json(res, 400, { error: 'invalid_grant', detail: 'redirect_uri' });
      if (b64url(sha256(b.code_verifier || '')) !== rec.challenge) return json(res, 400, { error: 'invalid_grant', detail: 'pkce' });
      const at = rand(32), rt = rand(32); tokens.set(at, { exp: now() + ACCESS_TTL }); refresh.set(rt, { exp: now() + REFRESH_TTL }); saveState();
      return json(res, 200, { access_token: at, token_type: 'Bearer', expires_in: ACCESS_TTL, refresh_token: rt, scope: 'cortex' }, { 'cache-control': 'no-store' });
    }
    if (b.grant_type === 'refresh_token') {
      const r = refresh.get(b.refresh_token); if (!r || r.exp < now()) return json(res, 400, { error: 'invalid_grant' });
      const at = rand(32); tokens.set(at, { exp: now() + ACCESS_TTL }); saveState();
      return json(res, 200, { access_token: at, token_type: 'Bearer', expires_in: ACCESS_TTL, scope: 'cortex' }, { 'cache-control': 'no-store' });
    }
    return json(res, 400, { error: 'unsupported_grant_type' });
  }

  // --- MCP (requer bearer estático OU token OAuth) ---
  const auth = req.headers['authorization'] || ''; const key = req.headers['x-api-key'] || '';
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!(validToken(bearer) || validToken(key)))
    return json(res, 401, { error: 'unauthorized' }, { 'www-authenticate': `Bearer resource_metadata="${ISSUER}/.well-known/oauth-protected-resource"` });
  if (req.method === 'GET') return json(res, 200, { server: 'cortex-bora', ok: true, write_enabled: WRITE_ENABLED, oauth: true });
  if (req.method !== 'POST') { res.writeHead(405).end(); return; }
  let msg; try { msg = JSON.parse(await readBody(req)); } catch { return json(res, 400, { error: 'bad_json' }); }
  const who = (msg && msg.params && msg.params.clientInfo && msg.params.clientInfo.name) || 'claude.ai';
  const out = Array.isArray(msg) ? msg.map((x) => handleRpc(x, who)).filter(Boolean) : handleRpc(msg, who);
  if (out === null || (Array.isArray(out) && out.length === 0)) { res.writeHead(202).end(); return; }
  return json(res, 200, out);
});
server.listen(PORT, () => console.log(`[cortex-mcp] :${PORT} issuer=${ISSUER} write=${WRITE_ENABLED} oauth+token`));
