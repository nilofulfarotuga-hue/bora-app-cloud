#!/usr/bin/env node
// Teste de regressão da PERSISTÊNCIA do estado OAuth (Parte 8 da missão sistema-redondo-2026-08-01).
//
// O que prova: um cliente registado + token emitido continuam válidos DEPOIS de o processo do
// servidor morrer e voltar — que é exactamente o que acontece a cada `deploy.sh` (server.mjs está
// baked na imagem, portanto todo o deploy faz `docker build` + `docker rm -f` + `docker run`).
// Antes deste fix, o Danilo tinha de religar o conector do claude.ai a cada redeploy.
//
// Corre o fluxo OAuth completo (DCR -> /authorize com PKCE -> /token), mata o servidor, arranca
// outro com o MESMO ficheiro de estado, e confirma que o access token antigo ainda autentica.
//
// Correr:  node _oauth_state_test.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'cortex-oauth-test-'));
const BRAIN = path.join(TMP, '.claude', '.ai', 'knowledge');
const FILA = path.join(TMP, 'orquestracao');
const STATE = path.join(TMP, 'state', 'oauth.json');
const PORT = 4501 + Math.floor(Math.random() * 300);
fs.mkdirSync(path.join(BRAIN, 'inbox', '_reports'), { recursive: true });
fs.mkdirSync(FILA, { recursive: true });

let fails = 0;
const check = (nome, cond, detalhe) => {
  console.log(`${cond ? '  OK  ' : ' FALHA'} | ${nome}${cond ? '' : '  -> ' + detalhe}`);
  if (!cond) fails++;
};
const b64url = (b) => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

let srv = null;
function arranca() {
  srv = spawn(process.execPath, [path.join(HERE, 'server.mjs')], {
    env: { ...process.env, PORT: String(PORT), CORTEX_BRAIN: BRAIN, CORTEX_FILA: FILA, CORTEX_OAUTH_STATE: STATE, CORTEX_TOKEN: '', CORTEX_WRITE_ENABLED: 'false', CORTEX_GIT_PUSH: 'false', CORTEX_ISSUER: `http://127.0.0.1:${PORT}` },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  srv.stderr.on('data', (d) => { const s = String(d); if (/\[oauth\]/.test(s)) process.stdout.write('       [servidor] ' + s.trim() + '\n'); });
}
async function mata() {
  if (!srv) return;
  try { srv.stderr.removeAllListeners('data'); srv.stderr.destroy(); } catch { }
  srv.kill(); srv = null;
  await new Promise((r) => setTimeout(r, 250));
}
const espera = async () => {
  for (let i = 0; i < 60; i++) {
    try { const r = await fetch(`http://127.0.0.1:${PORT}/.well-known/oauth-protected-resource`); if (r.ok) return true; } catch { }
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
};
const mcpComToken = async (tok) => (await fetch(`http://127.0.0.1:${PORT}/mcp`, {
  method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + tok },
  body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping', params: {} }),
})).status;

try {
  // ---- 1ª vida do servidor: fluxo OAuth completo -------------------------
  arranca();
  if (!(await espera())) { console.error('servidor nao arrancou'); process.exit(1); }

  const reg = await (await fetch(`http://127.0.0.1:${PORT}/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ redirect_uris: ['http://127.0.0.1:9999/cb'] }),
  })).json();
  check('DCR devolve client_id', !!reg.client_id, JSON.stringify(reg));

  const verifier = b64url(crypto.randomBytes(32));
  const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
  const authRes = await fetch(`http://127.0.0.1:${PORT}/authorize?response_type=code&client_id=${reg.client_id}`
    + `&redirect_uri=${encodeURIComponent('http://127.0.0.1:9999/cb')}&code_challenge=${challenge}&code_challenge_method=S256`,
    { redirect: 'manual' });
  const code = new URL(authRes.headers.get('location')).searchParams.get('code');
  check('/authorize devolve um code', !!code, 'status=' + authRes.status);

  const tk = await (await fetch(`http://127.0.0.1:${PORT}/token`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: 'http://127.0.0.1:9999/cb', code_verifier: verifier, client_id: reg.client_id }),
  })).json();
  check('/token devolve access + refresh', !!tk.access_token && !!tk.refresh_token, JSON.stringify(tk).slice(0, 120));
  check('o token autentica no /mcp', (await mcpComToken(tk.access_token)) === 200, 'x');

  await new Promise((r) => setTimeout(r, 800));   // deixa o debounce de 500ms gravar
  check('ficheiro de estado foi criado', fs.existsSync(STATE), STATE);
  const disco = JSON.parse(fs.readFileSync(STATE, 'utf8'));
  check('estado guarda o cliente e o token', !!disco.clients[reg.client_id] && !!disco.tokens[tk.access_token], Object.keys(disco).join(','));

  // ---- morte e ressurreição (== o que o deploy.sh faz) -------------------
  await mata();
  check('sem servidor, o /mcp nao responde', await (async () => { try { await mcpComToken(tk.access_token); return false; } catch { return true; } })(), 'x');

  arranca();
  if (!(await espera())) { console.error('servidor nao voltou'); process.exit(1); }

  check('DEPOIS DO REDEPLOY: o access token antigo continua a autenticar',
    (await mcpComToken(tk.access_token)) === 200, 'o conector ficaria deslogado');

  const novo = await (await fetch(`http://127.0.0.1:${PORT}/token`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: tk.refresh_token }),
  })).json();
  check('DEPOIS DO REDEPLOY: o refresh token antigo ainda troca por access novo', !!novo.access_token, JSON.stringify(novo).slice(0, 120));
  check('o access novo tambem autentica', (await mcpComToken(novo.access_token)) === 200, 'x');
  check('um token inventado continua a levar 401', (await mcpComToken('token-falso-qualquer')) === 401, 'x');

  // ---- estado ilegível não pode derrubar o servidor ----------------------
  await mata();
  fs.writeFileSync(STATE, '{ isto nao e json valido');
  arranca();
  check('estado corrompido nao impede o arranque', await espera(), 'servidor nao arrancou com estado corrompido');
  check('com estado corrompido, tokens antigos deixam de valer (fail-closed)', (await mcpComToken(tk.access_token)) === 401, 'x');
} finally {
  await mata();
  try { fs.rmSync(TMP, { recursive: true, force: true }); } catch { }
}

console.log(fails === 0 ? '\nTODOS OS CASOS PASSARAM' : `\n${fails} CASO(S) FALHARAM`);
process.exit(fails === 0 ? 0 : 1);
