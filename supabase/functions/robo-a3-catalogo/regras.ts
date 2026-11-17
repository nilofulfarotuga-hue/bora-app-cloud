// Regras puras do robô do catálogo da A3 Guarda (missão a3-guarda-16-11, parte 2, pontos 1 e 6).
// Sem rede nem base: tudo o que decide o que muda num produto está aqui e tem testes em
// regras_test.ts (deno test). O index.ts só lê a loja online da A3 e grava.
//
// Molde: robo-glovo-farmacias/regras.ts (16/11). Diferença: na A3 a fonte é a loja online da
// própria A3, por isso o esgotado de lá manda nos dois sentidos (esgota e volta a pôr à venda),
// desde que ninguém o tenha mudado à mão na Bora.

export type Produto = {
  id: string
  name: string
  price: number | string | null
  partner_shelf_price: number | string | null
  is_available: boolean
  photo_url?: string | null
}

export type Estado = {
  product_id: string
  ext_id: string
  ultimo_balcao_robo: number | string | null
  ultimo_disp_robo: boolean | null
  ignorar?: boolean
  motivo_ignorar?: string | null
  ultima_vez_visto?: string | null
}

/** Um produto como vem da lista da loja online (PrestaShop, controller=category, JSON). */
export type Lido = {
  id: string // id_product
  nome: string
  preco: number | null // preço de balcão (price_amount); 0 ou vazio = sem preço
  esgotado: boolean // sem add_to_cart_url
  foto: string | null // cover large_default
  ref?: string | null
  marca?: string | null
  categoria?: string | null // category_name da A3 (muitas vezes "Início")
}

export type Decisao = {
  upd: Record<string, unknown>
  estado: Estado
  conta: 'preco' | 'esgotou' | 'voltou' | 'desapareceu' | null
  maoPreco: boolean // a A3 (ou nós) mudou o preço à mão na Bora: o robô não pisa
  maoDisp: boolean // idem para o esgotado
  suspeito: boolean // salto de preço grande demais: não aplica, avisa
}

export const SALTO_MAX = 0.5 // mais de 50% de diferença = suspeito
export const PREFIXO = 'a3-'
export const HOST_A3 = 'a3guarda.com'

export function cents(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(String(v).replace(',', '.'))
  if (!Number.isFinite(n)) return null
  return Math.round(n * 100)
}

/** Preço ao cliente a partir do balcão, com o fator da loja (robo_a3_config.fator_preco). */
// Em inteiros (cêntimos × décimas de milésima) para arredondar igual ao round(numeric, 2) do
// Postgres: 1,70 × 1,15 = 1,955 → 1,96 (em vírgula flutuante dava 1,95).
export function precoCliente(balcao: number, fator: number): number {
  const c = Math.round(balcao * 100)
  const f = Math.round(fator * 10000)
  return Math.round((c * f) / 10000) / 100
}

/** A foto ainda aponta para o site da A3 (proibido: tem de estar no nosso Storage). */
export function fotoDeFora(url: string | null | undefined): boolean {
  if (!url) return false
  try {
    return new URL(url).hostname.replace(/^www\./, '').endsWith(HOST_A3)
  } catch {
    return false
  }
}

/** Converte um produto da lista JSON da loja online para Lido. */
export function lerProduto(p: Record<string, unknown>): Lido | null {
  const id = String(p.id_product ?? '').trim()
  const nome = String(p.name ?? '').trim()
  if (!/^\d+$/.test(id) || !nome) return null
  const preco = cents(p.price_amount)
  const cover = p.cover as Record<string, unknown> | null | undefined
  const bySize = (cover?.bySize ?? {}) as Record<string, { url?: string }>
  const foto = bySize.large_default?.url ?? (cover?.large as { url?: string } | undefined)?.url ?? null
  return {
    id,
    nome,
    preco: preco && preco > 0 ? preco / 100 : null,
    esgotado: !p.add_to_cart_url,
    foto,
    ref: (p.reference as string) || null,
    marca: (p.manufacturer_name as string) || null,
    categoria: (p.category_name as string) || null,
  }
}

