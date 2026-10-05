// Volta a correr os jobs que falharam numa corrida do GitHub Actions.
// Usado a 05/10/2026: o autoteste falhou às 08h20 porque a Auchan só abre às 09h00
// (carrinho travado com a loja fechada) — não por causa do código.
//   GH_T=... node relancar_ci.mjs <run_id>
const run = process.argv[2];
const t = process.env.GH_T;
const base = 'https://api.github.com/repos/nilofulfarotuga-hue/bora-app-cloud';
const h = { Authorization: `Bearer ${t}`, 'User-Agent': 'bora-ci', Accept: 'application/vnd.github+json' };
const r = await fetch(`${base}/actions/runs/${run}/rerun-failed-jobs`, { method: 'POST', headers: h });
console.log('rerun-failed-jobs http', r.status, (await r.text()).slice(0, 200));
const d = await (await fetch(`${base}/actions/runs/${run}`, { headers: h })).json();
console.log('corrida', d.name, '#' + d.run_number, 'tentativa', d.run_attempt, d.status, d.conclusion ?? '-');
