// @ts-nocheck
// supabase/functions/dispatch-engine/index.ts
//
// ── Architecture ─────────────────────────────────────────────────────────────
//
//  ALL dispatch logic lives here.  The Flutter frontend is NOT allowed to:
//    • control timeouts
//    • trigger driver rotation
//    • make any dispatch decisions
//
//  The frontend may only:
//    • call _invokeDispatch once when status → callingDriver  (primary trigger)
//    • call _invokeDispatch when a driver explicitly rejects   (fast-path rotation)
//    • accept / pick-up / deliver orders
//    • listen to real-time streams
//
// ── Self-scheduling loop ─────────────────────────────────────────────────────
//
//  When this function is invoked for a specific orderId it schedules a
//  re-invocation of itself (via EdgeRuntime.waitUntil + fetch) after
//  OFFER_TIMEOUT_SECONDS + 2 s — regardless of whether the current call
//  succeeded in assigning a driver or lost a race with another worker.
//
//  The re-invocation detects the expired offer, marks that driver as tried,
//  and assigns the next driver — without any Flutter involvement.
//
//  The chain terminates automatically when:
//    (a) a driver accepts  → assigned_driver_id IS NOT NULL → no pending order
//    (b) no drivers found  → processDispatch returns false  → no re-schedule
//
// ── Triggered by ─────────────────────────────────────────────────────────────
//   (1) DB trigger fn_dispatch_on_calling_driver  — fires on status=callingDriver
//   (2) Flutter  _invokeDispatch                  — explicit reject or cancel
//   (3) Self-invocation after offer timeout       — automatic driver rotation
//   (4) pg_cron (optional safety net)             — catches orphaned orders

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// How long a driver has to respond to an offer (seconds).
const OFFER_TIMEOUT_SECONDS = 40

// Re-invocation fires this many ms after assigning an offer.
// Must be > OFFER_TIMEOUT_SECONDS so the offer has already expired by the time
// processDispatch runs — preventing redundant invocations before expiry.
const REDISPATCH_DELAY_MS = (OFFER_TIMEOUT_SECONDS + 2) * 1000

// How many times scheduleRedispatch retries the self-invoke fetch on failure.
const REDISPATCH_MAX_RETRIES = 3

// Delay between retry attempts in scheduleRedispatch (ms).
const REDISPATCH_RETRY_DELAY_MS = 2000

// Preferred radius for dispatch. Falls back to nearest driver if no one is
// within this distance — prevents silent no-dispatch in sparse areas.
const PREFERRED_RADIUS_KM = 10

// Service types that require a car (motorcycle cannot handle these).
const CAR_REQUIRED_SERVICES = ['carryGroceries']

// ── Scoring constants (must stay in sync with dispatch_service.dart) ──────────
const DISTANCE_WEIGHT = 5.0
const COST_WEIGHT     = 1.0
const COST_PER_KM     = 1.0
const AVG_SPEED_KMH   = 30.0

/** Composite score — HIGHER is better. */
function computeScore(distanceKm: number): number {
  const cost = distanceKm * COST_PER_KM
  return (-distanceKm * DISTANCE_WEIGHT) + (-cost * COST_WEIGHT)
}

/** ETA in minutes. Informational only — not used for ordering. */
function estimateEtaMinutes(distanceKm: number): number {
  return Math.round((distanceKm / AVG_SPEED_KMH) * 60)
}

