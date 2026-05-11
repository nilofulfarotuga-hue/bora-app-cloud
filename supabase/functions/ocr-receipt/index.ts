// @ts-nocheck
// supabase/functions/ocr-receipt/index.ts
//
// 5G — Shadow OCR. Lê foto talão do Storage, chama Gemini 1.5 Flash vision,
// extrai total, compara com driver_typed_total_cents. Marca ocr_flagged=true
// se diff > 0.50 EUR. Sempre devolve 200 (Decisão H: shadow, não-bloqueante).
//
// Secrets: GEMINI_API_KEY (se em falta → no-op gracioso).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const geminiKey   = Deno.env.get('GEMINI_API_KEY')

  let orderId: string
  try {
    const body = await req.json()
    orderId = String(body.order_id ?? '')
  } catch {
    return json({ ok: false, error: 'invalid_json' }, 400)
  }
  if (!orderId) return json({ ok: false, error: 'order_id required' }, 400)

  const supabase = createClient(supabaseUrl, serviceKey)

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

  // Call Gemini 1.5 Flash vision
  let ocrTotalCents: number | null = null
  let rawResponse: unknown = null
  try {
    const b64 = base64Encode(photoBytes)
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`
    const payload = {
      contents: [{
        parts: [
          { text: 'Extract the TOTAL amount from this receipt photo. Return ONLY valid JSON: {"total_cents": <integer or null>, "currency": "EUR"}. The total_cents is the final amount paid in euro cents (e.g. 1234 for €12.34). If you cannot determine the total, return total_cents: null.' },
          { inline_data: { mime_type: 'image/jpeg', data: b64 } },
        ],
      }],
      generationConfig: { temperature: 0, response_mime_type: 'application/json' },
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
    const parsed = JSON.parse(text)
    if (typeof parsed.total_cents === 'number') {
      ocrTotalCents = Math.round(parsed.total_cents)
    }
  } catch (e) {
    console.error('[ocr-receipt] gemini call error:', e)
    await markFailed(supabase, receipt.id, 'gemini_exception')
    return json({ ok: false, reason: 'gemini_exception' })
  }

  const diffCents = ocrTotalCents != null
    ? receipt.driver_typed_total_cents - ocrTotalCents
    : null
  const flagged = diffCents != null && Math.abs(diffCents) > 50

  await supabase.from('order_receipts_v2').update({
    ocr_extracted_total_cents: ocrTotalCents,
    ocr_diff_cents:            diffCents,
    ocr_flagged:               flagged,
    ocr_raw_response:          rawResponse,
    ocr_ran_at:                new Date().toISOString(),
  }).eq('id', receipt.id)

  return json({ ok: true, ocr_total_cents: ocrTotalCents, diff_cents: diffCents, flagged })
})

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
