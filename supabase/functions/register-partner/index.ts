import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const supabase = createClient(supabaseUrl, serviceRoleKey);

interface RegisterPartnerRequest {
  restaurantName: string;
  nif?: string;
  iban?: string;
  address: string;
  phone: string;
  email: string;
  cuisineType: string;
  category: string;
  lat?: number;
  lng?: number;
  ownerDocUrl?: string;
  activityDocUrl?: string;
  photoUrl?: string;
  coverUrl?: string;
  reservationsEnabled?: boolean;
  takeawayEnabled?: boolean;
}

function validateNif(nif: string): boolean {
  if (!nif || nif.length !== 9) return false;
  const digits = nif.split("").map((d) => parseInt(d, 10));
  let sum = 0;
  for (let i = 0; i < 8; i++) {
    sum += digits[i] * (9 - i);
  }
  const checkDigit = (11 - (sum % 11)) % 11;
  return checkDigit === 10 ? digits[8] === 0 : digits[8] === checkDigit;
}

function validateIban(iban: string): boolean {
  if (!iban) return false;
  // Portuguese IBAN: PT + 23 digits (25 chars total: 2 check digits + 21-digit NIB)
  return /^PT\d{23}$/.test(iban.toUpperCase().replace(/\s/g, ""));
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Extract user_id from Authorization header JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Authorization header obrigatório" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.substring(7);
    const parts = token.split(".");
    if (parts.length !== 3) {
      return new Response(
        JSON.stringify({ error: "Token JWT inválido" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const payload = JSON.parse(
      new TextDecoder().decode(
        Uint8Array.from(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")), (c) =>
          c.charCodeAt(0)
        )
      )
    );

    const userId = payload.sub; // sub = user.id em Supabase JWT
    if (!userId) {
      return new Response(
        JSON.stringify({ error: "user_id não encontrado no token" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const body = (await req.json()) as RegisterPartnerRequest;

    // Validações de entrada
    if (!body.restaurantName?.trim()) {
      return new Response(
        JSON.stringify({ error: "restaurantName obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!body.address?.trim()) {
      return new Response(
        JSON.stringify({ error: "address obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!body.email?.trim()) {
      return new Response(
        JSON.stringify({ error: "email obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Validações NIF e IBAN (opcionais, mas validar formato se preenchidos)
    if (body.nif && !validateNif(body.nif)) {
      return new Response(
        JSON.stringify({ error: "NIF formato inválido (9 dígitos)" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (body.iban && !validateIban(body.iban)) {
      return new Response(
        JSON.stringify({
          error: "IBAN formato inválido (PT + 23 dígitos)",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── beauty / salão → service_providers ──────────────────────────────
    if (body.category === "beauty") {
      // Idempotência: um user_id que já tem candidatura (pending/rejected)
      // atualiza-a em vez de inserir outra linha — sem isto, cada retry do
      // wizard (retomada após login, double-submit, etc.) criava uma linha
      // nova, e queries que assumem "no máximo 1 candidatura por user_id"
      // (ex.: RestaurantStore.ownRestaurantApprovalStatus) rebentavam.
      const { data: existingProviders } = await supabase
        .from("service_providers")
        .select("id, approval_status")
        .eq("user_id", userId)
        .order("created_at", { ascending: false })
        .limit(1);
      const existingProvider = existingProviders?.[0];

      const providerId = existingProvider?.id ?? crypto.randomUUID();
      const providerPayload = {
        name: body.restaurantName,
        category: "beauty",
        address: body.address || null,
        phone: body.phone || null,
        lat: body.lat || null,
        lng: body.lng || null,
        nif: body.nif || null,
        iban: body.iban || null,
      };

      const spError = existingProvider && existingProvider.approval_status !== "approved"
        ? (await supabase
            .from("service_providers")
            .update({ ...providerPayload, approval_status: "pending", rejection_reason: null })
            .eq("id", providerId)).error
        : existingProvider
        ? null // já aprovado — não mexe, só devolve o id existente
        : (await supabase
            .from("service_providers")
            .insert({ id: providerId, user_id: userId, approval_status: "pending", ...providerPayload })).error;

      if (spError) {
        console.error("Register beauty provider upsert error:", spError);
        return new Response(
          JSON.stringify({ error: `Erro ao inserir prestador: ${spError.message}` }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }
      // Status devolvido reflete o estado PÓS-operação: "approved" só no caso
      // de no-op (já era aprovado); update/insert acabaram de pôr 'pending'.
      const providerStatus = existingProvider?.approval_status === "approved" ? "approved" : "pending";
      console.log(`[register-partner] Beauty provider ${existingProvider ? "resubmitted" : "submitted"}: ${providerId} (${body.email})`);
      return new Response(
        JSON.stringify({
          success: true,
          provider_id: providerId,
          status: providerStatus,
          message: "Registo submetido. Aguardando análise do admin (24-48h).",
        }),
        { status: 201, headers: { "Content-Type": "application/json" } }
      );
    }

    // Idempotência: mesma lógica do ramo beauty acima, para `restaurants`.
    const { data: existingRestaurants } = await supabase
      .from("restaurants")
      .select("id, approval_status")
      .eq("user_id", userId)
      .order("submitted_at", { ascending: false })
      .limit(1);
    const existingRestaurant = existingRestaurants?.[0];

    const restaurantId = existingRestaurant?.id ?? crypto.randomUUID();
    const restaurantPayload = {
      name: body.restaurantName,
      address: body.address,
      phone: body.phone,
      email: body.email,
      cuisine_type: body.cuisineType || "",
      category: body.category || "restaurant",
      lat: body.lat || null,
      lng: body.lng || null,
      nif: body.nif || null,
      iban: body.iban || null,
      owner_doc_url: body.ownerDocUrl || null,
      activity_doc_url: body.activityDocUrl || null,
      photo_url: body.photoUrl || "",
      cover_url: body.coverUrl || null,
      // Parte 5 — só restaurantes enviam estes toggles (switches no registo);
      // ligam os cartões "Reservar mesa" / "Ir buscar" no RestaurantOptionsScreen.
      reservations_enabled: body.reservationsEnabled ?? false,
      takeaway_enabled: body.takeawayEnabled ?? false,
    };

    let insertError;
    if (existingRestaurant && existingRestaurant.approval_status !== "approved") {
      // Candidatura pending/rejected já existe: atualiza + reabre para análise.
      ({ error: insertError } = await supabase
        .from("restaurants")
        .update({
          ...restaurantPayload,
          // Espelha o dono nas DUAS colunas (as RPCs de parceiro leem `user_`,
          // o cadastro histórico gravava `user_id`). Ver licao-dual-owner-column.
          user_: userId,
          user_id: userId,
          approval_status: "pending",
          rejection_reason: null,
          submitted_at: new Date().toISOString(),
          reviewed_at: null,
          approved_at: null,
        })
        .eq("id", restaurantId));
    } else if (!existingRestaurant) {
      // BUG-2 FIX: define user_id para permitir RLS em products
      ({ error: insertError } = await supabase
        .from("restaurants")
        .insert({
          id: restaurantId,
          // BUG-2 FIX: define user_id para permitir RLS em products.
          // user_ é a coluna que as RPCs de parceiro leem — gravar AMBAS
          // (ver licao-dual-owner-column). O trigger de espelho é a rede de segurança.
          user_id: userId,
          user_: userId,
          photo_url: "",
          is_partner: true,
          is_online: false,
          approval_status: "pending",
          rejection_reason: null,
          submitted_at: new Date().toISOString(),
          reviewed_at: null,
          approved_at: null,
          ...restaurantPayload,
        }));
    } else {
      // Já aprovado — não mexe, só devolve o id existente.
      insertError = null;
    }

    if (insertError) {
      console.error("Register partner upsert error:", insertError);
      return new Response(
        JSON.stringify({ error: `Erro ao inserir restaurante: ${insertError.message}` }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Status devolvido reflete o estado PÓS-operação: "approved" só no caso
    // de no-op (já era aprovado); update/insert acabaram de pôr 'pending'.
    const restaurantStatus = existingRestaurant?.approval_status === "approved" ? "approved" : "pending";
    console.log(`[register-partner] Partner ${existingRestaurant ? "resubmitted" : "submitted"}: ${restaurantId} (${body.email})`);

    return new Response(
      JSON.stringify({
        success: true,
        restaurant_id: restaurantId,
        status: restaurantStatus,
        message: "Restaurante criado. Aguardando análise do admin (24-48h).",
      }),
      {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("register-partner error:", err);
    return new Response(
      JSON.stringify({
        error: `Erro interno: ${err instanceof Error ? err.message : String(err)}`,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
