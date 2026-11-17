// deno test supabase/functions/robo-a3-catalogo/regras_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1'
import { decidir, fotoDeFora, lerProduto, precoCliente, seccaoNova, type Estado, type Produto } from './regras.ts'

const AGORA = '2026-11-17T07:00:00Z'
const base: Produto = { id: 'a3-21', name: 'Caneta', price: 2.24, partner_shelf_price: 1.95, is_available: true }
const est = (o: Partial<Estado> = {}): Estado => ({
  product_id: 'a3-21', ext_id: '21', ultimo_balcao_robo: 1.95, ultimo_disp_robo: true, ...o,
})
const lido = (o = {}) => ({ id: '21', nome: 'Caneta', preco: 1.95, esgotado: false, foto: null, ...o })

Deno.test('preço ao cliente = balcão × 1,15 arredondado (9,99 → 11,49; 3,95 → 4,54)', () => {
  assertEquals(precoCliente(9.99, 1.15), 11.49)
  assertEquals(precoCliente(3.95, 1.15), 4.54)
  assertEquals(precoCliente(1.7, 1.15), 1.96)
})

Deno.test('sem mudanças na A3 = nada muda', () => {
  const d = decidir(base, est(), lido(), true, 1.15, AGORA)
  assertEquals(d.upd, {})
  assertEquals(d.conta, null)
})

Deno.test('primeira corrida (sem estado) usa a base como último valor do robô', () => {
  const d = decidir(base, null, lido({ preco: 2.1 }), true, 1.15, AGORA)
  assertEquals(d.upd.partner_shelf_price, 2.1)
  assertEquals(d.upd.price, 2.42)
  assertEquals(d.estado.ext_id, '21')
})

Deno.test('preço mudou na A3 → balcão e preço ao cliente mudam', () => {
  const d = decidir(base, est(), lido({ preco: 2.2 }), true, 1.15, AGORA)
  assertEquals(d.upd, { partner_shelf_price: 2.2, price: 2.53 })
  assertEquals(d.estado.ultimo_balcao_robo, 2.2)
  assertEquals(d.conta, 'preco')
})

Deno.test('preço mudado à mão na Bora → o robô não pisa', () => {
  const p = { ...base, partner_shelf_price: 1.5, price: 1.73 }
  const d = decidir(p, est(), lido({ preco: 2.2 }), true, 1.15, AGORA)
  assert(d.maoPreco)
  assertEquals(d.upd.partner_shelf_price, undefined)
  assertEquals(d.upd.price, undefined)
})

Deno.test('só o preço ao cliente mudado à mão (balcão igual) → o robô não pisa', () => {
  const p = { ...base, price: 1.99 }
  const d = decidir(p, est(), lido({ preco: 2.2 }), true, 1.15, AGORA)
  assert(d.maoPreco)
  assertEquals(d.upd.price, undefined)
})

Deno.test('salto de preço acima de 50% é suspeito e não se aplica', () => {
  const d = decidir(base, est(), lido({ preco: 9.99 }), true, 1.15, AGORA)
  assert(d.suspeito)
  assertEquals(d.upd, {})
})

Deno.test('esgotou na A3 → esgota; voltou → volta a vender', () => {
  const d1 = decidir(base, est(), lido({ esgotado: true }), true, 1.15, AGORA)
  assertEquals(d1.upd, { is_available: false })
  assertEquals(d1.conta, 'esgotou')
  const p2 = { ...base, is_available: false }
  const d2 = decidir(p2, est({ ultimo_disp_robo: false }), lido(), true, 1.15, AGORA)
  assertEquals(d2.upd, { is_available: true })
  assertEquals(d2.conta, 'voltou')
})

Deno.test('esgotado mudado à mão na Bora → o robô não pisa', () => {
  const p = { ...base, is_available: false }
  const d = decidir(p, est({ ultimo_disp_robo: true }), lido(), true, 1.15, AGORA)
  assert(d.maoDisp)
  assertEquals(d.upd.is_available, undefined)
})

Deno.test('sem preço na A3 → nunca à venda a 0 €', () => {
  const p = { ...base, partner_shelf_price: 0, price: 0, is_available: false }
  const d = decidir(p, est({ ultimo_balcao_robo: 0, ultimo_disp_robo: false }), lido({ preco: null }), true, 1.15, AGORA)
  assertEquals(d.upd, {})
})

Deno.test('perdeu o preço na A3 → sai de venda (não fica pelo preço antigo)', () => {
  const d = decidir(base, est(), lido({ preco: null }), true, 1.15, AGORA)
  assertEquals(d.upd, { is_available: false })
  assertEquals(d.conta, 'esgotou')
})

Deno.test('sumiu da loja online: só tira de venda com leitura completa', () => {
  assertEquals(decidir(base, est(), null, false, 1.15, AGORA).upd, {})
  const d = decidir(base, est(), null, true, 1.15, AGORA)
  assertEquals(d.upd, { is_available: false })
  assertEquals(d.conta, 'desapareceu')
})

Deno.test('ignorado não muda nada', () => {
  assertEquals(decidir(base, est({ ignorar: true }), lido({ preco: 3, esgotado: true }), true, 1.15, AGORA).upd, {})
})

Deno.test('foto de fora = a3guarda.com', () => {
  assert(fotoDeFora('https://a3guarda.com/loja/img/p/3/4/34-large_default.jpg'))
  assert(fotoDeFora('https://www.a3guarda.com/x.jpg'))
  assert(!fotoDeFora('https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/product-images/lojas/a3-guarda/a3-21.jpg'))
  assert(!fotoDeFora(null))
})

Deno.test('ler produto da lista JSON da loja online', () => {
  const l = lerProduto({
    id_product: 21, name: ' Caneta Apagável ', price_amount: 1.95, add_to_cart_url: '',
    cover: { bySize: { large_default: { url: 'https://a3guarda.com/loja/img/p/3/4/34-large_default.jpg' } } },
    reference: '8052694005849', manufacturer_name: 'Legami', category_name: 'Início',
  })!
  assertEquals(l.id, '21')
  assertEquals(l.nome, 'Caneta Apagável')
  assertEquals(l.preco, 1.95)
  assert(l.esgotado)
  assertEquals(lerProduto({ id_product: 5, name: 'X', price_amount: 0, add_to_cart_url: 'u' })!.preco, null)
  assertEquals(lerProduto({ id_product: '', name: 'X' }), null)
})

Deno.test('secção de produto novo', () => {
  const s = new Set(['Cadernos', 'Natal'])
  assertEquals(seccaoNova(lido({ categoria: 'Cadernos' }), s), 'Cadernos')
  assertEquals(seccaoNova(lido({ categoria: 'Início' }), s), 'Novidades')
  assertEquals(seccaoNova(lido({ categoria: 'Outra' }), s), 'Novidades')
})
