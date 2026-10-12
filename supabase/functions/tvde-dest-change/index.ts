// =============================================================================
// tvde-dest-change — MUDAR DESTINO a meio da corrida TVDE (v2, 2026-09-30)
// =============================================================================
// Os km NÃO vêm da app (revisão adversarial 30/09: com km da app um cliente
// podia declarar menos km e pagar €0 por um destino mais longe). Aqui o
// SERVIDOR calcula a rota no Google Directions com a chave do servidor
// (server_config.google_maps_server_key, como a places-proxy):
//   · antes da recolha: 0 km feitos, rota ORIGEM -> destino novo;
//   · em viagem: km feitos = rota origem -> posição do carro (GPS do motorista
//     em drivers.lat/lng), + rota carro -> destino novo.
// Grava em tvde_dest_change_routes (só service_role escreve) e chama a RPC com
// o JWT do cliente — a RPC confere o dono da corrida e só aceita km desta tabela.
//
// Ações (cliente autenticado):
//   quote   {ride_id, dest_lat, dest_lng, dest_label}            -> cotação
//   request {ride_id, dest_lat, dest_lng, dest_label, expected_client_diff_cents}
//           -> dinheiro/diferença 0: aplica; cartão/MB Way: proposta (a
//              cobrança é na tvde-payment charge_dest_change).
// Sem rota do Google -> erro `route_failed` (nada muda, nada se cobra).
// v2 (2.ª revisão 30/09): a rota grava o estado da corrida (a RPC só a aceita
// 60 s e no mesmo estado); GPS do motorista com mais de 3 min -> recusa
// (`driver_position_stale`); interruptor desligado ou corrida fora dos estados
// permitidos -> recusa ANTES de gastar Google.
// v3 (2026-10-12, missão reserva-tvde-robo, Bloco 2): mudar o destino de uma
// RESERVA (corrida marcada, status 'agendada') — acções `reservation_quote` e
// `reservation_change` {ride_id, dest_text | dest_lat+dest_lng, dest_label?,
// expected_client_diff_cents?}. Aceita a morada ESCRITA (robô de suporte /
// painel): geocodifica no Google (país PT, viés Guarda) e devolve a morada
// encontrada para o cliente confirmar. Os km são sempre a rota ORIGEM → destino
// novo (a reserva ainda não arrancou). Chama as RPCs tvde_reservation_dest_quote
// / tvde_reservation_change_dest com o JWT de quem pede (dono ou admin). Tudo
// atrás do interruptor `tvde_reservation_dest_change_enabled` (nasce desligado:
// as RPCs só entram no ar com o "vai" do Danilo — mexem em dinheiro).
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const admin = createClient(SUPABASE_URL, SERVICE_KEY);

let chaveGoogle: string | null = null;
async function googleKey(): Promise<string> {
  if (chaveGoogle) return chaveGoogle;
  const env = Deno.env.get('GOOGLE_MAPS_SERVER_KEY');
  if (env) return (chaveGoogle = env);
  const { data, error } = await admin.from('server_config').select('valor')
    .eq('chave', 'google_maps_server_key').maybeSingle();
  if (error || !data?.valor) throw new Error('chave google indisponível');
  return (chaveGoogle = String(data.valor));
}

