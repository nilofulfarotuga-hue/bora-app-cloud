// @ts-nocheck
// supabase/functions/agentes-email-enviar/index.ts  v1  2026-10-21
//
// Caixa de e-mail dos agentes (missão agentes-email-2026-10-21): envia um e-mail EM NOME de um
// agente (<agente>@boraguarda.com) pelo Resend e regista-o em public.agentes_email (direcao='saida').
//
// verify_jwt = true. Dentro, só passa:
//   • o servidor (VPS/Emerson pelo `hermes email`, outra função) — chamadaDoServidor(req), ou
//   • um admin com sessão — is_admin() chamado com o JWT de quem pede.
// Qualquer outro → 403.
//
// Corpo JSON:
//   { agente, para (texto ou lista), assunto, texto, html?, idempotencia? }
//   { responder_a: <id de um e-mail recebido>, texto, html?, agente?, para?, assunto? }
//       → responde ao remetente, "Re: …", In-Reply-To/References, e marca o original como 'tratado'
//   { reenviar: <id de um e-mail enviado ou falhado> } → volta a mandar o mesmo conteúdo
//
// Limite diário (platform_settings.agentes_email_limite_dia) contado desde a meia-noite de Lisboa.
// A chave do Resend vem do cofre (get_resend_key); nunca vem do pedido.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { chamadaDoServidor, chavePublicavel, chaveSecreta, tokenBearer } from '../_shared/chaves.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const NOMES: Record<string, string> = {
  emerson: 'Emerson',
  suporte: 'Suporte',
  parceiros: 'Parceiros',
  vendas: 'Vendas',
  redes: 'Redes Sociais',
  radar: 'Radar',
  assinaturas: 'Assinaturas',
}
const DOMINIO = 'boraguarda.com'
const MAX_PEDIDO = 2_000_000
const MAX_DESTINOS = 10
const MAX_TEXTO = 200_000
const MAX_HTML = 500_000
const RE_EMAIL = /^[^\s@<>(),;:"]+@[^\s@<>(),;:"]+\.[A-Za-z]{2,}$/
const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405)

  const urlBase = Deno.env.get('SUPABASE_URL') ?? ''
  const admin = createClient(urlBase, chaveSecreta(), { auth: { persistSession: false } })

  // 1) Quem chama.
  let quem = ''
  if (await chamadaDoServidor(req)) {
    quem = 'servidor'
  } else {
    const token = tokenBearer(req)
    if (token && token.split('.').length === 3) {
      const comoUtilizador = createClient(urlBase, chavePublicavel(), {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false },
      })
      const { data: eAdmin } = await comoUtilizador.rpc('is_admin')
      if (eAdmin === true) quem = 'admin'
    }
  }
  if (!quem) return json({ ok: false, error: 'forbidden' }, 403)

  // 2) Pedido.
  let corpo: any
  try {
    const bruto = await req.text()
    if (bruto.length > MAX_PEDIDO) return json({ ok: false, error: 'pedido_grande_demais' }, 413)
    corpo = JSON.parse(bruto || '{}')
  } catch {
    return json({ ok: false, error: 'json_invalido' }, 400)
  }
  if (!corpo || typeof corpo !== 'object') return json({ ok: false, error: 'json_invalido' }, 400)

  const ativo = await setting(admin, 'agentes_email_ativo', true)
  if (ativo === false || ativo === 'false') return json({ ok: false, error: 'desligado' }, 503)

  let agente = String(corpo.agente ?? '').trim().toLowerCase()
  let para = listaDeEnderecos(corpo.para)
  let assunto = linha(corpo.assunto)
  let texto = corpo.texto != null ? limpar(String(corpo.texto)) : ''
  let html = corpo.html != null ? limpar(String(corpo.html)) : ''
  let emRespostaA: string | null = null
  let original: any = null

  if (corpo.responder_a != null) {
    const id = String(corpo.responder_a)
    if (!RE_UUID.test(id)) return json({ ok: false, error: 'responder_a_invalido' }, 400)
    const { data: r, error } = await admin
      .from('agentes_email')
      .select('id, agente, de, assunto, message_id, direcao')
      .eq('id', id)
      .maybeSingle()
    if (error) return json({ ok: false, error: 'db_leitura', detalhe: error.message }, 500)
    if (!r || r.direcao !== 'entrada') return json({ ok: false, error: 'original_nao_encontrado' }, 404)
    original = r
    if (!agente) agente = r.agente
    if (!para.length) para = listaDeEnderecos(enderecoDe(r.de))
    if (!assunto) {
      const a = linha(r.assunto)
      assunto = /^re:/i.test(a) ? a : `Re: ${a || '(sem assunto)'}`
    }
    if (r.message_id && !String(r.message_id).startsWith('sem-id:')) emRespostaA = String(r.message_id)
  }

  if (corpo.reenviar != null) {
    const id = String(corpo.reenviar)
    if (!RE_UUID.test(id)) return json({ ok: false, error: 'reenviar_invalido' }, 400)
    const { data: r, error } = await admin
      .from('agentes_email')
      .select('agente, para, assunto, texto, html, em_resposta_a, direcao')
      .eq('id', id)
      .maybeSingle()
    if (error) return json({ ok: false, error: 'db_leitura', detalhe: error.message }, 500)
    if (!r || r.direcao !== 'saida') return json({ ok: false, error: 'envio_nao_encontrado' }, 404)
    agente = r.agente
    para = listaDeEnderecos(r.para)
    assunto = linha(r.assunto)
    texto = r.texto ?? ''
    html = r.html ?? ''
    emRespostaA = r.em_resposta_a ?? null
  }

  // 3) Validar.
  if (!NOMES[agente]) return json({ ok: false, error: 'agente_desconhecido', agentes: Object.keys(NOMES) }, 400)
  if (!para.length) return json({ ok: false, error: 'sem_destinatario' }, 400)
  if (para.length > MAX_DESTINOS) return json({ ok: false, error: 'destinatarios_a_mais', limite: MAX_DESTINOS }, 400)
  const invalidos = para.filter((e) => !RE_EMAIL.test(e))
  if (invalidos.length) return json({ ok: false, error: 'endereco_invalido', invalidos }, 400)
  if (!texto.trim() && !html.trim()) return json({ ok: false, error: 'sem_conteudo' }, 400)
  if (!assunto) assunto = '(sem assunto)'
  assunto = assunto.slice(0, 300)
  texto = texto.slice(0, MAX_TEXTO)
  html = html.slice(0, MAX_HTML)

  // 4) Limite diário (desde a meia-noite de Lisboa).
  const limite = Number(await setting(admin, 'agentes_email_limite_dia', 80)) || 80
  const { count, error: erroConta } = await admin
    .from('agentes_email')
    .select('id', { count: 'exact', head: true })
    .eq('direcao', 'saida')
    .eq('estado', 'enviado')
    .gte('criado_em', inicioDoDiaLisboa())
  if (erroConta) return json({ ok: false, error: 'db_contagem', detalhe: erroConta.message }, 500)
  if ((count ?? 0) >= limite) {
    return json({ ok: false, error: 'limite_diario', enviados_hoje: count, limite }, 429)
  }

  // 5) Chave do Resend (cofre).
  const { data: chaveResend } = await admin.rpc('get_resend_key')
  const credResend = chaveResend ? String(chaveResend).trim() : ''
  if (!credResend) return json({ ok: false, error: 'resend_sem_chave' }, 500)

  const nomeBase = linha(await setting(admin, 'agentes_email_nome_remetente', 'Bora App')) || 'Bora App'
  const endereco = `${agente}@${DOMINIO}`
  const de = `${NOMES[agente]} - ${nomeBase.replace(/[<>"]/g, '')} <${endereco}>`
  const htmlFinal = html.trim() ? html : textoParaHtml(texto)

  const envio: any = {
    from: de,
    to: para,
    subject: assunto,
    html: htmlFinal,
    reply_to: endereco,
  }
  if (texto.trim()) envio.text = texto
  if (emRespostaA) envio.headers = { 'In-Reply-To': emRespostaA, References: emRespostaA }

  const cabecalhos: Record<string, string> = {
    Authorization: `Bearer ${credResend}`,
    'Content-Type': 'application/json',
  }
  if (corpo.idempotencia) cabecalhos['Idempotency-Key'] = String(corpo.idempotencia).slice(0, 256)

  let estado = 'enviado'
  let erro: string | null = null
  let resendId: string | null = null
  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: cabecalhos,
      body: JSON.stringify(envio),
    })
    const rb = await r.json().catch(() => ({}))
    if (r.ok && rb?.id) {
      resendId = String(rb.id)
    } else {
      estado = 'falhou'
      erro = `resend_${r.status}: ${String(rb?.message ?? rb?.name ?? '').slice(0, 300)}`
    }
  } catch (e) {
    estado = 'falhou'
    erro = `rede: ${String(e).slice(0, 300)}`
  }

  // 6) Registar (mesmo quando falha, para o painel mostrar e permitir reenviar).
  const registo = {
    direcao: 'saida',
    agente,
    de,
    para: para.join(', '),
    assunto,
    texto: texto || null,
    html: htmlFinal || null,
    anexos: [],
    tamanho_bytes: new TextEncoder().encode(htmlFinal + texto).byteLength,
    message_id: resendId ? `resend:${resendId}` : null,
    em_resposta_a: emRespostaA,
    estado,
    erro: erro ? `${erro} (por ${quem})` : null,
  }
  const { data: gravado, error: erroGravar } = await admin.from('agentes_email').insert(registo).select('id').single()

  if (estado === 'enviado' && original) {
    await admin.from('agentes_email').update({ estado: 'tratado' }).eq('id', original.id)
  }

  if (estado !== 'enviado') {
    return json({ ok: false, error: 'envio_falhou', detalhe: erro, id: gravado?.id ?? null }, 502)
  }
  return json({
    ok: true,
    id: gravado?.id ?? null,
    resend_id: resendId,
    de: endereco,
    para,
    registo_erro: erroGravar ? erroGravar.message : null,
  })
})

