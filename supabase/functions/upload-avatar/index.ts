// Edge Function: upload-avatar
// ─────────────────────────────────────────────────────────────────────────────
// Fallback path for client avatar uploads when direct storage upload fails
// (e.g. stale JWT, transient RLS issues, network conditions).
//
// Flow:
//  1. Caller sends Authorization: Bearer <user-jwt> + JSON body with bytes.
//  2. We verify the JWT belongs to a real user (anon client + getUser()).
//  3. We use service_role to upload to avatars bucket — bypassing RLS.
//  4. Returns public URL.
//
// Security:
//  - Requires verify_jwt=true (deploy flag).
//  - We further confirm via getUser() that the caller is actually who they say.
//  - Path is forced to {userId}/avatar_{ts}.jpg — caller cannot upload to
//    another user's folder.
//  - File size limit: 2 MB (decoded base64). Prevents abuse.
//  - contentType is forced to 'image/jpeg'.
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_BYTES = 2 * 1024 * 1024 // 2 MB

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

  // ── Verify caller identity via JWT ──────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await userClient.auth.getUser()
  if (userErr || !userData.user) {
    return jsonResp(401, { error: 'unauthorized', detail: userErr?.message })
  }
  const callerId = userData.user.id

  // ── Parse body ──────────────────────────────────────────────────────────
  let body: { fileBase64?: string; contentType?: string }
  try {
    body = await req.json()
  } catch (_) {
    return jsonResp(400, { error: 'invalid_json' })
  }
  if (!body.fileBase64 || typeof body.fileBase64 !== 'string') {
    return jsonResp(400, { error: 'fileBase64_required' })
  }

  // ── Decode base64 with size guard ───────────────────────────────────────
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

  // ── Upload via service-role client (bypasses RLS) ───────────────────────
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  })
  const path = `${callerId}/avatar_${Date.now()}.jpg`
  const { error: uploadErr } = await admin.storage.from('avatars').upload(
    path,
    bytes,
    { contentType: 'image/jpeg', upsert: true },
  )
  if (uploadErr) {
    console.error('[upload-avatar] upload failed:', uploadErr)
    return jsonResp(500, { error: 'upload_failed', detail: uploadErr.message })
  }

  const { data: urlData } = admin.storage.from('avatars').getPublicUrl(path)
  const publicUrl = urlData.publicUrl

  // Cache-bust suffix so app sees the new image immediately
  const versionedUrl = `${publicUrl}?v=${Date.now()}`

  // Persist photo URL in user_metadata via admin auth API.
  try {
    await admin.auth.admin.updateUserById(callerId, {
      user_metadata: { bora_photo_url: versionedUrl },
    })
  } catch (e) {
    // Non-fatal — caller should also try to update via their own SDK.
    console.warn('[upload-avatar] updateUserById failed:', e)
  }

  return jsonResp(200, {
    success: true,
    path,
    public_url: publicUrl,
    versioned_url: versionedUrl,
  })
})
