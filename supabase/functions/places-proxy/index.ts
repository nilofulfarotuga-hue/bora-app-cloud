// places-proxy — plano B do autocomplete de moradas (missão endereco-web-2026-08-31).
//
// Quando o SDK do Google Maps não carrega no browser do cliente (bloqueador,
// rede fraca, extensão de privacidade), a app web chama esta função e as
// moradas continuam a funcionar — a conversa com a Google passa a ser feita
// daqui, do lado do servidor, onde nada é bloqueado.
//
// Ações: autocomplete (input → predições PT, viés Guarda),
//        geocode (morada → lat/lng),
//        detalhes (place_id → lat/lng).
//
// verify_jwt: true (o anon key da app passa; chamadas sem JWT válido não).
// Rate limit simples por utilizador/IP + cache curto em memória, para não
// gastar quota à toa. A chave Google vive em server_config (RLS deny-all),
// lida via service role — nunca chega ao browser por este caminho.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const GUARDA_LAT = 40.5373;
const GUARDA_LNG = -7.2657;
const GUARDA_RADIUS = 25000;

// ── chave Google (cache por isolate) ─────────────────────────────────────────
let chaveGoogle: string | null = null;

async function obterChave(): Promise<string> {
  if (chaveGoogle) return chaveGoogle;
  const porEnv = Deno.env.get("GOOGLE_MAPS_SERVER_KEY");
  if (porEnv) {
    chaveGoogle = porEnv;
    return porEnv;
  }
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data, error } = await admin
    .from("server_config")
    .select("valor")
    .eq("chave", "google_maps_server_key")
    .maybeSingle();
  if (error || !data?.valor) {
    throw new Error("chave google indisponível no server_config");
  }
  chaveGoogle = data.valor as string;
  return chaveGoogle;
}

// ── rate limit simples (por isolate) ─────────────────────────────────────────
const janelas = new Map<string, { inicio: number; contagem: number }>();
const LIMITE_POR_MINUTO = 40;

function dentroDoLimite(quem: string): boolean {
  const agora = Date.now();
  const j = janelas.get(quem);
  if (!j || agora - j.inicio > 60_000) {
    janelas.set(quem, { inicio: agora, contagem: 1 });
    return true;
  }
  j.contagem++;
  return j.contagem <= LIMITE_POR_MINUTO;
}

// ── cache curto de respostas iguais ──────────────────────────────────────────
const cache = new Map<string, { ate: number; corpo: unknown }>();
const CACHE_TTL_MS = 5 * 60_000;
const CACHE_MAX = 500;

function doCache(chave: string): unknown | null {
  const hit = cache.get(chave);
  if (hit && hit.ate > Date.now()) return hit.corpo;
  if (hit) cache.delete(chave);
  return null;
}

function paraCache(chave: string, corpo: unknown) {
  if (cache.size >= CACHE_MAX) {
    const primeira = cache.keys().next().value;
    if (primeira !== undefined) cache.delete(primeira);
  }
  cache.set(chave, { ate: Date.now() + CACHE_TTL_MS, corpo });
}

// ── chamadas à Google ────────────────────────────────────────────────────────
async function googleJson(url: string): Promise<Record<string, unknown>> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`google http ${res.status}`);
  return await res.json();
}

async function autocomplete(input: string) {
  const key = await obterChave();
  const url =
    `https://maps.googleapis.com/maps/api/place/autocomplete/json` +
    `?input=${encodeURIComponent(input)}` +
    `&components=country:pt&language=pt-PT` +
    `&location=${GUARDA_LAT},${GUARDA_LNG}&radius=${GUARDA_RADIUS}` +
    `&key=${key}`;
  const data = await googleJson(url);
  const status = String(data.status ?? "");
  if (status !== "OK" && status !== "ZERO_RESULTS") {
    throw new Error(`google autocomplete ${status}`);
  }
  const predictions = Array.isArray(data.predictions)
    ? (data.predictions as Record<string, unknown>[]).map((p) => {
      const sf = (p.structured_formatting ?? {}) as Record<string, unknown>;
      const types = Array.isArray(p.types) ? (p.types as string[]) : [];
      return {
        place_id: p.place_id ?? "",
        description: p.description ?? "",
        main_text: sf.main_text ?? null,
        secondary_text: sf.secondary_text ?? null,
        establishment: types.includes("establishment"),
      };
    })
    : [];
  return { predictions };
}

