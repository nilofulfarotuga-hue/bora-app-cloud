// Prova local (PGlite = Postgres real em WASM, com pgvector) da proposta
// docs/propostas/fechar-app-15-11/8e_robos_sem_notas_internas.PROPOSTA.sql
// — missão fechar-app-15-11, Bloco 8 (parte E).
//
// O que se prova: com a função de produção de 14/11, uma pergunta de cliente
// traz notas internas (a fuga medida); com a proposta aplicada TAL COMO ESTÁ,
// os robôs só veem as regras do negócio, os tipos de ajuda e as 4 secções do
// mapa dos ecrãs, pela ordem certa, e nada é apagado da tabela.
//
// Uso: node supabase/tests/fechar_app_8e_prova.mjs <pasta-com-node_modules-do-pglite>
//
// Teste anti-mentira: MUTACAO="texto=>outro" estraga a proposta de propósito e
// a prova TEM de falhar. Dois estragos que ela apanha:
//   MUTACAO="where public._conhecimento_para_clientes(k.source_type, k.source_file, k.section_title)=>where true"
//   MUTACAO="('business_rules', 'manual', 'faq', 'ajuda')=>('business_rules', 'manual', 'faq', 'ajuda', 'obsidian')"

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const pastaPglite = process.argv[2];
if (!pastaPglite) {
  console.error('falta a pasta do pglite');
  process.exit(2);
}
const require = createRequire(path.join(path.resolve(pastaPglite), 'x.js'));
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href);
const { vector } = await import(pathToFileURL(require.resolve('@electric-sql/pglite/vector')).href);

let proposta = readFileSync(
  path.join(aqui, '..', '..', 'docs', 'propostas', 'fechar-app-15-11', '8e_robos_sem_notas_internas.PROPOSTA.sql'),
  'utf8').replace(/\r\n/g, '\n');
if (process.env.MUTACAO) {
  const [de, para] = process.env.MUTACAO.split('=>');
  if (!proposta.includes(de)) throw new Error(`mutação não encontrada: ${de}`);
  proposta = proposta.split(de).join(para);
  console.log(`MUTAÇÃO aplicada: ${de} => ${para}`);
}

let certos = 0;
let falhados = 0;
function confere(nome, obtido, esperado) {
  const a = JSON.stringify(obtido);
  const b = JSON.stringify(esperado);
  if (a === b) { certos++; console.log(`  ok   ${nome}`); }
  else { falhados++; console.log(`  FALHOU ${nome}\n         obtido:   ${a}\n         esperado: ${b}`); }
}

// Vetor de 384 (ou n) posições a apontar para "e0" com semelhança `sim` à pergunta.
function vetor(sim, n = 384, outro = 1) {
  const v = new Array(n).fill(0);
  v[0] = sim;
  v[outro] = Math.sqrt(Math.max(0, 1 - sim * sim));
  return `[${v.join(',')}]`;
}
const PERGUNTA = vetor(1);
const PERGUNTA8 = vetor(1, 8);

const db = new PGlite({ extensions: { vector } });
await db.exec(`
  create schema extensions;
  create extension vector with schema extensions;
  create role anon; create role authenticated; create role service_role;
  create table public.support_knowledge_chunks (
    id uuid primary key default gen_random_uuid(),
    source_file text, source_type text, chunk_index int, section_title text,
    chunk_text text, char_count int, content_hash text,
    embedding extensions.vector(8), indexed_at timestamptz,
    embedding_gte extensions.vector(384), indexed_gte_at timestamptz);
`);

