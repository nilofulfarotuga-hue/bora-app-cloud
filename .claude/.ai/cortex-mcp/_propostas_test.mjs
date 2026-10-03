#!/usr/bin/env node
// Teste de regressão das ferramentas cortex_propostas_pendentes / cortex_aprovar_proposta
// (Parte 2 da missão sistema-redondo-2026-08-01).
//
// Sobe o server.mjs REAL num porto efémero, com um BRAIN/FILA temporários e um proposals.jsonl
// de fixture, e fala com ele por HTTP (JSON-RPC) tal como o conector do claude.ai fala.
// Não toca no Córtex verdadeiro nem na fila verdadeira.
//
// Correr:  node _propostas_test.mjs
// Sai 0 se tudo passar, 1 se algum caso falhar.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'cortex-prop-test-'));
const BRAIN = path.join(TMP, '.claude', '.ai', 'knowledge');
const FILA = path.join(TMP, 'orquestracao');
const PORT = 4871 + Math.floor(Math.random() * 200);
const TOKEN = 'tok-teste-' + Math.random().toString(16).slice(2);

let fails = 0;
const check = (nome, cond, detalhe) => {
  console.log(`${cond ? '  OK  ' : ' FALHA'} | ${nome}${cond ? '' : '  -> ' + detalhe}`);
  if (!cond) fails++;
};

// ---- fixture -------------------------------------------------------------
fs.mkdirSync(path.join(BRAIN, 'inbox', '_reports'), { recursive: true });
fs.mkdirSync(FILA, { recursive: true });
const PROPOSALS = path.join(BRAIN, 'inbox', '_reports', 'proposals.jsonl');
const fixture = [
  // 1. pendente, ordem de orquestração vermelha (o caso da prop-85cf635b)
  { pid: 'prop-11111111', id: 'ordem-20260801071337-3cb4', tipo: 'ordem_orquestracao', zona: 'vermelha',
    tarefa: 'Audita as Edge Functions e NAO mexas em pricing nem no dispatch_engine.', who: 'claude.ai', ts: '2026-08-01T07:13:37Z' },
  // 2. pendente, proposta de edição do Córtex (usa 'conteudo', não 'tarefa')
  { pid: 'prop-22222222', id: 'licao-qualquer', zona: 'vermelha', conteudo: 'texto novo da pagina',
    who: 'claude.ai', ts: '2026-08-01T07:20:00Z' },
  // 3. JÁ aprovada na Central (o ficheiro -aprovado.md existe) -> não pode aparecer como pendente
  { pid: 'prop-33333333', id: 'ordem-ja-feita', tipo: 'ordem_orquestracao', zona: 'vermelha',
    tarefa: 'tarefa que ja foi aprovada na Central', who: 'claude.ai', ts: '2026-08-01T07:25:00Z' },
  // 4. sem texto nenhum -> aprovar tem de recusar
  { pid: 'prop-44444444', id: 'ordem-vazia', zona: 'vermelha', tarefa: '   ', who: 'claude.ai', ts: '2026-08-01T07:30:00Z' },
  // 5. linha corrompida é ignorada (a seguir, escrita à mão)
];
fs.writeFileSync(PROPOSALS, fixture.map((r) => JSON.stringify(r)).join('\n') + '\n{ isto nao e json\n');
fs.writeFileSync(path.join(FILA, 'ordem-ja-feita-aprovado.md'), '--- ordem ---\nid: ordem-ja-feita-aprovado\n--- fim ---\n');

// ---- servidor ------------------------------------------------------------
const srv = spawn(process.execPath, [path.join(HERE, 'server.mjs')], {
  env: { ...process.env, PORT: String(PORT), CORTEX_BRAIN: BRAIN, CORTEX_FILA: FILA, CORTEX_TOKEN: TOKEN, CORTEX_WRITE_ENABLED: 'false', CORTEX_GIT_PUSH: 'false' },
  stdio: ['ignore', 'pipe', 'pipe'],
});
srv.stderr.on('data', (d) => process.stderr.write('[server] ' + d));

const rpc = async (method, params) => {
  const r = await fetch(`http://127.0.0.1:${PORT}/mcp`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: 'Bearer ' + TOKEN },
    body: JSON.stringify({ jsonrpc: '2.0', id: Math.floor(Math.random() * 1e6), method, params }),
  });
  const j = await r.json();
  if (j.error) throw new Error(JSON.stringify(j.error));
  if (j.result && j.result.content) return JSON.parse(j.result.content[0].text);
  return j.result;
};

const esperaPorta = async () => {
  for (let i = 0; i < 60; i++) {
    try { await rpc('ping', {}); return true; } catch { await new Promise((r) => setTimeout(r, 100)); }
  }
  return false;
};

