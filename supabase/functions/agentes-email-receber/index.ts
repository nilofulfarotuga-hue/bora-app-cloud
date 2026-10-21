// @ts-nocheck
// supabase/functions/agentes-email-receber/index.ts  v1  2026-10-21
//
// Caixa de e-mail dos agentes (missão agentes-email-2026-10-21).
// E-mail de fora para <agente>@boraguarda.com → Cloudflare Email Routing → Worker "agentes-email"
// → ESTA função → tabela public.agentes_email (+ anexos no bucket privado "agentes-email").
//
// verify_jwt = false DE PROPÓSITO: quem chama é o Worker da Cloudflare, sem sessão Supabase.
// A porta é o segredo partilhado `agentes_email_key` (cofre do banco, lido por
// get_agentes_email_key(), só service_role) no cabeçalho `x-agentes-email-segredo`,
// comparado em tempo constante. Sem segredo certo → 403, nada é lido nem gravado.
//
// O Worker manda: corpo = e-mail cru (RFC 822); cabeçalhos x-agentes-email-para (destinatário
// do envelope, um só) e x-agentes-email-de (remetente do envelope).
//
// Defensivo: corpo grande (413), anexos grandes ou a mais (ficam listados mas não guardados),
// o mesmo e-mail repetido para o MESMO agente (Message-ID; sem Message-ID usa o resumo SHA-256
// do e-mail cru) não entra duas vezes, remetente sem nome, HTML sem texto (o texto sai do HTML),
// caracteres NUL tirados (o Postgres recusa-os).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import PostalMime from 'npm:postal-mime@2.7.6'
import { chaveSecreta, iguais } from '../_shared/chaves.ts'

const AGENTES = ['emerson', 'suporte', 'parceiros', 'vendas', 'redes', 'radar', 'assinaturas']
// Endereços que a norma pede que existam; vão para a caixa do Emerson.
const APELIDOS: Record<string, string> = { postmaster: 'emerson', abuse: 'emerson' }
const DOMINIO = 'boraguarda.com'
const BUCKET = 'agentes-email'
const MAX_CRU = 26 * 1024 * 1024 // a Cloudflare não entrega mais de 25 MiB
const MAX_ANEXO = 10 * 1024 * 1024 // = limite do bucket
const MAX_ANEXOS = 20
const MAX_TEXTO = 200_000
const MAX_HTML = 500_000

let segredoEmCache: { valor: string; ate: number } | null = null

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405)

  const urlBase = Deno.env.get('SUPABASE_URL') ?? ''
  const admin = createClient(urlBase, chaveSecreta(), { auth: { persistSession: false } })

  // 1) Porta: segredo partilhado com o Worker.
  const recebido = (req.headers.get('x-agentes-email-segredo') ?? '').trim()
  const esperado = await segredo(admin)
  if (!esperado) return json({ ok: false, error: 'sem_segredo_no_cofre' }, 500)
  if (!recebido || !(await iguais(recebido, esperado))) return json({ ok: false, error: 'forbidden' }, 403)

  // 2) Interruptor do painel.
  const ativo = await setting(admin, 'agentes_email_ativo', true)
  if (ativo === false || ativo === 'false') return json({ ok: false, error: 'desligado' }, 503)

  // 3) Para que agente.
  const envelopePara = limpar(req.headers.get('x-agentes-email-para') ?? '').trim().toLowerCase()
  const envelopeDe = limpar(req.headers.get('x-agentes-email-de') ?? '').trim()
  const agente = agenteDe(envelopePara)
  if (!agente) return json({ ok: false, error: 'agente_desconhecido', para: envelopePara }, 404)

  // 4) Corpo cru, com limite.
  const declarado = Number(req.headers.get('content-length') ?? '0')
  if (Number.isFinite(declarado) && declarado > MAX_CRU) {
    return json({ ok: false, error: 'grande_demais', bytes: declarado, limite: MAX_CRU }, 413)
  }
  let cru: Uint8Array
  try {
    cru = new Uint8Array(await req.arrayBuffer())
  } catch (e) {
    return json({ ok: false, error: 'corpo_ilegivel', detalhe: String(e).slice(0, 200) }, 400)
  }
  if (cru.byteLength === 0) return json({ ok: false, error: 'vazio' }, 400)
  if (cru.byteLength > MAX_CRU) return json({ ok: false, error: 'grande_demais', bytes: cru.byteLength, limite: MAX_CRU }, 413)

  let email: any
  try {
    email = await PostalMime.parse(cru)
  } catch (e) {
    return json({ ok: false, error: 'mime_invalido', detalhe: String(e).slice(0, 200) }, 422)
  }

  // 5) Identidade da mensagem (para não duplicar).
  const messageId = normalizarId(email?.messageId) ?? `sem-id:${await sha256hex(cru)}`

  const { data: ja, error: erroJa } = await admin
    .from('agentes_email')
    .select('id')
    .eq('direcao', 'entrada')
    .eq('agente', agente)
    .eq('message_id', messageId)
    .maybeSingle()
  if (erroJa) return json({ ok: false, error: 'db_leitura', detalhe: erroJa.message }, 500)
  if (ja) return json({ ok: true, duplicado: true, id: ja.id, agente })

  // 6) Campos.
  const deEndereco = limpar(
    email?.from?.address || email?.sender?.address || email?.from?.group?.[0]?.address || envelopeDe || '',
  ).trim()
  const deNome = limpar(email?.from?.name || email?.sender?.name || '').replace(/[<>"\r\n]/g, ' ').replace(/\s+/g, ' ').trim()
  const de = cortar(deEndereco ? (deNome ? `${deNome} <${deEndereco}>` : deEndereco) : 'desconhecido', 500)

  const html = cortar(limpar(email?.html ?? ''), MAX_HTML)
  let texto = limpar(email?.text ?? '')
  if (!texto.trim() && html) texto = htmlParaTexto(html)
  texto = cortar(texto, MAX_TEXTO)

  const assunto = cortar(limpar(email?.subject ?? '').replace(/[\r\n]+/g, ' ').trim(), 998) || null
  const emRespostaA = normalizarId(email?.inReplyTo)

  // 7) Anexos → bucket privado.
  const pasta = `${agente}/${hojeLisboa()}/${crypto.randomUUID()}`
  const anexos: any[] = []
  const guardados: string[] = []
  const lista = Array.isArray(email?.attachments) ? email.attachments : []
  for (let i = 0; i < lista.length; i++) {
    const a = lista[i]
    const bytes = paraBytes(a?.content)
    const nome = nomeSeguro(a?.filename) || `anexo-${i + 1}`
    const info: any = {
      nome,
      tipo: String(a?.mimeType || 'application/octet-stream').slice(0, 120),
      bytes: bytes.byteLength,
      inline: a?.disposition === 'inline',
      content_id: a?.contentId ? String(a.contentId).slice(0, 200) : null,
      caminho: null,
      guardado: false,
    }
    if (i >= MAX_ANEXOS) { anexos.push({ ...info, motivo: 'demasiados_anexos' }); continue }
    if (bytes.byteLength === 0) { anexos.push({ ...info, motivo: 'vazio' }); continue }
    if (bytes.byteLength > MAX_ANEXO) { anexos.push({ ...info, motivo: 'grande_demais' }); continue }
    const caminho = `${pasta}/${i + 1}-${nome}`
    const { error } = await admin.storage.from(BUCKET).upload(caminho, bytes, {
      contentType: info.tipo,
      upsert: false,
    })
    if (error) {
      anexos.push({ ...info, motivo: `falhou_upload: ${String(error.message).slice(0, 120)}` })
      continue
    }
    guardados.push(caminho)
    anexos.push({ ...info, caminho, guardado: true })
  }

  // 8) Gravar.
  const linha = {
    direcao: 'entrada',
    agente,
    de,
    para: cortar(envelopePara || `${agente}@${DOMINIO}`, 500),
    assunto,
    texto: texto || null,
    html: html || null,
    anexos,
    tamanho_bytes: cru.byteLength,
    message_id: messageId,
    em_resposta_a: emRespostaA,
    estado: 'novo',
  }
  const { data, error } = await admin.from('agentes_email').insert(linha).select('id').single()
  if (error) {
    if (guardados.length) await admin.storage.from(BUCKET).remove(guardados).catch(() => {})
    if (error.code === '23505') return json({ ok: true, duplicado: true, agente })
    return json({ ok: false, error: 'db_escrita', detalhe: error.message }, 500)
  }
  return json({
    ok: true,
    id: data.id,
    agente,
    anexos_guardados: guardados.length,
    anexos_recusados: anexos.length - guardados.length,
  })
})

