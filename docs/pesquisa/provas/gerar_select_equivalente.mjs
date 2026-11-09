// Gera a SELECT só de leitura que faz EXATAMENTE a lógica de public.pesquisa_produtos
// (missão m11, 09/11/2026), para medir o "depois" em produção sem CREATE nenhum.
//
// Como: lê o corpo da função entre "-- CORPO-INICIO" e "-- CORPO-FIM" da migração e a
// semente de sinónimos entre "-- SEMENTE-INICIO" e "-- SEMENTE-FIM"; troca a tabela
// pesquisa_sinonimos por um CTE com a semente (chave/alvo_chave calculados como o gatilho
// os calcula) e os parâmetros pelos valores de cada caso. Nada é escrito à mão.
//
// Uso:
//   node gerar_select_equivalente.mjs <migracao.sql> <casos.csv> <saida.sql> [modo]
//   modo = "casos" (os 60, com posição do produto certo) | "explain:<loja>:<termo>"
import { readFileSync, writeFileSync } from 'node:fs';

export function partes(migracao) {
  const sql = readFileSync(migracao, 'utf8');
  const corpo = sql.split('-- CORPO-INICIO')[1].split('-- CORPO-FIM')[0];
  const semente = sql.split('-- SEMENTE-INICIO')[1].split('-- SEMENTE-FIM')[0];
  const valores = semente.split('from (values')[1].split(') as v(termo, alvo)')[0];
  return { corpo, valores };
}

export function cteSinonimos(valores) {
  return `sinonimos_semente as (
  select v.termo, v.alvo, null::text as product_id, null::text as restaurant_id,
         array_to_string(public.assistant_tokens(btrim(v.termo)), ' ') as chave,
         array_to_string(public.assistant_tokens(btrim(v.alvo)), ' ') as alvo_chave,
         true as ativo
    from (values ${valores}) as v(termo, alvo)
)`;
}

// corpo com a tabela trocada pelo CTE e os parâmetros pelas expressões dadas
export function corpoCom(corpo, { q, loja, limite = '50', vetor = 'null::extensions.vector' }) {
  return corpo
    .replace(/public\.pesquisa_sinonimos\b/g, 'sinonimos_semente')
    .replace(/\bp_restaurant_id\b/g, loja)
    .replace(/\bp_limit\b/g, limite)
    .replace(/\bp_embedding\b/g, vetor)
    .replace(/\bp_q\b/g, q);
}

// Em produção corre com --read-only (só SELECT): o limiar do pg_trgm que a função tem no
// SET entra por set_config num CTE materializado, lido antes dos casos; cada caso devolve o
// limiar que estava ativo (prova de que a pesquisa correu com 0.45). Nomes todos qualificados
// (public./extensions.), por isso o search_path da sessão não muda nada.
const CFG = `cfg as materialized (
  select set_config('pg_trgm.word_similarity_threshold', '0.45', true) as limiar
)`;
const PREFIXO = '';

export function selectCasos(migracao, casosCsv) {
  const { corpo, valores } = partes(migracao);
  const linhas = readFileSync(casosCsv, 'utf8').trim().split(/\r?\n/).slice(1);
  const lit = (s) => `'${s.replace(/'/g, "''")}'`;
  const casos = linhas.map((l) => {
    const [id, g, loja, t, re] = l.split(';');
    return `(${[id, g, loja, t, re].map(lit).join(',')})`;
  }).join(',\n');
  const c = corpoCom(corpo, { q: 'caso.termo', loja: 'caso.loja' });
  return `with ${CFG},
casos(id, grupo, loja, termo, esperado) as (values
${casos}),
${cteSinonimos(valores)},
-- cada caso: relógio antes, a pesquisa (o corpo da função), relógio depois
corrida as (
  select caso.id, caso.esperado, d.ms, d.limiar, b.linhas
    from cfg cross join casos caso
    cross join lateral (select clock_timestamp() as t0, caso.id as cid) a
    cross join lateral (
      select coalesce(jsonb_agg(jsonb_build_object('name', z.name, 'kind', z.kind)
                                order by z.score desc, z.name), '[]'::jsonb) as linhas
        from (${c}) z(id, name, category, category_root, price, photo_url, restaurant_id, kind, score)
       where a.cid is not null
    ) b
    cross join lateral (
      select round(extract(epoch from clock_timestamp() - a.t0)::numeric * 1000, 1) as ms,
             jsonb_array_length(b.linhas) as n,
             current_setting('pg_trgm.word_similarity_threshold') as limiar
    ) d
),
res as (
  select r.id, x.pos::int as pos, x.e->>'name' as name, x.e->>'kind' as kind,
         public.bora_normalize(x.e->>'name') ~ r.esperado as ok
    from corrida r
    cross join lateral jsonb_array_elements(r.linhas) with ordinality as x(e, pos)
)
select c.id, c.grupo, c.loja, c.termo,
       (select r.ms from corrida r where r.id = c.id) as ms,
       (select r.limiar from corrida r where r.id = c.id) as limiar,
       (select count(*) from res where res.id = c.id) as n,
       (select min(pos) from res where res.id = c.id and ok) as pos_certo,
       (select string_agg(res.kind, ',' order by pos) from res where res.id = c.id and pos <= 5) as tipos_top5,
       (select left(string_agg(res.name, ' | ' order by pos), 200) from res where res.id = c.id and pos <= 5) as top5
  from casos c
 order by c.id;
`;
}

