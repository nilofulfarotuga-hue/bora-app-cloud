// BLOCO 7.1 — import-guarda-businesses
//
// One-time + re-executável. Consulta o Overpass API por comércios estruturais
// num raio de 8 km à volta do centro da Guarda (40.5373, -7.2674) e faz UPSERT
// por osm_id em public.guarda_businesses (service_role). Re-import NÃO duplica.
//
// Protegido: só admin (app_metadata.role='admin') pode invocar. A escrita usa
// service_role server-side (a tabela está trancada por RLS).
//
// API: POST /functions/v1/import-guarda-businesses
//      Headers: Authorization: Bearer <admin_jwt>
//      Returns 200 { ok: true, fetched, imported } | 401/403 | 500

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const GUARDA_LAT = 40.5373
const GUARDA_LNG = -7.2674
const RADIUS_M = 8000

// amenities consideradas comércio estrutural (resto é ignorado).
const AMENITIES = [
  'pharmacy',
  'cafe',
  'restaurant',
  'fast_food',
  'bar',
  'bakery',
  'fuel',
  'marketplace',
]

function jsonResp(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// Normaliza shop/amenity OSM → categoria canónica Bora.
function normalizeCategory(shop?: string, amenity?: string): string {
  const s = (shop ?? '').toLowerCase()
  const a = (amenity ?? '').toLowerCase()
  if (s === 'supermarket') return 'supermarket'
  if (s === 'convenience') return 'convenience'
  if (a === 'pharmacy' || s === 'chemist' || s === 'pharmacy') return 'pharmacy'
  if (s === 'bakery' || a === 'bakery') return 'bakery'
  if (a === 'cafe') return 'cafe'
  if (a === 'restaurant') return 'restaurant'
  if (a === 'fast_food') return 'fast_food'
  if (a === 'bar' || a === 'pub') return 'bar'
  if (a === 'fuel') return 'fuel'
  return 'other'
}

function buildAddress(tags: Record<string, string>): string | null {
  const street = tags['addr:street']
  const num = tags['addr:housenumber']
  const city = tags['addr:city']
  const parts: string[] = []
  if (street) parts.push(num ? `${street} ${num}` : street)
  if (city) parts.push(city)
  return parts.length > 0 ? parts.join(', ') : null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return jsonResp(405, { ok: false, error: 'method_not_allowed' })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return jsonResp(500, { ok: false, error: 'env_missing' })
  }

  // ── Guard: só admin pode importar ──────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userErr } = await userClient.auth.getUser()
  if (userErr || !userData.user) {
    return jsonResp(401, { ok: false, error: 'unauthorized' })
  }
  const role = (userData.user.app_metadata as Record<string, unknown> | null)
    ?.role
  if (role !== 'admin') {
    return jsonResp(403, { ok: false, error: 'admin_required' })
  }

  // ── Overpass ───────────────────────────────────────────────────────────
  const amenityRe = `^(${AMENITIES.join('|')})$`
  const query = `[out:json][timeout:60];
(
  node["shop"](around:${RADIUS_M},${GUARDA_LAT},${GUARDA_LNG});
  way["shop"](around:${RADIUS_M},${GUARDA_LAT},${GUARDA_LNG});
  node["amenity"~"${amenityRe}"](around:${RADIUS_M},${GUARDA_LAT},${GUARDA_LNG});
  way["amenity"~"${amenityRe}"](around:${RADIUS_M},${GUARDA_LAT},${GUARDA_LNG});
);
out center tags;`

  let elements: Array<Record<string, any>> = []
  try {
    const res = await fetch('https://overpass-api.de/api/interpreter', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `data=${encodeURIComponent(query)}`,
    })
    if (!res.ok) {
      return jsonResp(502, {
        ok: false,
        error: 'overpass_failed',
        status: res.status,
      })
    }
    const data = await res.json()
    elements = (data.elements ?? []) as Array<Record<string, any>>
  } catch (e) {
    return jsonResp(502, { ok: false, error: 'overpass_error', detail: String(e) })
  }

  // ── Transformar (só comércios estruturais com nome) ────────────────────
  const rows: Array<Record<string, unknown>> = []
  for (const el of elements) {
    const tags = (el.tags ?? {}) as Record<string, string>
    const name = (tags.name ?? '').trim()
    if (!name) continue // ignora sem nome

    const shop = tags.shop
    const amenity = tags.amenity
    // Só comércio estrutural: shop=* OU amenity na allowlist.
    if (!shop && !(amenity && AMENITIES.includes(amenity))) continue

    const lat = el.lat ?? el.center?.lat
    const lng = el.lon ?? el.center?.lon
    if (typeof lat !== 'number' || typeof lng !== 'number') continue

    rows.push({
      osm_id: `${el.type}/${el.id}`,
      name,
      category: normalizeCategory(shop, amenity),
      osm_shop: shop ?? null,
      osm_amenity: amenity ?? null,
      address: buildAddress(tags),
      lat,
      lng,
      source: 'osm',
      updated_at: new Date().toISOString(),
    })
  }

  // ── Upsert por osm_id (re-import actualiza, não duplica) ────────────────
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  })
  let imported = 0
  for (let i = 0; i < rows.length; i += 200) {
    const chunk = rows.slice(i, i + 200)
    const { error } = await admin
      .from('guarda_businesses')
      .upsert(chunk, { onConflict: 'osm_id' })
    if (error) {
      return jsonResp(500, {
        ok: false,
        error: 'upsert_failed',
        detail: error.message,
        imported,
      })
    }
    imported += chunk.length
  }

  return jsonResp(200, { ok: true, fetched: elements.length, imported })
})