function extrairLatLng(data: Record<string, unknown>) {
  const results = data.results as Record<string, unknown>[] | undefined;
  const result = data.result as Record<string, unknown> | undefined;
  const alvo = result ?? (results && results.length > 0 ? results[0] : null);
  const geometry = alvo?.geometry as Record<string, unknown> | undefined;
  const location = geometry?.location as Record<string, unknown> | undefined;
  const lat = location?.lat;
  const lng = location?.lng;
  if (typeof lat === "number" && typeof lng === "number") {
    return { lat, lng };
  }
  return { lat: null, lng: null };
}

async function geocode(morada: string) {
  const key = await obterChave();
  const url =
    `https://maps.googleapis.com/maps/api/geocode/json` +
    `?address=${encodeURIComponent(morada)}` +
    `&region=pt&language=pt-PT&key=${key}`;
  const data = await googleJson(url);
  const status = String(data.status ?? "");
  if (status !== "OK" && status !== "ZERO_RESULTS") {
    throw new Error(`google geocode ${status}`);
  }
  return extrairLatLng(data);
}

async function detalhes(placeId: string) {
  const key = await obterChave();
  const url =
    `https://maps.googleapis.com/maps/api/place/details/json` +
    `?place_id=${encodeURIComponent(placeId)}` +
    `&fields=geometry&language=pt-PT&key=${key}`;
  const data = await googleJson(url);
  const status = String(data.status ?? "");
  if (status !== "OK") throw new Error(`google details ${status}`);
  return extrairLatLng(data);
}

// ── servidor ─────────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const responder = (corpo: unknown, statusHttp = 200) =>
    new Response(JSON.stringify(corpo), {
      status: statusHttp,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  try {
    const body = await req.json().catch(() => ({}));
    const acao = String(body.acao ?? "");

    // Identifica quem chama (sub do JWT quando houver; senão o IP).
    let quem = req.headers.get("x-forwarded-for") ?? "anon";
    const auth = req.headers.get("authorization") ?? "";
    const partes = auth.replace("Bearer ", "").split(".");
    if (partes.length === 3) {
      try {
        const payload = JSON.parse(atob(partes[1]));
        if (payload.sub) quem = String(payload.sub);
      } catch (_) { /* fica o IP */ }
    }
    if (!dentroDoLimite(quem)) {
      return responder({ erro: "limite excedido, tenta daqui a um minuto" }, 429);
    }

    if (acao === "autocomplete") {
      const input = String(body.input ?? "").trim().slice(0, 120);
      if (input.length < 2) return responder({ predictions: [] });
      const chaveCache = `a|${input.toLowerCase()}`;
      const emCache = doCache(chaveCache);
      if (emCache) return responder(emCache);
      const corpo = await autocomplete(input);
      paraCache(chaveCache, corpo);
      return responder(corpo);
    }

    if (acao === "geocode") {
      const morada = String(body.morada ?? "").trim().slice(0, 200);
      if (morada.length < 3) return responder({ lat: null, lng: null });
      const chaveCache = `g|${morada.toLowerCase()}`;
      const emCache = doCache(chaveCache);
      if (emCache) return responder(emCache);
      const corpo = await geocode(morada);
      paraCache(chaveCache, corpo);
      return responder(corpo);
    }

    if (acao === "detalhes") {
      const placeId = String(body.place_id ?? "").trim().slice(0, 200);
      if (!placeId) return responder({ lat: null, lng: null });
      const chaveCache = `d|${placeId}`;
      const emCache = doCache(chaveCache);
      if (emCache) return responder(emCache);
      const corpo = await detalhes(placeId);
      paraCache(chaveCache, corpo);
      return responder(corpo);
    }

    return responder({ erro: "acao desconhecida" }, 400);
  } catch (e) {
    return responder({ erro: String(e) }, 500);
  }
});
