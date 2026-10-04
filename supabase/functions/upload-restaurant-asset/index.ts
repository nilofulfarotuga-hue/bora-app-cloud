import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";

const supabase = createClient(supabaseUrl, serviceRoleKey);

interface UploadRequest {
  restaurantId: string;
  kind: string; // 'owner_doc' | 'activity_doc' | 'logo' | 'cover' | 'hero' | ...
  fileBase64: string;
  contentType: string;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-client-info",
};

// 8 MB de ficheiro (base64 ≈ 4/3 do tamanho).
const MAX_BYTES = 8 * 1024 * 1024;
// kinds em uso: owner_doc, activity_doc, logo, cover, hero, gallery/photo, staff_photo.
const KIND_OK = /^[a-z_]{1,40}(\/[a-z_]{1,40})?$/;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/**
 * 04/10/2026 (agente parceiro): antes aceitava envio para a pasta de QUALQUER
 * loja sem verificar quem pedia. Agora:
 *  - pasta de uma loja/prestador que existe → só o dono (user_id/user_) ou admin;
 *  - "temp-..." (registo de parceiro novo, ainda sem loja e às vezes sem sessão)
 *    → a pasta é gerada AQUI (temp-<uuid>), nunca a que o telemóvel manda;
 *  - qualquer outro id → recusado.
 */
async function quemPede(req: Request): Promise<{ uid: string | null; admin: boolean; service: boolean }> {
  const auth = req.headers.get("Authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) return { uid: null, admin: false, service: false };
  if (serviceRoleKey && token === serviceRoleKey) return { uid: null, admin: true, service: true };
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) return { uid: null, admin: false, service: false };
  const uid = data.user.id;
  let admin = false;
  try {
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: isAdmin } = await userClient.rpc("is_admin");
    admin = isAdmin === true;
  } catch (_) {
    admin = false;
  }
  return { uid, admin, service: false };
}

async function donoDaPasta(id: string, uid: string): Promise<"dono" | "alheia" | "nao_existe"> {
  const { data: r } = await supabase
    .from("restaurants")
    .select("id, user_id, user_")
    .eq("id", id)
    .maybeSingle();
  if (r) return r.user_id === uid || r.user_ === uid ? "dono" : "alheia";
  const { data: sp } = await supabase
    .from("service_providers")
    .select("id, user_id")
    .eq("id", id)
    .maybeSingle();
  if (sp) return sp.user_id === uid ? "dono" : "alheia";
  return "nao_existe";
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const body = (await req.json()) as UploadRequest;

    if (!body.restaurantId || !body.kind || !body.fileBase64) {
      return json({ error: "restaurantId, kind, and fileBase64 required" }, 400);
    }
    if (!KIND_OK.test(body.kind)) {
      return json({ error: "kind inválido" }, 400);
    }
    let contentType = (body.contentType || "image/jpeg").toLowerCase();
    // A app manda "image/<extensão>" também para PDFs dos documentos.
    if (contentType === "image/pdf") contentType = "application/pdf";
    // Sem SVG (bucket público + script embutido).
    if (!/^(image\/[a-z0-9.-]{1,20}|application\/pdf)$/.test(contentType) || contentType.includes("svg")) {
      return json({ error: "Tipo de ficheiro não aceite" }, 400);
    }
    if (body.fileBase64.length > Math.ceil((MAX_BYTES * 4) / 3) + 4) {
      return json({ error: "Ficheiro demasiado grande (máx. 8 MB)" }, 413);
    }

    // ── Quem pode escrever nesta pasta ───────────────────────────────────
    const caller = await quemPede(req);
    let pasta: string;
    const pedida = String(body.restaurantId).trim();
    if (/^temp-/i.test(pedida)) {
      // Registo de parceiro novo: a pasta é sempre nova e gerada aqui.
      pasta = `temp-${crypto.randomUUID()}`;
    } else if (caller.admin) {
      pasta = pedida;
    } else if (!caller.uid) {
      return json({ error: "Sessão necessária" }, 401);
    } else {
      const dono = await donoDaPasta(pedida, caller.uid);
      if (dono !== "dono") {
        return json({ error: "Sem permissão para enviar ficheiros para esta loja" }, 403);
      }
      pasta = pedida;
    }

    // Decode base64 to bytes
    const binaryString = atob(body.fileBase64);
    if (binaryString.length > MAX_BYTES) {
      return json({ error: "Ficheiro demasiado grande (máx. 8 MB)" }, 413);
    }
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Generate unique filename
    const extension = (contentType.split("/")[1] || "jpg").replace(/[^a-z0-9]/g, "") || "jpg";
    const timestamp = Date.now();
    const filename = `${pasta}/${body.kind}-${timestamp}.${extension}`;

    // RGPD fix 2026-06-02: docs sensíveis (owner_doc, activity_doc) vão para
    // bucket PRIVADO `restaurant-documents`. Logo/hero/outros continuam no
    // bucket público `restaurant-assets`.
    const isPrivateDoc = body.kind === "owner_doc" || body.kind === "activity_doc";
    const bucket = isPrivateDoc ? "restaurant-documents" : "restaurant-assets";

    const { error: uploadError } = await supabase.storage
      .from(bucket)
      .upload(filename, bytes, {
        contentType,
        upsert: false,
      });

    if (uploadError) {
      console.error("Upload error:", uploadError);
      return json({ error: `Upload failed: ${uploadError.message}` }, 500);
    }

    // Public URL só para bucket público; private bucket devolve path (admin
    // gera signed URL no momento via PrivateBucketImage).
    let publicUrl: string | null = null;
    if (!isPrivateDoc) {
      const { data: publicUrlData } = supabase.storage
        .from(bucket)
        .getPublicUrl(filename);
      publicUrl = publicUrlData.publicUrl;
    }

    return json({
      success: true,
      public_url: publicUrl,
      path: filename,
      bucket,
    });
  } catch (error) {
    console.error("Unexpected error:", error);
    return json({ error: `Server error: ${(error as Error).message}` }, 500);
  }
});
