// auditar-site.mjs - auditoria de SO LEITURA a um site NOSSO. Codigo nosso (missao C-liga, 30/10/2026).
// So faz GET/HEAD/OPTIONS simples, com pausa entre pedidos, e RECUSA qualquer dominio que nao seja do Bora.
// Uso: node auditar-site.mjs boraguarda.com
// Saida: JSON no stdout (achados com severidade, evidencia e correcao). Nao explora nada, nao envia dados, nao guarda nada.
import tls from 'node:tls'
import crypto from 'node:crypto'

const PERMITIDOS = [/^(www\.)?boraguarda\.com$/, /^[a-z0-9-]+\.boraguarda\.com$/, /^ojykpzwqrtusfeakzrna\.supabase\.co$/]
const alvo = String(process.argv[2] ?? '').replace(/^https?:\/\//, '').replace(/\/.*$/, '').toLowerCase()
if (!alvo || !PERMITIDOS.some((re) => re.test(alvo))) {
  console.error(`RECUSADO: ${alvo || '(vazio)'} nao e um dominio do Bora. Só audito o que é nosso (boraguarda.com e subdominios, e a nossa API do Supabase).`)
  process.exit(3)
}
const UA = 'bora-audit/1.0 (leitura; dono do site)'
const pausa = (ms) => new Promise((r) => setTimeout(r, ms))
const achados = []
const info = {}
const achado = (id, severidade, titulo, evidencia, correcao) => achados.push({ id, severidade, titulo, evidencia, correcao })

async function pedir(url, opcoes = {}) {
  try {
    const r = await fetch(url, { redirect: 'manual', method: opcoes.metodo ?? 'GET', headers: { 'user-agent': UA, ...(opcoes.headers ?? {}) }, signal: AbortSignal.timeout(15000) })
    const corpo = opcoes.semCorpo ? '' : (await r.text()).slice(0, 200000)
    await pausa(400)
    return { status: r.status, headers: r.headers, corpo }
  } catch (e) {
    await pausa(400)
    return { status: 0, headers: new Headers(), corpo: '', erro: String(e.cause?.code ?? e.message).slice(0, 80) }
  }
}
const assinatura = (t) => crypto.createHash('sha1').update(t.replace(/\s+/g, ' ').slice(0, 4000)).digest('hex').slice(0, 10)

// 1. pagina inicial e HTTP -> HTTPS
const home = await pedir(`https://${alvo}/`)
info.home = { status: home.status, erro: home.erro, servidor: home.headers.get('server') ?? null }
const http = await pedir(`http://${alvo}/`, { semCorpo: true })
info.http_para_https = { status: http.status, location: http.headers.get('location') }
if (http.status !== 0 && !(http.status >= 300 && http.status < 400 && /^https:/i.test(http.headers.get('location') ?? ''))) {
  achado('http-sem-redirecao', 'media', 'O endereço http:// não redireciona para https://', `GET http://${alvo}/ -> ${http.status} (location: ${http.headers.get('location') ?? 'nenhum'})`, 'Ligar "Always Use HTTPS" na Cloudflare.')
}

// 2. cabecalhos de seguranca
const h = home.headers
const hsts = h.get('strict-transport-security')
if (!hsts) achado('sem-hsts', 'media', 'Falta o cabeçalho HSTS', `GET https://${alvo}/ sem strict-transport-security`, 'Cabeçalho Strict-Transport-Security: max-age=31536000; includeSubDomains.')
else if ((/max-age=(\d+)/i.exec(hsts)?.[1] ?? 0) < 15552000) achado('hsts-curto', 'baixa', 'HSTS com validade curta', `strict-transport-security: ${hsts}`, 'max-age de pelo menos 6 meses.')
if (!h.get('content-security-policy')) achado('sem-csp', 'media', 'Falta a Content-Security-Policy', 'sem content-security-policy na página inicial', 'Definir uma CSP que limite de onde se carregam scripts.')
if ((h.get('x-content-type-options') ?? '').toLowerCase() !== 'nosniff') achado('sem-nosniff', 'baixa', 'Falta X-Content-Type-Options: nosniff', `x-content-type-options: ${h.get('x-content-type-options') ?? 'ausente'}`, 'Acrescentar X-Content-Type-Options: nosniff.')
if (!h.get('x-frame-options') && !/frame-ancestors/i.test(h.get('content-security-policy') ?? '')) achado('sem-anti-framing', 'baixa', 'A página pode ser posta dentro de outra (clickjacking)', 'sem x-frame-options nem frame-ancestors', 'X-Frame-Options: SAMEORIGIN ou CSP frame-ancestors.')
if (!h.get('referrer-policy')) achado('sem-referrer-policy', 'baixa', 'Falta Referrer-Policy', 'referrer-policy ausente', 'Referrer-Policy: strict-origin-when-cross-origin.')
if (!h.get('permissions-policy')) achado('sem-permissions-policy', 'informativa', 'Falta Permissions-Policy', 'permissions-policy ausente', 'Limitar câmara, microfone e localização.')
for (const nome of ['x-powered-by', 'x-aspnet-version', 'x-generator']) if (h.get(nome)) achado(`revela-${nome}`, 'baixa', `O servidor revela tecnologia (${nome})`, `${nome}: ${h.get(nome)}`, 'Remover o cabeçalho.')
const cookies = h.getSetCookie?.() ?? []
info.cookies_na_home = cookies.length
for (const c of cookies) {
  const nome = c.split('=')[0]
  const falta = [!/;\s*secure/i.test(c) && 'Secure', !/;\s*httponly/i.test(c) && 'HttpOnly', !/;\s*samesite/i.test(c) && 'SameSite'].filter(Boolean)
  if (falta.length) achado(`cookie-${nome}`, 'baixa', `Cookie ${nome} sem ${falta.join(', ')}`, c.replace(/=[^;]*/, '=[valor]'), 'Pôr os atributos em falta.')
}

// 3. CORS reflexivo
const cors = await pedir(`https://${alvo}/`, { headers: { origin: 'https://exemplo-malicioso.test' }, semCorpo: true })
const acao = cors.headers.get('access-control-allow-origin')
info.cors_origem_estranha = acao ?? null
if (acao === 'https://exemplo-malicioso.test' || (acao === '*' && cors.headers.get('access-control-allow-credentials') === 'true')) {
  achado('cors-aberto', 'alta', 'CORS aceita qualquer origem', `Origin estranha -> access-control-allow-origin: ${acao}`, 'Lista fechada de origens permitidas.')
}

// 4. TLS
info.tls = await new Promise((resolve) => {
  const s = tls.connect({ host: alvo, port: 443, servername: alvo, timeout: 10000 }, () => {
    const c = s.getPeerCertificate()
    const dias = Math.round((new Date(c.valid_to) - Date.now()) / 86400000)
    resolve({ protocolo: s.getProtocol(), emitido_por: c.issuer?.O ?? c.issuer?.CN, valido_ate: c.valid_to, dias_para_expirar: dias })
    s.end()
  })
  s.on('error', (e) => resolve({ erro: String(e.code ?? e.message) }))
  s.on('timeout', () => { resolve({ erro: 'timeout' }); s.destroy() })
})
if (info.tls.dias_para_expirar != null && info.tls.dias_para_expirar < 21) achado('tls-a-expirar', 'alta', 'Certificado perto de expirar', `${info.tls.dias_para_expirar} dias`, 'Renovar o certificado.')
if (/TLSv1(\.0|\.1)?$/.test(info.tls.protocolo ?? '')) achado('tls-antigo', 'media', 'TLS antigo aceite', info.tls.protocolo, 'Exigir TLS 1.2 ou superior.')

// 5. ficheiros que nao deviam estar publicos (so conta se o conteudo bate com o tipo; paginas que repetem a inicial nao contam)
const assinaturaHome = assinatura(home.corpo)
const SONDAS = [
  ['/.env', (c) => /^[A-Z][A-Z0-9_]+=.+/m.test(c), 'alta', 'Ficheiro .env público'],
  ['/.git/HEAD', (c) => /^ref:\s*refs\//.test(c), 'alta', 'Repositório git exposto (.git)'],
  ['/.git/config', (c) => /\[core\]/.test(c), 'alta', 'Configuração do git exposta'],
  ['/.dart_defines', (c) => /^[A-Z][A-Z0-9_]+=.+/m.test(c), 'alta', 'Chaves da app (.dart_defines) públicas'],
  ['/package.json', (c) => /"name"\s*:/.test(c) && c.trim().startsWith('{'), 'media', 'package.json público'],
  ['/pubspec.yaml', (c) => /^name:\s*\w+/m.test(c) && /dependencies:/.test(c), 'media', 'pubspec.yaml público'],
  ['/.DS_Store', (c) => c.startsWith('\u0000\u0000\u0000\u0001Bud1'), 'baixa', '.DS_Store público'],
  ['/main.dart.js.map', (c) => c.trim().startsWith('{') && /"sources"\s*:/.test(c), 'media', 'Mapa de código-fonte público (main.dart.js.map)'],
]
info.sondas = {}
for (const [caminho, bate, sev, titulo] of SONDAS) {
  const r = await pedir(`https://${alvo}${caminho}`)
  const repete = r.status === 200 && assinatura(r.corpo) === assinaturaHome
  info.sondas[caminho] = r.status === 200 ? (repete ? '200 (repete a página inicial)' : '200') : String(r.status)
  if (r.status === 200 && !repete && bate(r.corpo)) achado(`exposto${caminho.replace(/[^\w]+/g, '-')}`, sev, titulo, `GET https://${alvo}${caminho} -> 200 com conteúdo do tipo certo`, 'Retirar o ficheiro do site publicado.')
}

// 6. ficheiros informativos
for (const caminho of ['/robots.txt', '/sitemap.xml', '/.well-known/security.txt']) {
  const r = await pedir(`https://${alvo}${caminho}`, { semCorpo: true })
  info.sondas[caminho] = r.status
}
if (info.sondas['/.well-known/security.txt'] !== 200) achado('sem-security-txt', 'informativa', 'Falta security.txt', '/.well-known/security.txt não existe', 'Publicar um contacto para quem encontrar falhas.')

// 7. mistura de http dentro de https e scripts de terceiros
const mistos = [...home.corpo.matchAll(/(?:src|href)=["'](http:\/\/[^"']+)["']/gi)].map((m) => m[1]).filter((u) => !/w3\.org/.test(u))
info.recursos_http_na_home = mistos.length
if (mistos.length) achado('conteudo-misto', 'media', 'Página https carrega recursos http', mistos.slice(0, 3).join(' | '), 'Trocar por https://.')
const externos = [...new Set([...home.corpo.matchAll(/<script[^>]+src=["'](https?:\/\/[^"']+)["']/gi)].map((m) => new URL(m[1]).host).filter((x) => x !== alvo))]
info.scripts_de_terceiros = externos
const semIntegridade = [...home.corpo.matchAll(/<script[^>]+src=["']https?:\/\/(?!(?:www\.)?boraguarda\.com)[^"']+["'][^>]*>/gi)].filter((m) => !/integrity=/i.test(m[0]))
if (semIntegridade.length) achado('script-externo-sem-sri', 'baixa', 'Script de terceiros sem verificação de integridade (SRI)', `${semIntegridade.length} script(s) externos sem integrity`, 'Acrescentar integrity= e crossorigin=.')

const ordem = { alta: 0, media: 1, baixa: 2, informativa: 3 }
achados.sort((a, b) => ordem[a.severidade] - ordem[b.severidade])
console.log(JSON.stringify({ alvo, quando: new Date().toISOString(), total: achados.length, achados, informativo: info }, null, 2))
