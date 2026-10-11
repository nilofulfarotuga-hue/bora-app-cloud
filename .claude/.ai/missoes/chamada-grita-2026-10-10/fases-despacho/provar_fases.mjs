// Prova da decisão das fases do despacho num Postgres local (PGlite), com a
// função copiada TAL E QUAL do ficheiro da migração (não é uma reescrita).
// Uso: node provar_fases.mjs <caminho-do-pglite> <caminho-da-migracao>
// Simula a linha do tempo de um pedido: cada volta pergunta a fase, faz a
// oferta que a fase manda (rotação como o motor: o 1.º online ainda não
// tentado nesta volta) e regista-a; pára em "esgotado".
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const [, , pgliteDir, migracao] = process.argv
const { PGlite } = await import(pathToFileURL(`${pgliteDir}/node_modules/@electric-sql/pglite/dist/index.js`).href)

const sql = readFileSync(migracao, 'utf8')
const ini = sql.indexOf('CREATE OR REPLACE FUNCTION public.dispatch_fase_decidir(')
const fim = sql.indexOf('$function$;', sql.indexOf('AS $function$', ini)) + '$function$;'.length
if (ini < 0 || fim < ini) throw new Error('função não encontrada na migração')
const ddl = sql.slice(ini, fim)

const db = new PGlite()
await db.exec(ddl)

const U = (n) => `00000000-0000-4000-8000-00000000000${n}`
const NOMES = { [U(1)]: 'Danilo', [U(2)]: 'Valdemir', [U(3)]: 'Outro', [U(4)]: 'Ana', [U(5)]: 'Bruno' }

async function decidir(online, ofertas, forcados, cfg) {
  const r = await db.query(
    `SELECT public.dispatch_fase_decidir($1::uuid[], $2::jsonb, $3::uuid[], $4, $5, $6, $7) AS d`,
    [online, JSON.stringify(ofertas), forcados, cfg.ligado, cfg.antes, cfg.tentativas, cfg.depois])
  return r.rows[0].d
}

async function simular(titulo, online, forcados, cfg, esperado) {
  const ofertas = []
  let tentadosNaVolta = []
  const passos = []
  for (let i = 0; i < 30; i++) {
    const d = await decidir(online, ofertas, forcados, cfg)
    if (d.fase === 'esgotado') { passos.push('SEM ESTAFETA (cancela)'); break }
    if (d.fase === 'forcado') {
      ofertas.push({ user_id: d.user_id, fase: 'forcado' })
      passos.push(`reforço→${NOMES[d.user_id]}`)
      continue
    }
    // online1 / online2: o motor oferece ao 1.º online ainda não tentado; tentados todos → volta nova.
    if (online.length === 0) { passos.push(`${d.fase}: ninguém online (o motor espera)`); break }
    let livre = online.find((u) => !tentadosNaVolta.includes(u))
    if (!livre) { tentadosNaVolta = []; livre = online[0] }
    tentadosNaVolta.push(livre)
    ofertas.push({ user_id: livre, fase: d.fase })
    passos.push(`${d.fase}→${NOMES[livre]}`)
  }
  const obtido = passos.join(' | ')
  const ok = obtido === esperado
  console.log(`${ok ? 'OK ' : 'FALHOU'} ${titulo}\n     obtido:   ${obtido}${ok ? '' : `\n     esperado: ${esperado}`}`)
  return ok
}

const base = { ligado: true, antes: 2, tentativas: 2, depois: 1 }
const res = []
res.push(await simular('Regra do Danilo: 1 online, 2 do reforço (Valdemir 1.º)',
  [U(1)], [U(2), U(3)], base,
  'online1→Danilo | online1→Danilo | reforço→Valdemir | reforço→Outro | online2→Danilo | SEM ESTAFETA (cancela)'))
res.push(await simular('2 online, só 1 consentiu no reforço',
  [U(4), U(5)], [U(2)], base,
  'online1→Ana | online1→Bruno | online1→Ana | online1→Bruno | reforço→Valdemir | online2→Ana | online2→Bruno | SEM ESTAFETA (cancela)'))
res.push(await simular('Ninguém online, 2 no reforço: chama logo o reforço',
  [], [U(2), U(3)], base,
  'reforço→Valdemir | reforço→Outro | SEM ESTAFETA (cancela)'))
res.push(await simular('Ninguém online e ninguém no reforço: esgotado sem ofertas (a varredura NÃO cancela; vale o tempo de sempre)',
  [], [], base,
  'SEM ESTAFETA (cancela)'))
res.push(await simular('Reforço desligado: igual a hoje (sempre online1, nunca esgota)',
  [U(1)], [U(2)], { ...base, ligado: false },
  Array(30).fill('online1→Danilo').join(' | ')))
res.push(await simular('Uma vez por pedido: o Valdemir aparece 2 vezes na lista mas só é chamado 1 vez',
  [U(1)], [U(2), U(2)], { ...base, tentativas: 2 },
  'online1→Danilo | online1→Danilo | reforço→Valdemir | online2→Danilo | SEM ESTAFETA (cancela)'))
res.push(await simular('Tentativas = 1: só o 1.º da ordem',
  [U(1)], [U(2), U(3)], { ...base, tentativas: 1 },
  'online1→Danilo | online1→Danilo | reforço→Valdemir | online2→Danilo | SEM ESTAFETA (cancela)'))

// Casos soltos da decisão (sem simulação).
const d0 = await decidir([U(1)], [], [U(2)], base)
console.log(`${d0.fase === 'online1' ? 'OK ' : 'FALHOU'} pedido novo começa em online1 (veio ${d0.fase})`)
res.push(d0.fase === 'online1')

const passou = res.filter(Boolean).length
console.log(`\nRESULTADO: ${passou}/${res.length} ${passou === res.length ? 'TODOS OK' : 'COM FALHAS'}`)
process.exit(passou === res.length ? 0 : 1)
