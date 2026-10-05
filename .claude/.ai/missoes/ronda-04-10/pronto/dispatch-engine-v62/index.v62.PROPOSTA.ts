// @ts-nocheck
// dispatch-engine v62 (ronda 04/10/2026) — duas mudanças, mais nada:
//   (1) QUEM PODE CHAMAR. Até aqui qualquer pessoa na internet podia acordar o
//       motor (verify_jwt=false e nenhuma verificação). Agora só passa: a chave
//       de serviço (a do ambiente ou a do cofre do banco, validada na Auth), um
//       admin, um estafeta aprovado, o dono do pedido ou o dono da loja do
//       pedido. É a mesma autenticação do notify-driver v42, mais os papéis com
//       que a app chama o motor. verify_jwt continua false.
//   (2) QUEM RECEBE A OFERTA. Os candidatos vêm TODOS de
//       public.dispatch_candidatos_entrega(order_id) — o matching das entregas
//       num sítio só: online + aprovado + não banido + batimento E GPS frescos
//       (dispatch_gps_fresh_seconds_entregas) + uma oferta viva de cada vez +
//       favor sozinho + máx. 3 ativos + raio (dispatch_raio_max_oferta_km),
//       já ordenados (mesma loja primeiro, depois o mais perto).
//   Ofertas, TTL, claim, redispatch e identidade (v59) ficam IGUAIS.
// dispatch-engine v59 (2026-08-16) — FIX identidade do estafeta (drivers.id vs drivers.user_id).
//   PROBLEMA PROVADO: a app do estafeta consulta ofertas/pedidos por auth.uid()
//   (= drivers.user_id), mas o engine gravava drivers.id em current_driver_offer_id.
//   Para estafetas em que id <> user_id (ex: Valdemir) a oferta NUNCA aparecia no
//   ecra e driver_accept_offer (que exige current_driver_offer_id = auth.uid())
//   rejeitava sempre. So funcionava para as contas em que id == user_id.
//   v59: current_driver_offer_id passa a levar drivers.user_id (fallback id);
//   toda a exclusao/contagem passa a aceitar OS DOIS formatos (legado incluido).
// dispatch-engine v58 — work_mode + dual-driver (AUTORIZADO Danilo 2026-07-02):
//   • filtro work_mode: 'rides_only' fica fora do matching de entregas
//     (padrão defensivo work_mode IS NULL OR <> 'rides_only'; default 'everything');
//   • dual-driver: 'carro_passageiros' elegível para entregas (conta como carro
//     nos serviços que exigem carro) MAS excluído enquanto tem corrida TVDE ativa.
//   Nada mais mudou: ofertas, timeouts, rotação e pricing intactos.
// dispatch-engine v57 — TTL honrado em TODOS os caminhos + claim anti-duplicação de cadeias.
//
// ROOT CAUSE do loop 5M+ invocações (corrigido aqui + bora_dispatch_maintenance v2):
//   (1) decideRedispatch caso "pendente sem oferta" reagendava a cada 10s SEM TTL;
//   (2) sem oferta ativa não havia deteção de dono da cadeia → cada invocação externa
//       (trigger, maintenance, manual) criava uma cadeia self-sustaining NOVA;
//   (3) dispatch_max_total_seconds_with_drivers_online nunca era aplicado e o safety
//       só corria com drivers online.
// v57:
//   • loadDispatchSettings lê também dispatch_max_total_seconds_with_drivers_online
//     e dispatch_auto_cancel_safety_seconds;
//   • TTL excedido → RPC dispatch_cancel_expired_order (cancel + alerta admin +
//     push cliente) e a cadeia TERMINA;
//   • claim atómico em orders.dispatch_next_retry_at: só a cadeia que ganha o
//     UPDATE condicional agenda o próximo retry — N cadeias colapsam em 1.
// v56 — notify-driver movido para DB trigger tr_notify_driver_on_offer.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const DEFAULT_OFFER_TIMEOUT_SECONDS = 40
const DEFAULT_RETRY_NO_DRIVER_SECONDS = 10
const DEFAULT_MAX_TOTAL_SECONDS = 1200
const DEFAULT_SAFETY_SECONDS = 1800
const REDISPATCH_MAX_RETRIES = 3
const REDISPATCH_RETRY_DELAY_MS = 2000

