// livro-ao-acordar.mjs — gancho SessionStart do Claude Code (missão livro-comum-2026-10-23).
// Imprime páginas do LIVRO comum (public.claude_ai_memoria) para entrarem no contexto da sessão.
// Uso: node livro-ao-acordar.mjs erros   → erros-aprendidos + digest mais recente
//      node livro-ao-acordar.mjs regras  → regras-do-danilo
// Duas partes porque a saída de cada gancho acima de ~10 KB vai para ficheiro e não entra no contexto.
// Cache de 1 hora em ~/.claude/cache/livro/; sem rede usa a última cópia. Nunca imprime a chave.
// Vive fora de ~/.claude/hooks/ porque essa pasta é da tranca (bora-tranca) e recusa escrita.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const PARTE = (process.argv[2] || 'erros').toLowerCase();
const DIR = path.join(os.homedir(), '.claude', 'cache', 'livro');
const CACHE = path.join(DIR, `${PARTE}.md`);
const TTL_MS = 60 * 60 * 1000;
const LIMITE = 9500;
const ENVS = [
  process.env.BORA_LIVRO_ENV,
  'C:/BoraLocal/projetosflutter/bora_app/backend/.env',
].filter(Boolean);

function lerEnv() {
  for (const f of ENVS) {
    try {
      const e = {};
      for (const ln of fs.readFileSync(f, 'utf8').split(/\r?\n/)) {
        const m = ln.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
        if (m) e[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
      }
      const key = e.SUPABASE_SERVICE_ROLE_KEY || e.SUPABASE_SERVICE_KEY;
      if (e.SUPABASE_URL && key) return { url: e.SUPABASE_URL.replace(/\/$/, ''), key };
    } catch { /* tenta o próximo */ }
  }
  return null;
}

async function pedir(env, query) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 8000);
  try {
    const r = await fetch(`${env.url}/rest/v1/claude_ai_memoria?${query}`, {
      headers: { apikey: env.key, Authorization: `Bearer ${env.key}` }, signal: ctl.signal,
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.json();
  } finally { clearTimeout(t); }
}

function bloco(r, max) {
  if (!r) return '';
  let txt = (r.conteudo || '').trim();
  if (txt.length > max) txt = txt.slice(0, max) + '\n[... cortado; lê a página inteira no livro]';
  return `## [livro] ${r.pagina} — atualizada ${String(r.atualizado_em || '').slice(0, 16)}\n\n${txt}\n`;
}

async function gerar() {
  const env = lerEnv();
  if (!env) throw new Error('sem chave do Supabase no PC');
  const cab = `# LIVRO AO ACORDAR (${PARTE}) — páginas de public.claude_ai_memoria, lidas às ${new Date().toISOString().slice(0, 16)}Z\n` +
    'Ler antes de agir. Quando o Danilo te corrigir: skill aprender (select public.livro_aprender(...)). Índice: página livro-indice.\n\n';
  if (PARTE === 'regras') {
    const [r] = await pedir(env, 'select=pagina,conteudo,atualizado_em&pagina=eq.regras-do-danilo');
    if (!r) throw new Error('página regras-do-danilo não encontrada');
    return cab + bloco(r, LIMITE - cab.length - 200);
  }
  const [e] = await pedir(env, 'select=pagina,conteudo,atualizado_em&pagina=eq.erros-aprendidos');
  if (!e) throw new Error('página erros-aprendidos não encontrada');
  const [d] = await pedir(env, 'select=pagina,conteudo,atualizado_em&pagina=like.digest-*&order=atualizado_em.desc&limit=1');
  const parteE = bloco(e, 7000);
  const resto = LIMITE - cab.length - parteE.length - 200;
  return cab + parteE + (d ? '\n' + bloco(d, Math.max(600, resto)) : '');
}

let saida = '';
try {
  const st = fs.existsSync(CACHE) ? fs.statSync(CACHE) : null;
  if (st && process.argv[3] !== 'forcar' && Date.now() - st.mtimeMs < TTL_MS) {
    saida = fs.readFileSync(CACHE, 'utf8');
  } else {
    saida = await gerar();
    fs.mkdirSync(DIR, { recursive: true });
    fs.writeFileSync(CACHE, saida, 'utf8');
  }
} catch (err) {
  if (fs.existsSync(CACHE)) {
    saida = fs.readFileSync(CACHE, 'utf8') +
      `\n(Aviso: o livro não respondeu agora — ${err.message}. Esta é a última cópia guardada.)\n`;
  } else {
    saida = `LIVRO AO ACORDAR: não consegui ler o livro (${err.message}) e não há cópia guardada. Lê com o MCP Supabase: erros-aprendidos, regras-do-danilo, livro-indice.\n`;
  }
}
process.stdout.write(saida.slice(0, 9900));
