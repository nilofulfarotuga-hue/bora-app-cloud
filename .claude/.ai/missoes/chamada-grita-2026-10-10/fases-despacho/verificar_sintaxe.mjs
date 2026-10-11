// Cria num Postgres local (PGlite) TODAS as funções das migrações dadas, para
// apanhar erros de escrita no PL/pgSQL antes de chegarem a produção.
// (O Postgres verifica a sintaxe do corpo ao criar; tabelas/funções chamadas
// lá dentro só são resolvidas quando correm.)
// Uso: node verificar_sintaxe.mjs <pglite> <migracao1> [migracao2 ...]
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const [, , pgliteDir, ...migracoes] = process.argv
const { PGlite } = await import(pathToFileURL(`${pgliteDir}/node_modules/@electric-sql/pglite/dist/index.js`).href)
const db = new PGlite()
let ok = 0, falhas = 0
for (const m of migracoes) {
  const sql = readFileSync(m, 'utf8')
  const re = /CREATE OR REPLACE FUNCTION public\.([a-z_0-9]+)\([\s\S]*?\$function\$;/g
  let x
  while ((x = re.exec(sql))) {
    try {
      await db.exec(x[0])
      ok++
      console.log(`OK     ${x[1]}`)
    } catch (e) {
      falhas++
      console.log(`FALHOU ${x[1]}: ${e.message}`)
    }
  }
}
console.log(`\nfunções criadas: ${ok}, falhas: ${falhas}`)
process.exit(falhas ? 1 : 0)
