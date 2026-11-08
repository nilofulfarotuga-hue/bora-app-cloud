---
id: memoria-claude-ai-proposta-m1-2026-11-08-edge-upload-receipt
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 adendo 1 — Edge upload-receipt v2 (index.ts completo; nunca substitui, confirma no servidor)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-edge-upload-receipt`, origem `claude-code`, atualizada em 2026-11-08T21:12:12.248892+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 edge upload receipt · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08, adendo 1 (Claude Code do PC, 08/11/2026). Ficheiro: supabase/functions/upload-receipt/index.ts. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio).

```ts
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
//   Body: { orderId: string, fileBase64: string, totalCents?: number, fotoId?: string, tiradaEm?: ISO }
//
// Returns:
//   200 { success: true, path, bucket, order_id, total_cents, foto_id, confirmado, tamanho_bytes, repetida }
//   (path = AAAA/MM/<order_id>/<fotoId>.jpg desde 08/11/2026; as antigas <order_id>.jpg ficam como estão)
//   400 invalid_json | orderId_required | fileBase64_required | invalid_base64
//   401 unauthorized
//   403 not_your_order
//   404 order_not_found
//   413 file_too_large
//   500 env_missing | upload_failed

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { secretKey } from '../_shared/keys.ts'

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
  const serviceKey = secretKey()
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

  let body: { orderId?: string; fileBase64?: string; totalCents?: number; fotoId?: string; tiradaEm?: string }
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
    .select('id, assigned_driver_id, current_driver_offer_id, status')
    .eq('id', body.orderId)
    .single()
  if (orderErr || !order) {
    return jsonResp(404, { error: 'order_not_found', detail: orderErr?.message })
  }
  // Primary check: assigned_driver_id set (normal accepted flow)
  // Fallback: assigned_driver_id is NULL (race condition — dispatch set status before
  // Flutter wrote assigned_driver_id) but caller holds the active offer.
  const isOwner =
    order.assigned_driver_id === callerId ||
    (order.assigned_driver_id == null && order.current_driver_offer_id === callerId)
  if (!isOwner) {
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

  // M1 adendo 1 (08/11/2026, Danilo: "toda foto de talão ... nunca se pode perder"):
  // cada foto tem o SEU ficheiro, nunca substituído (antes era <order_id>.jpg com upsert:true e a
  // 2.ª foto apagava a 1.ª). Caminho: AAAA/MM/<order_id>/<fotoId>.jpg (mês de Lisboa da foto).
  // fotoId vem da app (o mesmo em cada nova tentativa da MESMA foto) → repetir não duplica nem
  // apaga: se o ficheiro já existe, é a mesma foto e devolve-se o mesmo caminho.
  const fotoId = (typeof body.fotoId === 'string' && /^[A-Za-z0-9_-]{6,64}$/.test(body.fotoId))
    ? body.fotoId
    : `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`
  const tirada = typeof body.tiradaEm === 'string' && !Number.isNaN(Date.parse(body.tiradaEm))
    ? new Date(body.tiradaEm) : new Date()
  const partes = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit' })
    .formatToParts(tirada)
  const ano = partes.find((p) => p.type === 'year')?.value ?? String(tirada.getUTCFullYear())
  const mes = partes.find((p) => p.type === 'month')?.value ?? String(tirada.getUTCMonth() + 1).padStart(2, '0')
  const pasta = `${ano}/${mes}/${body.orderId}`
  const nome = `${fotoId}.jpg`
  const path = `${pasta}/${nome}`
  const { error: uploadErr } = await admin.storage.from('receipts').upload(
    path,
    bytes,
    { contentType: 'image/jpeg', upsert: false },
  )
  const jaExistia = !!uploadErr && /exist|duplicate|409/i.test(`${uploadErr.message} ${(uploadErr as { statusCode?: string }).statusCode ?? ''}`)
  if (uploadErr && !jaExistia) {
    console.error('[upload-receipt] upload failed:', uploadErr)
    return jsonResp(500, { error: 'upload_failed', detail: uploadErr.message })
  }

  // Confirmação no servidor: o ficheiro existe e não está vazio. Só então a app diz "guardado".
  const { data: lista, error: listErr } = await admin.storage.from('receipts').list(pasta, { search: nome, limit: 5 })
  const obj = (lista ?? []).find((o: { name: string }) => o.name === nome) as { metadata?: { size?: number } } | undefined
  const tamanho = Number(obj?.metadata?.size ?? 0)
  if (listErr || !obj || tamanho <= 0) {
    console.error('[upload-receipt] confirmação falhou:', listErr?.message, path, tamanho)
    return jsonResp(500, { error: 'upload_not_confirmed', detail: listErr?.message ?? `tamanho=${tamanho}` })
  }

  // Registo de TODAS as fotos (tabela order_receipt_fotos, proposta 07). Sem a tabela no ar, a
  // foto continua guardada e o pedido fecha na mesma; o erro fica no log.
  const { error: regErr } = await admin.from('order_receipt_fotos').upsert({
    order_id: body.orderId, bucket: 'receipts', path, foto_id: fotoId,
    total_cents: Number.isInteger(body.totalCents) ? body.totalCents : null,
    driver_uid: callerId, tirada_em: tirada.toISOString(), tamanho_bytes: tamanho, origem: 'upload-receipt',
  }, { onConflict: 'path', ignoreDuplicates: true })
  if (regErr) console.warn('[upload-receipt] registo da foto falhou (foto guardada):', regErr.message)

  return jsonResp(200, {
    success: true,
    path,
    bucket: 'receipts',
    order_id: body.orderId,
    total_cents: body.totalCents ?? null,
    foto_id: fotoId,
    confirmado: true,
    tamanho_bytes: tamanho,
    repetida: jaExistia,
  })
})

```

