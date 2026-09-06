// Bora App — RAG Knowledge Ingest (Sessão 5C-α/7)
//
// Walks 3 sources (.obsidian-vault/, .claude/.ai/knowledge/, business_rules.md),
// chunks markdown by ## sections (fallback \n\n), embeds via Gemini
// text-embedding-004 (768 dims), and upserts into support_knowledge_chunks.
//
// Run:
//   cd scripts/rag
//   deno run --allow-net --allow-read --allow-env \
//     --env-file=.env ingest_knowledge.ts

import { walk } from "https://deno.land/std@0.224.0/fs/walk.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";

// ─────────────────────────────────────────────────────────────────────────
// CONFIG
// ─────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !GEMINI_API_KEY) {
  console.error(
    "✗ Missing env vars. Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY",
  );
  console.error("  Copy .env.example → .env and fill values.");
  Deno.exit(1);
}

const REPO_ROOT = new URL("../../", import.meta.url).pathname.replace(
  /^\/([A-Z]):/,
  "$1:",
);

const SOURCES: Array<{ path: string; type: string }> = [
  { path: `${REPO_ROOT}.obsidian-vault`, type: "obsidian" },
  { path: `${REPO_ROOT}.claude/.ai/knowledge`, type: "knowledge" },
  { path: `${REPO_ROOT}.claude/.ai/business_rules.md`, type: "business_rules" },
];

const MAX_CHUNK_CHARS = 8000;
const RATE_LIMIT_MS = 1000;
// gemini-embedding-001 (Matryoshka) — text-embedding-004 deprecated em 2026.
// outputDimensionality=768 mantém compat com vector(768) na tabela.
const GEMINI_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent";
const EMBED_DIM = 768;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ─────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────

