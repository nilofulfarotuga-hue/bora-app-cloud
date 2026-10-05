// Lê os passos e o registo do job que falhou numa corrida do GitHub Actions e
// mostra só as linhas que interessam. O token vem do ambiente e nunca é impresso.
//   GH_T=... node ler_falha_ci.mjs <run_id> [filtro-regex]
import fs from 'node:fs';
const run = process.argv[2];
const filtro = new RegExp(process.argv[3] ??
  'não apareceu|nao apareceu|EXCEPTION|Exception|══╡|The following|Test failed|FALHOU|falhou|exigir|foto:|Some tests failed|\\[E\\]|Error:|RangeError|Null check|setState|dispose|carrinho|pagamento|ecra-', 'i');
const t = process.env.GH_T;
const base = 'https://api.github.com/repos/nilofulfarotuga-hue/bora-app-cloud';
const h = { Authorization: `Bearer ${t}`, 'User-Agent': 'bora-ci', Accept: 'application/vnd.github+json' };

const jobs = (await (await fetch(`${base}/actions/runs/${run}/jobs?per_page=30`, { headers: h })).json()).jobs ?? [];
for (const j of jobs) {
  console.log(`JOB ${j.name} :: ${j.status}/${j.conclusion} (${j.started_at} -> ${j.completed_at})`);
  for (const s of j.steps ?? []) {
    if (s.conclusion !== 'success' && s.conclusion !== 'skipped') console.log(`   passo ${s.number} "${s.name}": ${s.conclusion}`);
  }
  if (j.conclusion !== 'failure') continue;
  const r = await fetch(`${base}/actions/jobs/${j.id}/logs`, { headers: h, redirect: 'follow' });
  const texto = await r.text();
  fs.writeFileSync(process.env.SAIDA ?? 'job_falhado.log', texto);
  const linhas = texto.split('\n').map((l) => l.replace(/^\S+Z /, '').replace(/\x1b\[[0-9;]*m/g, ''));
  console.log(`   registo: ${linhas.length} linhas; a mostrar as que batem no filtro (máx. 70, as últimas)`);
  const bate = linhas.filter((l) => filtro.test(l));
  for (const l of bate.slice(-70)) console.log('   | ' + l.slice(0, 230));
}
