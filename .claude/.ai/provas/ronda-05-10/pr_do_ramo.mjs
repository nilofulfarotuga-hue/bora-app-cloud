// Diz se já existe um pull request aberto para o ramo de produção (e quais).
// Só lê. O token vem do ambiente (GH_T) e nunca é impresso.
//   GH_T=... node pr_do_ramo.mjs [ramo]
const ramo = process.argv[2] ?? 'autonomous-night-2026-04-29';
const t = process.env.GH_T;
if (!t) { console.log('falta o token'); process.exit(2); }
const dono = 'nilofulfarotuga-hue';
const base = `https://api.github.com/repos/${dono}/bora-app-cloud`;
const h = { Authorization: `Bearer ${t}`, 'User-Agent': 'bora-ci', Accept: 'application/vnd.github+json' };

const r = await fetch(`${base}/pulls?state=all&head=${dono}:${encodeURIComponent(ramo)}&per_page=10`, { headers: h });
console.log('pulls http', r.status);
const prs = r.ok ? await r.json() : [];
console.log(`pull requests com cabeça em ${ramo}: ${prs.length}`);
for (const p of prs) {
  console.log(`#${p.number} ${p.state}${p.draft ? ' (rascunho)' : ''}${p.merged_at ? ' (fundido)' : ''} -> ${p.base.ref} :: ${p.title.slice(0, 80)} :: criado ${p.created_at}`);
}
const repo = await (await fetch(base, { headers: h })).json();
console.log('ramo por omissão do repositório:', repo.default_branch);
