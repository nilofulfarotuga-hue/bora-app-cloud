// Sessão 5F B4 — Robô B: lista perguntas pendentes do Robô A
// Run: deno run --allow-env --allow-read --allow-net scripts/crosstalk/check_pending.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { load } from 'https://deno.land/std@0.224.0/dotenv/mod.ts';

const env = await load({ envPath: 'scripts/rag/.env' });
const SUPABASE_URL = env.SUPABASE_URL;
const SERVICE_ROLE_KEY = env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error('❌ scripts/rag/.env precisa de SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY');
  Deno.exit(1);
}

const supa = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const { data, error } = await supa
  .from('robot_crosstalk')
  .select('id, created_at, question, question_context, skill_triggered, session_id')
  .eq('direction', 'a_to_b')
  .eq('status', 'pending')
  .order('created_at', { ascending: false })
  .limit(50);

if (error) {
  console.error('❌ Erro ao consultar:', error.message);
  Deno.exit(1);
}

if (!data || data.length === 0) {
  console.log('✓ Sem perguntas pendentes do Robô A.');
  Deno.exit(0);
}

console.log(`\n${data.length} pergunta${data.length > 1 ? 's' : ''} pendente${data.length > 1 ? 's' : ''}:\n`);

for (const row of data) {
  const ts = row.created_at;
  console.log(`[${ts}] id=${row.id}`);
  console.log(`  question: "${row.question}"`);
  if (row.question_context && Object.keys(row.question_context).length > 0) {
    console.log(`  context:  ${JSON.stringify(row.question_context)}`);
  }
  if (row.skill_triggered) {
    console.log(`  skill:    ${row.skill_triggered}`);
  }
  if (row.session_id) {
    console.log(`  session:  ${row.session_id}`);
  }
  console.log('');
}

console.log('Próximo passo: query_knowledge.ts "<termo>" para consultar RAG.');
console.log('Resposta:      respond.ts <id> "<resposta>"');