// ───────────────────────── ajudas ─────────────────────────

async function setting(admin: any, chave: string, omissao: any): Promise<any> {
  const { data, error } = await admin.from('platform_settings').select('value').eq('key', chave).maybeSingle()
  if (error || !data) return omissao
  return data.value ?? omissao
}

function listaDeEnderecos(v: any): string[] {
  const partes = Array.isArray(v) ? v : String(v ?? '').split(/[,;]/)
  const fora = partes
    .map((p) => enderecoDe(String(p ?? '')))
    .map((p) => p.trim().toLowerCase())
    .filter((p) => p.length > 0)
  return [...new Set(fora)]
}

function enderecoDe(s: string): string {
  const m = String(s ?? '').match(/<([^<>\s]+@[^<>\s]+)>/)
  return (m ? m[1] : String(s ?? '')).trim()
}

function linha(v: any): string {
  return limpar(String(v ?? '')).replace(/[\r\n]+/g, ' ').trim()
}

function limpar(s: string): string {
  return String(s ?? '').replace(/\u0000/g, '')
}

function textoParaHtml(t: string): string {
  const esc = t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5">${esc.replace(/\r?\n/g, '<br>')}</div>`
}

function inicioDoDiaLisboa(): string {
  const dia = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit', day: '2-digit',
  })
  const hora = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Lisbon', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  })
  const hoje = dia.format(new Date())
  // Lisboa está em UTC+0 (inverno) ou UTC+1 (verão): procura a hora UTC que é 00:00 em Lisboa.
  for (const desvio of [0, 1]) {
    const t = new Date(`${hoje}T00:00:00Z`)
    t.setUTCHours(t.getUTCHours() - desvio)
    if (hora.format(t) === '00:00' && dia.format(t) === hoje) return t.toISOString()
  }
  return new Date(`${hoje}T00:00:00Z`).toISOString()
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