// v59: um estafeta pode ser referido por drivers.id OU drivers.user_id.
function driverKeys(d: any): string[] {
  const ks: string[] = []
  if (d?.id) ks.push(String(d.id))
  if (d?.user_id && String(d.user_id) !== String(d.id)) ks.push(String(d.user_id))
  return ks
}
function offerKeyFor(d: any): string {
  // A app do estafeta filtra por auth.uid() = drivers.user_id.
  return String(d?.user_id ?? d?.id)
}

type DispatchSettings = {
  offerTimeoutS: number
  retryNoDriverS: number
  maxTotalS: number
  safetyS: number
}

async function loadDispatchSettings(supabase: any): Promise<DispatchSettings> {
  try {
    const { data, error } = await supabase.from('platform_settings').select('key, value')
      .in('key', [
        'dispatch_offer_timeout_seconds',
        'dispatch_retry_no_driver_seconds',
        'dispatch_max_total_seconds_with_drivers_online',
        'dispatch_auto_cancel_safety_seconds',
      ])
    if (error) throw error
    const map = new Map<string, number>()
    for (const row of data ?? []) {
      const n = typeof row.value === 'number' ? row.value : Number(row.value)
      if (!Number.isNaN(n)) map.set(row.key, n)
    }
    return {
      offerTimeoutS: map.get('dispatch_offer_timeout_seconds') ?? DEFAULT_OFFER_TIMEOUT_SECONDS,
      retryNoDriverS: map.get('dispatch_retry_no_driver_seconds') ?? DEFAULT_RETRY_NO_DRIVER_SECONDS,
      maxTotalS: map.get('dispatch_max_total_seconds_with_drivers_online') ?? DEFAULT_MAX_TOTAL_SECONDS,
      safetyS: map.get('dispatch_auto_cancel_safety_seconds') ?? DEFAULT_SAFETY_SECONDS,
    }
  } catch (e) {
    console.warn('[dispatch-engine] loadDispatchSettings failed:', e)
    return {
      offerTimeoutS: DEFAULT_OFFER_TIMEOUT_SECONDS,
      retryNoDriverS: DEFAULT_RETRY_NO_DRIVER_SECONDS,
      maxTotalS: DEFAULT_MAX_TOTAL_SECONDS,
      safetyS: DEFAULT_SAFETY_SECONDS,
    }
  }
}

