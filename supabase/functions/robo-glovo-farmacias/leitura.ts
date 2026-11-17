// Leitura da Glovo do robô das farmácias (missão noite-farmacia-17-11, 1.1).
// Separado do index.ts para se poder fazer uma leitura de prova sem gravar nada.
import { type LidoGlovo, parseGlovo, precoBalcao } from './regras.ts'

export type Loja = { storeId: string; addressId: string; slug: string; prefix: string }
export const LOJAS: Record<string, Loja> = {
  'farmacia-se-guarda': { storeId: '461279', addressId: '732949', slug: 'farmacia-da-se-grd', prefix: 'fse' },
  'farmacia-teixeira-guarda': { storeId: '461596', addressId: '733650', slug: 'farmacia-teixeira-grd', prefix: 'fte' },
}

export const INTERVALO_MS = 1_500 // 1 pedido a cada 1,5 s (a 2,6/s a Glovo deu 429 a 11/11)

export const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
const SESSAO = crypto.randomUUID()
let ultimoPedido = 0

function cabecalhos(L: Loja): Record<string, string> {
  return {
    'User-Agent': UA,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'pt-PT,pt;q=0.9',
    'glovo-api-version': '14',
    'glovo-app-platform': 'web',
    'glovo-app-type': 'customer',
    'glovo-location-country-code': 'PT',
    'glovo-location-city-code': 'GRD',
    'glovo-location-latitude': '40.5373',
    'glovo-location-longitude': '-7.2674',
    'glovo-language-code': 'pt',
    'Glovo-Perseus-Session-Id': SESSAO,
    Origin: 'https://glovoapp.com',
    Referer: `https://glovoapp.com/pt/pt/guarda/stores/${L.slug}`,
  }
}

export const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms))

export type Resposta = { status: number; json: any; text: string }
export async function glovo(L: Loja, caminho: string): Promise<Resposta> {
  const espera = ultimoPedido + INTERVALO_MS - Date.now()
  if (espera > 0) await dormir(espera)
  ultimoPedido = Date.now()
  const url = caminho.startsWith('http') ? caminho : 'https://api.glovoapp.com' + caminho
  try {
    const ctl = new AbortController()
    const t = setTimeout(() => ctl.abort(), 20_000)
    const r = await fetch(url, { headers: cabecalhos(L), signal: ctl.signal })
    const text = await r.text()
    clearTimeout(t)
    let json: any = null
    if (r.status === 200) {
      try {
        json = parseGlovo(text)
      } catch (_) { /* fica null */ }
    }
    return { status: r.status, json, text: text.slice(0, 300) }
  } catch (e) {
    return { status: 0, json: null, text: String(e).slice(0, 200) }
  }
}

export type Item = { p: string; sc: string; c: string; cs: string; subs: { slug: string; sid: string | null }[] }
export type Progresso = {
  fase?: 'categorias' | 'aplicar' | 'feito'
  fila?: Item[]
  i?: number
  produtos?: Record<string, LidoGlovo>
  falhas?: { c: string; s: string; st: number }[]
  pedidos?: number
  r429?: number
}

function addTile(d: any, item: Item, prog: Progresso) {
  if (!d || d.id === undefined || d.id === null) return
  const id = String(d.id)
  if (prog.produtos![id]) return
  const img = d.imageUrl
    ? String(d.imageUrl)
    : d.imageId
    ? 'https://glovo.dhmedia.io/image/' + String(d.imageId).replace(/^dh:/, '')
    : null
  prog.produtos![id] = {
    n: String(d.name ?? ''),
    p: precoBalcao(d),
    o: !!d.outOfStock,
    r: !!d.restricted,
    img,
    sc: item.sc,
    c: item.c,
  }
}

/** Lê uma categoria do menu (página + partes + secções que faltarem). '429' = parar e tentar depois. */
export async function lerCategoria(L: Loja, item: Item, prog: Progresso): Promise<'ok' | '429'> {
  const vistas = new Set<string>()
  const addGrid = (grid: any) => {
    const g = grid?.data ?? {}
    if (g.slug) vistas.add(String(g.slug))
    for (const el of g.elements ?? []) if (el?.type === 'PRODUCT_TILE') addTile(el.data, item, prog)
  }
  const r = await glovo(L, item.p)
  prog.pedidos = (prog.pedidos ?? 0) + 1
  if (r.status === 429) return '429'
  if (r.status === 404 && /no valid products/i.test(r.text)) return 'ok' // categoria vazia na Glovo
  if (r.status !== 200 || !r.json) {
    prog.falhas!.push({ c: item.cs, s: '*', st: r.status })
    return 'ok'
  }
  for (const b of r.json?.data?.body ?? []) {
    if (b?.type === 'GRID') addGrid(b)
    else if (b?.type === 'CONTENT_PLACEHOLDER' && b.data?.contentUri) {
      const pr = await glovo(L, b.data.contentUri)
      prog.pedidos!++
      if (pr.status === 429) return '429'
      if (pr.status !== 200 || !pr.json) {
        if (pr.status !== 404) prog.falhas!.push({ c: item.cs, s: String(b.data.slug ?? '?'), st: pr.status })
        continue
      }
      for (const pb of pr.json?.data?.body ?? []) if (pb?.type === 'GRID') addGrid(pb)
    }
  }
  for (const s of item.subs) {
    if (!s.slug || vistas.has(s.slug) || !s.sid) continue
    const pr = await glovo(L, `/v4/stores/${L.storeId}/addresses/${L.addressId}/content/partial?component=section&id=${s.sid}`)
    prog.pedidos!++
    if (pr.status === 429) return '429'
    if (pr.status !== 200 || !pr.json) {
      if (pr.status !== 404) prog.falhas!.push({ c: item.cs, s: s.slug, st: pr.status })
      continue // 404 = secção vazia na Glovo (3 na Sé a 11/11)
    }
    for (const pb of pr.json?.data?.body ?? []) if (pb?.type === 'GRID') addGrid(pb)
  }
  return 'ok'
}

/** Menu da loja na Glovo → fila de categorias a ler. */
export function montarFila(menu: any): Item[] {
  const fila: Item[] = []
  for (const sc of menu?.data?.elements ?? []) {
    for (const cat of sc?.elements ?? []) {
      const p = cat?.action?.data?.path
      if (!p) continue
      fila.push({
        p,
        sc: String(sc.name ?? ''),
        c: String(cat.name ?? ''),
        cs: String(cat.slug ?? ''),
        subs: (cat.elements ?? []).map((s: any) => ({ slug: String(s?.slug ?? ''), sid: s?.tracking?.sectionId ? String(s.tracking.sectionId) : null })),
      })
    }
  }
  return fila
}

export const caminhoMenu = (L: Loja) => `/v3/stores/${L.storeId}/addresses/${L.addressId}/node/store_menu`
