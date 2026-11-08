// pesquisar_internet (missão m3, 08/11/2026): a pesquisa do próprio dsh (web_search) só funciona com a DeepSeek paga, por
// isso o Dipsy pesquisa por aqui. DuckDuckGo (página HTML simples); se falhar, o RSS do Bing. Tudo sai pelo fetch do Node,
// que no dsh passa pelo proxy do Dipsy (HTTPS_PROXY) e fica registado. Só leitura: nada vai para fora além da pergunta.

const AGENTE = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

function semHtml(s) {
  return String(s ?? '').replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#x27;|&#39;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim()
}
function destinoDdg(href) {
  try {
    const u = new URL(href.startsWith('//') ? 'https:' + href : href, 'https://duckduckgo.com')
    const real = u.searchParams.get('uddg')
    return real ? decodeURIComponent(real) : u.toString()
  } catch { return href }
}

async function buscar(url, signal, corpo) {
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), 20000)
  signal?.addEventListener?.('abort', () => ctl.abort(), { once: true })
  try {
    const headers = { 'User-Agent': AGENTE, 'Accept-Language': 'pt-PT,pt;q=0.9,en;q=0.6' }
    if (corpo) headers['Content-Type'] = 'application/x-www-form-urlencoded'
    const r = await fetch(url, { method: corpo ? 'POST' : 'GET', headers, body: corpo, signal: ctl.signal })
    const texto = await r.text()
    if (!r.ok) throw new Error(`HTTP ${r.status}${/proxy do dipsy/i.test(texto) ? ' (proxy do Dipsy: ' + texto.slice(0, 160) + ')' : ''}`)
    return texto
  } finally { clearTimeout(t) }
}

export function lerDuckDuckGo(html, max) {
  const res = []
  const blocos = String(html).split(/<div[^>]+class="[^"]*\bresult\b[^"]*"/i).slice(1)
  for (const b of blocos) {
    const a = /<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i.exec(b)
    if (!a) continue
    const sn = /class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/(a|td|div)>/i.exec(b)
    const url = destinoDdg(a[1].replace(/&amp;/g, '&'))
    if (/duckduckgo\.com\/y\.js|ad_provider|\/\/duckduckgo\.com\/l\/\?.*ad_domain/.test(url)) continue
    res.push({ titulo: semHtml(a[2]), url, resumo: semHtml(sn?.[1] ?? '') })
    if (res.length >= max) break
  }
  return res
}
export function lerBingRss(xml, max) {
  const res = []
  for (const m of String(xml).matchAll(/<item>([\s\S]*?)<\/item>/gi)) {
    const tit = /<title>([\s\S]*?)<\/title>/i.exec(m[1])?.[1]
    const url = /<link>([\s\S]*?)<\/link>/i.exec(m[1])?.[1]
    const desc = /<description>([\s\S]*?)<\/description>/i.exec(m[1])?.[1]
    if (tit && url) res.push({ titulo: semHtml(tit), url: semHtml(url), resumo: semHtml(desc) })
    if (res.length >= max) break
  }
  return res
}

export async function pesquisar(pergunta, maximo, signal) {
  const q = String(pergunta ?? '').trim().slice(0, 300)
  if (!q) return 'Escreve o que queres procurar.'
  const max = Math.min(15, Math.max(1, Number(maximo) || 8))
  let res = []
  let fonte = 'DuckDuckGo'
  const erros = []
  try {
    // o DuckDuckGo corta (ECONNRESET) os GET da página HTML vindos de programas; o POST do formulário responde (08/11)
    res = lerDuckDuckGo(await buscar('https://html.duckduckgo.com/html/', signal, `q=${encodeURIComponent(q)}&kl=pt-pt`), max)
  } catch (e) { erros.push(`DuckDuckGo: ${String(e?.message ?? e).slice(0, 160)}`) }
  if (!res.length) {
    fonte = 'Bing'
    try {
      res = lerBingRss(await buscar(`https://www.bing.com/search?format=rss&mkt=pt-PT&setlang=pt-PT&cc=PT&q=${encodeURIComponent(q)}`, signal), max)
    } catch (e) { erros.push(`Bing: ${String(e?.message ?? e).slice(0, 160)}`) }
  }
  if (!res.length) return `Não encontrei resultados para "${q}".${erros.length ? ' ' + erros.join(' | ') : ''}`
  return [`Resultados (${fonte}) para "${q}":`, ...res.map((x, i) => `${i + 1}. ${x.titulo}\n   ${x.url}${x.resumo ? '\n   ' + x.resumo.slice(0, 300) : ''}`)].join('\n')
}
