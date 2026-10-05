// Acompanha as corridas do GitHub Actions de um commit até acabarem (ou até ao limite).
// O token vem do ambiente (GH_T, tirado do Git Credential Manager) e nunca é impresso.
//   GH_T=... node vigiar_ci.mjs <sha> [minutos-maximo]
const sha = process.argv[2];
const limiteMin = Number(process.argv[3] ?? 70);
const t = process.env.GH_T;
if (!t || !sha) { console.log('falta o token ou o sha'); process.exit(2); }
const base = 'https://api.github.com/repos/nilofulfarotuga-hue/bora-app-cloud';
const h = { Authorization: `Bearer ${t}`, 'User-Agent': 'bora-ci', Accept: 'application/vnd.github+json' };
const esperar = (ms) => new Promise((r) => setTimeout(r, ms));
const hora = () => new Date().toLocaleTimeString('pt-PT', { timeZone: 'Europe/Lisbon' });

if (sha.length < 40) { console.log('o GitHub só filtra pelo sha COMPLETO (40 letras): com o curto devolve zero corridas'); process.exit(2); }
const inicio = Date.now();
let ultimo = null;
for (;;) {
  let runs = [];
  try {
    const r = await fetch(`${base}/actions/runs?head_sha=${sha}&per_page=10`, { headers: h });
    if (!r.ok) { console.log(hora(), 'github http', r.status); }
    else runs = (await r.json()).workflow_runs ?? [];
  } catch (e) { console.log(hora(), 'rede:', String(e).slice(0, 80)); }

  const linhas = [];
  for (const x of runs) {
    let jobs = [];
    try {
      const j = await fetch(`${base}/actions/runs/${x.id}/jobs?per_page=30`, { headers: h });
      if (j.ok) jobs = (await j.json()).jobs ?? [];
    } catch (_) {}
    const resumo = jobs.map((jb) => `${jb.name}=${jb.conclusion ?? jb.status}`).join(', ');
    linhas.push(`${x.name} #${x.run_number} (${x.id}) ${x.status}/${x.conclusion ?? '-'} :: ${resumo}`);
  }
  const estado = linhas.join(' || ');
  if (estado !== ultimo) { console.log(hora(), estado || 'ainda sem corridas para este commit'); ultimo = estado; }

  const todasFechadas = runs.length > 0 && runs.every((x) => x.status === 'completed');
  if (todasFechadas) { console.log(hora(), 'FIM: todas as corridas fecharam'); process.exit(runs.every((x) => x.conclusion === 'success' || x.conclusion === 'skipped') ? 0 : 1); }
  if ((Date.now() - inicio) / 60000 > limiteMin) { console.log(hora(), `LIMITE de ${limiteMin} min atingido, corridas ainda abertas`); process.exit(3); }
  await esperar(60000);
}