// Função TAL COMO ESTAVA em produção a 14/11/2026 (pg_get_functiondef).
await db.exec(`
CREATE OR REPLACE FUNCTION public.match_knowledge(query_embedding extensions.vector, match_count integer DEFAULT 5, min_similarity double precision DEFAULT 0.5)
 RETURNS TABLE(id uuid, source_file text, source_type text, section_title text, chunk_text text, similarity double precision)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  (select k.id, k.source_file, k.source_type, k.section_title, k.chunk_text,
          1 - (k.embedding_gte <=> query_embedding) as similarity
     from public.support_knowledge_chunks k
    where extensions.vector_dims(query_embedding) = 384
      and k.embedding_gte is not null
      and 1 - (k.embedding_gte <=> query_embedding) >= min_similarity
    order by k.embedding_gte <=> query_embedding
    limit match_count)
  union all
  (select k.id, k.source_file, k.source_type, k.section_title, k.chunk_text,
          1 - (k.embedding <=> query_embedding) as similarity
     from public.support_knowledge_chunks k
    where extensions.vector_dims(query_embedding) <> 384
      and k.embedding is not null
      and 1 - (k.embedding <=> query_embedding) >= min_similarity
    order by k.embedding <=> query_embedding
    limit match_count);
$function$;
revoke all on function public.match_knowledge(extensions.vector, integer, double precision) from public, anon, authenticated;
grant execute on function public.match_knowledge(extensions.vector, integer, double precision) to service_role;
`);

async function trecho(tipo, ficheiro, seccao, texto, sim, sim8 = null) {
  await db.query(
    `insert into public.support_knowledge_chunks
       (source_type, source_file, section_title, chunk_text, embedding_gte, embedding)
     values ($1, $2, $3, $4, $5::extensions.vector, $6::extensions.vector)`,
    [tipo, ficheiro, seccao, texto, vetor(sim), sim8 == null ? null : vetor(sim8, 8)]);
}
// Material interno, MUITO parecido com a pergunta (é o que ganhava a pesquisa).
await trecho('obsidian', 'bugs/auditoria-estafeta-completa.md', '🔴 BUGS CRÍTICOS', 'INTERNO auditoria', 1, 1);
await trecho('knowledge', 'permanente/credenciais-teste.md', null, 'INTERNO credenciais', 0.99);
await trecho('knowledge', 'permanente/preferencias-operacionais-danilo.md', null, 'INTERNO dono', 0.985);
await trecho('obsidian', 'mapa-ecras.md', 'Ecrãs Admin', 'INTERNO ecrãs admin', 0.95);
await trecho('obsidian', 'mapa-ecras.md', 'Ecrãs em Falta (a criar)', 'INTERNO ecrãs em falta', 0.9);
await trecho('obsidian', 'notas/nao-mapa-ecras.md', 'Ecrãs do Cliente', 'INTERNO ficheiro parecido', 0.88);
for (let i = 0; i < 60; i++) {
  await trecho('obsidian', `sessoes/2026-04-${String((i % 28) + 1).padStart(2, '0')}-sessao.md`,
    'Próxima sessão', `INTERNO nota ${i}`, 0.97 - i * 0.0005);
}
// O que é para clientes.
await trecho('business_rules', 'business_rules.md', 'Entrega', 'PUBLICO entrega 2,50 até 4 km', 0.8, 0.9);
await trecho('obsidian', 'mapa-ecras.md', 'Ecrãs do Cliente', 'PUBLICO onde fica o histórico', 0.7);
await trecho('knowledge', 'C:\\vault\\Bora\\mapa-ecras.md', 'Ecrãs do Driver', 'PUBLICO ecrãs do estafeta', 0.65);
await trecho('manual', 'manual-da-app.md', 'Como pagar', 'PUBLICO manual', 0.6);
await trecho('business_rules', 'business_rules.md', 'Reservas', 'PUBLICO longe da pergunta', 0.1);

const total = async () => Number((await db.query('select count(*) n from public.support_knowledge_chunks')).rows[0].n);
const procurar = async (q, n, min) =>
  (await db.query(
    'select chunk_text, round(similarity::numeric, 2)::float8 as sim from public.match_knowledge($1::extensions.vector, $2, $3)',
    [q, n, min])).rows;
const totalAntes = await total();

console.log('ANTES (função de produção de 14/11):');
const antes = await procurar(PERGUNTA, 5, 0.5);
confere('a pergunta de um cliente traz 5 trechos, TODOS internos (a fuga medida)',
  antes.map((r) => r.chunk_text.startsWith('INTERNO')), [true, true, true, true, true]);
confere('o primeiro é a auditoria interna', antes[0].chunk_text, 'INTERNO auditoria');

