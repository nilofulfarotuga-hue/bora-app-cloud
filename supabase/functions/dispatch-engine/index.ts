// @ts-nocheck
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
const PREFERRED_RADIUS_KM = 10
const CAR_REQUIRED_SERVICES = ['carryGroceries']
const DISTANCE_WEIGHT = 5.0
const COST_WEIGHT = 1.0
const COST_PER_KM = 1.0
const AVG_SPEED_KMH = 30.0

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
function computeScore(d: number) { return (-d * DISTANCE_WEIGHT) + (-d * COST_PER_KM * COST_WEIGHT) }
function estimateEta(d: number) { return Math.round((d / AVG_SPEED_KMH) * 60) }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const supabase = createClient(supabaseUrl, serviceKey)
  let orderId: string | null = null
  try { const b = await req.json(); orderId = b?.orderId ?? null } catch (_) {}
  console.log(`[dispatch-engine] v57 INVOKED orderId=${orderId ?? 'ALL'}`)
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
  if (triedIds.length > 0) {
    const reqCar = order.requires_car === true || CAR_REQUIRED_SERVICES.includes(order.service_type)
    let q = supabase.from('drivers').select('id').eq('is_online', true)
    if (reqCar) q = q.eq('vehicle_type', 'car')
    const { data: online } = await q
    if (online?.length > 0 && online.every((d: any) => triedIds.includes(d.id))) {
      console.log(`[dispatch] All ${online.length} drivers tried — cycle reset`)
      triedIds.length = 0
    }
  }
  const driver = await findNextDriver(supabase, order, triedIds)
  if (!driver) {
    console.log(`[dispatch] NO DRIVERS for order ${order.id}`)
    await supabase.from('orders').update({ current_driver_offer_id: null, driver_offer_expires_at: null }).eq('id', order.id)
    return false
  }
  if (!triedIds.includes(driver.id)) triedIds.push(driver.id)
  const assigned = await assignDriver(supabase, order.id, driver.id, triedIds, settings.offerTimeoutS)
  if (!assigned) { console.log(`[dispatch] LOST RACE order=${order.id}`); return false }
  return true
}

async function findNextDriver(supabase: any, order: any, excludeIds: string[]) {
  let q = supabase.from('drivers').select('id,lat,lng,vehicle_type').eq('is_online', true)
  if (excludeIds.length > 0) q = q.not('id', 'in', `(${excludeIds.join(',')})`)
  const { data: drivers } = await q
  console.log(`[dispatch] ${drivers?.length ?? 0} online drivers (excl ${excludeIds.length})`)
  if (!drivers?.length) return null
  const reqCar = order.requires_car === true || CAR_REQUIRED_SERVICES.includes(order.service_type)
  let elig = reqCar ? drivers.filter((d: any) => d.vehicle_type === 'car') : drivers
  if (!elig.length) return null
  const { data: active } = await supabase.from('orders').select('assigned_driver_id').in('status', ['driverAccepted','pickedUp','onTheWay']).not('assigned_driver_id','is',null)
  const cnt: Record<string,number> = {}
  for (const r of active ?? []) { cnt[r.assigned_driver_id] = (cnt[r.assigned_driver_id] ?? 0) + 1 }
  elig = elig.filter((d: any) => (cnt[d.id] ?? 0) < 3)
  if (!elig.length) return null
  if (!order.pickup_lat || !order.pickup_lng) return elig[0]
  const withCoords = elig.filter((d: any) => d.lat && d.lng)
  if (!withCoords.length) return elig[0]
  const scored = withCoords.map((d: any) => ({ ...d, dist: haversine(order.pickup_lat, order.pickup_lng, d.lat, d.lng) }))
    .sort((a: any, b: any) => computeScore(b.dist) - computeScore(a.dist))
  const best = scored.find((d: any) => d.dist <= PREFERRED_RADIUS_KM) ?? scored[0]
  console.log(`[dispatch] Best driver=${best.id} dist=${best.dist?.toFixed(2)}km eta=${estimateEta(best.dist)}min`)
  return best
}

async function assignDriver(supabase: any, orderId: string, driverId: string, triedIds: string[], offerTimeoutS: number): Promise<boolean> {
  const now = new Date()
  const expiresAt = new Date(now.getTime() + offerTimeoutS * 1000)
  console.log(`[dispatch] assigning order=${orderId} driver=${driverId} — notify-driver via DB trigger`)
  const { data, error } = await supabase.from('orders').update({
    current_driver_offer_id: driverId,
    driver_offer_expires_at: expiresAt.toISOString(),
    tried_driver_ids: triedIds,
  }).eq('id', orderId).is('assigned_driver_id', null)
    .or(`current_driver_offer_id.is.null,driver_offer_expires_at.lt."${now.toISOString()}",driver_offer_expires_at.is.null`)
    .select()
  if (error) { console.error('[dispatch] assignDriver error:', JSON.stringify(error)); throw error }
  if (!data?.length) { console.log(`[dispatch] LOST RACE order=${orderId}`); return false }
  console.log(`[dispatch] SUCCESS order=${orderId} → driver=${driverId} (notify-driver via DB trigger)`)
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

function haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371, dLat = (lat2-lat1)*Math.PI/180, dLng = (lng2-lng1)*Math.PI/180
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2
  return R*2*Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
}
