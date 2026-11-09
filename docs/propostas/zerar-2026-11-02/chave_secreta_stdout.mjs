// Escreve no stdout (para um pipe, nunca para o ecra) a chave secreta nova "default" do projeto.
const tok = process.env.SUPABASE_ACCESS_TOKEN;
if (!tok) process.exit(2);
const r = await fetch('https://api.supabase.com/v1/projects/ojykpzwqrtusfeakzrna/api-keys?reveal=true', {
  headers: { Authorization: `Bearer ${tok}` },
});
if (!r.ok) process.exit(3);
const k = (await r.json()).find((x) => x.type === 'secret' && x.name === 'default');
const v = String(k?.api_key ?? '');
if (!v.startsWith('sb_secret_')) process.exit(4);
process.stdout.write(v + '\n');
