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

    // REGRA DO DANILO (2026-07-15): so email e telefone sao obrigatorios.
    // NIF, IBAN, nome, morada - aceita o que vier, sem validar formato.
    // Quem decide o que falta e o Danilo na aprovacao manual (approval_status=pending),
    // nao o sistema. O sistema so regista e deixa pendente.
    if (!body.email?.trim()) {
      return new Response(
        JSON.stringify({ error: "email obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!body.phone?.trim()) {
      return new Response(
        JSON.stringify({ error: "telefone obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // ── beauty / salão → service_providers ──────────────────────────────
    if (body.category === "beauty") {
      const providerId = crypto.randomUUID();
      const { error: spError } = await supabase
        .from("service_providers")
        .insert({
          id: providerId,
          user_id: userId,
          name: body.restaurantName || "",
          category: "beauty",
          address: body.address || "",
          phone: body.phone,
          lat: body.lat || null,
          lng: body.lng || null,
          nif: body.nif || null,
          iban: body.iban || null,
          photo_url: body.photoUrl || null,
          approval_status: "pending",
        });
      if (spError) {
        console.error("Register beauty provider insert error:", spError);
        return new Response(
          JSON.stringify({ error: `Erro ao inserir prestador: ${spError.message}` }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }
      console.log(`[register-partner] New beauty provider submitted: ${providerId} (${body.email})`);
      return new Response(
        JSON.stringify({
          success: true,
          provider_id: providerId,
          status: "pending",
          message: "Registo submetido. Aguardando análise do admin (24-48h).",
        }),
        { status: 201, headers: { "Content-Type": "application/json" } }
      );
    }

    // Gera UUID para restaurant.id
    const restaurantId = crypto.randomUUID();

    // INSERT em restaurants com approval_status='pending'
    // Danilo decide na aprovacao manual o que falta - sistema so regista.
    const { data: restaurantData, error: insertError } = await supabase
      .from("restaurants")
      .insert({
        id: restaurantId,
        user_id: userId,
        name: body.restaurantName || "",
        address: body.address || "",
        phone: body.phone,
        email: body.email,
        photo_url: body.photoUrl || "",
        cover_url: body.coverUrl || null,
        cuisine_type: body.cuisineType || "",
        category: body.category || "restaurant",
        is_partner: true,
        is_online: false,
        lat: body.lat || null,
        lng: body.lng || null,
        nif: body.nif || null,
        iban: body.iban || null,
        owner_doc_url: body.ownerDocUrl || null,
        activity_doc_url: body.activityDocUrl || null,
        approval_status: "pending",
        rejection_reason: null,
        submitted_at: new Date().toISOString(),
        reviewed_at: null,
        approved_at: null,
      })
      .select()
      .single();

    if (insertError) {
      console.error("Register partner insert error:", insertError);
      return new Response(
        JSON.stringify({ error: `Erro ao inserir restaurante: ${insertError.message}` }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`[register-partner] New partner submitted: ${restaurantId} (${body.email})`);

    return new Response(
      JSON.stringify({
        success: true,
        restaurant_id: restaurantId,
        status: "pending",
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