// ───────────────────────── ajudas ─────────────────────────

async function segredo(admin: any): Promise<string> {
  const agora = Date.now()
  if (segredoEmCache && segredoEmCache.ate > agora) return segredoEmCache.valor
  const { data, error } = await admin.rpc('get_agentes_email_key')
  if (error || !data) return ''
  const valor = String(data).trim()
  segredoEmCache = { valor, ate: agora + 5 * 60 * 1000 }
  return valor
}

async function setting(admin: any, chave: string, omissao: any): Promise<any> {
  const { data, error } = await admin.from('platform_settings').select('value').eq('key', chave).maybeSingle()
  if (error || !data) return omissao
  return data.value ?? omissao
}

function agenteDe(endereco: string): string | null {
  const m = endereco.match(/^([^@\s]+)@([^@\s]+)$/)
  if (!m) return null
  if (m[2] !== DOMINIO) return null
  const local = m[1].split('+')[0]
  if (AGENTES.includes(local)) return local
  return APELIDOS[local] ?? null
}

function normalizarId(v: any): string | null {
  if (v == null) return null
  let s = limpar(String(Array.isArray(v) ? v[0] : v)).trim()
  if (!s) return null
  const m = s.match(/<[^<>\s]+>/)
  if (m) s = m[0]
  else s = `<${s.replace(/[<>\s]/g, '')}>`
  return s.length > 2 ? s.slice(0, 500) : null
}

function paraBytes(c: any): Uint8Array {
  if (!c) return new Uint8Array(0)
  if (c instanceof Uint8Array) return c
  if (c instanceof ArrayBuffer) return new Uint8Array(c)
  if (ArrayBuffer.isView(c)) return new Uint8Array(c.buffer, c.byteOffset, c.byteLength)
  if (typeof c === 'string') return new TextEncoder().encode(c)
  return new Uint8Array(0)
}

function nomeSeguro(n: any): string {
  const base = String(n ?? '')
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^A-Za-z0-9._-]+/g, '_')
    .replace(/^[._]+/, '')
    .slice(-100)
  return base
}

function limpar(s: string): string {
  return String(s ?? '').replace(/\u0000/g, '')
}

function cortar(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) : s
}

function htmlParaTexto(html: string): string {
  return html
    .replace(/<(script|style|head)[^>]*>[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s*\n\s*\n+/g, '\n\n')
    .trim()
}

function hojeLisboa(): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date())
}

async function sha256hex(bytes: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return Array.from(h, (b) => b.toString(16).padStart(2, '0')).join('')
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { 'Content-Type': 'application/json' } })
}