async function sha256(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return encodeHex(new Uint8Array(hash));
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function relativePath(absPath: string): string {
  return absPath.replace(REPO_ROOT, "").replaceAll("\\", "/");
}

interface Chunk {
  source_file: string;
  source_type: string;
  chunk_index: number;
  section_title: string | null;
  chunk_text: string;
  content_hash: string;
}

// ─────────────────────────────────────────────────────────────────────────
// CHUNKING
// ─────────────────────────────────────────────────────────────────────────

function splitParagraphsRespectingCap(
  text: string,
  cap: number,
): string[] {
  const paragraphs = text.split(/\n\n+/).filter((p) => p.trim().length > 0);
  const out: string[] = [];
  let current = "";
  for (const p of paragraphs) {
    if (p.length > cap) {
      if (current) {
        out.push(current);
        current = "";
      }
      // hard split oversized paragraph by chars
      for (let i = 0; i < p.length; i += cap) {
        out.push(p.slice(i, i + cap));
      }
      continue;
    }
    if ((current + "\n\n" + p).length > cap) {
      if (current) out.push(current);
      current = p;
    } else {
      current = current ? `${current}\n\n${p}` : p;
    }
  }
  if (current) out.push(current);
  return out;
}

async function chunkFile(
  absPath: string,
  sourceType: string,
): Promise<Chunk[]> {
  const text = await Deno.readTextFile(absPath);
  const sourceFile = relativePath(absPath);

  // Split by ## sections (preserves order)
  const sectionRegex = /^##\s+(.+)$/gm;
  const matches = [...text.matchAll(sectionRegex)];

  const rawSections: Array<{ title: string | null; body: string }> = [];

  if (matches.length === 0) {
    // No ## headings → whole file as one section
    rawSections.push({ title: null, body: text });
  } else {
    // Preamble before first ##
    if (matches[0].index! > 0) {
      const preamble = text.slice(0, matches[0].index).trim();
      if (preamble.length > 0) {
        rawSections.push({ title: null, body: preamble });
      }
    }
    for (let i = 0; i < matches.length; i++) {
      const start = matches[i].index!;
      const end = i + 1 < matches.length ? matches[i + 1].index! : text.length;
      const section = text.slice(start, end);
      const titleLine = matches[i][1].trim();
      rawSections.push({ title: titleLine, body: section });
    }
  }

  const chunks: Chunk[] = [];
  let chunkIndex = 0;
  for (const sec of rawSections) {
    const body = sec.body.trim();
    if (body.length === 0) continue;

    const subChunks = body.length > MAX_CHUNK_CHARS
      ? splitParagraphsRespectingCap(body, MAX_CHUNK_CHARS)
      : [body];

    for (const sub of subChunks) {
      const trimmed = sub.trim();
      if (trimmed.length === 0) continue;
      chunks.push({
        source_file: sourceFile,
        source_type: sourceType,
        chunk_index: chunkIndex++,
        section_title: sec.title,
        chunk_text: trimmed,
        content_hash: await sha256(trimmed),
      });
    }
  }

  return chunks;
}

// ─────────────────────────────────────────────────────────────────────────
// GEMINI EMBEDDING
// ─────────────────────────────────────────────────────────────────────────

async function embedText(
  text: string,
  retries = 3,
): Promise<number[] | null> {
  for (let attempt = 0; attempt <= retries; attempt++) {
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
        console.warn(`  ⚠ 429 rate-limited — wait 60s (attempt ${attempt + 1})`);
        await sleep(60_000);
        continue;
      }

      if (!res.ok) {
        const body = await res.text();
        console.error(`  ✗ Gemini ${res.status}: ${body.slice(0, 200)}`);
        if (res.status >= 500 && attempt < retries) {
          await sleep(2_000 * (attempt + 1));
          continue;
        }
        return null;
      }

      const json = await res.json();
      const values = json?.embedding?.values;
      if (!Array.isArray(values) || values.length !== EMBED_DIM) {
        console.error(`  ✗ Unexpected embedding shape (got ${values?.length ?? "null"})`);
        return null;
      }
      return values as number[];
    } catch (err) {
      console.error(`  ✗ Network error: ${(err as Error).message}`);
      if (attempt < retries) {
        await sleep(2_000 * (attempt + 1));
        continue;
      }
      return null;
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────
// UPSERT
// ─────────────────────────────────────────────────────────────────────────

async function hashExists(hash: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("support_knowledge_chunks")
    .select("id")
    .eq("content_hash", hash)
    .maybeSingle();
  if (error) {
    console.error(`  ✗ Hash check error: ${error.message}`);
    return false;
  }
  return data !== null;
}

async function upsertChunk(
  chunk: Chunk,
  embedding: number[],
): Promise<"new" | "updated" | "failed"> {
  // pgvector accepts a JSON array via PostgREST when column type is vector
  const embeddingLiteral = `[${embedding.join(",")}]`;
  const { error } = await supabase
    .from("support_knowledge_chunks")
    .upsert(
      {
        source_file: chunk.source_file,
        source_type: chunk.source_type,
        chunk_index: chunk.chunk_index,
        section_title: chunk.section_title,
        chunk_text: chunk.chunk_text,
        content_hash: chunk.content_hash,
        embedding: embeddingLiteral,
        indexed_at: new Date().toISOString(),
      },
      { onConflict: "source_file,chunk_index" },
    );
  if (error) {
    console.error(`  ✗ Upsert error: ${error.message}`);
    return "failed";
  }
  return "new";
}

// ─────────────────────────────────────────────────────────────────────────
// FILE WALK
// ─────────────────────────────────────────────────────────────────────────

async function* iterateMarkdownFiles(
  source: { path: string; type: string },
): AsyncGenerator<{ absPath: string; type: string }> {
  let stat: Deno.FileInfo | null = null;
  try {
    stat = await Deno.stat(source.path);
  } catch {
    console.warn(`⚠ Source not found: ${source.path} — skipping`);
    return;
  }
  if (stat.isFile) {
    if (source.path.endsWith(".md")) {
      yield { absPath: source.path, type: source.type };
    }
    return;
  }
  for await (
    const entry of walk(source.path, {
      exts: [".md"],
      includeDirs: false,
      followSymlinks: false,
    })
  ) {
    yield { absPath: entry.path, type: source.type };
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────────────────────

async function main() {
  console.log("🔍 Bora RAG Ingest — start");
  console.log(`   Repo root: ${REPO_ROOT}`);

  const totals = {
    files: 0,
    chunks_total: 0,
    chunks_new: 0,
    chunks_dup: 0,
    chunks_failed: 0,
  };

  const t0 = Date.now();

  for (const source of SOURCES) {
    console.log(`\n── source: ${source.type} (${source.path})`);
    for await (const file of iterateMarkdownFiles(source)) {
      totals.files++;
      const rel = relativePath(file.absPath);
      let chunks: Chunk[] = [];
      try {
        chunks = await chunkFile(file.absPath, file.type);
      } catch (err) {
        console.error(`✗ Chunk error ${rel}: ${(err as Error).message}`);
        continue;
      }

      let fileNew = 0;
      let fileDup = 0;
      let fileFailed = 0;

      for (const chunk of chunks) {
        totals.chunks_total++;

        if (await hashExists(chunk.content_hash)) {
          totals.chunks_dup++;
          fileDup++;
          continue;
        }

        const embedding = await embedText(chunk.chunk_text);
        if (!embedding) {
          totals.chunks_failed++;
          fileFailed++;
          await sleep(RATE_LIMIT_MS);
          continue;
        }

        const r = await upsertChunk(chunk, embedding);
        if (r === "failed") {
          totals.chunks_failed++;
          fileFailed++;
        } else {
          totals.chunks_new++;
          fileNew++;
        }

        await sleep(RATE_LIMIT_MS);
      }

      console.log(
        `✅ ${rel} → ${chunks.length} chunks (${fileNew} new, ${fileDup} dup, ${fileFailed} failed)`,
      );
    }
  }

  const tookSec = Math.round((Date.now() - t0) / 1000);
  console.log("\n── summary ──");
  console.log(`   files:           ${totals.files}`);
  console.log(`   chunks total:    ${totals.chunks_total}`);
  console.log(`   chunks new:      ${totals.chunks_new}`);
  console.log(`   chunks dup:      ${totals.chunks_dup}`);
  console.log(`   chunks failed:   ${totals.chunks_failed}`);
  console.log(`   elapsed:         ${tookSec}s`);
}

await main();
