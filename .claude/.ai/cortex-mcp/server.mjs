#!/usr/bin/env node
// Cortex MCP server — a PONTE: Claude.ai <-> Hermes sobre o MESMO Cortex.
// MCP (JSON-RPC) sobre Streamable HTTP. Auth por token. SÓ mexe no Cortex (ficheiros .md).
// NUNCA toca DB / dinheiro / shell arbitrário. Zona 🔴 = recusa e manda propor. Dial cauteloso.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const PORT = parseInt(process.env.PORT || '4870', 10);
const BRAIN = process.env.CORTEX_BRAIN || '/brain/.claude/.ai/knowledge';
const TOKEN = process.env.CORTEX_TOKEN || '';
const WRITE_ENABLED = process.env.CORTEX_WRITE_ENABLED === 'true';   // dial: começa false
const GIT_PUSH = process.env.CORTEX_GIT_PUSH === 'true';
const LOG = path.join(BRAIN, 'log.md');
const PROPOSALS = path.join(BRAIN, 'inbox', '_reports', 'proposals.jsonl');
const RED = /dispatch|pricing|finalizepurchase|bora_tokens|stripe|\brls\b|wallet|ledger|refund|comiss|markup|service_fee/i;

// ---- rate limit por IP (60/min) ----
const buckets = new Map();
const rateOk = (ip) => { const now = Date.now(); const b = buckets.get(ip) || { n: 0, t: now }; if (now - b.t > 60000) { b.n = 0; b.t = now; } b.n++; buckets.set(ip, b); return b.n <= 60; };

// ---- util (leitura só dentro do BRAIN — sem path traversal) ----
function walk(dir) { const out = []; (function r(d) { let it; try { it = fs.readdirSync(d, { withFileTypes: true }); } catch { return; } for (const e of it) { if (e.isDirectory()) { if (['_descartado', '.git', '__pycache__', '.obsidian'].includes(e.name)) continue; r(path.join(d, e.name)); } else if (e.name.endsWith('.md')) out.push(path.join(d, e.name)); } })(dir); return out; }
const readf = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
function frontmatter(txt) { const fm = {}; if (!txt || !txt.startsWith('---')) return fm; const end = txt.indexOf('\n---', 3); if (end < 0) return fm; for (const line of txt.slice(3, end).split('\n')) { const m = line.match(/^([a-zA-Z_]+):\s*(.*)$/); if (m) fm[m[1]] = m[2].trim(); } return fm; }
function findById(id) { for (const p of walk(BRAIN)) { const t = readf(p); if (frontmatter(t).id === id) return { p, t }; } return null; }
function logWrite(who, what) { try { const d = new Date().toISOString().slice(0, 10); fs.appendFileSync(LOG, `| ${d} | vps-mcp | ${who} | ${what} |\n`); } catch { } }

// ---- ferramentas ----
function t_buscar({ query }) { const q = (query || '').toLowerCase(); const res = []; for (const p of walk(BRAIN)) { const t = readf(p) || ''; const fm = frontmatter(t); if ((path.basename(p) + ' ' + t).toLowerCase().includes(q)) { const i = t.toLowerCase().indexOf(q); res.push({ id: fm.id || null, path: path.relative(BRAIN, p), tipo: fm.tipo, zona: fm.zona, snippet: i >= 0 ? t.slice(Math.max(0, i - 40), i + 90).replace(/\s+/g, ' ') : '' }); } if (res.length >= 20) break; } return { total: res.length, resultados: res }; }
function t_ler({ id }) { const f = findById(id); return f ? { id, path: path.relative(BRAIN, f.p), conteudo: f.t } : { error: `id '${id}' não encontrado` }; }
function t_listar({ filtro }) { const res = []; for (const p of walk(BRAIN)) { const fm = frontmatter(readf(p)); if (!fm.id) continue; if (filtro && fm.tipo !== filtro && fm.zona !== filtro) continue; res.push({ id: fm.id, tipo: fm.tipo, zona: fm.zona, path: path.relative(BRAIN, p) }); } return { total: res.length, paginas: res }; }
function t_debt() { const t = readf(path.join(BRAIN, '_debt.md')); return t ? { conteudo: t } : { error: '_debt.md ausente' }; }
function t_propor({ id, conteudo }, who) { const pid = 'prop-' + crypto.randomBytes(4).toString('hex'); const f = findById(id); const rec = { pid, id, zona: f ? frontmatter(f.t).zona : '?', who, ts: new Date().toISOString(), conteudo: String(conteudo || '') }; try { fs.mkdirSync(path.dirname(PROPOSALS), { recursive: true }); fs.appendFileSync(PROPOSALS, JSON.stringify(rec) + '\n'); } catch (e) { return { error: String(e).slice(0, 200) }; } logWrite(who, `PROPOSTA ${pid} p/ ${id} (${rec.zona})`); return { pid, status: 'na fila de aprovação do admin (Central do Córtex)' }; }
function t_escrever({ id, conteudo }, who) {
  if (!WRITE_ENABLED) return { refused: 'escrita DESLIGADA (CORTEX_WRITE_ENABLED=false, dial cauteloso). Usa cortex_propor.' };
  const f = findById(id); if (!f) return { refused: `id '${id}' não encontrado — não crio páginas novas por MCP nesta versão. Usa cortex_propor.` };
  if (frontmatter(f.t).zona === 'vermelha' || RED.test(String(conteudo))) return { refused: 'ZONA VERMELHA — recusado no servidor. Usa cortex_propor (vai à fila do admin).', redirect: 'cortex_propor' };
  try { fs.writeFileSync(f.p, String(conteudo)); } catch (e) { return { error: String(e).slice(0, 200) }; }
  logWrite(who, `ESCREVEU ${id}`);
  let pushed = false;
  if (GIT_PUSH) { try { const repo = path.resolve(BRAIN, '..', '..', '..'); execFileSync('git', ['-C', repo, 'add', path.relative(repo, f.p)]); execFileSync('git', ['-C', repo, 'commit', '-m', `cortex(mcp): ${who} atualizou ${id} [skip ci]`]); execFileSync('git', ['-C', repo, 'push']); pushed = true; } catch (e) { return { written: true, pushed: false, gitError: String(e).slice(0, 160) }; } }
  return { written: true, pushed };
}