export function selectUm(migracao, loja, termo) {
  const { corpo, valores } = partes(migracao);
  const lit = (s) => (s === null ? 'null::text' : `'${s.replace(/'/g, "''")}'::text`);
  const c = corpoCom(corpo, { q: lit(termo), loja: lit(loja) });
  return `with ${CFG}, ${cteSinonimos(valores)}
select z.* from cfg,  (${c}) z(id, name, category, category_root, price, photo_url, restaurant_id, kind, score)`;
}

if (process.argv[1] && process.argv[1].endsWith('gerar_select_equivalente.mjs')) {
  const [, , migracao, casosCsv, saida, modo = 'casos'] = process.argv;
  let out;
  if (modo === 'casos') {
    out = selectCasos(migracao, casosCsv);
  } else if (modo === 'antes') {
    // o "antes": a search_products que está no ar hoje (a mesma chamada da app, 50 linhas)
    const linhas = readFileSync(casosCsv, 'utf8').trim().split(/\r?\n/).slice(1);
    const lit = (s) => `'${s.replace(/'/g, "''")}'`;
    const casos = linhas.map((l) => `(${l.split(';').map(lit).join(',')})`).join(',\n');
    out = `with casos(id, grupo, loja, termo, esperado) as (values
${casos}),
corrida as (
  select caso.id, caso.esperado, d.ms, b.linhas
    from casos caso
    cross join lateral (select clock_timestamp() as t0, caso.id as cid) a
    cross join lateral (
      select coalesce(jsonb_agg(jsonb_build_object('name', s.name) order by s.o), '[]'::jsonb) as linhas
        from public.search_products(caso.termo, caso.loja, 50)
               with ordinality s(result_type, id, name, category, category_root, price, photo_url, match_rank, o)
       where s.result_type = 'product' and a.cid is not null
    ) b
    cross join lateral (
      select round(extract(epoch from clock_timestamp() - a.t0)::numeric * 1000, 1) as ms, b.linhas as l
    ) d
),
res as (
  select r.id, x.pos::int as pos, x.e->>'name' as name,
         public.bora_normalize(x.e->>'name') ~ r.esperado as ok
    from corrida r
    cross join lateral jsonb_array_elements(r.linhas) with ordinality as x(e, pos)
)
select c.id, c.grupo, c.loja, c.termo,
       (select r.ms from corrida r where r.id = c.id) as ms,
       (select count(*) from res where res.id = c.id) as n,
       (select min(pos) from res where res.id = c.id and ok) as pos_certo,
       (select left(string_agg(res.name, ' | ' order by pos), 200) from res where res.id = c.id and pos <= 5) as top5
  from casos c
 order by c.id;
`;
  } else if (modo.startsWith('explain:')) {
    const [, loja, termo] = modo.split(':');
    out = `${PREFIXO}explain (analyze, buffers, format text)\n${selectUm(migracao, loja === 'null' ? null : loja, termo)};\n`;
  } else {
    throw new Error(`modo desconhecido: ${modo}`);
  }
  writeFileSync(saida, out);
  console.log(`escrito ${saida} (${out.length} caracteres)`);
}