/** Promise that resolves after [ms] milliseconds. */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// ─────────────────────────────────────────────────────────────────────────────
// FIX #1: Use Deno.serve (native) instead of serve() from std/http.
//         EdgeRuntime.waitUntil is only guaranteed to work with Deno.serve.
// ─────────────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

  if (!supabaseUrl || !serviceKey) {
    console.error('[dispatch-engine] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set')
    return new Response(JSON.stringify({ ok: false, error: 'Missing env vars' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const supabase = createClient(supabaseUrl, serviceKey)

  let orderId: string | null = null
  try {
    const body = await req.json()
    orderId = body?.orderId ?? null
  } catch (_) {
    // No body — cron / manual call, process all pending orders.
  }

  console.log(`[dispatch-engine] ── INVOKED ── orderId=${orderId ?? 'ALL (cron/manual)'}`)

  // redispatchPromise is declared OUTSIDE try/catch so finally can always see it.
  let redispatchPromise: Promise<void> | null = null
  let response: Response

  try {
    const assigned = await processDispatch(supabase, orderId)

    if (orderId) {
      // FIX: decideRedispatch now returns boolean (schedule or not).
      // scheduleRedispatch() is called WITHOUT await so it returns its
      // Promise<void> immediately — the 42s sleep runs in the background.
      // EdgeRuntime.waitUntil keeps the isolate alive for those 42s.
      // Previously: `await decideRedispatch()` returned scheduleRedispatch()'s
      // Promise, which JS async-flattening caused await to resolve only AFTER
      // the full 42s sleep + fetch, making redispatchPromise = void (falsy)
      // and waitUntil never called. Chain died within 150s for 4+ drivers.
      const shouldSchedule = await decideRedispatch(supabase, orderId, assigned)
      if (shouldSchedule) {
        redispatchPromise = scheduleRedispatch(supabaseUrl, serviceKey, orderId)
      }
    }

    response = new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[dispatch-engine] Fatal error:', err)

    if (orderId) {
      try {
        const shouldSchedule = await decideRedispatch(supabase, orderId, false)
        if (shouldSchedule) {
          redispatchPromise = scheduleRedispatch(supabaseUrl, serviceKey, orderId)
        }
      } catch (_) {}
    }

    response = new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } finally {
    // waitUntil runs in finally — guaranteed even if catch ran.
    // Keeps the Deno isolate alive until scheduleRedispatch finishes (~42s + fetch).
    if (redispatchPromise) {
      EdgeRuntime.waitUntil(redispatchPromise)
    }
  }

  return response
})

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Decides whether to schedule a self-invocation (redispatch) and returns the
 * Promise if one is needed, or null if the chain should stop.
 *
 * Three cases are distinguished by peeking at the DB:
 *
 *   (a) assigned = true
 *       This worker just assigned a driver.  Schedule a redispatch to rotate
 *       automatically if the driver ignores the offer (timeout path).
 *
 *   (b) assigned = false, order is callingDriver, NO active offer
 *       processDispatch ran but found zero available drivers (or all were tried
 *       and the offer field was cleared).  Schedule a retry so the order is not
 *       orphaned while waiting for a driver to come online.
 *
 *   (c) assigned = false, order is callingDriver, active offer present
 *       Another concurrent worker won the race and already assigned a driver.
 *       That worker will schedule its own redispatch — we must NOT add a
 *       duplicate chain (exponential growth).
 *
 *   (d) assigned = false, order is no longer callingDriver (accepted/delivered)
 *       Dispatch is done.  Chain terminates cleanly.
 */
// FIX: returns boolean instead of Promise<void> | null.
// Returning scheduleRedispatch() from an async function caused JS to flatten
// the Promise chain — `await decideRedispatch()` would block for the full
// 42s sleep before returning, making redispatchPromise=void (falsy) and
// EdgeRuntime.waitUntil never called. Each hop cascaded synchronously,
// killing chains of 4+ drivers within the 150s isolate limit.
async function decideRedispatch(
  supabase: any,
  orderId: string,
  assigned: boolean,
): Promise<boolean> {
  if (assigned) {
    // Case (a): happy path — we own the offer, monitor for timeout.
    console.log(
      `[dispatch-engine] redispatch scheduled for order=${orderId} ` +
      `in ${REDISPATCH_DELAY_MS / 1000}s (offer timeout monitor)`
    )
    return true
  }

  // Need to know WHY we didn't assign — peek at current order state.
  const { data: peek, error: peekErr } = await supabase
    .from('orders')
    .select('status, assigned_driver_id, current_driver_offer_id, driver_offer_expires_at')
    .eq('id', orderId)
    .maybeSingle()

  if (peekErr) {
    console.error('[dispatch-engine] decideRedispatch peek error:', JSON.stringify(peekErr))
    // Safe default: schedule retry to avoid orphaning the order.
    return true
  }

  const isPending = peek?.status === 'callingDriver' && !peek?.assigned_driver_id

  if (!isPending) {
    // Case (d): order is accepted / delivered / cancelled — chain ends.
    console.log(
      `[dispatch-engine] order=${orderId} status=${peek?.status ?? 'unknown'} ` +
      `— chain terminates`
    )
    return false
  }

  // Case (c): check if another worker already owns an active, non-expired offer.
  // If yes, return false — that worker will schedule its own redispatch.
  // Returning true here was causing exponential worker growth (error 546).
  const offerExpiry = peek?.driver_offer_expires_at
  const hasActiveOffer =
    peek?.current_driver_offer_id != null &&
    offerExpiry != null &&
    new Date(offerExpiry) > new Date()

  if (hasActiveOffer) {
    console.log(
      `[dispatch-engine] order=${orderId} has active offer ` +
      `(driver=${peek.current_driver_offer_id}, expires=${offerExpiry}) ` +
      `— another worker owns the chain, NOT scheduling duplicate`
    )
    return false
  }

  // Case (b): no active offer — order is orphaned or offer just expired.
  // Schedule retry so order is not permanently stuck.
  console.log(
    `[dispatch-engine] order=${orderId} pending, no active offer ` +
    `— redispatch in ${REDISPATCH_DELAY_MS / 1000}s`
  )
  return true
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Finds orders that need dispatch (callingDriver, not yet assigned, no active
 * offer OR offer expired) and dispatches each one to the next available driver.
 *
 * Returns true if at least one driver offer was successfully assigned.
 */
async function processDispatch(
  supabase: any,
  orderId: string | null,
): Promise<boolean> {
  const now = new Date().toISOString()

  // Select orders that are:
  //   • waiting for a driver          (status = callingDriver)
  //   • not yet accepted              (assigned_driver_id IS NULL)
  //   • either have no current offer  (current_driver_offer_id IS NULL)
  //   • or the current offer expired  (driver_offer_expires_at < NOW)
  let query = supabase
    .from('orders')
    .select(
      'id, service_type, requires_car, pickup_lat, pickup_lng, ' +
      'tried_driver_ids, current_driver_offer_id, driver_offer_expires_at'
    )
    .eq('status', 'callingDriver')
    .is('assigned_driver_id', null)
    .or(`current_driver_offer_id.is.null,driver_offer_expires_at.lt."${now}",driver_offer_expires_at.is.null`)

  if (orderId) query = query.eq('id', orderId)

  const { data: orders, error } = await query

  if (error) {
    console.error('[dispatch-engine] Query orders error:', JSON.stringify(error))
    throw error
  }

  if (!orders || orders.length === 0) {
    console.log(
      `[dispatch-engine] No pending orders ` +
      `(filter: orderId=${orderId ?? 'all'}, status=callingDriver, ` +
      `assigned=null, offer=null/expired)`
    )
    return false
  }

  console.log(`[dispatch-engine] ${orders.length} order(s) to dispatch`)

  let anyAssigned = false
  for (const order of orders) {
    try {
      const assigned = await dispatchOrder(supabase, order)
      if (assigned) anyAssigned = true
    } catch (err) {
      console.error(`[dispatch-engine] Error on order ${order.id}:`, err)
    }
  }

  return anyAssigned
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Dispatches a single order to the next available driver.
 * Returns true if the offer was successfully written to the DB.
 */
async function dispatchOrder(supabase: any, order: any): Promise<boolean> {
  console.log(
    `[dispatch] ── order=${order.id} ` +
    `service=${order.service_type} requires_car=${order.requires_car} ` +
    `pickup=(${order.pickup_lat},${order.pickup_lng})`
  )

  const triedIds: string[] = order.tried_driver_ids ?? []

  // If the previous offer expired without acceptance, mark that driver as tried
  // so we don't offer the same driver again immediately.
  if (
    order.current_driver_offer_id &&
    !triedIds.includes(order.current_driver_offer_id)
  ) {
    triedIds.push(order.current_driver_offer_id)
    console.log(
      `[dispatch] Previous offer expired — ` +
      `driver ${order.current_driver_offer_id} added to tried list. ` +
      `Tried: [${triedIds.join(', ')}]`
    )
  }

  // ── Cycle reset: if ALL ELIGIBLE online drivers are already in tried list ──
  // This guarantees A → B → A → B → ∞ with any number of online drivers.
  // Runs before findNextDriver so the reset is reflected in the DB write
  // inside assignDriver — even if a concurrent worker wins the race.
  //
  // NOTE: eligibility must mirror findNextDriver's vehicle filter so that
  // ineligible drivers (e.g. motas on a requires_car order) never prevent
  // the reset from firing.
  if (triedIds.length > 0) {
    const requiresCar =
      order.requires_car === true ||
      CAR_REQUIRED_SERVICES.includes(order.service_type)

    let eligibleQuery = supabase
      .from('drivers')
      .select('id')
      .eq('is_online', true)

    if (requiresCar) {
      eligibleQuery = eligibleQuery.eq('vehicle_type', 'car')
    }

    const { data: onlineNow } = await eligibleQuery

    if (
      onlineNow &&
      onlineNow.length > 0 &&
      onlineNow.every((d: any) => triedIds.includes(d.id))
    ) {
      console.log(
        `[dispatch] All ${onlineNow.length} eligible online driver(s) tried for order ${order.id} ` +
        `— cycle reset`
      )
      triedIds.length = 0
    }
  }

  // ── Find next available driver ───────────────────────────────────────────
  const driver = await findNextDriver(supabase, order, triedIds)

  if (!driver) {
    console.log(`[dispatch] ✗ NO AVAILABLE DRIVERS for order ${order.id}`)
    // Clear the active offer fields so processDispatch can pick this order up
    // on the next invocation (current.is.null filter), but intentionally do NOT
    // reset tried_driver_ids — preserving history lets the cycle-reset logic
    // (all online drivers tried → reset to []) run correctly on the next hop.
    // Resetting here was causing A to be re-selected immediately after rejecting,
    // because tried=[A] → reset → exclude=[] → nearest driver = A again.
    await supabase
      .from('orders')
      .update({
        current_driver_offer_id: null,
        driver_offer_expires_at: null,
      })
      .eq('id', order.id)
    return false
  }

  if (!triedIds.includes(driver.id)) {
    triedIds.push(driver.id)
  }

  const assigned = await assignDriver(supabase, order.id, driver.id, triedIds)
  if (!assigned) {
    console.log(
      `[dispatch] ⚠ LOST RACE — order=${order.id} driver=${driver.id} ` +
      `(another worker won)`
    )
    return false
  }

  return true
}

// ─────────────────────────────────────────────────────────────────────────────

async function findNextDriver(
  supabase: any,
  order: any,
  excludeIds: string[],
) {
  let baseQuery = supabase
    .from('drivers')
    .select('id, lat, lng, vehicle_type, is_online')
    .eq('is_online', true)

  if (excludeIds.length > 0) {
    baseQuery = baseQuery.not('id', 'in', `(${excludeIds.join(',')})`)
  }

  let { data: drivers, error } = await baseQuery

  if (error) {
    console.error('[dispatch] Query drivers error:', JSON.stringify(error))
    throw error
  }

  console.log(
    `[dispatch] DB returned ${drivers?.length ?? 0} is_online=true driver(s) ` +
    `(excluding ${excludeIds.length} tried)`
  )

  if (!drivers || drivers.length === 0) {
    console.log('[dispatch] No is_online=true drivers available')
    return null
  }

  // ── Vehicle filter ────────────────────────────────────────────────────────
  const requiresCar =
    order.requires_car === true ||
    CAR_REQUIRED_SERVICES.includes(order.service_type)

  let eligible = requiresCar
    ? drivers.filter((d: any) => d.vehicle_type === 'car')
    : drivers

  console.log(
    `[dispatch] Vehicle filter: requiresCar=${requiresCar} → ` +
    `${eligible.length}/${drivers.length} eligible`
  )

  if (eligible.length === 0) {
    console.log('[dispatch] ✗ No eligible drivers after vehicle filter')
    return null
  }

  // ── Stacking cap: exclude drivers already at 3 active orders ─────────────
  const MAX_ORDERS_PER_DRIVER = 3
  const { data: activeRows } = await supabase
    .from('orders')
    .select('assigned_driver_id')
    .in('status', ['driverAccepted', 'pickedUp', 'onTheWay'])
    .not('assigned_driver_id', 'is', null)

  const activeCount: Record<string, number> = {}
  for (const row of activeRows ?? []) {
    const id = row.assigned_driver_id as string
    activeCount[id] = (activeCount[id] ?? 0) + 1
  }

  const beforeCap = eligible.length
  eligible = eligible.filter((d: any) => (activeCount[d.id] ?? 0) < MAX_ORDERS_PER_DRIVER)
  console.log(
    `[dispatch] Stacking cap: ${eligible.length}/${beforeCap} eligible ` +
    `(cap=${MAX_ORDERS_PER_DRIVER} active orders)`
  )

  if (eligible.length === 0) {
    console.log('[dispatch] ✗ All eligible drivers at stacking capacity')
    return null
  }

  // ── No pickup coordinates → first eligible driver ─────────────────────────
  if (order.pickup_lat == null || order.pickup_lng == null) {
    console.log(`[dispatch] No pickup coords — assigning first eligible: ${eligible[0].id}`)
    return eligible[0]
  }

  // ── Score all drivers with coordinates ───────────────────────────────────
  const withCoords = eligible.filter((d: any) => d.lat != null && d.lng != null)

  console.log(
    `[dispatch] Drivers with coords: ${withCoords.length}, ` +
    `without: ${eligible.length - withCoords.length}`
  )

  if (withCoords.length === 0) {
    console.log(`[dispatch] No driver coordinates — fallback to first eligible: ${eligible[0].id}`)
    return eligible[0]
  }

  const scored = withCoords.map((d: any) => {
    const distance = haversineKm(order.pickup_lat, order.pickup_lng, d.lat, d.lng)
    const cost     = distance * COST_PER_KM
    const score    = computeScore(distance)
    return { ...d, distance, cost, score }
  })

  // Sort DESC — highest score = nearest / best driver first.
  scored.sort((a: any, b: any) => b.score - a.score)

  for (const d of scored) {
    console.log(
      `[dispatch] candidate id=${d.id} ` +
      `dist=${d.distance.toFixed(2)}km ` +
      `cost=${d.cost.toFixed(2)} ` +
      `score=${d.score.toFixed(2)}`
    )
  }

  // ── Preferred: best driver within PREFERRED_RADIUS_KM ────────────────────
  const withinRadius = scored.filter((d: any) => d.distance <= PREFERRED_RADIUS_KM)
  if (withinRadius.length > 0) {
    const pick = withinRadius[0]
    console.log(
      `[dispatch] ✓ Best within ${PREFERRED_RADIUS_KM}km: ` +
      `id=${pick.id} dist=${pick.distance.toFixed(2)}km ` +
      `eta=${estimateEtaMinutes(pick.distance)}min`
    )
    return pick
  }

  // ── Fallback: best driver regardless of distance ──────────────────────────
  const best = scored[0]
  console.log(
    `[dispatch] ⚠ No drivers within ${PREFERRED_RADIUS_KM}km — ` +
    `using best available: id=${best.id} dist=${best.distance.toFixed(2)}km ` +
    `eta=${estimateEtaMinutes(best.distance)}min`
  )
  return best
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Writes the driver offer to the DB atomically.
 * Uses an optimistic lock (.is('assigned_driver_id', null) +
 * .or(offer null/expired)) so that concurrent workers cannot double-assign.
 */
async function assignDriver(
  supabase: any,
  orderId: string,
  driverId: string,
  triedIds: string[],
): Promise<boolean> {
  const now       = new Date()
  const expiresAt = new Date(now.getTime() + OFFER_TIMEOUT_SECONDS * 1000)

  console.log(
    `[dispatch] assigning: order=${orderId} driver=${driverId} ` +
    `expires=${expiresAt.toISOString()}`
  )

  const { data, error } = await supabase
    .from('orders')
    .update({
      current_driver_offer_id: driverId,
      driver_offer_expires_at: expiresAt.toISOString(),
      tried_driver_ids:        triedIds,
    })
    .eq('id', orderId)
    .is('assigned_driver_id', null)
    .or(
      `current_driver_offer_id.is.null,` +
      `driver_offer_expires_at.lt."${now.toISOString()}",` +
      `driver_offer_expires_at.is.null`
    )
    .select()

  if (error) {
    console.error('[dispatch] assignDriver error:', JSON.stringify(error))
    throw error
  }

  if (!data || data.length === 0) {
    console.log(
      `[dispatch] ⚠ LOST RACE — order=${orderId} was claimed by another worker`
    )
    return false
  }

  console.log(`[dispatch] ✓ SUCCESS — order=${orderId} → driver=${driverId}`)

  // Fire-and-forget: notify driver via FCM (no await — don't block dispatch).
  notifyDriver(driverId, orderId).catch((e) =>
    console.warn(`[dispatch] notify-driver failed silently: ${e}`)
  )

  return true
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Calls the notify-driver Edge Function to send a FCM push to the assigned driver.
 * Fire-and-forget — failures are logged but never propagate to the dispatch chain.
 * No-op when FIREBASE_PROJECT_ID / FIREBASE_SERVICE_ACCOUNT are not set.
 */
async function notifyDriver(driverId: string, orderId: string): Promise<void> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) return

  // Fetch order summary for the notification body.
  const supabase = createClient(supabaseUrl, serviceKey)
  const { data: order } = await supabase
    .from('orders')
    .select('vendor_name, estimated_total, price')
    .eq('id', orderId)
    .maybeSingle()

  const vendorName = order?.vendor_name ?? 'Pedido'
  const total      = order?.estimated_total ?? order?.price ?? 0

  const res = await fetch(`${supabaseUrl}/functions/v1/notify-driver`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${serviceKey}`,
    },
    body: JSON.stringify({ driverId, orderId, vendorName, total }),
  })
  console.log(`[dispatch] notify-driver → status=${res.status}`)
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Waits for the offer timeout then re-invokes this Edge Function so that —
 * if the driver ignored the offer — the next driver is assigned automatically.
 *
 * FIX #4: Retries up to REDISPATCH_MAX_RETRIES times with REDISPATCH_RETRY_DELAY_MS
 * between attempts so a transient network/cold-start error does not kill the chain.
 *
 * Registered with EdgeRuntime.waitUntil (in finally) so it survives after the
 * HTTP response is returned.
 *
 * Termination guarantee:
 *   If the driver accepted during the sleep, processDispatch will find
 *   assigned_driver_id IS NOT NULL → no pending orders → returns false →
 *   the re-invoked function sees orderId but finds 0 pending orders →
 *   does NOT set redispatchPromise → chain ends cleanly.
 */
async function scheduleRedispatch(
  supabaseUrl: string,
  serviceKey: string,
  orderId: string,
): Promise<void> {
  await sleep(REDISPATCH_DELAY_MS)

  const functionUrl = `${supabaseUrl}/functions/v1/dispatch-engine`

  for (let attempt = 1; attempt <= REDISPATCH_MAX_RETRIES; attempt++) {
    try {
      console.log(
        `[dispatch] ⏰ redispatch attempt=${attempt}/${REDISPATCH_MAX_RETRIES} ` +
        `order=${orderId} (offer timeout elapsed)`
      )
      const res = await fetch(functionUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({ orderId }),
      })
      // Always read the body for logging — helps diagnose 401/403/4xx failures.
      const bodyText = await res.text().catch(() => '<unreadable>')
      console.log(
        `[dispatch] redispatch HTTP status=${res.status} order=${orderId} body=${bodyText}`
      )
      // Only a true 2xx means the next hop was accepted — return and let that
      // invocation own the chain.  Treat ALL non-2xx (including 4xx such as
      // 401/403) as retryable: a transient auth hiccup or cold-start must not
      // silently kill the dispatch chain.
      if (res.status >= 200 && res.status < 300) return
      console.warn(
        `[dispatch] redispatch got ${res.status} — retrying in ${REDISPATCH_RETRY_DELAY_MS}ms`
      )
    } catch (e) {
      console.error(
        `[dispatch] redispatch fetch error attempt=${attempt}:`, e
      )
    }

    if (attempt < REDISPATCH_MAX_RETRIES) {
      await sleep(REDISPATCH_RETRY_DELAY_MS)
    }
  }

  console.error(
    `[dispatch] ✗ redispatch FAILED after ${REDISPATCH_MAX_RETRIES} attempts ` +
    `for order=${orderId}`
  )

  // ── Last-resort fallback ─────────────────────────────────────────────────
  // Fires immediately after all retries are exhausted — no extra sleep.
  // assignDriver's optimistic lock (.is null / .lt expiry) guarantees only
  // one worker can write the offer — concurrent invocations cannot
  // double-assign a driver.
  try {
    console.log(`[dispatch] ⚠ last-resort fallback invoke for order=${orderId}`)
    const fbRes = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ orderId }),
    })
    const fbBody = await fbRes.text().catch(() => '<unreadable>')
    console.log(`[dispatch] fallback status=${fbRes.status} body=${fbBody}`)
  } catch (fe) {
    console.error(`[dispatch] fallback invoke failed for order=${orderId}:`, fe)
  }
}

// ─────────────────────────────────────────────────────────────────────────────

function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R    = 6371
  const dLat = ((lat2 - lat1) * Math.PI) / 180
  const dLng = ((lng2 - lng1) * Math.PI) / 180
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}
