// Copia a memória automática do Claude Code (PC) para a página livro-claude-code-aprendeu do livro.
// Uma linha por memória: nome — descrição (sem o corpo, para não levar detalhes nem dados pessoais).
// Missão livro-comum-2026-10-23. Corre à mão ou pelo renovar-livro.cmd.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const DIR = path.join(os.homedir(), '.claude', 'projects', 'C--BoraLocal-projetosflutter-bora-app', 'memory');
const ENVF = 'C:/BoraLocal/projetosflutter/bora_app/backend/.env';
const SEGREDO = /(sk_live_|sk_test_|sb_secret_|eyJhbGciOi|ghp_[A-Za-z0-9]{20}|AIza[0-9A-Za-z_-]{30}|PRIVATE KEY)/;

const e = {};
for (const ln of fs.readFileSync(ENVF, 'utf8').split(/\r?\n/)) {
  const m = ln.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (m) e[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
}
const key = e.SUPABASE_SERVICE_ROLE_KEY;
const linhas = [];
for (const f of fs.readdirSync(DIR).sort()) {
  if (!f.endsWith('.md') || f === 'MEMORY.md') continue;
  const t = fs.readFileSync(path.join(DIR, f), 'utf8');
  const nome = (t.match(/^name:\s*(.+)$/m) || [, f.replace(/\.md$/, '')])[1].trim();
  const desc = (t.match(/^description:\s*(.+)$/m) || [, ''])[1].trim().replace(/^["']|["']$/g, '');
  const tipo = (t.match(/^\s*type:\s*(\w+)/m) || [, ''])[1];
  const ln = `- ${nome} [${tipo}] — ${desc}`;
  if (!SEGREDO.test(ln)) linhas.push(ln);
}
const hoje = new Date().toISOString().slice(0, 10);
const conteudo = `# O que o Claude Code aprendeu sozinho (memória automática do PC, cópia de ${hoje})\n\n` +
  `Uma linha por memória (nome [tipo] — descrição). O texto inteiro vive em ~/.claude/projects/C--BoraLocal-projetosflutter-bora-app/memory/<nome>.md no PC. ` +
  `A Claude.ai lê e funde no livro o que valer.\n\nTotal: ${linhas.length}\n\n${linhas.join('\n')}\n`;
const r = await fetch(`${e.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/claude_ai_memoria?on_conflict=pagina`, {
  method: 'POST',
  headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
  body: JSON.stringify([{ pagina: 'livro-claude-code-aprendeu', titulo: 'O que o Claude Code aprendeu sozinho (memória automática do PC), cópia', conteudo, origem: 'claude-code', atualizado_em: new Date().toISOString() }]),
});
console.log(r.ok ? `OK livro-claude-code-aprendeu ${linhas.length} memórias, ${conteudo.length} caracteres` : `FALHOU HTTP ${r.status} ${await r.text()}`);
