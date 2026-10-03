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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? '');
    if (action !== 'quote' && action !== 'request') return json({ error: 'unknown_action' }, 400);

    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: 'not_authenticated' }, 401);

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
