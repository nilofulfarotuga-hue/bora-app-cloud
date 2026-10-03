// ficha-google-diagnostico — o que falta na ficha Google de um negócio local.
// Missão agente-avenca-preparacao-2026-09-24 (avença «Presença Digital Bora»).
//
// PORQUÊ UMA FUNÇÃO NOVA, e não mais uma ação no places-proxy: o places-proxy é o plano B
// do autocomplete de moradas da app e está a funcionar. Uma ação nova lá dentro punha o
// caminho das moradas a partilhar código com isto sem necessidade nenhuma. Aqui não há
// risco: se esta função cair, cai só a prospeção.
//
// O que devolve, por negócio: se tem ficha, o que lá está (telefone, site, horário, quantas
// fotos, quantas avaliações) e uma LISTA DO QUE FALTA, em português simples — que é
// exactamente o que se mostra ao dono na amostra.
//
// Só dados públicos do próprio negócio, os mesmos que qualquer pessoa vê ao procurar o nome
// no Google Maps. A chave Google vive em server_config (RLS deny-all) e nunca sai daqui.
//
// verify_jwt fica LIGADO (o anon key da app passa). Só o robô da prospeção chama isto.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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
  if (error || !data?.valor) throw new Error("chave google indisponível no server_config");
  chaveGoogle = data.valor as string;
  return chaveGoogle;
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let nome = "", morada = "";
  try {
    const body = await req.json();
    nome = String(body.nome ?? "").trim();
    morada = String(body.morada ?? "").trim();
  } catch {
    return json({ ok: false, erro: "corpo inválido" }, 400);
  }
  if (!nome) return json({ ok: false, erro: "falta o nome" }, 400);

  const chave = await obterChave();
  const procura = [nome, morada, "Guarda, Portugal"].filter(Boolean).join(", ");

  // Places API (new) — Text Search. Uma chamada só; a máscara pede apenas o que se usa.
  const r = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": chave,
      "X-Goog-FieldMask": [
        "places.id",
        "places.displayName",
        "places.formattedAddress",
        "places.nationalPhoneNumber",
        "places.websiteUri",
        "places.rating",
        "places.userRatingCount",
        "places.regularOpeningHours.openNow",
        "places.photos",
        "places.businessStatus",
        "places.googleMapsUri",
      ].join(","),
    },
    body: JSON.stringify({
      textQuery: procura,
      languageCode: "pt-PT",
      regionCode: "PT",
      maxResultCount: 1,
    }),
  });

  const corpo = await r.json().catch(() => ({}));
  if (!r.ok) return json({ ok: false, erro: `google_${r.status}`, detalhe: corpo }, 200);

  const p = (corpo.places ?? [])[0];
  if (!p) {
    return json({
      ok: true,
      encontrado: false,
      estado: "sem_ficha",
      falta: ["Não encontrámos ficha no Google. Quem procura o nome não vos acha no mapa."],
    });
  }

  const fotos = Array.isArray(p.photos) ? p.photos.length : 0;
  const avaliacoes = p.userRatingCount ?? 0;
  const falta: string[] = [];
  if (!p.websiteUri) falta.push("A ficha não tem site. O botão «Website» está vazio.");
  if (!p.nationalPhoneNumber) falta.push("A ficha não tem telefone. Ninguém liga a partir do Google.");
  if (!p.regularOpeningHours) falta.push("A ficha não tem horário. O Google não diz se estão abertos.");
  if (fotos < 5) falta.push(`Só ${fotos} foto(s) na ficha. Abaixo de cinco, a ficha parece abandonada.`);
  if (avaliacoes < 10) falta.push(`Só ${avaliacoes} avaliação(ões). Poucas avaliações afastam quem não vos conhece.`);

  return json({
    ok: true,
    encontrado: true,
    estado: falta.length === 0 ? "completa" : "incompleta",
    place_id: p.id ?? null,
    nome_no_google: p.displayName?.text ?? null,
    morada: p.formattedAddress ?? null,
    telefone: p.nationalPhoneNumber ?? null,
    site: p.websiteUri ?? null,
    avaliacao: p.rating ?? null,
    n_avaliacoes: avaliacoes,
    n_fotos: fotos,
    tem_horario: !!p.regularOpeningHours,
    estado_negocio: p.businessStatus ?? null,
    link_maps: p.googleMapsUri ?? null,
    falta,
  });
});