try {
  if (!(await esperaPorta())) { console.error('servidor nao arrancou em 6s'); process.exit(1); }

  // --- A: as ferramentas estão declaradas -------------------------------
  const nomes = (await rpc('tools/list', {})).tools.map((t) => t.name);
  check('cortex_propostas_pendentes declarada em tools/list', nomes.includes('cortex_propostas_pendentes'), nomes.join(','));
  check('cortex_aprovar_proposta declarada em tools/list', nomes.includes('cortex_aprovar_proposta'), nomes.join(','));

  const call = (name, args) => rpc('tools/call', { name, arguments: args || {} });

  // --- B: listar ---------------------------------------------------------
  const lista = await call('cortex_propostas_pendentes', {});
  const pids = lista.propostas.map((p) => p.pid);
  check('lista devolve as 3 pendentes', lista.total_pendentes === 3, JSON.stringify(pids));
  check('linha JSON corrompida é ignorada (nao rebenta)', lista.total_no_ficheiro === 4, 'total=' + lista.total_no_ficheiro);
  check('proposta ja aprovada na Central NAO aparece como pendente', !pids.includes('prop-33333333'), JSON.stringify(pids));
  check('proposta ja aprovada aparece em ja_encaminhadas(via=central)',
    lista.ja_encaminhadas.some((p) => p.pid === 'prop-33333333' && p.encaminhada_via === 'central'), JSON.stringify(lista.ja_encaminhadas));
  check('mais recentes primeiro', pids[0] === 'prop-44444444', JSON.stringify(pids));
  check('le o texto de "conteudo" quando nao ha "tarefa"',
    lista.propostas.find((p) => p.pid === 'prop-22222222')?.tarefa === 'texto novo da pagina', 'x');
  check('limite é respeitado', (await call('cortex_propostas_pendentes', { limite: 1 })).propostas.length === 1, 'x');

  // --- C: aprovar --------------------------------------------------------
  const ap = await call('cortex_aprovar_proposta', { pid: 'prop-11111111' });
  const dest = path.join(FILA, 'ordem-20260801071337-3cb4-aprovado-chat.md');
  check('aprovar cria o ficheiro da ordem na fila', fs.existsSync(dest), dest);
  const md = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf8') : '';
  // Estrito de propósito: nem como campo do frontmatter, nem sequer em prosa — para que um
  // `grep audit_id` a jusante nunca dê falso-positivo neste ficheiro.
  check('a ordem NAO leva audit_id (barreira do dinheiro intacta)', !/audit_id/.test(md), md.slice(0, 200));
  check('a ordem NAO leva autorizado_por_admin', !/autorizado_por_admin/.test(md), md.slice(0, 200));
  check('a ordem nasce aberta', /^estado: aberta$/m.test(md), md.slice(0, 200));
  check('a tarefa vai numa unica linha (frontmatter nao parte)',
    (md.match(/^tarefa: .*$/m) || [''])[0].includes('NAO mexas em pricing'), 'x');
  check('resposta aponta o pid e a ordem', ap.aprovada === 'prop-11111111' && /-aprovado-chat$/.test(ap.ordem_id), JSON.stringify(ap));

  // --- D: idempotência e recusas ----------------------------------------
  const ap2 = await call('cortex_aprovar_proposta', { pid: 'prop-11111111' });
  check('aprovar 2x é idempotente (nao duplica ordem)', ap2.ja_encaminhada === true && ap2.via === 'chat', JSON.stringify(ap2));
  const nOrdens = fs.readdirSync(FILA).filter((f) => f.includes('3cb4')).length;
  check('so existe 1 ficheiro para essa proposta', nOrdens === 1, 'n=' + nOrdens);

  const jaCentral = await call('cortex_aprovar_proposta', { pid: 'prop-33333333' });
  check('nao cria 2a ordem para o que a Central ja aprovou', jaCentral.ja_encaminhada === true && jaCentral.via === 'central', JSON.stringify(jaCentral));

  check('recusa pid inexistente', !!(await call('cortex_aprovar_proposta', { pid: 'prop-99999999' })).error, 'x');
  check('recusa tarefa vazia', !!(await call('cortex_aprovar_proposta', { pid: 'prop-44444444' })).error, 'x');
  check('recusa pid mal formado', !!(await call('cortex_aprovar_proposta', { pid: 'nao-e-um-pid' })).error, 'x');
  // path traversal: o pid nunca pode escapar da FILA
  check('recusa pid com travessia de caminho', !!(await call('cortex_aprovar_proposta', { pid: '../../etc/passwd' })).error, 'x');

  // --- E: a listagem passa a mostrar a aprovada como encaminhada ---------
  const lista2 = await call('cortex_propostas_pendentes', {});
  check('depois de aprovada sai das pendentes', !lista2.propostas.map((p) => p.pid).includes('prop-11111111'), JSON.stringify(lista2.propostas.map((p) => p.pid)));
  check('e aparece como encaminhada via chat',
    lista2.ja_encaminhadas.some((p) => p.pid === 'prop-11111111' && p.encaminhada_via === 'chat'), 'x');

  // --- F: auth continua a ser exigida ------------------------------------
  const semToken = await fetch(`http://127.0.0.1:${PORT}/mcp`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'cortex_propostas_pendentes', arguments: {} } }),
  });
  check('sem token -> 401 (as ferramentas novas nao sao publicas)', semToken.status === 401, 'status=' + semToken.status);
} finally {
  // Fechar o pipe do stderr ANTES do kill: no Windows, matar o filho com o pipe ainda ligado
  // faz o libuv rebentar com "Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)" e o
  // processo sai 127, mascarando o resultado real dos testes.
  try { srv.stderr.removeAllListeners('data'); srv.stderr.destroy(); } catch { }
  srv.kill();
  await new Promise((r) => setTimeout(r, 150));
  try { fs.rmSync(TMP, { recursive: true, force: true }); } catch { }
}

console.log(fails === 0 ? '\nTODOS OS CASOS PASSARAM' : `\n${fails} CASO(S) FALHARAM`);
process.exit(fails === 0 ? 0 : 1);
