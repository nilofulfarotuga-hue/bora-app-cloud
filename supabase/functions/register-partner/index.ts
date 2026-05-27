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
  // Portuguese IBAN: PT + 21 digits (23 chars total)
  return /^PT\d{21}$/.test(iban.toUpperCase().replace(/\s/g, ""));
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
          error: "IBAN formato inválido (PT + 21 dígitos)",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Gera UUID para restaurant.id
    const restaurantId = crypto.randomUUID();

    // INSERT em restaurants com approval_status='pending'
    // BUG-2 FIX: define user_id para permitir RLS em products
    const { data: restaurantData, error: insertError } = await supabase
      .from("restaurants")
      .insert({
        id: restaurantId,
        user_id: userId,
        name: body.restaurantName,
        address: body.address,
        phone: body.phone,
        email: body.email,
        photo_url: "",
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

    // Trigger notificação admin (via Edge Function notify-admin-urgent se existir)
    // Para simplicidade, apenas log aqui — admin vê em dashboard quando load partners
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
