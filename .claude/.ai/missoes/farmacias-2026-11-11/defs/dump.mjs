import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
const nomes = process.argv.slice(2);
const sql = `select p.proname, pg_get_function_identity_arguments(p.oid) args, pg_get_functiondef(p.oid) def from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in (${nomes.map(n=>`'${n}'`).join(',')}) order by 1,2`;
const out = execSync(`npx supabase db query --remote=ojykpzwqrtusfeakzrna --read-only --output-format json "${sql.replace(/"/g,'\\"')}"`, { encoding: 'utf8', maxBuffer: 64*1024*1024 });
const j = JSON.parse(out.slice(out.indexOf('{')));
const rows = j.rows ?? j.result ?? j.data ?? Object.values(j).find(Array.isArray);
const cnt = {};
for (const r of rows) { cnt[r.proname]=(cnt[r.proname]||0)+1; const f = `${r.proname}${cnt[r.proname]>1?'_'+cnt[r.proname]:''}.sql`; writeFileSync(f, r.def + ';\n'); console.log(f, r.args, r.def.length); }
