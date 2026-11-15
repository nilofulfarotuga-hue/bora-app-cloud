// deno test --allow-read supabase/functions/ocr-receipt/talao_deposito_test.ts
// Missão fechar-tudo-15-11 (15/11/2026): o robô do talão reconhece as linhas de depósito com a
// MESMA regra do servidor (public._talao_e_deposito), que soma o depósito Volta do talão
// (talao_aplicar_deposito_volta -> orders.cash_total_due / carteira). Uma linha que o servidor
// conta como depósito nunca pode sair aqui como "repetida".
//
// Os valores do servidor abaixo foram lidos por SELECT em produção (ojykpzwqrtusfeakzrna) a
// 15/11/2026: public._talao_norm(nome) e public._talao_e_deposito(nome). Nomes ao jeito de talões
// reais, sem dados de clientes.
import {
  DEPOSITO_EM_QUALQUER_SITIO, DEPOSITO_NO_INICIO, eDeposito, normTalao, tirarLinhasRepetidas, type LinhaTalao,
} from './talao_regras.ts'

function igual(a: unknown, b: unknown, msg: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`)
}

const l = (name: string, unit_price_cents: number, qty = 1): LinhaTalao => ({ name, qty, unit_price_cents })

// [nome no talão, public._talao_norm(nome), public._talao_e_deposito(nome)] — saída do servidor.
const SERVIDOR: ReadonlyArray<readonly [string, string, boolean]> = [
  // "deposito", "depositos", "vasilhame", "vasilhames": em qualquer sítio, como palavra inteira
  ['VALOR DE DEPOSITO', 'valor de deposito', true],
  ['Depósito Embalagem', 'deposito embalagem', true],
  ['DEPÓSITO VOLTA', 'deposito volta', true],
  ['Total Depósitos', 'total depositos', true],
  ['DEPOSITOS EMBALAGENS', 'depositos embalagens', true],
  ['VASILHAME', 'vasilhame', true],
  ['Vasilhame Sagres 33cl', 'vasilhame sagres 33cl', true],
  ['Super Bock c/ vasilhame', 'super bock c  vasilhame', true],
  ['VASILHAMES', 'vasilhames', true],
  ['Devolução Vasilhames', 'devolucao vasilhames', true],
  ['* VASILHAME', 'vasilhame', true],
  ['Depósito (Volta)', 'deposito  volta', true],
  // "sdr", "volta", "dep", "dep emb": só no início do nome
  ['SDR', 'sdr', true],
  ['SDR Garrafa Plástico', 'sdr garrafa plastico', true],
  ['SDR-EMBALAGEM', 'sdr embalagem', true],
  ['VOLTA', 'volta', true],
  ['Volta Embalagem 0,10', 'volta embalagem 0 10', true],
  ['VOLTA: Lata', 'volta  lata', true],
  ['DEP', 'dep', true],
  ['Dep. Garrafa', 'dep  garrafa', true],
  ['DEP EMB', 'dep emb', true],
  ['DEP. EMB.', 'dep  emb', true],
  ['Dep.Emb. Lata', 'dep emb  lata', true],
  ['DEP-EMB 0,10', 'dep emb 0 10', true],
  ['- dep  emb', 'dep  emb', true],
  ['DEP\tEMB', 'dep emb', true],
  // acentos, maiúsculas, acento à parte (U+0301), espaço duro (U+00A0), símbolos colados (®, ©)
  ['depósitos', 'depositos', true],
  ['DEPÓSITO', 'deposito', true],
  ['Depo\u{301}sito', 'deposito', true],
  ['VASILHAME\u{a0}CERVEJA', 'vasilhame cerveja', true],
  ['Vasilhame\u{ae}', 'vasilhame r', true],
  ['DEPOSITO\u{a9}', 'deposito c', true],
  // NÃO são depósito no servidor, e por isso também não aqui. Os primeiros quatro mostram as
  // regras do servidor tal como estão: "volta" e "sdr" só contam no início do nome e "S.D.R."
  // com pontos não conta. Se um dia se quiser contá-los, muda-se o SQL e eDeposito juntos.
  ['Bilhete Ida e Volta', 'bilhete ida e volta', false],
  ['Água Luso 1,5L Volta', 'agua luso 1 5l volta', false],
  ['Taxa SDR', 'taxa sdr', false],
  ['2x DEP EMB', '2x dep emb', false],
  ['S.D.R. Embalagem', 's d r  embalagem', false],
  ['TARA', 'tara', false], // o robô antigo contava "tara"; o servidor nunca contou
  ['Tara Embalagem', 'tara embalagem', false],
  ['Voltaren Emulgel', 'voltaren emulgel', false],
  ['Depilatório Creme', 'depilatorio creme', false],
  ['Depositário', 'depositario', false],
  ['Revolta', 'revolta', false],
  ['Coca-Cola 33cl', 'coca cola 33cl', false],
  ['Saco de Transporte', 'saco de transporte', false],
  ["McDonald's", 'mcdonald s', false],
  ['\u{bd} Frango', '1 2 frango', false],
]

Deno.test('igual ao servidor, linha a linha: _talao_norm e _talao_e_deposito', () => {
  for (const [nome, norm, dep] of SERVIDOR) {
    igual(normTalao(nome), norm, `normTalao(${JSON.stringify(nome)})`)
    igual(eDeposito(nome), dep, `eDeposito(${JSON.stringify(nome)})`)
  }
})

Deno.test('cada palavra da lista do servidor tem pelo menos uma linha de talão que a prova', () => {
  const provadas = (re: (p: string) => RegExp, palavras: string[]) => {
    for (const p of palavras) {
      if (!SERVIDOR.some(([, norm, dep]) => dep && re(p).test(norm))) throw new Error(`falta uma linha com "${p}"`)
    }
  }
  provadas((p) => new RegExp(`(^| )${p}( |$)`), ['deposito', 'depositos', 'vasilhame', 'vasilhames'])
  provadas((p) => new RegExp(`^${p}( |$)`), ['sdr', 'volta', 'dep', 'dep emb'])
})

// Letra a letra, em produção (15/11/2026):
//   SELECT encode(sha256(convert_to(string_agg(public._talao_norm('x' || chr(cp) || 'x'), '|' ORDER BY cp), 'UTF8')), 'hex')
//     FROM (SELECT generate_series(1, 383) UNION ALL SELECT generate_series(768, 879)) c(cp);
// -> 495 caracteres, texto com 1903 letras.
const SHA256_SERVIDOR = '6187b9095dbc1a9c001774ad7a319d2389e7cdf19f0814e7c6eaf2d13e9c8f8e'

function intervalo(de: number, ate: number): number[] {
  return Array.from({ length: ate - de + 1 }, (_, i) => de + i)
}

async function sha256Hex(s: string): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))
  return [...h].map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.test('letra a letra igual ao servidor: U+0001–U+017F e as marcas U+0300–U+036F', async () => {
  const cps = [...intervalo(1, 383), ...intervalo(768, 879)]
  const texto = cps.map((cp) => normTalao('x' + String.fromCharCode(cp) + 'x')).join('|')
  igual(cps.length, 495, 'quantos caracteres')
  igual(texto.length, 1903, 'tamanho do texto')
  const hash = await sha256Hex(texto)
  if (hash !== SHA256_SERVIDOR) throw new Error(`difere do servidor (${hash}):\n${texto}`)
  // Amostras legíveis do que o unaccent faz e a decomposição NFD sozinha não faria.
  igual(normTalao('x\u{a9}x'), 'x c x', '© vira (C)')
  igual(normTalao('x\u{bd}x'), 'x 1 2x', '½ vira " 1/2"')
  igual(normTalao('Wei\u{df}bier'), 'weissbier', 'ß vira ss')
  igual(normTalao('x\u{363}x'), 'x x', 'U+0363 fica e vira espaço')
})

Deno.test('os padrões são os da última migração de public._talao_e_deposito (e _talao_norm igual)', async () => {
  const pasta = new URL('../../migrations/', import.meta.url)
  // As duas funções nasceram em 20261108234633 e 20261110173749; só uma migração mais nova as pode
  // mudar, por isso não se leem as ~900 antigas (a pasta tem quase 10 MB).
  const ficheiros: string[] = []
  for await (const e of Deno.readDir(pasta)) {
    if (e.isFile && e.name.endsWith('.sql') && e.name >= '20261108234633') ficheiros.push(e.name)
  }
  ficheiros.sort()
  const corpo = (nome: string) => new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${nome}\\s*\\(\\s*p\\s+text\\s*\\)[\\s\\S]*?\\$(\\w*)\\$([\\s\\S]*?)\\$\\1\\$`,
    'gi',
  )
  let deposito: string | null = null
  let norm: string | null = null
  for (const f of ficheiros) {
    const sql = await Deno.readTextFile(new URL(f, pasta))
    for (const m of sql.matchAll(corpo('_talao_e_deposito'))) deposito = m[2]
    for (const m of sql.matchAll(corpo('_talao_norm'))) norm = m[2]
  }
  if (!deposito || !norm) throw new Error('não achei public._talao_e_deposito / _talao_norm nas migrações')
  igual(
    deposito.replace(/\s+/g, ' ').trim(),
    `select public._talao_norm(p) ~ '${DEPOSITO_EM_QUALQUER_SITIO.source}' or public._talao_norm(p) ~ '${DEPOSITO_NO_INICIO.source}'`,
    'public._talao_e_deposito mudou: mudar eDeposito ao mesmo tempo',
  )
  igual(
    norm.replace(/\s+/g, ' ').trim(),
    "SELECT btrim(regexp_replace(lower(extensions.unaccent(COALESCE(p, ''))), '[^a-z0-9 ]+', ' ', 'g'))",
    'public._talao_norm mudou: mudar normTalao ao mesmo tempo',
  )
})