/** Distância de estrada (km) pelo Google Directions; null se falhar. */
async function rotaKm(o: [number, number], d: [number, number]): Promise<number | null> {
  if (Math.abs(o[0] - d[0]) < 1e-6 && Math.abs(o[1] - d[1]) < 1e-6) return 0;
  const url = 'https://maps.googleapis.com/maps/api/directions/json' +
    `?origin=${o[0]},${o[1]}&destination=${d[0]},${d[1]}&mode=driving&key=${await googleKey()}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const j = await res.json().catch(() => null);
  if (j?.status !== 'OK') return null;
  // deno-lint-ignore no-explicit-any
  const legs: any[] = j.routes?.[0]?.legs ?? [];
  const metros = legs.reduce((t, l) => t + Number(l?.distance?.value ?? 0), 0);
  return metros > 0 ? Math.round(metros / 10) / 100 : null;
}

/** Morada escrita → ponto no mapa (Google Geocoding, país PT, viés Guarda). */
async function geocodificar(texto: string): Promise<{ lat: number; lng: number; label: string } | null> {
  const url = 'https://maps.googleapis.com/maps/api/geocode/json' +
    `?address=${encodeURIComponent(texto)}&region=pt&language=pt-PT&components=country:PT` +
    `&bounds=40.45,-7.40|40.65,-7.10&key=${await googleKey()}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const j = await res.json().catch(() => null);
  if (j?.status !== 'OK') return null;
  const r = j.results?.[0];
  const loc = r?.geometry?.location;
  if (!r || !loc || !Number.isFinite(Number(loc.lat)) || !Number.isFinite(Number(loc.lng))) return null;
  return { lat: Number(loc.lat), lng: Number(loc.lng), label: String(r.formatted_address ?? texto).slice(0, 300) };
}

/**
 * v3 — RESERVA (corrida marcada): cotação / mudança de destino. Quem pede é o
 * dono ou um admin; a RPC volta a conferir com o JWT. A morada pode vir
 * escrita (robô, painel) ou já como coordenadas (app). Os km são a rota
 * origem → destino novo pelo Google (nunca da app, nunca do modelo).
 */
