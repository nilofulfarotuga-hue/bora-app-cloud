// deno test supabase/functions/ocr-receipt/talao_regras_test.ts
// Missão fechar-app-15-11, bloco 4 (14/11/2026). Dados do caso real lidos por SELECT em
// order_receipts_v2 (pedido 7a3468d5): só loja, linhas e valores — sem nomes nem telefones.
import {
  conferirLoja, lojasBatem, normalizarNome, somaDasLinhas, tirarLinhasRepetidas, type LinhaTalao,
} from './talao_regras.ts'

function igual(a: unknown, b: unknown, msg: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`)
}

const l = (name: string, unit_price_cents: number, qty = 1): LinhaTalao => ({ name, qty, unit_price_cents })

// Tal como o robô o gravou a 14/11: total impresso 25,10 €, soma das linhas 25,40 €.
const MCDONALDS_7A3468D5: LinhaTalao[] = [
  l('Mn CBO', 562), l('Coca-Cola Mn', 128), l('Batata Média', 125),
  l('Mn CBO', 562), l('Sumol An. Mn', 128), l('Batata Média', 125),
  l('Cheeseburger', 190), l('Molho Agridoce', 90), l('Wrap Cheddar', 240),
  l('M. Maio. e Alh', 90), l('Pp Wrap Chk Ma', 240),
  l('Taxa Saco', 30), l('Saco de Tran', 30),
]

Deno.test('caso real: o saco em duas linhas conta uma vez (25,40 -> 25,10)', () => {
  igual(somaDasLinhas(MCDONALDS_7A3468D5), 2540, 'soma como o robô a deixou')
  const r = tirarLinhasRepetidas(MCDONALDS_7A3468D5, 2510)
  igual(r.aviso, 'linha_repetida_tirada', 'aviso')
  igual(r.soma_antes_cents, 2540, 'antes')
  igual(r.soma_depois_cents, 2510, 'depois bate com o total impresso')
  igual(r.removidas, [l('Saco de Tran', 30)], 'saiu a linha de baixo do saco')
  igual(r.linhas.length, 12, 'ficaram 12 linhas')
  // Os dois menus iguais e as duas batatas iguais (comprados a sério) continuam lá.
  igual(r.linhas.filter((x) => x.name === 'Mn CBO').length, 2, 'dois menus')
  igual(r.linhas.filter((x) => x.name === 'Batata Média').length, 2, 'duas batatas')
  // A entrada não foi alterada.
  igual(MCDONALDS_7A3468D5.length, 13, 'lista original intacta')
})

Deno.test('repetição verdadeira NÃO se tira: a soma bate com o total', () => {
  const linhas = [l('Hambúrguer', 650), l('Hambúrguer', 650), l('Saco', 10)]
  const r = tirarLinhasRepetidas(linhas, 1310)
  igual(r.aviso, null, 'sem aviso')
  igual(r.removidas, [], 'nada removido')
  igual(r.linhas, linhas, 'linhas iguais')
})

Deno.test('a mesma linha lida duas vezes: sai a de baixo', () => {
  const r = tirarLinhasRepetidas([l('Pizza', 900), l('Água', 100), l('Pizza', 900)], 1000)
  igual(r.aviso, 'linha_repetida_tirada', 'aviso')
  igual(r.linhas, [l('Pizza', 900), l('Água', 100)], 'fica uma pizza')
})

Deno.test('sem total impresso não se tira nada', () => {
  for (const total of [null, undefined, 0]) {
    const r = tirarLinhasRepetidas(MCDONALDS_7A3468D5, total as number | null)
    igual(r.removidas, [], `total ${total}`)
    igual(r.aviso, null, `aviso com total ${total}`)
    igual(r.linhas.length, 13, `linhas com total ${total}`)
  }
})

Deno.test('soma acima do total sem linha repetida que o explique: só avisa', () => {
  const r = tirarLinhasRepetidas([l('Arroz', 200), l('Massa', 150), l('Saco', 10)], 300)
  igual(r.aviso, 'soma_das_linhas_acima_do_total', 'aviso')
  igual(r.removidas, [], 'nada removido')
  igual(r.linhas.length, 3, 'tudo como veio')
})

Deno.test('soma abaixo do total (descontos, linhas em falta): não mexe', () => {
  const r = tirarLinhasRepetidas([l('Arroz', 200), l('Arroz', 200)], 500)
  igual(r.aviso, null, 'sem aviso')
  igual(r.linhas.length, 2, 'duas linhas')
})

Deno.test('linhas de depósito nunca se tiram aqui (alimentam o depósito Volta)', () => {
  const linhas = [l('Coca-Cola 33cl', 120), l('VALOR DE DEPOSITO', 10), l('VALOR DE DEPOSITO', 10)]
  const r = tirarLinhasRepetidas(linhas, 130)
  igual(r.removidas, [], 'depósito fica')
  igual(r.aviso, 'soma_das_linhas_acima_do_total', 'fica o aviso para o painel')
})

Deno.test('só sai a repetida cujo valor é exatamente o excesso', () => {
  // Duas águas iguais, mas o excesso (50) não é o valor de uma água (100): não se tira.
  const r = tirarLinhasRepetidas([l('Água', 100), l('Água', 100), l('Pão', 80)], 230)
  igual(r.removidas, [], 'nada removido')
  igual(r.aviso, 'soma_das_linhas_acima_do_total', 'aviso')
})

Deno.test('nomes de loja: mesma loja com grafias diferentes', () => {
  igual(normalizarNome("McDonald's"), 'mcdonalds', 'apóstrofo')
  igual(normalizarNome('  FARMÁCIA   da Sé '), 'farmacia da se', 'acentos e espaços')
  for (const lida of ["McDonald's", 'MC DONALDS', 'Mcdonalds Guarda', "Sistemas McDonald's Portugal", 'MCDONALDS']) {
    igual(lojasBatem(lida, "McDonald's"), true, lida)
  }
  igual(lojasBatem('Continente Modelo Guarda', 'Continente'), true, 'continente')
  igual(lojasBatem('KFC', "McDonald's"), false, 'KFC não é McDonalds')
  igual(lojasBatem('Pingo Doce', 'Continente'), false, 'pingo doce não é continente')
  igual(lojasBatem(null, "McDonald's"), null, 'sem loja lida')
  igual(lojasBatem('KFC', ''), null, 'sem loja do pedido')
})

Deno.test('caso real: leu KFC num pedido do McDonalds -> outra loja conhecida', () => {
  const conhecidas = ["McDonald's", 'KFC', 'Burger King', 'Continente', 'Farmácia da Sé']
  igual(conferirLoja('KFC', "McDonald's", conhecidas),
    { ok: false, lida: 'KFC', pedido: "McDonald's", outra_loja_conhecida: 'KFC' }, 'KFC vs McDonalds')
})

Deno.test('loja certa: bate e não aponta outra', () => {
  igual(conferirLoja('MC DONALDS GUARDA', "McDonald's", ["McDonald's", 'KFC']),
    { ok: true, lida: 'MC DONALDS GUARDA', pedido: "McDonald's", outra_loja_conhecida: null }, 'bate')
})

Deno.test('nome da empresa dona da loja: não bate, mas não é outra loja conhecida', () => {
  const r = conferirLoja('Estrela Dourada Restaurantes Lda', "McDonald's", ["McDonald's", 'KFC', 'Burger King'])
  igual(r.ok, false, 'não bate')
  igual(r.outra_loja_conhecida, null, 'fica só a nota, sem ir a revisão')
})

Deno.test('sem loja lida ou sem loja no pedido: não se sabe', () => {
  igual(conferirLoja(null, "McDonald's", ['KFC']).ok, null, 'sem lida')
  igual(conferirLoja('KFC', null, ['KFC']).ok, null, 'sem pedido')
  igual(conferirLoja('  ', "McDonald's", ['KFC']).ok, null, 'lida em branco')
})

Deno.test('pela fonte: o texto enviado ao modelo já não dá nomes de lojas como exemplo', async () => {
  const fonte = await Deno.readTextFile(new URL('./index.ts', import.meta.url))
  const ini = fonte.indexOf('const sistema =')
  const fim = fonte.indexOf('const r = await pedirIa(')
  if (ini < 0 || fim < ini) throw new Error('não achei o texto do sistema')
  const texto = fonte.slice(ini, fim)
  for (const proibido of ['KFC', 'KENTUCKY', 'McDonald', 'Burger King']) {
    if (texto.includes(proibido)) throw new Error(`o texto ainda cita "${proibido}"`)
  }
  if (!texto.includes('nunca o adivinhes')) throw new Error('falta a regra de não adivinhar a loja')
  if (!texto.includes('UMA só vez')) throw new Error('falta a regra de não repetir linhas')
})
