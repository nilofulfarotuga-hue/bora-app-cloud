// Estado, num só tiro, das últimas corridas do ramo de produção no GitHub Actions.
// As horas são as do GitHub (UTC). O token vem do ambiente (GH_T) e nunca é impresso.
//   GH_T=... node estado_ci.mjs [ramo] [quantas]
const ramo = process.argv[2] ?? 'autonomous-night-2026-04-29';
const quantas = Number(process.argv[3] ?? 14);
const t = process.env.GH_T;
if (!t) { console.log('falta o token'); process.exit(2); }
const base = 'https://api.github.com/repos/nilofulfarotuga-hue/bora-app-cloud';
const h = { Authorization: `Bearer ${t}`, 'User-Agent': 'bora-ci', Accept: 'application/vnd.github+json' };

const r = await fetch(`${base}/actions/runs?branch=${encodeURIComponent(ramo)}&per_page=${quantas}`, { headers: h });
if (!r.ok) { console.log('github http', r.status); process.exit(1); }
const runs = (await r.json()).workflow_runs ?? [];
console.log('agora (UTC):', new Date().toISOString());
for (const x of runs) {
  let resumo = '';
  if (/android|ios/i.test(x.name)) {
    const j = await fetch(`${base}/actions/runs/${x.id}/jobs?per_page=30`, { headers: h });
    if (j.ok) resumo = ((await j.json()).jobs ?? []).map((jb) => `${jb.name}=${jb.conclusion ?? jb.status}`).join(', ');
  }
  const titulo = (x.head_commit?.message ?? '').split('\n')[0].slice(0, 56);
  console.log(`${x.created_at} ${x.name} #${x.run_number} (${x.id}) t${x.run_attempt} ${x.head_sha.slice(0, 8)} ${x.status}/${x.conclusion ?? '-'} "${titulo}"${resumo ? ' :: ' + resumo : ''}`);
}