// deno-lint-ignore no-explicit-any
async function reservaDestino(action: string, body: any, user: { id: string }, userClient: any) {
  const rideId = String(body.ride_id ?? '');
  if (!rideId) return json({ error: 'invalid_ride' }, 400);

  const { data: ligado } = await admin.rpc('get_setting', { p_key: 'tvde_reservation_dest_change_enabled' });
  if (!(ligado === true || String(ligado).toLowerCase() === 'true')) {
    return json({ error: 'reservation_dest_change_disabled' }, 403);
  }

  const { data: ride } = await admin.from('tvde_rides')
    .select('id, client_id, status, scheduled_at, origin_lat, origin_lng, reservation_status')
    .eq('id', rideId).maybeSingle();
  if (!ride) return json({ error: 'reservation_not_found' }, 404);
  if (ride.client_id !== user.id) {
    const { data: souAdmin } = await userClient.rpc('is_admin');
    if (souAdmin !== true) return json({ error: 'reservation_not_yours' }, 403);
  }
  if (ride.status !== 'agendada' || !ride.scheduled_at) return json({ error: 'too_late_to_change' }, 400);
  if (ride.reservation_status === 'aguarda_pagamento') return json({ error: 'reservation_awaiting_payment' }, 400);

  let lat = Number(body.dest_lat), lng = Number(body.dest_lng);
  let label: string | null = body.dest_label == null ? null : String(body.dest_label).slice(0, 300);
  const texto = body.dest_text == null ? '' : String(body.dest_text).trim().slice(0, 300);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    if (!texto) return json({ error: 'invalid_dest' }, 400);
    const g = await geocodificar(texto);
    if (!g) return json({ error: 'address_not_found' }, 404);
    lat = g.lat; lng = g.lng;
    label = label ?? g.label;
  }
  if (!label) label = texto || null;

  const km = await rotaKm([Number(ride.origin_lat), Number(ride.origin_lng)], [lat, lng]);
  if (km == null) return json({ error: 'route_failed' }, 502);

  const params: Record<string, unknown> = {
    p_ride: rideId, p_dest_lat: lat, p_dest_lng: lng, p_dest_label: label, p_est_distance_km: km,
  };
  if (action === 'reservation_change') {
    params.p_expected_client_diff_cents = body.expected_client_diff_cents == null
      ? null : Math.trunc(Number(body.expected_client_diff_cents));
  }
  const { data, error } = await userClient.rpc(
    action === 'reservation_quote' ? 'tvde_reservation_dest_quote' : 'tvde_reservation_change_dest', params);
  if (error) return json({ error: String(error.message ?? 'rpc_failed') }, 400);
  const out = (data && typeof data === 'object') ? data : {};
  return json({ ...out, dest_lat: lat, dest_lng: lng, dest_label: label, route_km: km });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');
    if (!['quote', 'request', 'reservation_quote', 'reservation_change'].includes(action)) {
      return json({ error: 'unknown_action' }, 400);
    }

    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'not_authenticated' }, 401);

    // v3 — reserva (corrida marcada): ramo próprio, nada do caminho a meio da corrida mudou.
    if (action === 'reservation_quote' || action === 'reservation_change') {
      return await reservaDestino(action, body, user, userClient);
    }

    const rideId = String(body.ride_id ?? '');
    const lat = Number(body.dest_lat), lng = Number(body.dest_lng);
    if (!rideId || !Number.isFinite(lat) || !Number.isFinite(lng)) return json({ error: 'invalid_dest' }, 400);
    const label = body.dest_label == null ? null : String(body.dest_label).slice(0, 300);

    const { data: ride } = await admin.from('tvde_rides')
      .select('id, client_id, driver_id, status, origin_lat, origin_lng, agreed_fare_cents').eq('id', rideId).maybeSingle();
    if (!ride) return json({ error: 'ride_not_found' }, 404);
    // A RPC volta a conferir tudo com o JWT; aqui só se evita gastar Google à toa.
    if (ride.client_id !== user.id) return json({ error: 'not_ride_client' }, 403);
    const { data: ligado } = await admin.rpc('get_setting', { p_key: 'tvde_dest_change_enabled' });
    if (!(ligado === true || String(ligado).toLowerCase() === 'true')) {
      return json({ error: 'dest_change_disabled' }, 403);
    }
    if (!['motorista_a_caminho', 'motorista_chegou', 'em_andamento'].includes(String(ride.status))) {
      return json({ error: `invalid_ride_state_for_dest_change: ${ride.status}` }, 400);
    }
    if (ride.agreed_fare_cents != null) return json({ error: 'counter_ride_admin_only' }, 400);

    const origem: [number, number] = [Number(ride.origin_lat), Number(ride.origin_lng)];
    const destino: [number, number] = [lat, lng];
    let desde = origem;
    let kmFeitos = 0;
    if (ride.status === 'em_andamento' && ride.driver_id) {
      const { data: d } = await admin.from('drivers').select('lat, lng, last_heartbeat_at')
        .eq('user_id', ride.driver_id).maybeSingle();
      const idadeS = d?.last_heartbeat_at ? (Date.now() - Date.parse(String(d.last_heartbeat_at))) / 1000 : Infinity;
      if (d?.lat == null || d?.lng == null || !(idadeS <= 180)) {
        return json({ error: 'driver_position_stale' }, 409);
      }
      {
        desde = [Number(d.lat), Number(d.lng)];
        const feitos = await rotaKm(origem, desde);
        if (feitos == null) return json({ error: 'route_failed' }, 502);
        kmFeitos = feitos;
      }
    }
    const kmResto = await rotaKm(desde, destino);
    if (kmResto == null) return json({ error: 'route_failed' }, 502);

    const { error: insErr } = await admin.from('tvde_dest_change_routes').insert({
      ride_id: rideId, dest_lat: lat, dest_lng: lng, from_lat: desde[0], from_lng: desde[1],
      km_done: kmFeitos, km_remaining: kmResto, ride_status: ride.status,
    });
    if (insErr) return json({ error: 'route_save_failed' }, 500);

    const params: Record<string, unknown> = {
      p_ride_id: rideId, p_dest_lat: lat, p_dest_lng: lng, p_dest_label: label,
    };
    if (action === 'request') {
      params.p_expected_client_diff_cents = body.expected_client_diff_cents == null
        ? null : Math.trunc(Number(body.expected_client_diff_cents));
    }
    const { data, error } = await userClient.rpc(
      action === 'quote' ? 'tvde_dest_change_quote' : 'tvde_dest_change_request', params);
    if (error) return json({ error: String(error.message ?? 'rpc_failed') }, 400);
    return json(data);
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});
