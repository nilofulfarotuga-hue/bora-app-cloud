// @ts-nocheck
// supabase/functions/ocr-receipt/index.ts
//
// Fase 6 (Bloco 3) — Upgrade Gemini 2.5-flash. Extrai talão estruturado:
//   { store, total_cents, lines[{name,qty,unit_price_cents}], datetime }
// e grava em order_receipts_v2.receipt_parsed* + receipt_match.
//
// Mantém o shadow legacy de storeShopping (ocr_extracted_total_cents/diff/flagged)
// para retrocompat — o valor digitado pelo estafeta continua a ser a fonte de verdade.
//
// Settings (platform_settings):
//   receipt_ocr_enabled            — kill-switch (default true)
//   receipt_divergence_alert_cents — threshold |digitado-parsed| (default 100)
//
// Armadilha gemini-2.5-flash: thinkingBudget=0 obrigatório (memória do projecto),
// senão maxOutputTokens é consumido em "thinking" e o output JSON sai truncado.
//
// Secrets: GEMINI_API_KEY (se em falta → no-op gracioso).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const DEFAULT_DIVERGENCE_CENTS = 100 // €1.00 — Fase 1.C setting
const DEFAULT_LEGACY_FLAG_CENTS = 50 // legacy storeShopping (ocr_flagged)

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
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

  // Call Gemini 2.5 Flash vision — JSON estruturado
  let parsed: ParsedReceipt | null = null
  let rawResponse: unknown = null
  try {
    const b64 = base64Encode(photoBytes)
    // 2026-08-12: era gemini-2.5-flash — retirado para projectos novos (404) depois de
    // a GEMINI_API_KEY passar para um projecto sem faturação. thinkingBudget=0 continua válido.
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=${geminiKey}`
    const prompt =
      'Lê este talão de compra e devolve JSON ESTRITO (sem markdown, sem prosa). ' +
      'Schema: {"store": string|null, "total_cents": integer|null, ' +
      '"lines": [{"name": string, "qty": number, "unit_price_cents": integer}], ' +
      '"datetime": "YYYY-MM-DDTHH:MM" or null}. ' +
      'Regras: total_cents é o total final em cêntimos de euro (€12.34 → 1234). ' +
      'lines pode ser [] se não conseguires distinguir produtos. ' +
      'store é o nome da loja/farmácia/supermercado (sem morada). ' +
      'datetime usa hora local do talão se visível. ' +
      'Se não conseguires ler o talão, devolve {"store":null,"total_cents":null,"lines":[],"datetime":null}.'
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
        // ARMADILHA gemini-2.5-flash: thinkingBudget=0 obrigatório.
        thinkingConfig: { thinkingBudget: 0 },
      },
    }
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    rawResponse = await r.json().catch(() => ({}))
    if (!r.ok) {
      await markFailed(supabase, receipt.id, `gemini_${r.status}`)
      return json({ ok: false, reason: 'gemini_error', detail: rawResponse })
    }
    const text = (rawResponse as any)?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}'
    parsed = sanitizeParsed(JSON.parse(text))
  } catch (e) {
    console.error('[ocr-receipt] gemini call error:', e)
    await markFailed(supabase, receipt.id, 'gemini_exception')
    return json({ ok: false, reason: 'gemini_exception' })
  }

  // Divergência (Fase 6): |digitado - parsed| > receipt_divergence_alert_cents → match=false
  const parsedTotal = parsed?.total_cents ?? null
  const typedTotal = receipt.driver_typed_total_cents
  const divergenceLimit = settings.divergenceCents ?? DEFAULT_DIVERGENCE_CENTS
  const diffCents = parsedTotal != null ? typedTotal - parsedTotal : null
  const match = parsedTotal == null ? null : Math.abs(diffCents!) <= divergenceLimit
  // Legacy ocr_flagged mantém threshold legacy 50 cents para retrocompat
  const legacyFlagged = diffCents != null && Math.abs(diffCents) > DEFAULT_LEGACY_FLAG_CENTS

  await supabase.from('order_receipts_v2').update({
    // Campos novos (Fase 1 schema)
    receipt_parsed: parsed,
    receipt_parsed_total_cents: parsedTotal,
    receipt_parsed_store: parsed?.store ?? null,
    receipt_match: match,
    // Campos legacy (retrocompat shadow)
    ocr_extracted_total_cents: parsedTotal,
    ocr_diff_cents: diffCents,
    ocr_flagged: legacyFlagged,
    ocr_raw_response: rawResponse,
    ocr_ran_at: new Date().toISOString(),
  }).eq('id', receipt.id)

  return json({
    ok: true,
    parsed_total_cents: parsedTotal,
    parsed_store: parsed?.store ?? null,
    diff_cents: diffCents,
    match,
    divergence_limit: divergenceLimit,
  })
})

// ── Helpers ───────────────────────────────────────────────────────────────

type ParsedLine = { name: string; qty: number; unit_price_cents: number }
type ParsedReceipt = {
  store: string | null
  total_cents: number | null
  lines: ParsedLine[]
  datetime: string | null
}

function sanitizeParsed(raw: any): ParsedReceipt {
  const store = typeof raw?.store === 'string' && raw.store.trim().length
    ? String(raw.store).trim().slice(0, 200) : null
  const total = typeof raw?.total_cents === 'number' && raw.total_cents > 0
    ? Math.round(raw.total_cents) : null
  const datetime = typeof raw?.datetime === 'string' ? raw.datetime.slice(0, 32) : null
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
  return { store, total_cents: total, lines, datetime }
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
