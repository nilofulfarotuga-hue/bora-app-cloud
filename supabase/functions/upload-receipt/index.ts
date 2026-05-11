// supabase/functions/upload-receipt/index.ts
//
// BUG #1 v2 (sessão exec 2026-05-12 pós-teste manual)
//
// Padrão idêntico a `upload-avatar`: cliente envia base64 + orderId,
// Edge Function valida ownership server-side e faz upload via service_role
// (bypass de storage rate limits que causavam HTTP 400 silenciosos no
// cliente Flutter mesmo com path correcto).
//
// Deployed via MCP em 2026-05-12. Este ficheiro é sync repo para
// dev/staging fresh (deploy via supabase CLI).
//
// API:
//   POST /functions/v1/upload-receipt
//   Headers: Authorization: Bearer <user_jwt>, Content-Type: application/json
//   Body: { orderId: string, fileBase64: string, totalCents?: number }
//
// Returns:
//   200 { success: true, path, bucket, order_id, total_cents }
//   400 invalid_json | orderId_required | fileBase64_required | invalid_base64
//   401 unauthorized
//   403 not_your_order
//   404 order_not_found
//   413 file_too_large
//   500 env_missing | upload_failed

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_BYTES = 10 * 1024 * 1024 // 10MB

function jsonResp(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return jsonResp(405, { error: 'method_not_allowed' })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResp(500, { error: 'env_missing' })
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await userClient.auth.getUser()
  if (userErr || !userData.user) {
    return jsonResp(401, { error: 'unauthorized', detail: userErr?.message })
  }
  const callerId = userData.user.id

  let body: { orderId?: string; fileBase64?: string; totalCents?: number }
  try {
    body = await req.json()
  } catch (_) {
    return jsonResp(400, { error: 'invalid_json' })
  }
  if (!body.orderId || typeof body.orderId !== 'string') {
    return jsonResp(400, { error: 'orderId_required' })
  }
  if (!body.fileBase64 || typeof body.fileBase64 !== 'string') {
    return jsonResp(400, { error: 'fileBase64_required' })
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  })
  const { data: order, error: orderErr } = await admin
    .from('orders')
    .select('id, assigned_driver_id, status')
    .eq('id', body.orderId)
    .single()
  if (orderErr || !order) {
    return jsonResp(404, { error: 'order_not_found', detail: orderErr?.message })
  }
  if (order.assigned_driver_id !== callerId) {
    return jsonResp(403, { error: 'not_your_order' })
  }

  let bytes: Uint8Array
  try {
    const raw = atob(body.fileBase64)
    if (raw.length > MAX_BYTES) {
      return jsonResp(413, { error: 'file_too_large', max_bytes: MAX_BYTES })
    }
    bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0))
  } catch (_) {
    return jsonResp(400, { error: 'invalid_base64' })
  }

  const path = `${body.orderId}.jpg`
  const { error: uploadErr } = await admin.storage.from('receipts').upload(
    path,
    bytes,
    { contentType: 'image/jpeg', upsert: true },
  )
  if (uploadErr) {
    console.error('[upload-receipt] upload failed:', uploadErr)
    return jsonResp(500, { error: 'upload_failed', detail: uploadErr.message })
  }

  return jsonResp(200, {
    success: true,
    path,
    bucket: 'receipts',
    order_id: body.orderId,
    total_cents: body.totalCents ?? null,
  })
})
