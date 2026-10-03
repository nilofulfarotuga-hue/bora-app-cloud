// F1.6 — validação das zonas vermelhas RED/RED_ORDER em server.mjs
// Lê o source de server.mjs e extrai as regex RED e RED_ORDER dinamicamente
// (sem drift), depois testa casos MATCH/NOMATCH.
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '../../..');
const src = fs.readFileSync(path.join(root, '.claude/.ai/cortex-mcp/server.mjs'), 'utf8');
const lines = src.split('\n');

function grabRegex(varName) {
  const line = lines.find(l => new RegExp(`const ${varName} = /`).test(l));
  if (!line) throw new Error(`var ${varName} não encontrada em server.mjs`);
  // pega entre a primeira '/' após '=' e a '/' imediatamente antes de 'i;'
  const m = line.match(new RegExp(`const ${varName} = /(.*)/i`));
  if (!m) throw new Error(`regex ${varName} não parseada`);
  return m[1];
}

const RED_SRC = grabRegex('RED');
const RED_ORDER_SRC = grabRegex('RED_ORDER');
console.log('RED_SRC      =', RED_SRC);
console.log('RED_ORDER_SRC=', RED_ORDER_SRC);

const RED = new RegExp(RED_SRC, 'i');
const RED_ORDER = new RegExp(RED_ORDER_SRC, 'i');

let pass = 0, fail = 0;
function t(desc, regex, word, expected) {
  const got = regex.test(word) ? 'MATCH' : 'NOMATCH';
  if (got === expected) { pass++; console.log(`PASS [${got}]    ${desc}`); }
  else { fail++; console.log(`FAIL [want=${expected} got=${got}] ${desc}`); }
}

console.log('\n=== RED (conteudo propostas) ===');
const redMatch = ['dispatch','pricing','finalizepurchase','bora_tokens','stripe','wallet','ledger','refund','comissao','markup','service_fee','disable rls on cortex'];
for (const w of redMatch) t(`RED match ' ${w}'`, RED, w, 'MATCH');

console.log('\n=== RED_ORDER (ordens vermelhas) ===');
const redOrderMatch = ['dispatch_engine','dispatch','pricing','finalizepurchase','bora_tokens','stripe','payment','webhook','wallet','ledger','refund','payout','comiss','commission','markup','service_fee','platform_settings','rls','force push','forcepush'];
for (const w of redOrderMatch) t(`RED_ORDER match ' ${w}'`, RED_ORDER, w, 'MATCH');

console.log('\n=== Nomatch (termos neutros) ===');
const neutros = ['user-notifications','appointments','finish a ride','update profile','read inbox','hello world'];
for (const w of neutros) t(`RED nomatch ' ${w}'`, RED, w, 'NOMATCH');
for (const w of neutros) t(`RED_ORDER nomatch ' ${w}'`, RED_ORDER, w, 'NOMATCH');

console.log('\n=== Drift: RED_MODEL.md exige vs server.mjs tem ===');
// Palavras-chave listadas em RED_MODEL.md §1 (RED)
const redFromModel = ['dispatch','pricing','finalizepurchase','bora_tokens','stripe','rls','wallet','ledger','refund','comiss','markup','service_fee'];
const redOrderFromModel = ['dispatch_engine','dispatch','pricing','finalizepurchase','bora_tokens','stripe','payment','webhook','wallet','ledger','refund','payout','comiss','commission','markup','service_fee','platform_settings','rls','force push','forcepush'];
for (const w of redFromModel) {
  // 'comiss' deve bater em 'comissao' (substring). Use diretamente a palavra
  const res = RED.test(w) ? 'MATCH' : 'NOMATCH';
  if (res === 'MATCH') { pass++; console.log(`PASS [drift RED]      ${w} coberto`); }
  else { fail++; console.log(`FAIL [drift RED]      ${w} NAO coberto em RED`); }
}
for (const w of redOrderFromModel) {
  const res = RED_ORDER.test(w) ? 'MATCH' : 'NOMATCH';
  if (res === 'MATCH') { pass++; console.log(`PASS [drift RED_ORDER] ${w} coberto`); }
  else { fail++; console.log(`FAIL [drift RED_ORDER] ${w} NAO coberto`); }
}

console.log(`\n=== Result: ${pass} pass, ${fail} fail ===`);
process.exit(fail > 0 ? 1 : 0);