Deno.test('nenhuma linha que o servidor conta como depósito sai como repetida', () => {
  for (const [nome, , dep] of SERVIDOR) {
    // Duas garrafas, cada uma com a sua linha de depósito; a soma passa o total impresso por 0,10.
    const linhas = [l('Água Luso 1,5L', 65), l(nome, 10), l('Coca-Cola 1L', 150), l(nome, 10)]
    const r = tirarLinhasRepetidas(linhas, 225)
    if (dep) {
      igual(r.removidas, [], `${nome}: o depósito fica`)
      igual(r.aviso, 'soma_das_linhas_acima_do_total', `${nome}: fica só o aviso para o painel`)
      igual(r.linhas.length, 4, `${nome}: as quatro linhas ficam`)
    } else {
      // Como qualquer artigo: não conta para o depósito Volta no servidor, por isso tirar a
      // repetida não muda o depósito.
      igual(r.removidas, [l(nome, 10)], `${nome}: não é depósito no servidor, sai a repetida`)
    }
  }
})

Deno.test('caso que o robô antigo estragava: o DEP. EMB. de duas garrafas fica nas duas', () => {
  // Antes "dep emb" não contava como depósito aqui: saía o segundo DEP. EMB. e o servidor via
  // 0,10 € de depósito em vez de 0,20 € (e devolvia 0,10 € ao cliente no cash_total_due).
  const linhas = [l('AGUA LUSO 1,5L', 65), l('DEP. EMB.', 10), l('COCA-COLA 1L', 150), l('DEP. EMB.', 10)]
  const r = tirarLinhasRepetidas(linhas, 225)
  igual(r.removidas, [], 'nenhum depósito sai')
  const deposito = r.linhas.filter((x) => eDeposito(x.name)).reduce((s, x) => s + x.qty * x.unit_price_cents, 0)
  igual(deposito, 20, 'o servidor continua a ver 0,20 € de depósito')
  // Os outros nomes que o robô antigo não reconhecia.
  for (const nome of ['DEP EMB', 'Dep. Garrafa', 'DEPOSITOS', 'VASILHAMES', 'Total Depósitos']) {
    igual(tirarLinhasRepetidas([l('Cerveja', 90), l(nome, 10), l(nome, 10)], 100).removidas, [], nome)
  }
})
