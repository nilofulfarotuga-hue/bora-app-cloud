// deno test supabase/functions/robo-glovo-farmacias/regras_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1'
import { categoriaDe, decidir, eMedicamento, type Estado, limparNome, parseGlovo, precoBalcao, tipoImagem } from './regras.ts'

const AGORA = '2026-11-17T07:30:00.000Z'
const prod = (over: Record<string, unknown> = {}) => ({ id: 'fse-1', name: 'NUXE X', price: '20.00', is_available: true, ...over })
const est = (over: Partial<Estado> = {}): Estado => ({
  product_id: 'fse-1', loja: 'farmacia-se-guarda', glovo_id: '1',
  ultimo_preco_robo: 20, ultimo_disp_robo: true, robo_esgotou: false, ...over,
})

Deno.test('primeira corrida: preço mudou na Glovo → copia preço e preço de balcão', () => {
  const d = decidir(prod(), null, { n: 'NUXE X', p: 21.5, o: false }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, { price: 21.5, partner_shelf_price: 21.5 })
  assertEquals(d.estado.ultimo_preco_robo, 21.5)
  assert(d.precoMudou)
})

Deno.test('preço igual e à venda → nada muda', () => {
  const d = decidir(prod(), est(), { n: 'NUXE X', p: 20, o: false }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, {})
  assertEquals(d.conta, null)
})

Deno.test('a farmácia mudou o preço à mão → o robô não pisa', () => {
  const d = decidir(prod({ price: '18.00' }), est({ ultimo_preco_robo: 20 }), { n: 'NUXE X', p: 22, o: false }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, {})
  assert(d.maoPreco)
})

Deno.test('esgotado na Glovo → esgota na Bora e lembra que foi o robô', () => {
  const d = decidir(prod(), est(), { n: 'NUXE X', p: 20, o: true }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, { is_available: false })
  assert(d.estado.robo_esgotou)
})

Deno.test('volta à venda só se foi o robô a esgotar', () => {
  const robo = decidir(prod({ is_available: false }), est({ ultimo_disp_robo: false, robo_esgotou: true }), { n: 'X', p: 20, o: false }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(robo.upd, { is_available: true })
  // a farmácia esgotou à mão (base false, robô tinha posto true) → não reabre
  const mao = decidir(prod({ is_available: false }), est({ ultimo_disp_robo: true }), { n: 'X', p: 20, o: false }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(mao.upd, {})
  assert(mao.maoDisp)
})

Deno.test('a farmácia voltou a pôr à venda à mão um que o robô esgotou → não volta a esgotar só por isso', () => {
  const d = decidir(prod({ is_available: true }), est({ ultimo_disp_robo: false, robo_esgotou: true }), { n: 'X', p: 20, o: true }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, {})
  assert(d.maoDisp)
})

Deno.test('saiu da Glovo: esgota só se a leitura não teve falhas', () => {
  const sem = decidir(prod(), est(), null, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(sem.upd, { is_available: false })
  assertEquals(sem.conta, 'desapareceu')
  const com = decidir(prod(), est(), null, false, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(com.upd, {})
})

Deno.test('salto de preço acima de 50% → suspeito, não aplica', () => {
  const d = decidir(prod(), est(), { n: 'X', p: 45, o: false }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, {})
  assert(d.suspeito)
})

Deno.test('produto marcado para ignorar → nada', () => {
  const d = decidir(prod(), est({ ignorar: true }), { n: 'X', p: 25, o: true }, true, 'farmacia-se-guarda', '1', AGORA)
  assertEquals(d.upd, {})
})

Deno.test('preço de balcão: promoção mais barata não baixa o preço', () => {
  assertEquals(precoBalcao({ price: 10.5, promotions: [{ price: 8.4 }] }), 10.5)
  assertEquals(precoBalcao({ price: 8.4, promotions: [{ priceInfo: { amount: 10.5 } }] }), 10.5)
  assertEquals(precoBalcao({ price: null }), null)
})

Deno.test('nomes, categorias e medicamento como a carga de 11/11', () => {
  assertEquals(limparNome('Ben-u-ron, 500 mg x 20 comp-2438489'), 'Ben-u-ron, 500 mg x 20 comp')
  assertEquals(categoriaDe('Medicamentos e Saúde', 'Dor e Febre'), 'Dor e febre')
  assertEquals(categoriaDe('Cosmética Rosto', 'Solares Rosto'), 'Solares')
  assertEquals(categoriaDe('Bebé e Mamã', 'Fraldas'), 'Bebé e mamã')
  assertEquals(categoriaDe('Coisa Nova', 'X'), null)
  assert(eMedicamento('Brufen, 400 mg x 20 comprimidos', 'Medicamentos', false))
  assert(!eMedicamento('ISDIN FOTOPROTECTOR GEL CREME SPF50 50ML', 'Solares', false))
})

Deno.test('ids grandes da Glovo ficam texto', () => {
  const j = parseGlovo('{"id": 4611686018581478511, "price": 3.5}') as Record<string, unknown>
  assertEquals(j.id, '4611686018581478511')
  assertEquals(j.price, 3.5)
})

Deno.test('tipo da imagem pelos primeiros bytes', () => {
  assertEquals(tipoImagem(new Uint8Array([0xff, 0xd8, 0xff, 0xe0]))?.ext, 'jpg')
  assertEquals(tipoImagem(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0]))?.ext, 'png')
  assertEquals(tipoImagem(new Uint8Array([1, 2, 3, 4])), null)
})
