// @ts-nocheck
// supabase/functions/ficha-fiscalizacao-email/index.ts  v1  2026-09-23
//
// "Enviar cópia por e-mail" do ecrã Fiscalização do motorista TVDE: gera um
// PDF com a mesma ficha que o ecrã mostra à PSP/GNR e manda-o ao PRÓPRIO
// motorista (email da conta). Nunca a outra pessoa.
//
// Os dados vêm de `motorista_ficha_fiscalizacao()` chamada com o JWT do
// motorista — a mesma fonte do ecrã. Esta função não decide nada.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { PDFDocument, StandardFonts, rgb } from 'https://esm.sh/pdf-lib@1.17.1'

const EMAIL_FROM = 'Bora <recibos@boraguarda.com>'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } })
  const { data: me } = await userClient.auth.getUser()
  if (!me?.user) return json({ ok: false, error: 'sem_sessao' }, 401)
  const destino = me.user.email ?? ''
  if (!destino || destino.endsWith('@driver.bora.app')) {
    return json({ ok: false, error: 'sem_email', mensagem: 'A tua conta não tem e-mail. Pede ao apoio para o acrescentar.' })
  }

  const { data: ficha, error } = await userClient.rpc('motorista_ficha_fiscalizacao')
  if (error || !ficha) return json({ ok: false, error: error?.message ?? 'sem_ficha' }, 403)

  const pdf = await gerarPdf(ficha)

  const admin = createClient(supabaseUrl, serviceKey)
  let resendKey = Deno.env.get('RESEND_API_KEY') ?? null
  if (!resendKey) {
    const { data: k } = await admin.rpc('get_resend_key')
    if (k && String(k).trim()) resendKey = String(k).trim()
  }
  if (!resendKey) return json({ ok: false, error: 'resend_sem_chave' })

  const nome = ficha?.motorista?.nome ?? 'motorista'
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: EMAIL_FROM, to: [destino],
      subject: 'A tua ficha de fiscalização TVDE (Bora)',
      html: `<p>Olá ${esc(nome)},</p><p>Segue em anexo a cópia da tua ficha de fiscalização, gerada a ${esc(dataPt(ficha.gerado_em))}.</p>
<p>A página de verificação para a autoridade é válida até ${esc(dataPt(ficha?.verificacao?.expira_em))}:<br><a href="${esc(ficha?.verificacao?.url)}">${esc(ficha?.verificacao?.url)}</a></p><p>Bora</p>`,
      attachments: [{ filename: 'ficha-fiscalizacao-bora.pdf', content: b64(pdf) }],
    }),
  })
  const rb = await res.json().catch(() => ({}))
  if (!res.ok) return json({ ok: false, error: `resend_${res.status}`, detalhe: rb })
  return json({ ok: true, email: destino, id: rb?.id ?? null })
})

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
function esc(s: any): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}
function b64(bytes: Uint8Array): string {
  let s = ''
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(s)
}
function dataPt(iso: string | null | undefined): string {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString('pt-PT', { timeZone: 'Europe/Lisbon', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  } catch (_e) { return String(iso) }
}
function dia(d: string | null | undefined): string {
  if (!d) return 'por preencher'
  const [y, m, dd] = String(d).split('-')
  return `${dd}/${m}/${y}`
}
// Helvetica do pdf-lib só conhece WinAnsi: o que não couber vira "?".
function wa(s: any): string {
  return String(s ?? '—').replace(/[^\x20-\x7E -ÿ€•–—]/g, '?')
}
const MEIOS: Record<string, string> = { card: 'Cartão', mbway: 'MB Way', cash: 'Dinheiro' }
const ESTADOS: Record<string, string> = { valido: 'válido', a_expirar: 'a expirar', expirado: 'EXPIRADO', em_falta: 'por preencher' }

async function gerarPdf(f: any): Promise<Uint8Array> {
  const doc = await PDFDocument.create()
  const page = doc.addPage([595, 842])
  const font = await doc.embedFont(StandardFonts.Helvetica)
  const bold = await doc.embedFont(StandardFonts.HelveticaBold)
  const verde = rgb(0.086, 0.639, 0.29)
  let y = 800
  const t = (txt: string, size = 11, b = false, cor = rgb(0.1, 0.1, 0.1)) => {
    page.drawText(wa(txt), { x: 48, y, size, font: b ? bold : font, color: cor })
    y -= size + 7
  }
  const sec = (txt: string) => { y -= 6; t(txt, 13, true, verde) }

  t('Ficha de fiscalização TVDE', 18, true, verde)
  t(`Gerada a ${dataPt(f.gerado_em)} · Lei 45/2018 (rev. Lei 59/2026)`, 9)
  const m = f.motorista ?? {}, v = f.veiculo ?? {}, o = f.operador, p = f.plataforma ?? {}, vg = f.viagem
  sec('Motorista')
  t(`Nome: ${m.nome ?? '—'}`)
  t(`NIF: ${m.nif ?? '—'}`)
  t(`Certificado TVDE (IMT): ${m.tvde_cert_numero ?? '—'} · válido até ${dia(m.tvde_cert_validade)}`)
  t(`Carta de condução: ${m.carta_numero ?? '—'} · válida até ${dia(m.carta_validade)}`)
  sec('Veículo')
  t(`Matrícula: ${v.matricula ?? '—'}`, 14, true)
  t(`Marca/modelo: ${v.marca_modelo ?? '—'} · Cor: ${v.cor ?? '—'} · Ano: ${v.ano ?? '—'}`)
  t(`Dístico TVDE: ${v.distico_numero ?? '—'} · válido até ${dia(v.distico_validade)}`)
  t(`Inspeção válida até ${dia(v.inspecao_validade)}`)
  t(`Seguro: ${v.seguro_seguradora ?? '—'} · apólice ${v.seguro_apolice ?? '—'} · válido até ${dia(v.seguro_validade)}`)
  t(`Cobre passageiros: ${v.seguro_cobre_passageiros === true ? 'sim' : v.seguro_cobre_passageiros === false ? 'não' : '—'}`)
  sec('Operador TVDE')
  if (o) {
    t(`${o.nome} · NIF ${o.nif ?? '—'} · licença IMT ${o.licenca ?? '—'}`)
  } else {
    t('Motorista por conta própria (sem frota)')
  }
  sec('Operador de plataforma')
  t(`${p.nome ?? 'Bora'} · NIF ${p.nif ?? 'em processo'} · licença IMT ${p.licenca ?? 'em processo'}`)
  sec(vg?.em_curso ? 'Viagem em curso' : 'Última viagem')
  if (vg) {
    t(`Início: ${dataPt(vg.inicio)}`)
    t(`Origem: ${vg.origem ?? '—'}`, 10)
    t(`Destino: ${vg.destino ?? '—'}`, 10)
    const preco = vg.preco_cents != null ? (vg.preco_cents / 100).toFixed(2).replace('.', ',') + ' €' : '—'
    t(`Preço ${vg.preco_final ? 'cobrado' : 'estimado'}: ${preco} · Pagamento: ${MEIOS[vg.pagamento] ?? vg.pagamento ?? '—'} · Passageiro: ${vg.passageiro_inicial ?? '—'}`)
  } else {
    t('Sem viagens registadas.')
  }
  sec('Documentos')
  for (const d of f.documentos ?? []) t(`${d.rotulo}: ${ESTADOS[d.estado] ?? d.estado}${d.validade ? ' (' + dia(d.validade) + ')' : ''}`)
  sec('Verificação')
  t(`${f?.verificacao?.url ?? '—'}`, 10)
  t(`Válida até ${dataPt(f?.verificacao?.expira_em)}`, 9)
  return await doc.save()
}
