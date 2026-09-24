// upload-order-photo v1 (2026-05-13)
// Cliente faz upload de foto da encomenda (sendPackage) via service_role.
// Evita erro 403 RLS no storage.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResp(405, { error: 'method_not_allowed' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceKey) return jsonResp(500, { error: 'env_missing' })

  // Autenticar utilizador
  const authHeader = req.headers.get('Authorization') ?? ''
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await userClient.auth.getUser()
  if (userErr || !userData.user) return jsonResp(401, { error: 'unauthorized' })
  const userId = userData.user.id

  // Parse body
  let body: { fileBase64?: string; fileName?: string }
  try { body = await req.json() } catch (_) { return jsonResp(400, { error: 'invalid_json' }) }
  if (!body.fileBase64 || typeof body.fileBase64 !== 'string') return jsonResp(400, { error: 'fileBase64_required' })

  // Decode base64
  let bytes: Uint8Array
  try {
    const raw = atob(body.fileBase64)
    if (raw.length > MAX_BYTES) return jsonResp(413, { error: 'file_too_large' })
    bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0))
  } catch (_) { return jsonResp(400, { error: 'invalid_base64' }) }

  // Upload com service_role (bypassa RLS)
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } })
  const fileName = body.fileName ?? `${Date.now()}.jpg`
  const path = `${userId}/${fileName}`

  const { error: uploadErr } = await admin.storage
    .from('order-photos')
    .upload(path, bytes, { contentType: 'image/jpeg', upsert: true })

  if (uploadErr) {
    console.error('[upload-order-photo] upload failed:', uploadErr)
    return jsonResp(500, { error: 'upload_failed', detail: uploadErr.message })
  }

  const { data: urlData } = admin.storage.from('order-photos').getPublicUrl(path)

  return jsonResp(200, {
    success: true,
    path,
    bucket: 'order-photos',
    url: urlData.publicUrl,
  })
})
