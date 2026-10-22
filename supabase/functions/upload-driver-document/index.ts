// upload-driver-document
// Recebe imagem em base64, faz upload para driver-documents usando service_role
// Body: { kind: 'selfie'|'document'|'vehicle'|'vehicle_doc', fileBase64, contentType? }
// Retorna: { success, signed_url, path }
//
// 22/10/2026 (missão cadastro-estafeta-fotos): a app mandava `image/jpg`
// (tirado da extensão) e o bucket só aceitava `image/jpeg` → 415 → 500 e o
// estafeta ficava sem fotos. O tipo passa a ser decidido pelos primeiros bytes
// (o cabeçalho só serve de desempate) e sai sempre com o nome oficial. O
// `vehicle_doc` (carta/livrete), que a app manda desde sempre, era recusado
// com 400 — passa a ser aceite.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { secretKey } from '../_shared/keys.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_BYTES = 10 * 1024 * 1024
const KINDS = ['selfie', 'document', 'vehicle', 'vehicle_doc']

function jsonResp(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

/** Tipo pelos primeiros bytes: jpeg/png/webp/pdf, 'heic' ou null. */
export function tipoPelosBytes(b: Uint8Array): string | null {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg'
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png'
  if (
    b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
    b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50
  ) return 'image/webp'
  if (b.length >= 5 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46) return 'application/pdf'
  if (b.length >= 12 && b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) {
    const marca = String.fromCharCode(b[8], b[9], b[10], b[11])
    if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'heim', 'heis', 'avif'].includes(marca)) return 'heic'
  }
  return null
}

/** `image/jpg`, `JPG`, `jpeg`… → nome oficial. */
export function normalizarMime(m: string | undefined | null): string {
  const v = (m ?? '').trim().toLowerCase()
  if (!v) return 'image/jpeg'
  if (v === 'image/jpg' || v === 'jpg' || v === 'jpeg' || v === 'image/pjpeg') return 'image/jpeg'
  if (v === 'png') return 'image/png'
  if (v === 'webp') return 'image/webp'
  return v
}

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'application/pdf': 'pdf',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return jsonResp(405, { error: 'method_not_allowed' })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = secretKey()!

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
  if (!KINDS.includes(kind)) {
    return jsonResp(400, { error: 'kind deve ser selfie, document, vehicle ou vehicle_doc' })
  }

  let bytes: Uint8Array
  try {
    const raw = atob(fileBase64)
    if (raw.length > MAX_BYTES) return jsonResp(413, { error: 'file_too_large' })
    bytes = Uint8Array.from(raw, (c) => c.charCodeAt(0))
  } catch (_) { return jsonResp(400, { error: 'invalid_base64' }) }

  const pelosBytes = tipoPelosBytes(bytes)
  if (pelosBytes === 'heic') {
    return jsonResp(415, { error: 'heic_nao_suportado', detail: 'converter para JPEG antes de enviar' })
  }
  const mime = pelosBytes ?? normalizarMime(contentType)
  const ext = EXT[mime]
  if (!ext) return jsonResp(415, { error: 'tipo_invalido', detail: mime })
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

  console.log(`[upload-driver-document] OK uid=${uid} kind=${kind} mime=${mime}`)
  return jsonResp(200, {
    success: true,
    path,
    signed_url: signedData?.signedUrl ?? null,
  })
})
