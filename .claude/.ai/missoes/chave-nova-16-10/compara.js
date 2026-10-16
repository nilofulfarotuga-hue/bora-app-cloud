// compara.js <slug> <ficheiro-com-o-que-esta-no-ar>
//
// Compara, byte a byte (CRLF normalizado), a Edge Function que está NO AR com a do repositório.
// O ficheiro "do ar" pode ser:
//   - o resultado do MCP get_edge_function guardado em disco (JSON com "files": [{name, content}])
//   - ou o index.ts em bruto.
// Guarda a cópia do ar em .claude/.ai/missoes/chave-nova-16-10/_ar/<slug>/ e imprime
// "IGUAL" ou "DIFERE" com um diff curto. Nunca altera o repositório.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const [slug, arq] = process.argv.slice(2);
if (!slug || !arq) { console.log('uso: node compara.js <slug> <ficheiro>'); process.exit(2); }
const root = 'C:/BoraLocal/wt-chave-nova-16-10';
const fx = path.join(root, 'supabase/functions');
const pastaAr = path.join(root, '.claude/.ai/missoes/chave-nova-16-10/_ar', slug);
fs.mkdirSync(pastaAr, { recursive: true });

let raw = fs.readFileSync(arq, 'utf8');
let files = null;
try {
  let o = JSON.parse(raw);
  if (Array.isArray(o) && o[0] && typeof o[0].text === 'string') o = JSON.parse(o[0].text);
  if (o && o.files) files = o.files;
  else if (o && o.result && o.result.files) files = o.result.files;
} catch (_) { /* nao e JSON: tratar como index.ts em bruto */ }
if (!files) files = [{ name: 'index.ts', content: raw }];

const norm = (s) => s.replace(/\r\n/g, '\n').replace(/\s+$/, '') + '\n';
let difere = false;
for (const f of files) {
  const nome = String(f.name || 'index.ts').replace(/\\/g, '/');
  // mapear o nome que vem do ar para o caminho local
  let local;
  const base = path.basename(nome);
  if (nome.includes('_shared/')) local = path.join(fx, '_shared', base);
  else if (/(^|\/)index\.ts$/.test(nome) || files.length === 1) local = path.join(fx, slug, 'index.ts');
  else local = path.join(fx, slug, base);
  const destino = path.join(pastaAr, nome.includes('_shared/') ? '_shared_' + base : base);
  fs.writeFileSync(destino, f.content, 'utf8');
  if (!fs.existsSync(local)) { console.log(`DIFERE ${slug}/${base}: nao existe no repo (${local})`); difere = true; continue; }
  const a = norm(fs.readFileSync(local, 'utf8'));
  const b = norm(f.content);
  if (a === b) { console.log(`IGUAL  ${slug}/${base} (${b.split('\n').length - 1} linhas)`); continue; }
  difere = true;
  const tmpA = path.join(pastaAr, '.repo_' + base), tmpB = path.join(pastaAr, '.ar_' + base);
  fs.writeFileSync(tmpA, a); fs.writeFileSync(tmpB, b);
  let diff = '';
  try { execSync(`git diff --no-index --no-color -U1 -- "${tmpA}" "${tmpB}"`, { cwd: root }); }
  catch (e) { diff = e.stdout ? e.stdout.toString() : String(e); }
  const linhas = diff.split('\n');
  const mais = linhas.filter((l) => l.startsWith('+') && !l.startsWith('+++')).length;
  const menos = linhas.filter((l) => l.startsWith('-') && !l.startsWith('---')).length;
  console.log(`DIFERE ${slug}/${base}: repo ${a.split('\n').length - 1} linhas, ar ${b.split('\n').length - 1} linhas; +${mais} -${menos} (ar vs repo)`);
  console.log(linhas.slice(4, 4 + 70).join('\n'));
  if (linhas.length > 74) console.log(`… (+${linhas.length - 74} linhas de diff; ficheiro do ar em ${destino})`);
}
process.exit(difere ? 1 : 0);
