// Regras puras do robô Glovo das farmácias (missão noite-farmacia-17-11, 1.1).
// Sem rede nem base: tudo o que decide o que muda num produto está aqui e tem testes
// em regras_test.ts (deno test). O index.ts só lê a Glovo e grava.

export type Produto = {
  id: string
  name: string
  price: number | string | null
  is_available: boolean
}

export type Estado = {
  product_id: string
  loja: string
  glovo_id: string
  ultimo_preco_robo: number | string | null
  ultimo_disp_robo: boolean | null
  robo_esgotou: boolean
  ignorar?: boolean
  motivo_ignorar?: string | null
  ultima_vez_visto?: string | null
}

export type LidoGlovo = {
  n: string // nome na Glovo
  p: number | null // preço ao balcão (o maior entre o preço e as promoções)
  o: boolean // esgotado na Glovo (outOfStock)
  r?: boolean // restricted
  img?: string | null
  sc?: string // secção do menu da Glovo
  c?: string // categoria do menu da Glovo
}

export type Decisao = {
  upd: Record<string, unknown> // o que muda em products (vazio = nada)
  estado: Estado // estado novo do robô para este produto
  conta: 'preco' | 'esgotou' | 'voltou' | 'desapareceu' | null
  precoMudou: boolean
  maoPreco: boolean // a farmácia mudou o preço à mão: o robô não pisa
  maoDisp: boolean // a farmácia mudou o esgotado à mão: o robô não pisa
  suspeito: boolean // salto de preço grande demais: não aplica, avisa
}

export const SALTO_MAX = 0.5 // mais de 50% de diferença = suspeito

export function cents(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(String(v).replace(',', '.'))
  if (!Number.isFinite(n)) return null
  return Math.round(n * 100)
}

/** Preço ao balcão: o maior entre o preço do cartão e o das promoções (igual à carga de 11/11). */
export function precoBalcao(d: Record<string, unknown>): number | null {
  let base = cents(d.price)
  const promos = Array.isArray(d.promotions) ? d.promotions : []
  for (const pr of promos) {
    if (!pr || typeof pr !== 'object') continue
    const o = pr as Record<string, unknown>
    const pi = (o.priceInfo ?? {}) as Record<string, unknown>
    const c = cents(o.price ?? pi.amount ?? o.discountedPrice ?? o.promoPrice)
    if (c !== null && base !== null && c > base) base = c
  }
  return base === null ? null : base / 100
}

/**
 * Decide o que muda num produto que já existe na loja.
 * - Primeira vez (sem estado): o valor que está na base conta como o último que o robô pôs
 *   (a carga de 11/11 veio da Glovo e ninguém mexeu desde 14/11).
 * - Preço: se o preço na base já não é o último que o robô pôs, foi a farmácia → não mexe.
 * - Esgotado: igual; e só volta a pôr à venda o que FOI o robô a esgotar.
 * - g = null (produto não apareceu na leitura): só esgota se a leitura correu sem falhas.
 */
export function decidir(
  p: Produto,
  e: Estado | null | undefined,
  g: LidoGlovo | null,
  semFalhas: boolean,
  loja: string,
  glovoId: string,
  agoraIso: string,
): Decisao {
  const est: Estado = e
    ? { ...e }
    : {
        product_id: p.id,
        loja,
        glovo_id: glovoId,
        ultimo_preco_robo: p.price,
        ultimo_disp_robo: p.is_available,
        robo_esgotou: false,
      }
  const d: Decisao = {
    upd: {},
    estado: est,
    conta: null,
    precoMudou: false,
    maoPreco: false,
    maoDisp: false,
    suspeito: false,
  }
  if (est.ignorar) return d

  const precoBase = cents(p.price)
  d.maoPreco = !!e && precoBase !== cents(e.ultimo_preco_robo)
  d.maoDisp = !!e && e.ultimo_disp_robo !== null && p.is_available !== e.ultimo_disp_robo

  if (g) {
    est.ultima_vez_visto = agoraIso
    const novo = g.p === null ? null : cents(g.p)
    if (novo !== null && precoBase !== null && novo !== precoBase && !d.maoPreco) {
      const salto = Math.abs(novo - precoBase) / Math.max(precoBase, 1)
      if (salto > SALTO_MAX) {
        d.suspeito = true
      } else {
        d.upd.price = novo / 100
        d.upd.partner_shelf_price = novo / 100
        est.ultimo_preco_robo = novo / 100
        d.precoMudou = true
        d.conta = 'preco'
      }
    }
    if (!d.maoDisp) {
      if (g.o && p.is_available) {
        d.upd.is_available = false
        est.ultimo_disp_robo = false
        est.robo_esgotou = true
        d.conta = d.conta ?? 'esgotou'
      } else if (!g.o && !p.is_available && est.robo_esgotou) {
        d.upd.is_available = true
        est.ultimo_disp_robo = true
        est.robo_esgotou = false
        d.conta = d.conta ?? 'voltou'
      }
    }
  } else if (semFalhas && !d.maoDisp && p.is_available) {
    d.upd.is_available = false
    est.ultimo_disp_robo = false
    est.robo_esgotou = true
    d.conta = 'desapareceu'
  }
  return d
}

// ---------- produtos novos (mesmas regras da carga de 11/11: construir_catalogo.py) ----------

export function limparNome(s: string): string {
  let t = (s ?? '').trim()
  t = t.replace(/\s*-\s*\d{7}$/, '')
  t = t.replace(/\s+-$/, '')
  return t.replace(/\s{2,}/g, ' ').trim()
}