/**
 * Decide o que muda num produto que já existe na Bora.
 * - Primeira vez (sem estado): o que está na base conta como o último valor do robô
 *   (a carga de 16/11 veio da mesma loja online e ninguém mexeu desde então).
 * - Preço: se o balcão na base já não é o último que o robô pôs, foi mão humana → não mexe.
 * - Esgotado: igual; sem mão humana, segue a loja online nos dois sentidos.
 * - Produto sem preço na A3 fica fora de venda (nunca se vende a 0 €).
 * - Nome e foto de produtos que já existem NUNCA mudam (só a cópia da foto para o Storage).
 * - l = null (não apareceu na leitura): só tira de venda se a leitura veio completa.
 */
export function decidir(
  p: Produto,
  e: Estado | null | undefined,
  l: Lido | null,
  leituraCompleta: boolean,
  fator: number,
  agoraIso: string,
): Decisao {
  const extId = p.id.startsWith(PREFIXO) ? p.id.slice(PREFIXO.length) : p.id
  const est: Estado = e
    ? { ...e }
    : { product_id: p.id, ext_id: extId, ultimo_balcao_robo: p.partner_shelf_price, ultimo_disp_robo: p.is_available }
  const d: Decisao = { upd: {}, estado: est, conta: null, maoPreco: false, maoDisp: false, suspeito: false }
  if (est.ignorar) return d

  const balcaoBase = cents(p.partner_shelf_price)
  // mão humana no preço: mudou o balcão OU só o preço ao cliente (o painel pode mexer num só)
  const ultimo = cents(e?.ultimo_balcao_robo)
  d.maoPreco = !!e && (balcaoBase !== ultimo ||
    (ultimo !== null && ultimo > 0 && cents(p.price) !== cents(precoCliente(ultimo / 100, fator))))
  d.maoDisp = !!e && e.ultimo_disp_robo !== null && p.is_available !== e.ultimo_disp_robo

  if (l) {
    est.ultima_vez_visto = agoraIso
    const novo = l.preco === null ? null : cents(l.preco)
    if (novo !== null && novo !== balcaoBase && !d.maoPreco) {
      const salto = balcaoBase ? Math.abs(novo - balcaoBase) / balcaoBase : 0
      if (balcaoBase && salto > SALTO_MAX) {
        d.suspeito = true
      } else {
        d.upd.partner_shelf_price = novo / 100
        d.upd.price = precoCliente(novo / 100, fator)
        est.ultimo_balcao_robo = novo / 100
        d.conta = 'preco'
      }
    }
    if (!d.maoDisp) {
      const balcaoFinal = d.upd.partner_shelf_price !== undefined ? novo : balcaoBase
      const deveVender = !l.esgotado && !!balcaoFinal && balcaoFinal > 0
      if (deveVender !== p.is_available) {
        d.upd.is_available = deveVender
        est.ultimo_disp_robo = deveVender
        d.conta = d.conta ?? (deveVender ? 'voltou' : 'esgotou')
      }
    }
  } else if (leituraCompleta && !d.maoDisp && p.is_available) {
    d.upd.is_available = false
    est.ultimo_disp_robo = false
    d.conta = 'desapareceu'
  }
  return d
}

/** Secção (category) de um produto novo: a categoria da A3 se já existir na loja, senão "Novidades". */
export function seccaoNova(l: Lido, seccoesExistentes: Set<string>): string {
  const c = (l.categoria ?? '').trim()
  if (c && c.toLowerCase() !== 'início' && c.toLowerCase() !== 'inicio' && seccoesExistentes.has(c)) return c
  return 'Novidades'
}

export function tipoImagem(b: Uint8Array): { ext: string; type: string } | null {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { ext: 'jpg', type: 'image/jpeg' }
  if (b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return { ext: 'png', type: 'image/png' }
  if (b.length > 12 && String.fromCharCode(...b.slice(8, 12)) === 'WEBP') return { ext: 'webp', type: 'image/webp' }
  return null
}
