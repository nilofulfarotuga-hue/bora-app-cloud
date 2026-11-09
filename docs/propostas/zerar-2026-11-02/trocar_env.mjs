// Le a chave nova do stdin e troca o valor de SUPABASE_SERVICE_ROLE_KEY nos ficheiros dados.
// Copia <ficheiro>.bak-legada-20261102 antes. Imprime so prefixos.
import fs from 'node:fs';
const nova = fs.readFileSync(0, 'utf8').split(/\r?\n/)[0].trim();
if (!nova.startsWith('sb_secret_')) { console.log('chave invalida'); process.exit(2); }
const nome = 'SUPABASE_SERVICE_ROLE_KEY';
for (const c of process.argv.slice(2)) {
  const linhas = fs.readFileSync(c, 'utf8').split('\n');
  let n = 0; let antes = '';
  for (let i = 0; i < linhas.length; i++) {
    if (linhas[i].startsWith(nome + '=')) {
      antes = linhas[i].slice(nome.length + 1, nome.length + 11);
      linhas[i] = `${nome}=${nova}${linhas[i].endsWith('\r') ? '\r' : ''}`;
      n++;
    }
  }
  if (!n) { console.log(c, 'sem a variavel'); continue; }
  fs.copyFileSync(c, c + '.bak-legada-20261102');
  fs.writeFileSync(c, linhas.join('\n'));
  console.log(c, `linhas=${n}`, `antes=${antes}...`, `depois=${nova.slice(0, 10)}...`);
}
