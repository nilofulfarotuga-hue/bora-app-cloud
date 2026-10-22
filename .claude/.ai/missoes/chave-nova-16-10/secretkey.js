// secretkey.js — troca, em todas as Edge Functions, a leitura directa da chave de serviço
//   Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')  →  secretKey()
// e acrescenta `import { secretKey } from '../_shared/keys.ts'` quando falta.
// Missão chave-nova-16-10 (Bloco 2). Não toca em _shared/, _arquivo/, chaves-* nem em refund,
// finalize-order-from-intent, stripe-webhook e dispatch-engine (zona vermelha: ficam como proposta).
// Determinístico e idempotente; imprime o que mudou. Corre com: node secretkey.js [--dry]
const fs = require('fs');
const path = require('path');
const root = 'C:/BoraLocal/wt-chave-nova-16-10/supabase/functions';
const dry = process.argv.includes('--dry');
const SALTAR = new Set(['refund', 'finalize-order-from-intent', 'stripe-webhook', 'dispatch-engine', 'chaves-diagnostico', 'chaves-semear']);
const RE = /Deno\.env\.get\(\s*['"]SUPABASE_SERVICE_ROLE_KEY['"]\s*\)/g;
const dirs = fs.readdirSync(root).filter((d) => !d.startsWith('_') && fs.statSync(path.join(root, d)).isDirectory()).sort();
let alterados = 0, saltados = 0, semUso = 0;
for (const d of dirs) {
  const p = path.join(root, d, 'index.ts');
  if (!fs.existsSync(p)) continue;
  if (SALTAR.has(d)) { saltados++; console.log('salta    ' + d); continue; }
  const bruto = fs.readFileSync(p, 'utf8');
  const eol = bruto.includes('\r\n') ? '\r\n' : '\n';
  if (!RE.test(bruto)) { semUso++; continue; }
  RE.lastIndex = 0;
  let novo = bruto.replace(RE, 'secretKey()');
  const n = (bruto.match(RE) || []).length;
  if (!/from ['"]\.\.\/_shared\/keys\.ts['"]/.test(novo)) {
    const lines = novo.split(/\r?\n/);
    let ultimoImport = -1;
    for (let i = 0; i < Math.min(lines.length, 120); i++) if (/^import\s/.test(lines[i])) ultimoImport = i;
    if (ultimoImport >= 0) {
      const l = lines[ultimoImport];
      const semi = l.trimEnd().endsWith(';') ? ';' : '';
      const q = l.includes('"') && !l.includes("'") ? '"' : "'";
      lines.splice(ultimoImport + 1, 0, 'import { secretKey } from ' + q + '../_shared/keys.ts' + q + semi);
    } else {
      let i = 0;
      while (i < lines.length && (/^\s*\/\//.test(lines[i]) || lines[i].trim() === '')) i++;
      lines.splice(i, 0, "import { secretKey } from '../_shared/keys.ts';", '');
    }
    novo = lines.join(eol);
  }
  if (!dry) fs.writeFileSync(p, novo, 'utf8');
  alterados++;
  console.log((dry ? 'mudaria ' : 'alterado ') + d + ' (' + n + ' leitura(s))');
}
console.log('alterados=' + alterados + ' saltados=' + saltados + ' sem_uso=' + semUso + (dry ? ' (ensaio)' : ''));