export function normNome(s: string): string {
  return (s ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

/** Secção e categoria do menu da Glovo → categoria da Bora (cópia de categoria_de de 11/11). */
export function categoriaDe(sc: string, c: string): string | null {
  if (sc.startsWith('Medicamentos')) {
    if (['Dor e Febre', 'Dores Musculares e Articulações'].includes(c)) return 'Dor e febre'
    if (['Gripes e Constipações', 'Tosse', 'Dor de Garganta e Roquidão', 'Alergias e Congestão Nasal'].includes(c)) {
      return 'Constipação, gripe e alergias'
    }
    return 'Medicamentos sem receita'
  }
  if (sc === 'Bebé e Mamã') return 'Bebé e mamã'
  if (sc === 'Saúde e Bem-Estar') {
    if (c === 'Primeiros-Socorros') return 'Primeiros socorros'
    if (c === 'Saúde e Respiração') return 'Constipação, gripe e alergias'
    return 'Ortopedia e bem-estar'
  }
  if (sc === 'Nutrição e Suplementos') {
    return c === 'Suplementos Alimentares' ? 'Suplementos e vitaminas' : 'Nutrição e controlo de peso'
  }
  if (sc === 'Higiene Oral') return 'Saúde oral'
  if (sc === 'Saúde Sexual e Íntima') return 'Saúde sexual e íntima'
  if (sc === 'Cosmética Rosto') return c.startsWith('Solares') ? 'Solares' : 'Dermocosmética'
  if (sc === 'Cuidado Corpo') return c.startsWith('Solares') ? 'Solares' : 'Higiene e cuidado pessoal'
  if (sc === 'Cuidado Cabelo') return 'Cabelo'
  if (sc === 'Cosmética Masculina') return 'Homem'
  if (sc === 'Perfumes' || sc === 'Maquilhagem') return 'Maquilhagem e perfumes'
  if (sc === 'Solares') return 'Solares'
  if (sc === 'Ortopedia') return 'Ortopedia e bem-estar'
  return null
}

const DOSE_MG = /\d+([.,]\d+)?\s?(mg|mcg|µg)\b|\bmg\/(ml|g|dose)\b|\d+\s?ui\b/i
const FORMA_FARM =
  /\b(comprimidos?|c[aá]psulas?|xarope|suspens[aã]o|solu[cç][aã]o|gotas|granulado|gr[aâ]nulos|pastilhas?|gomas?|emplastro|gel|creme|pomada|emuls[aã]o|enema|col[ií]rio|efervescente|transd[eé]rmico)\b/i
const INFARMED = /^[^,]+,\s.*(\bx\s?\d+\b|Blister|Frasco|Bisnaga|Recipiente|Saqueta).*-\d{7}$/
const NAO_MED =
  /\b(repel|repelente|ohropax|tamp[oõ]es|thermacare|faixa term|breathe right|penso nasal|fisiocrem|rhinomer|arko\w*|advancis|supracare|grintuss|uriage|ducray|isdin\w*|lrposay|la roche|bepanthene eczema|paranix|previpiq|stop repel|preservativ\w*|teste de gravidez|lubrificante|corega)\b/i

function maiusculas(s: string): boolean {
  const letras = [...s].filter((c) => c.toLowerCase() !== c.toUpperCase())
  if (!letras.length) return false
  return letras.filter((c) => c === c.toUpperCase()).length / letras.length >= 0.7
}

/** Medicamento não sujeito a receita? Na dúvida, sim (igual a 11/11). */
export function eMedicamento(nomeGlovo: string, sc: string, restricted: boolean): boolean {
  const razoes: string[] = []
  if (restricted) razoes.push('restricted')
  if (INFARMED.test(nomeGlovo)) razoes.push('infarmed')
  if (DOSE_MG.test(nomeGlovo) && FORMA_FARM.test(nomeGlovo)) razoes.push('dose+forma')
  if (sc.startsWith('Medicamentos') && !maiusculas(nomeGlovo) && !NAO_MED.test(nomeGlovo)) razoes.push('secção')
  if (razoes.length && NAO_MED.test(nomeGlovo)) return false
  return razoes.length > 0
}

/** Fotos da Glovo que NÃO são o produto (md5 vistos à mão a 11/11). */
export const MARCADORES_MD5: Record<string, string> = {
  '20d45f8205433b1bfa777c9df3d3b962': "quadro 'PRODUTO SEM IMAGEM DISPONÍVEL'",
  'a4a692fa886f6d8f7e9f5875913dccc0': "quadro 'SKIN — IMAGEM INDISPONÍVEL'",
  'fff7a8430da14474c04fe230f7db6d88': 'logótipo Caudalie em vez do produto',
}

/** Tipo da imagem pelos primeiros bytes (a Glovo serve jpeg, png e às vezes webp/avif). */
export function tipoImagem(b: Uint8Array): { ext: string; type: string } | null {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { ext: 'jpg', type: 'image/jpeg' }
  if (b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return { ext: 'png', type: 'image/png' }
  if (b.length > 12 && String.fromCharCode(...b.slice(8, 12)) === 'WEBP') return { ext: 'webp', type: 'image/webp' }
  return null
}

/** A Glovo manda ids maiores que 2^53: passam a texto antes do JSON.parse. */
export function parseGlovo(text: string): unknown {
  return JSON.parse(text.replace(/([:\[,]\s*)(-?\d{16,})(?=\s*[,\]}])/g, '$1"$2"'))
}
