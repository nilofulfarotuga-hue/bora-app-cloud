// Sessão 5C-β/7 — Edge Fn reindex-knowledge
// Re-indexa embeddings em support_knowledge_chunks via Gemini.
// Modes: 'pending' (embedding IS NULL) | 'all' (todos chunks).
// Admin-only (is_admin() guard).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent";
const EMBED_DIM = 768;
const RATE_LIMIT_MS = 1000;
const DEFAULT_MAX = 100;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function embedText(text: string): Promise<number[] | null> {
  for (let attempt = 0; attempt <= 2; attempt++) {
    try {
      const res = await fetch(GEMINI_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": GEMINI_API_KEY!,
        },
        body: JSON.stringify({
          content: { parts: [{ text }] },
          taskType: "RETRIEVAL_DOCUMENT",
          outputDimensionality: EMBED_DIM,
        }),
      });

      if (res.status === 429) {
        if (attempt < 2) {
          await sleep(5_000);
          continue;
        }
        return null;
      }
      if (!res.ok) return null;

      const json = await res.json();
      const values = json?.embedding?.values;
      if (!Array.isArray(values) || values.length !== EMBED_DIM) return null;
      return values as number[];
    } catch {
      if (attempt < 2) {
        await sleep(2_000);
        continue;
      }
      return null;
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  if (!GEMINI_API_KEY) {
    return jsonResponse({ error: "GEMINI_API_KEY missing" }, 503);
  }

  // 1. Auth — verify_jwt=true ensures token is valid; we additionally check is_admin
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return jsonResponse({ error: "no jwt" }, 401);
  const userJwt = authHeader.replace("Bearer ", "");

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: "invalid jwt" }, 401);

  // is_admin() check via user-scoped RPC (uses auth.jwt() inside)
  const { data: isAdmin, error: adminErr } = await userClient.rpc("is_admin");
  if (adminErr || isAdmin !== true) {
    return jsonResponse({ error: "NOT_ADMIN" }, 403);
  }

  // 2. Parse body
  let body: { mode?: string; max_chunks?: number };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const mode = (body.mode === "all") ? "all" : "pending";
  const maxChunks = Math.min(
    Math.max(parseInt(String(body.max_chunks ?? DEFAULT_MAX), 10) || DEFAULT_MAX, 1),
    500,
  );

  // 3. Fetch chunks
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  let query = adminClient
    .from("support_knowledge_chunks")
    .select("id, chunk_text")
    .order("indexed_at", { ascending: true })
    .limit(maxChunks);
  if (mode === "pending") query = query.is("embedding", null);

  const { data: chunks, error: fetchErr } = await query;
  if (fetchErr) return jsonResponse({ error: `fetch: ${fetchErr.message}` }, 500);
  if (!chunks || chunks.length === 0) {
    return jsonResponse({ reindexed: 0, errors: 0, mode, message: "no chunks to reindex" });
  }

  // 4. Embed + UPDATE (rate-limited 1 req/s)
  let reindexed = 0;
  let errors = 0;
  const errorIds: string[] = [];
  const startTs = Date.now();

  for (const c of chunks) {
    const emb = await embedText(c.chunk_text as string);
    if (!emb) {
      errors++;
      errorIds.push(c.id as string);
      await sleep(RATE_LIMIT_MS);
      continue;
    }

    // pgvector accepts bracketed-array literal as text
    const embLit = `[${emb.join(",")}]`;
    const { error: updErr } = await adminClient
      .from("support_knowledge_chunks")
      .update({
        embedding: embLit,
        indexed_at: new Date().toISOString(),
      })
      .eq("id", c.id);

    if (updErr) {
      errors++;
      errorIds.push(c.id as string);
    } else {
      reindexed++;
    }

    await sleep(RATE_LIMIT_MS);
  }

  const elapsedSec = Math.round((Date.now() - startTs) / 1000);

  return jsonResponse({
    reindexed,
    errors,
    mode,
    max_chunks: maxChunks,
    elapsed_sec: elapsedSec,
    error_ids: errorIds.slice(0, 20),
  });
});
