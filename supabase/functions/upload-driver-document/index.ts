// upload-driver-document
// Recebe imagem em base64, faz upload para driver-documents usando service_role
// Body: { kind: 'selfie'|'document'|'vehicle', fileBase64, contentType? }
// Retorna: { success, public_url, path }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_BYTES = 10 * 1024 * 1024

function jsonResp(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResp(405, { error: 'method_not_allowed' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authHeader = req.headers.get('Authorization') ?? ''
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await userClient.auth.getUser()
  if (userErr || !userData.user) {
    return jsonResp(401, { error: 'unauthorized' })
  }
  const uid = userData.user.id

  let body: { kind?: string; fileBase64?: string; contentType?: string }
  try { body = await req.json() } catch (_) { return jsonResp(400, { error: 'invalid_json' }) }

  const { kind, fileBase64, contentType } = body
  if (!kind || !fileBase64) return jsonResp(400, { error: 'kind e fileBase64 obrigatorios' })
  if (!['selfie','document','vehicle'].includes(kind)) {
    return jsonResp(400, { error: 'kind deve ser selfie, document ou vehicle' })
  }

  let bytes: Uint8Array
  try {
    const raw = atob(fileBase64)
    if (raw.length > MAX_BYTES) return jsonResp(413, { error: 'file_too_large' })
    bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0))
  } catch (_) { return jsonResp(400, { error: 'invalid_base64' }) }

  const mime = contentType ?? 'image/jpeg'
  const ext = mime.includes('png') ? 'png' : mime.includes('webp') ? 'webp' : 'jpg'
  const path = `${uid}/${kind}_${Date.now()}.${ext}`

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } })

  const { error: uploadErr } = await admin.storage
    .from('driver-documents')
    .upload(path, bytes, { contentType: mime, upsert: true })

  if (uploadErr) {
    console.error('[upload-driver-document] failed:', uploadErr)
    return jsonResp(500, { error: 'upload_failed', detail: uploadErr.message })
  }

  // URL assinada valida 1 ano (para admin ver durante aprovacao)
  const { data: signedData } = await admin.storage
    .from('driver-documents')
    .createSignedUrl(path, 365 * 24 * 3600)

  console.log(`[upload-driver-document] OK uid=${uid} kind=${kind}`)
  return jsonResp(200, {
    success: true,
    path,
    signed_url: signedData?.signedUrl ?? null,
  })
})