const TOOL_DEFS = [
  { name: 'cortex_buscar', description: 'Procura no Córtex por nome+conteúdo. Devolve páginas com id/tipo/zona/snippet.', inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
  { name: 'cortex_ler', description: 'Devolve uma página do Córtex pelo id do frontmatter.', inputSchema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] } },
  { name: 'cortex_listar', description: 'Lista páginas; filtro opcional por tipo (service|conceito|decisao|licao|negocio) ou zona (verde|vermelha).', inputSchema: { type: 'object', properties: { filtro: { type: 'string' } } } },
  { name: 'cortex_debt', description: 'Devolve o _debt.md (cartão de dívida do cérebro).', inputSchema: { type: 'object', properties: {} } },
  { name: 'cortex_escrever', description: 'Escreve/atualiza uma página EXISTENTE — SÓ zona verde. Zona vermelha é recusada. Pode estar desligado (dial).', inputSchema: { type: 'object', properties: { id: { type: 'string' }, conteudo: { type: 'string' } }, required: ['id', 'conteudo'] } },
  { name: 'cortex_propor', description: 'Para zona 🔴 (ou quando não podes escrever): NÃO escreve, cria proposta na fila de aprovação do admin.', inputSchema: { type: 'object', properties: { id: { type: 'string' }, conteudo: { type: 'string' } }, required: ['id', 'conteudo'] } },
];
function dispatch(name, a, who) { switch (name) { case 'cortex_buscar': return t_buscar(a); case 'cortex_ler': return t_ler(a); case 'cortex_listar': return t_listar(a); case 'cortex_debt': return t_debt(a); case 'cortex_propor': return t_propor(a, who); case 'cortex_escrever': return t_escrever(a, who); default: return { error: 'ferramenta desconhecida: ' + name }; } }

// ---- MCP JSON-RPC ----
function handleRpc(m, who) {
  if (!m || m.id === undefined || m.id === null) return null; // notification -> sem resposta
  const ok = (result) => ({ jsonrpc: '2.0', id: m.id, result });
  if (m.method === 'initialize') return ok({ protocolVersion: (m.params && m.params.protocolVersion) || '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'cortex-bora', version: '1.0.0' } });
  if (m.method === 'ping') return ok({});
  if (m.method === 'tools/list') return ok({ tools: TOOL_DEFS });
  if (m.method === 'tools/call') { const p = m.params || {}; let out; try { out = dispatch(p.name, p.arguments || {}, who); } catch (e) { out = { error: String(e).slice(0, 200) }; } return ok({ content: [{ type: 'text', text: JSON.stringify(out) }] }); }
  return { jsonrpc: '2.0', id: m.id, error: { code: -32601, message: 'method not found: ' + m.method } };
}

const server = http.createServer((req, res) => {
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '?').toString().split(',')[0];
  const auth = req.headers['authorization'] || ''; const key = req.headers['x-api-key'] || '';
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (TOKEN && bearer !== TOKEN && key !== TOKEN) { res.writeHead(401, { 'content-type': 'application/json' }); return res.end(JSON.stringify({ error: 'unauthorized' })); }
  if (!rateOk(ip)) { res.writeHead(429, { 'content-type': 'text/plain' }); return res.end('rate limited'); }
  if (req.method === 'GET') { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(JSON.stringify({ server: 'cortex-bora', ok: true, write_enabled: WRITE_ENABLED })); }
  if (req.method !== 'POST') { res.writeHead(405).end(); return; }
  let body = ''; req.on('data', (c) => { body += c; if (body.length > 1e6) req.destroy(); });
  req.on('end', () => {
    let msg; try { msg = JSON.parse(body); } catch { res.writeHead(400, { 'content-type': 'text/plain' }); return res.end('bad json'); }
    const who = (msg && msg.params && msg.params.clientInfo && msg.params.clientInfo.name) || 'claude.ai';
    const out = Array.isArray(msg) ? msg.map((x) => handleRpc(x, who)).filter(Boolean) : handleRpc(msg, who);
    if (out === null || (Array.isArray(out) && out.length === 0)) { res.writeHead(202).end(); return; }
    res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(out));
  });
});
server.listen(PORT, () => console.log(`[cortex-mcp] :${PORT} brain=${BRAIN} write=${WRITE_ENABLED} push=${GIT_PUSH}`));