function sleep(ms: number): Promise<void> { return new Promise(r => setTimeout(r, ms)) }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabase = createClient(supabaseUrl, serviceKey)
  let orderId: string | null = null
  try { const b = await req.json(); orderId = b?.orderId ?? null } catch (_) {}
  const autorizado = await autorizar(req, supabase, supabaseUrl, serviceKey, orderId)
  if (!autorizado.ok) {
    console.warn(`[dispatch-engine] v62 403 motivo=${autorizado.reason} orderId=${orderId ?? 'ALL'}`)
    return new Response(JSON.stringify({ ok: false, error: 'forbidden' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
  console.log(`[dispatch-engine] v62 INVOKED orderId=${orderId ?? 'ALL'}`)
  const settings = await loadDispatchSettings(supabase)
  console.log(`[dispatch-engine] settings: offerTimeout=${settings.offerTimeoutS}s retryNoDriver=${settings.retryNoDriverS}s maxTotal=${settings.maxTotalS}s safety=${settings.safetyS}s`)
  let redispatchPromise: Promise<void> | null = null
  let response: Response
  try {
    const assigned = await processDispatch(supabase, orderId, settings)
    if (orderId) {
      const decision = await decideRedispatch(supabase, orderId, assigned, settings)
      if (decision.schedule) redispatchPromise = scheduleRedispatch(supabaseUrl, serviceKey, orderId, decision.delayMs)
    }
    response = new Response(JSON.stringify({ ok: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err) {
    console.error('[dispatch-engine] Fatal error:', err)
    if (orderId) {
      try {
        const decision = await decideRedispatch(supabase, orderId, false, settings)
        if (decision.schedule) redispatchPromise = scheduleRedispatch(supabaseUrl, serviceKey, orderId, decision.delayMs)
      } catch (_) {}
    }
    response = new Response(JSON.stringify({ ok: false, error: String(err) }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } finally {
    if (redispatchPromise) EdgeRuntime.waitUntil(redispatchPromise)
  }
  return response
})

async function decideRedispatch(supabase: any, orderId: string, assigned: boolean, settings: DispatchSettings) {
  const { data: peek } = await supabase.from('orders')
    .select('status,assigned_driver_id,current_driver_offer_id,driver_offer_expires_at,dispatch_calling_since,dispatch_online_attempt_seconds')
    .eq('id', orderId).maybeSingle()
  if (!peek || peek.status !== 'callingDriver' || peek.assigned_driver_id) {
    console.log(`[dispatch-engine] order=${orderId} status=${peek?.status} — chain terminates`)
    return { schedule: false, delayMs: 0 }
  }

  // TTL HARD STOP — honra platform_settings em TODOS os caminhos.
  // Sem isto, um pedido sem drivers online era reagendado a cada 10s para sempre.
  const callingSinceMs = peek.dispatch_calling_since ? Date.parse(peek.dispatch_calling_since) : null
  const safetyExceeded = callingSinceMs != null && (Date.now() - callingSinceMs) >= settings.safetyS * 1000
  const maxTotalExceeded = (peek.dispatch_online_attempt_seconds ?? 0) >= settings.maxTotalS
  if (safetyExceeded || maxTotalExceeded) {
    const reason = safetyExceeded ? 'dispatch_safety_timeout' : 'dispatch_max_total_with_drivers_exceeded'
    console.log(`[dispatch-engine] order=${orderId} TTL EXCEEDED (${reason}) — auto-cancel, chain terminates`)
    try {
      const { error } = await supabase.rpc('dispatch_cancel_expired_order', { p_order_id: orderId, p_reason: reason })
      if (error) console.error('[dispatch-engine] auto-cancel rpc error:', JSON.stringify(error))
    } catch (e) {
      console.error('[dispatch-engine] auto-cancel rpc failed:', e)
    }
    return { schedule: false, delayMs: 0 }
  }

  if (assigned) {
    const delayMs = (settings.offerTimeoutS + 2) * 1000
    console.log(`[dispatch-engine] redispatch scheduled order=${orderId} in ${delayMs/1000}s`)
    return { schedule: true, delayMs }
  }

  const hasActiveOffer = peek.current_driver_offer_id && peek.driver_offer_expires_at && new Date(peek.driver_offer_expires_at) > new Date()
  if (hasActiveOffer) {
    console.log(`[dispatch-engine] order=${orderId} has active offer — another worker owns the chain`)
    return { schedule: false, delayMs: 0 }
  }

  // CLAIM atómico anti-cadeias-múltiplas: só quem ganha este UPDATE agenda retry.
  // Quem perde (0 rows) sabe que outra cadeia viva é dona — termina sem duplicar.
  const nowIso = new Date().toISOString()
  const retryAtIso = new Date(Date.now() + settings.retryNoDriverS * 1000).toISOString()
  const { data: claimed, error: claimErr } = await supabase.from('orders')
    .update({ dispatch_next_retry_at: retryAtIso })
    .eq('id', orderId)
    .eq('status', 'callingDriver')
    .is('assigned_driver_id', null)
    .or(`dispatch_next_retry_at.is.null,dispatch_next_retry_at.lte."${nowIso}"`)
    .select('id')
  if (claimErr) {
    // Fail-open: erro transitório não pode órfanar o pedido; cadeias duplicadas
    // auto-colapsam no próximo claim bem-sucedido (só uma ganha).
    console.error('[dispatch-engine] retry claim error (fail-open):', JSON.stringify(claimErr))
    return { schedule: true, delayMs: settings.retryNoDriverS * 1000 }
  }
  if (!claimed?.length) {
    console.log(`[dispatch-engine] order=${orderId} retry already claimed by a live chain — NOT scheduling duplicate`)
    return { schedule: false, delayMs: 0 }
  }
  const delayMs = settings.retryNoDriverS * 1000
  console.log(`[dispatch-engine] order=${orderId} pending — redispatch in ${delayMs/1000}s (claim ok)`)
  return { schedule: true, delayMs }
}

async function processDispatch(supabase: any, orderId: string | null, settings: DispatchSettings): Promise<boolean> {
  const now = new Date().toISOString()
  let query = supabase.from('orders')
    .select('id,service_type,requires_car,pickup_lat,pickup_lng,tried_driver_ids,current_driver_offer_id,driver_offer_expires_at')
    .eq('status', 'callingDriver').is('assigned_driver_id', null)
    .or(`current_driver_offer_id.is.null,driver_offer_expires_at.lt."${now}",driver_offer_expires_at.is.null`)
  if (orderId) query = query.eq('id', orderId)
  const { data: orders, error } = await query
  if (error) { console.error('[dispatch-engine] Query error:', JSON.stringify(error)); throw error }
  if (!orders || orders.length === 0) {
    console.log(`[dispatch-engine] No pending orders (orderId=${orderId ?? 'all'})`)
    return false
  }
  console.log(`[dispatch-engine] ${orders.length} order(s) to dispatch`)
  let anyAssigned = false
  for (const order of orders) {
    try {
      const assigned = await dispatchOrder(supabase, order, settings)
      if (assigned) anyAssigned = true
    } catch (err) { console.error(`[dispatch-engine] Error on order ${order.id}:`, err) }
  }
  return anyAssigned
}

async function dispatchOrder(supabase: any, order: any, settings: DispatchSettings): Promise<boolean> {
  console.log(`[dispatch] order=${order.id} service=${order.service_type}`)
  const triedIds: string[] = order.tried_driver_ids ?? []
  if (order.current_driver_offer_id && !triedIds.includes(order.current_driver_offer_id)) {
    triedIds.push(order.current_driver_offer_id)
  }
  // v62: o matching vive em dispatch_candidatos_entrega (banco). Um erro aqui
  // sobe — a cadeia volta a tentar; nunca se cai num matching antigo às escondidas.
  const candidatos = await carregarCandidatos(supabase, order.id)
  if (triedIds.length > 0 && candidatos.length > 0 &&
      candidatos.every((d: any) => driverKeys(d).some(k => triedIds.includes(k)))) {
    console.log(`[dispatch] All ${candidatos.length} drivers tried — cycle reset`)
    triedIds.length = 0
  }
  const driver = findNextDriver(candidatos, triedIds)
  if (!driver) {
    console.log(`[dispatch] NO DRIVERS for order ${order.id}`)
    await supabase.from('orders').update({ current_driver_offer_id: null, driver_offer_expires_at: null }).eq('id', order.id)
    return false
  }
  // tried_driver_ids guarda drivers.id (chave estável do matching)
  if (!triedIds.includes(driver.id)) triedIds.push(driver.id)
  const assigned = await assignDriver(supabase, order.id, driver, triedIds, settings.offerTimeoutS)
  if (!assigned) { console.log(`[dispatch] LOST RACE order=${order.id}`); return false }
  return true
}

async function carregarCandidatos(supabase: any, orderId: string): Promise<any[]> {
  const { data, error } = await supabase.rpc('dispatch_candidatos_entrega', { p_order_id: orderId })
  if (error) { console.error('[dispatch] dispatch_candidatos_entrega error:', JSON.stringify(error)); throw error }
  return (data ?? []).map((c: any) => ({
    id: c.driver_id, user_id: c.user_id, lat: c.lat, lng: c.lng, vehicle_type: c.vehicle_type, dist: c.dist_km,
  }))
}

function findNextDriver(candidatos: any[], excludeIds: string[]) {
  // A ordem já vem do banco: quem leva pedido da mesma loja primeiro, depois o mais perto.
  // v59: excludeIds pode conter drivers.id OU drivers.user_id (legado).
  const livres = candidatos.filter((d: any) => !driverKeys(d).some(k => excludeIds.includes(k)))
  console.log(`[dispatch] ${livres.length} candidatos (de ${candidatos.length}, excl ${excludeIds.length})`)
  const best = livres[0] ?? null
  if (best) console.log(`[dispatch] Best driver=${best.id} dist=${best.dist != null ? Number(best.dist).toFixed(2) : '?'}km`)
  return best
}

async function assignDriver(supabase: any, orderId: string, driver: any, triedIds: string[], offerTimeoutS: number): Promise<boolean> {
  const now = new Date()
  const expiresAt = new Date(now.getTime() + offerTimeoutS * 1000)
  // v59: a oferta vai com drivers.user_id — é o que a app do estafeta e
  // driver_accept_offer (auth.uid()) esperam encontrar.
  const offerId = offerKeyFor(driver)
  console.log(`[dispatch] assigning order=${orderId} driver=${driver.id} offerKey=${offerId} — notify-driver via DB trigger`)
  const { data, error } = await supabase.from('orders').update({
    current_driver_offer_id: offerId,
    driver_offer_expires_at: expiresAt.toISOString(),
    tried_driver_ids: triedIds,
  }).eq('id', orderId).is('assigned_driver_id', null)
    .or(`current_driver_offer_id.is.null,driver_offer_expires_at.lt."${now.toISOString()}",driver_offer_expires_at.is.null`)
    .select()
  if (error) { console.error('[dispatch] assignDriver error:', JSON.stringify(error)); throw error }
  if (!data?.length) { console.log(`[dispatch] LOST RACE order=${orderId}`); return false }
  console.log(`[dispatch] SUCCESS order=${orderId} → driver=${driver.id} (notify-driver via DB trigger)`)
  return true
}

async function scheduleRedispatch(supabaseUrl: string, serviceKey: string, orderId: string, delayMs: number): Promise<void> {
  await sleep(delayMs)
  for (let i = 1; i <= REDISPATCH_MAX_RETRIES; i++) {
    try {
      console.log(`[dispatch] redispatch attempt=${i} order=${orderId}`)
      const res = await fetch(`${supabaseUrl}/functions/v1/dispatch-engine`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
        body: JSON.stringify({ orderId }),
      })
      if (res.ok) return
    } catch (e) { console.error(`[dispatch] redispatch error attempt=${i}:`, e) }
    if (i < REDISPATCH_MAX_RETRIES) await sleep(REDISPATCH_RETRY_DELAY_MS)
  }
}

// ── Autenticação (v62) — a do notify-driver v42, mais os papéis da app ────────
const servicoOk = new Set<string>()
const ADMIN_EMAILS = ['nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com']
function lerPayload(token: string): any {
  try {
    let b = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    while (b.length % 4) b += '='
    return JSON.parse(atob(b))
  } catch (_) { return null }
}
async function autorizar(req: Request, supabase: any, supabaseUrl: string, serviceKey: string, orderId: string | null): Promise<{ ok: boolean, reason?: string }> {
  const h = req.headers.get('authorization') ?? ''
  if (!h.toLowerCase().startsWith('bearer ')) return { ok: false, reason: 'sem_token' }
  const token = h.slice(7).trim()
  if (!token) return { ok: false, reason: 'sem_token' }
  // Gatilhos, cron, webhooks e o próprio motor (redispatch) mandam a chave de serviço.
  if (token === serviceKey || servicoOk.has(token)) return { ok: true }
  const p = lerPayload(token)
  if (p?.role === 'service_role') {
    // Chave de serviço do cofre do banco (pode não ser igual à do ambiente):
    // só passa se a Auth a aceitar como admin.
    try {
      const r = await fetch(`${supabaseUrl}/auth/v1/admin/users?per_page=1`, { headers: { apikey: token, Authorization: `Bearer ${token}` } })
      if (r.ok) { servicoOk.add(token); return { ok: true } }
    } catch (_) {}
    return { ok: false, reason: 'service_invalido' }
  }
  if (p?.role !== 'authenticated') return { ok: false, reason: `papel_${p?.role ?? 'desconhecido'}` }
  const { data: u, error } = await supabase.auth.getUser(token)
  if (error || !u?.user) return { ok: false, reason: 'jwt_invalido' }
  const uid = String(u.user.id)
  if (u.user.app_metadata?.role === 'admin' || ADMIN_EMAILS.includes(String(u.user.email ?? '').toLowerCase())) return { ok: true }
  // Estafeta aprovado: a app dele acorda o motor ao ficar online (por pedido pendente).
  const { data: d } = await supabase.from('drivers').select('id').eq('user_id', uid).eq('approval_status', 'approved').limit(1)
  if (d?.length) return { ok: true }
  if (!orderId) return { ok: false, reason: 'sem_pedido' }
  // Dono do pedido (cliente) ou dono da loja do pedido (parceiro).
  const { data: o } = await supabase.from('orders').select('user_id,restaurant_id').eq('id', orderId).maybeSingle()
  if (!o) return { ok: false, reason: 'pedido_desconhecido' }
  if (o.user_id && String(o.user_id) === uid) return { ok: true }
  if (o.restaurant_id) {
    const { data: r } = await supabase.from('restaurants').select('user_id,user_').eq('id', o.restaurant_id).maybeSingle()
    if (r && (String(r.user_id ?? '') === uid || String(r.user_ ?? '') === uid)) return { ok: true }
  }
  return { ok: false, reason: 'papel_sem_permissao' }
}
