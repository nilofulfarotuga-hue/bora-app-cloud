// Helper ad-hoc: INSERT literal em e2e_log via REST (service role). Uso:
//   node _insert_e2e_log.js <fluxo> <run_id> <passo> <estado> <ficheiro-com-detalhe|-> [device]
// O detalhe vem de um ficheiro (para conteudo literal grande, sem escaping de shell)
// ou de stdin se o argumento for "-".
const fs = require('fs');
const path = require('path');

function loadEnv(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*"?([^"#]+)/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const env = { ...loadEnv(path.join(repoRoot, '.claude', 'testes-e2e', '.env')), ...process.env };
const url = env.SUPABASE_URL;
const key = env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('faltam SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY'); process.exit(1); }

const [fluxo, run_id, passo, estado, detalheArg, device] = process.argv.slice(2);
if (!fluxo || !run_id || !passo || !estado || !detalheArg) {
  console.error('uso: node _insert_e2e_log.js <fluxo> <run_id> <passo> <estado> <ficheiro|-> [device]');
  process.exit(1);
}
const detalhe = detalheArg === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(detalheArg, 'utf8');

const body = JSON.stringify([{ fluxo, run_id, passo, estado, detalhe, device: device || 'executor-opus' }]);

const req = require('https').request(url.replace(/\/$/, '') + '/rest/v1/e2e_log', {
  method: 'POST',
  headers: {
    'apikey': key,
    'Authorization': `Bearer ${key}`,
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  },
}, (res) => {
  let data = '';
  res.on('data', (c) => (data += c));
  res.on('end', () => {
    console.log('HTTP', res.statusCode);
    console.log(data);
  });
});
req.on('error', (e) => { console.error(e); process.exit(1); });
req.write(body);
req.end();