console.log('APLICAR a proposta tal como está:');
let erroAoAplicar = null;
try { await db.exec(proposta); } catch (e) { erroAoAplicar = String(e.message ?? e); }
confere('a proposta aplica-se sem erro', erroAoAplicar, null);

console.log('DEPOIS:');
const depois = await procurar(PERGUNTA, 5, 0.5);
confere('só o que é para clientes, do mais parecido para o menos',
  depois.map((r) => r.chunk_text),
  ['PUBLICO entrega 2,50 até 4 km', 'PUBLICO onde fica o histórico', 'PUBLICO ecrãs do estafeta', 'PUBLICO manual']);
confere('as semelhanças são as certas', depois.map((r) => r.sim), [0.8, 0.7, 0.65, 0.6]);
confere('nenhum trecho interno', depois.filter((r) => r.chunk_text.startsWith('INTERNO')).length, 0);
confere('mesmo pedindo 100 trechos sem mínimo, não vem nenhum interno',
  (await procurar(PERGUNTA, 100, -1)).filter((r) => r.chunk_text.startsWith('INTERNO')).length, 0);
confere('pedindo 100 sem mínimo vêm os 5 públicos (não se perdeu nenhum)',
  (await procurar(PERGUNTA, 100, -1)).length, 5);
confere('match_count continua a mandar', (await procurar(PERGUNTA, 2, 0.5)).map((r) => r.chunk_text),
  ['PUBLICO entrega 2,50 até 4 km', 'PUBLICO onde fica o histórico']);
confere('min_similarity continua a mandar', (await procurar(PERGUNTA, 5, 0.75)).map((r) => r.chunk_text),
  ['PUBLICO entrega 2,50 até 4 km']);
confere('o outro tamanho de vetor (coluna embedding) também vem filtrado',
  (await procurar(PERGUNTA8, 5, 0.5)).map((r) => r.chunk_text), ['PUBLICO entrega 2,50 até 4 km']);
confere('nada foi apagado da tabela', await total(), totalAntes);

const regra = async (t, f, s) =>
  (await db.query('select public._conhecimento_para_clientes($1, $2, $3) as r', [t, f, s])).rows[0].r;
confere('regra: regras do negócio', await regra('business_rules', 'business_rules.md', 'Tokens'), true);
confere('regra: nota de programação', await regra('obsidian', 'sessoes/x.md', 'Próxima sessão'), false);
confere('regra: cérebro interno', await regra('knowledge', 'credenciais-teste.md', null), false);
confere('regra: mapa dos ecrãs, cliente', await regra('obsidian', 'mapa-ecras.md', 'Ecrãs do Cliente'), true);
confere('regra: mapa dos ecrãs, entrada', await regra('obsidian', 'a/b/mapa-ecras.md', 'Ecrãs de Entrada / Auth'), true);
confere('regra: mapa dos ecrãs, admin', await regra('obsidian', 'mapa-ecras.md', 'Ecrãs Admin'), false);
confere('regra: ficheiro de nome parecido', await regra('obsidian', 'nao-mapa-ecras.md', 'Ecrãs do Cliente'), false);
confere('regra: tudo vazio', await regra(null, null, null), false);

const perm = async (papel, f) =>
  (await db.query('select has_function_privilege($1, $2, $3) as r', [papel, f, 'execute'])).rows[0].r;
const fRegra = 'public._conhecimento_para_clientes(text, text, text)';
const fMatch = 'public.match_knowledge(extensions.vector, integer, double precision)';
confere('a regra não fica aberta a anon', await perm('anon', fRegra), false);
confere('a regra não fica aberta a authenticated', await perm('authenticated', fRegra), false);
confere('match_knowledge continua fechada a anon', await perm('anon', fMatch), false);
confere('match_knowledge continua fechada a authenticated', await perm('authenticated', fMatch), false);
confere('match_knowledge continua aberta ao servidor', await perm('service_role', fMatch), true);
confere('a proposta não mexe na pesquisa do robô interno',
  /function\s+public\.match_cortex_knowledge/i.test(proposta), false);

console.log(`\nRESULTADO: ${certos} certos, ${falhados} falhados`);
process.exit(falhados === 0 ? 0 : 1);
