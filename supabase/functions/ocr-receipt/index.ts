// @ts-nocheck
// supabase/functions/ocr-receipt/index.ts
//
// v11 (2026-08-16 — CORRECOES 1o DIA + adendo 4): tres upgrades apos o caso
// real do Valdemir (2 talaos "nao conseguiu ler" e uma foto do SACO aceite):
//   1. RETRY com modelo mais forte (gemini-3.1-flash) quando o lite devolve
//      tudo vazio — o lite (downgrade de 2026-08-12) e fraco para talao.
//   2. `looks_like_receipt` na resposta: total+linhas+loja todos vazios =
//      isto nao parece um talao — a app avisa e pede outra foto ANTES de aceitar.
//   3. Gancho do PRECO VIVO: linhas parseadas -> RPC
//      catalog_price_update_from_receipt (nao-parceiros, guardas, auditoria).
//
// Fase 6 (Bloco 3) — Extrai talao estruturado:
//   { store, total_cents, lines[{name,qty,unit_price_cents}], datetime }
// e grava em order_receipts_v2.receipt_parsed* + receipt_match.
//
// Settings (platform_settings):
//   receipt_ocr_enabled            — kill-switch (default true)
//   receipt_divergence_alert_cents — threshold |digitado-parsed| (default 100)
//
// Armadilha gemini flash: thinkingBudget=0 obrigatorio (memoria do projecto).
// Secrets: GEMINI_API_KEY (se em falta → no-op gracioso).
//
// v12 (M10 b2-nif, 09/11/2026): o modelo le tambem o NIF do ADQUIRENTE impresso no talao
// (buyer_nif) e compara-se com o NIF que o estafeta tinha de dar na caixa (_nif_caixa_regra,
// loja nao-parceira / Favor com compra). Em falta ou diferente -> ocr_flagged (revisao no
// painel) + aviso nif_talao_diferente com os dois numeros. Resultado em receipt_parsed.nif_check
// e na resposta (nif). Sem a migracao 20261109010000 no servidor nao faz nada. Ver nif_talao.ts.
//
// v13 (missao volta-deposito-kfc, 09/11/2026): (1) o modelo devolve tambem o NIF da loja
// (seller_nif) e todos os NIF impressos (nifs); o NIF do cliente escolhe-se entre eles, nunca o
// da loja (talao do KFC 2190210d: "N. Contrib. 502604735" da loja + "NIF:123456789" do cliente
// davam nif_em_falta). (2) o modelo devolve as linhas a 0,00 dos menus e as linhas de deposito e
// de saco como linhas proprias — o robo do catalogo soma os menus e as caixas e o servidor trata o
// deposito Volta (gatilho trg_talao_deposito_volta).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { exigirCallerOk, secretKey } from '../_shared/keys.ts'
import { respostaAoPing } from '../_shared/chaves.ts'
import { avisarNifDoTalao, escolherNifCliente, limparNif, verificarNifDoTalao } from './nif_talao.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const DEFAULT_DIVERGENCE_CENTS = 100 // €1.00 — Fase 1.C setting
const DEFAULT_LEGACY_FLAG_CENTS = 50 // legacy storeShopping (ocr_flagged)

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  // 16/10/2026 (chave nova): verify_jwt passa a false — quem chama tem de ser o servidor (chave secreta,
  // ou a legada confirmada no Auth) ou um utilizador com sessão válida. Ver _shared/keys.ts.
  const bloqueio = await exigirCallerOk(req, corsHeaders)
  if (bloqueio) return bloqueio
  const pong = await respostaAoPing(req, corsHeaders) // vigia diário das chaves (31/10/2026)
  if (pong) return pong

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = secretKey()!
  const geminiKey = Deno.env.get('GEMINI_API_KEY')

  let orderId: string
  try {
    const body = await req.json()
    orderId = String(body.order_id ?? '')
  } catch {
    return json({ ok: false, error: 'invalid_json' }, 400)
  }
  if (!orderId) return json({ ok: false, error: 'order_id required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

  // Kill-switch (Fase 1.C)
  const settings = await loadSettings(supabase)
  if (settings.ocrEnabled === false) {
    return json({ ok: false, reason: 'ocr_disabled' })
  }

  const { data: receipt, error: recErr } = await supabase
    .from('order_receipts_v2')
    .select('id, photo_url, driver_typed_total_cents')
    .eq('order_id', orderId)
    .maybeSingle()

  if (recErr || !receipt) {
    return json({ ok: false, reason: 'no_receipt' })
  }

  if (!geminiKey) {
    console.warn('[ocr-receipt] GEMINI_API_KEY not set — skipping (shadow no-op)')
    return json({ ok: false, reason: 'gemini_not_configured' })
  }

  // Download receipt photo from Storage
  let photoBytes: Uint8Array
  try {
    let path = receipt.photo_url
    if (path.startsWith('http')) {
      const m = path.match(/\/object\/(?:public|sign|authenticated)\/receipts\/(.+?)(?:\?|$)/)
      if (m) path = m[1]
      else path = path.split('receipts/').pop() || ''
    } else {
      path = path.replace(/^receipts\//, '')
    }
    const dl = await supabase.storage.from('receipts').download(path)
    if (dl.error || !dl.data) throw dl.error || new Error('download_failed')
    photoBytes = new Uint8Array(await dl.data.arrayBuffer())
  } catch (e) {
    console.error('[ocr-receipt] storage download error:', e)
    await markFailed(supabase, receipt.id, 'storage_download_error')
    return json({ ok: false, reason: 'storage_download_error' })
  }

  // Chamada Gemini — v11: lite primeiro; vazio -> retry 1x com o flash forte.
  const b64 = base64Encode(photoBytes)
  let parsed: ParsedReceipt | null = null
  let rawResponse: unknown = null
  let modelUsed = 'gemini-3.1-flash-lite'
  try {
    const first = await callGemini(geminiKey, 'gemini-3.1-flash-lite', b64)
    parsed = first.parsed
    rawResponse = first.raw
    if (first.httpError) {
      await markFailed(supabase, receipt.id, `gemini_${first.httpError}`)
      return json({ ok: false, reason: 'gemini_error', detail: first.raw })
    }
    if (isEmptyParse(parsed)) {
      console.log('[ocr-receipt] lite devolveu vazio — retry com gemini-3.1-flash')
      const second = await callGemini(geminiKey, 'gemini-3.1-flash', b64)
      if (!second.httpError && !isEmptyParse(second.parsed)) {
        parsed = second.parsed
        rawResponse = second.raw
        modelUsed = 'gemini-3.1-flash'
      }
    }
  } catch (e) {
    console.error('[ocr-receipt] gemini call error:', e)
    await markFailed(supabase, receipt.id, 'gemini_exception')
    return json({ ok: false, reason: 'gemini_exception' })
  }

  // v11: nada extraido = provavelmente NAO e um talao (caso real: foto do saco).
  const looksLikeReceipt = !isEmptyParse(parsed)

  // Divergencia (Fase 6): |digitado - parsed| > receipt_divergence_alert_cents → match=false
  const parsedTotal = parsed?.total_cents ?? null
  const typedTotal = receipt.driver_typed_total_cents
  const divergenceLimit = settings.divergenceCents ?? DEFAULT_DIVERGENCE_CENTS
  const diffCents = parsedTotal != null ? typedTotal - parsedTotal : null
  const match = parsedTotal == null ? null : Math.abs(diffCents!) <= divergenceLimit
  const legacyFlagged = diffCents != null && Math.abs(diffCents) > DEFAULT_LEGACY_FLAG_CENTS

  // v12 — NIF do talao vs NIF que tinha de ser dado na caixa (nunca lanca).
  // v13: o NIF do cliente escolhe-se entre todos os impressos (nunca o da loja) — ver escolherNifCliente.
  const nifCheck = await verificarNifDoTalao(supabase, orderId, parsed?.buyer_nif ?? null, looksLikeReceipt,
    { seller: parsed?.seller_nif ?? null, nifs: parsed?.nifs ?? [] })
  const nifFlagged = nifCheck.aplica === true && nifCheck.ok === false
  const buyerNifFinal = (nifCheck as { talao?: string | null }).talao
    ?? escolherNifCliente(parsed?.buyer_nif ?? null, parsed?.seller_nif ?? null, parsed?.nifs ?? [], null)

  // O depósito Volta das linhas do talão (DEPOSITO, VALOR DE DEPOSITO, VASILHAME…) é tratado no
  // servidor pelo gatilho trg_talao_deposito_volta quando receipt_parsed muda (PARTE 2 da missão
  // volta-deposito-kfc-2026-11-09); aqui só se lê e grava.
  await supabase.from('order_receipts_v2').update({
    receipt_parsed: parsed ? { ...parsed, buyer_nif: buyerNifFinal, nif_check: nifCheck } : parsed,
    receipt_parsed_total_cents: parsedTotal,
    receipt_parsed_store: parsed?.store ?? null,
    receipt_match: match,
    ocr_extracted_total_cents: parsedTotal,
    ocr_diff_cents: diffCents,
    ocr_flagged: legacyFlagged || !looksLikeReceipt || nifFlagged,
    ocr_raw_response: rawResponse,
    ocr_ran_at: new Date().toISOString(),
  }).eq('id', receipt.id)

  const nifAvisado = nifFlagged ? await avisarNifDoTalao(supabase, orderId, nifCheck) : false

  // v11 — PRECO VIVO: linhas parseadas -> motor de atualizacao de catalogo
  // (so nao-parceiros; guardas ±30%; auditoria; kill switch proprio na RPC).
  let priceLive: unknown = null
  if (parsed && Array.isArray(parsed.lines) && parsed.lines.length > 0) {
    try {
      const { data: plData, error: plErr } = await supabase.rpc(
        'catalog_price_update_from_receipt', { p_receipt_id: receipt.id })
      priceLive = plErr ? { error: plErr.message } : plData
      console.log('[ocr-receipt] preco-vivo:', JSON.stringify(priceLive))
    } catch (e) {
      console.error('[ocr-receipt] preco-vivo exception:', e)
    }
  }

  return json({
    ok: true,
    looks_like_receipt: looksLikeReceipt,
    model_used: modelUsed,
    parsed_total_cents: parsedTotal,
    parsed_store: parsed?.store ?? null,
    parsed_lines_count: parsed?.lines?.length ?? 0,
    diff_cents: diffCents,
    match,
    divergence_limit: divergenceLimit,
    price_live: priceLive,
    nif: { ...nifCheck, avisado: nifAvisado },
  })
})

// ── Helpers ───────────────────────────────────────────────────────────────

type ParsedLine = { name: string; qty: number; unit_price_cents: number }
type ParsedReceipt = {
  store: string | null
  total_cents: number | null
  lines: ParsedLine[]
  datetime: string | null
  buyer_nif: string | null // v12: NIF do adquirente impresso no talao (9 digitos) ou null
  seller_nif?: string | null // v13: NIF/NIPC da loja (cabecalho)
  nifs?: string[] // v13: todos os NIF de 9 digitos impressos no talao
}

function isEmptyParse(p: ParsedReceipt | null): boolean {
  return !p || (p.total_cents == null && (!p.lines || p.lines.length === 0) && !p.store)
}

async function callGemini(key: string, model: string, b64: string):
  Promise<{ parsed: ParsedReceipt | null; raw: unknown; httpError: number | null }> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`
  const prompt =
    'Lê este talão de compra e devolve JSON ESTRITO (sem markdown, sem prosa). ' +
    'Schema: {"store": string|null, "total_cents": integer|null, ' +
    '"lines": [{"name": string, "qty": number, "unit_price_cents": integer}], ' +
    '"datetime": "YYYY-MM-DDTHH:MM" or null, "buyer_nif": string|null, ' +
    '"seller_nif": string|null, "nifs": [string]}. ' +
    'Regras: total_cents é o total final em cêntimos de euro (€12.34 → 1234). ' +
    'lines são TODAS as linhas de artigos pela ordem impressa, uma por linha do talão: qty é a quantidade ' +
    'e unit_price_cents o preço de UMA unidade (se só houver o total da linha, divide pela quantidade). ' +
    'Inclui as linhas a 0,00 (ex.: "MENU KENTUCKY BBQ 0,00" seguido das sublinhas do menu), as linhas ' +
    'de depósito de embalagens (DEPOSITO, VALOR DE DEPOSITO, VASILHAME, SDR, VOLTA) e de sacos, cada ' +
    'uma como linha própria; ignora linhas de traços. lines pode ser [] se não conseguires distinguir produtos. ' +
    'store é o nome da loja/farmácia/supermercado (sem morada). ' +
    'datetime usa hora local do talão se visível. ' +
    'seller_nif é o NIF/NIPC da LOJA (no cabeçalho, junto ao nome/morada, muitas vezes "N. Contrib.", ' +
    '"Contribuinte", "NIPC"). nifs são TODOS os números de 9 dígitos impressos junto a "NIF", "Contrib", ' +
    '"Contribuinte" ou "NIPC", em qualquer parte do talão. ' +
    'buyer_nif é o NIF do CLIENTE/adquirente (linhas como "NIF:", "NIF Cliente", "NIF Adquirente", ' +
    '"Contribuinte:"), só os 9 dígitos; NUNCA o NIF/NIPC da loja. Atenção: há talões (ex.: KFC) com os dados da ' +
    'empresa e "N. Contrib." da loja e, logo a seguir, uma linha "NIF:" com OUTRO número — esse é o do ' +
    'cliente. Se diz "Consumidor final" ou não há NIF do cliente, null. ' +
    'Se não conseguires ler o talão, devolve {"store":null,"total_cents":null,"lines":[],"datetime":null,' +
    '"buyer_nif":null,"seller_nif":null,"nifs":[]}.'
  const payload = {
    contents: [{
      parts: [
        { text: prompt },
        { inline_data: { mime_type: 'image/jpeg', data: b64 } },
      ],
    }],
    generationConfig: {
      temperature: 0,
      response_mime_type: 'application/json',
      maxOutputTokens: 2048,
      thinkingConfig: { thinkingBudget: 0 },
    },
  }
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  const raw = await r.json().catch(() => ({}))
  if (!r.ok) return { parsed: null, raw, httpError: r.status }
  const text = (raw as any)?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}'
  let parsed: ParsedReceipt | null = null
  try { parsed = sanitizeParsed(JSON.parse(text)) } catch { parsed = null }
  return { parsed, raw, httpError: null }
}

function sanitizeParsed(raw: any): ParsedReceipt {
  const store = typeof raw?.store === 'string' && raw.store.trim().length
    ? String(raw.store).trim().slice(0, 200) : null
  const total = typeof raw?.total_cents === 'number' && raw.total_cents > 0
    ? Math.round(raw.total_cents) : null
  const datetime = typeof raw?.datetime === 'string' ? raw.datetime.slice(0, 32) : null
  const buyerNif = limparNif(raw?.buyer_nif)
  const sellerNif = limparNif(raw?.seller_nif)
  const nifs: string[] = Array.isArray(raw?.nifs)
    ? [...new Set(raw.nifs.map(limparNif).filter((n: string | null): n is string => !!n))].slice(0, 10) as string[]
    : []
  const lines: ParsedLine[] = Array.isArray(raw?.lines)
    ? raw.lines
        .filter((l: any) => l && typeof l.name === 'string')
        .slice(0, 100) // hard-cap defensivo
        .map((l: any) => ({
          name: String(l.name).slice(0, 200),
          qty: typeof l.qty === 'number' && l.qty > 0 ? l.qty : 1,
          unit_price_cents: typeof l.unit_price_cents === 'number' && l.unit_price_cents >= 0
            ? Math.round(l.unit_price_cents)
            : 0,
        }))
    : []
  return { store, total_cents: total, lines, datetime, buyer_nif: buyerNif, seller_nif: sellerNif, nifs }
}

async function loadSettings(supabase: any): Promise<{ ocrEnabled: boolean; divergenceCents: number }> {
  try {
    const { data } = await supabase
      .from('platform_settings')
      .select('key, value')
      .in('key', ['receipt_ocr_enabled', 'receipt_divergence_alert_cents'])
    let ocrEnabled = true
    let divergenceCents = DEFAULT_DIVERGENCE_CENTS
    for (const row of data ?? []) {
      if (row.key === 'receipt_ocr_enabled') ocrEnabled = parseJsonBool(row.value)
      if (row.key === 'receipt_divergence_alert_cents') {
        const v = parseJsonInt(row.value)
        if (v != null && v > 0) divergenceCents = v
      }
    }
    return { ocrEnabled, divergenceCents }
  } catch {
    return { ocrEnabled: true, divergenceCents: DEFAULT_DIVERGENCE_CENTS }
  }
}

function parseJsonBool(v: any): boolean {
  if (typeof v === 'boolean') return v
  if (typeof v === 'string') return v === 'true' || v === '"true"'
  return Boolean(v)
}

function parseJsonInt(v: any): number | null {
  if (typeof v === 'number') return Math.round(v)
  if (typeof v === 'string') {
    const s = v.replace(/"/g, '')
    const n = Number.parseInt(s, 10)
    return Number.isFinite(n) ? n : null
  }
  return null
}

async function markFailed(supabase: any, receiptId: string, reason: string) {
  try {
    await supabase.from('order_receipts_v2').update({
      ocr_ran_at: new Date().toISOString(),
      ocr_raw_response: { error: reason },
    }).eq('id', receiptId)
  } catch (_e) {}
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function base64Encode(bytes: Uint8Array): string {
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i])
  return btoa(s)
}
