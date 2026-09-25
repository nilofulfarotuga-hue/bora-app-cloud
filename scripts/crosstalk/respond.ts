// Sessão 5F B4 — Robô B: submete resposta a pergunta crosstalk pendente
// Run: deno run --allow-env --allow-read --allow-net \
//        scripts/crosstalk/respond.ts <crosstalk_id> "<resposta inline>"
// Ou:  ... respond.ts <crosstalk_id> < resposta.md   (stdin)
//
// Pode incluir terceiro arg JSON com rag_chunks_used:
//   respond.ts <id> "answer" '[{"id":"...","sim":0.85}]'

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { load } from 'https://deno.land/std@0.224.0/dotenv/mod.ts';
import { readAll } from 'https://deno.land/std@0.224.0/io/read_all.ts';

const env = await load({ envPath: 'scripts/rag/.env' });
const SUPABASE_URL = env.SUPABASE_URL;
const SERVICE_ROLE_KEY = env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('❌ scripts/rag/.env precisa de SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY');
  Deno.exit(1);
}

const args = Deno.args;
if (args.length < 1) {
  console.error('Uso:');
  console.error('  respond.ts <crosstalk_id> "<resposta>"');
  console.error('  respond.ts <crosstalk_id> < resposta.md');
  console.error('  respond.ts <crosstalk_id> "<resposta>" \'[{"id":"...","sim":0.85}]\'');
  Deno.exit(1);
}

const crosstalkId = args[0];
const uuidRe = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
if (!uuidRe.test(crosstalkId)) {
  console.error('❌ crosstalk_id não é UUID válido:', crosstalkId);
  Deno.exit(1);
}

let answer: string;
if (args.length >= 2) {
  answer = args[1];
} else {
  const stdinBytes = await readAll(Deno.stdin);
  answer = new TextDecoder().decode(stdinBytes).trim();
}

if (!answer || answer.length === 0) {
  console.error('❌ Resposta vazia.');
  Deno.exit(1);
}

let ragChunks: unknown = [];
if (args.length >= 3) {
  try {
    ragChunks = JSON.parse(args[2]);
    if (!Array.isArray(ragChunks)) throw new Error('not an array');
  } catch (e) {
    console.error('❌ Terceiro arg deve ser JSON array de chunks:', (e as Error).message);
    Deno.exit(1);
  }
}

const supa = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const { error } = await supa.rpc('robot_b_respond', {
  p_crosstalk_id: crosstalkId,
  p_answer: answer,
  p_rag_chunks: ragChunks,
});

if (error) {
  console.error('❌ robot_b_respond erro:', error.message);
  Deno.exit(1);
}

console.log(`✓ Resposta submetida para crosstalk ${crosstalkId}`);
console.log(`  Chars: ${answer.length}`);
console.log(`  RAG chunks: ${(ragChunks as unknown[]).length}`);
console.log('');
console.log('Estado actualizado: status="answered", answered_by="robot_b"');
