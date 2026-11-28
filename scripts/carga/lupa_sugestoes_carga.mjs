// Teste de carga da missão lupa-sugestoes-17-11 (bloco 3.2). Correr DEPOIS de aplicar as
// migrações 20261117140000 e 20261117140100 (APLICAR.md, passo 5).
//
// Simula N pessoas SEM login (chave pública da app) durante S segundos a escrever na lupa letra a
// letra (a, ag, agu, agua…), com o comportamento da app NOVA:
//   * 1-2 letras: quando a pessoa pára 250 ms, pede `lupa_sugestoes` (memória de 10 min por prefixo);
//   * 3+ letras: quando pára 400 ms, a pesquisa completa (`cliente_pesquisar` na página inicial,
//     `search_products` na lupa de uma loja), memória de 5 min;
//   * metade das vezes toca numa sugestão (pesquisa completa já com esse texto).
// NUNCA cria pedidos nem escreve nada. Alvo: p95 das sugestões < 300 ms, 0 erros, servidor < 30%.
//
// Travão: de 15 em 15 s, se o p95 passar 4 s ou mais de 5% dos pedidos falharem, PÁRA. O vigia do
// servidor (vigia_servidor_registos, de 5 em 5 min) não é legível sem login: quem corre isto vê-o
// pelo MCP ao mesmo tempo e pára o script (Ctrl+C) se passar 85%.
// Uso: BORA_ANON=<chave pública anon> node lupa_sugestoes_carga.mjs <pessoas> <segundos> <saida.json>
import { readFileSync, writeFileSync } from 'node:fs'

const BASE = 'https://ojykpzwqrtusfeakzrna.supabase.co'
const CHAVE = process.env.BORA_ANON
if (!CHAVE) throw new Error('falta BORA_ANON (chave pública anon da app)')
const [, , nTxt = '100', sTxt = '180', saida = 'carga_lupa.json'] = process.argv
const PESSOAS = Number(nTxt)
const SEGUNDOS = Number(sTxt)
const H = { apikey: CHAVE, Authorization: `Bearer ${CHAVE}`, 'Content-Type': 'application/json' }

const aqui = new URL('.', import.meta.url)
const palavras = readFileSync(new URL('../../docs/propostas/busca-leve-2026-11-17/consultas_teste.txt', aqui), 'utf8')
  .split('\n').map((s) => s.trim()).filter((s) => s.length >= 3)
palavras.push('agua', 'arroz', 'azeite', 'cafe', 'chocolate', 'leite', 'pao', 'papel')
const LOJAS = ['continente-guarda', 'auchan-guarda', 'intermarche-guarda', 'pingodoce-guarda', 'a3-guarda']

const sorte = (a) => a[Math.floor(Math.random() * a.length)]
const espera = (ms) => new Promise((r) => setTimeout(r, ms))
const entre = (a, b) => a + Math.random() * (b - a)
const letras = (t) => (t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().match(/[a-z0-9]/g) || []).length

const reg = [] // {t, tipo, ms, estado, n}
let parar = false
let motivoParagem = null

async function pedir(tipo, nome, corpo) {
  const t0 = Date.now()
  let estado = 0
  let n = null
  try {
    const r = await fetch(`${BASE}/rest/v1/rpc/${nome}`, {
      method: 'POST', headers: H, body: JSON.stringify(corpo), signal: AbortSignal.timeout(20000),
    })
    estado = r.status
    const txt = await r.text()
    try { const j = JSON.parse(txt); n = Array.isArray(j) ? j.length : null } catch { /* resposta não-JSON */ }
  } catch (e) {
    estado = e?.name === 'TimeoutError' ? 'timeout' : 'rede'
  }
  reg.push({ t: Date.now(), tipo, ms: Date.now() - t0, estado, n })
}

async function lupa(loja, memSug, memPesq) {
  const palavra = sorte(palavras)
  const sugerir = (t) => pedir('lupa_sugestoes', 'lupa_sugestoes', { p_q: t, p_restaurant_id: loja })
  const pesquisar = (t) => loja
    ? pedir('search_products', 'search_products', { query_text: t, p_restaurant_id: loja, max_results: 50 })
    : pedir('cliente_pesquisar', 'cliente_pesquisar', { p_q: t, p_limit: 30 })
  const chave = (t) => `${loja ?? '*'}|${t}`
  for (let i = 1; i <= palavra.length && !parar; i++) {
    const t = palavra.slice(0, i)
    const pausa = entre(120, 450) // tempo até à letra seguinte
    await espera(pausa)
    const n = letras(t)
    if (n >= 1 && n < 3 && pausa >= 250 && !memSug.has(chave(t))) { memSug.add(chave(t)); await sugerir(t) }
    if (n >= 3 && pausa >= 400 && !memPesq.has(chave(t))) { memPesq.add(chave(t)); await pesquisar(t) }
    // metade das pessoas toca numa sugestão com 2 letras: pesquisa completa já com a palavra
    if (n === 2 && Math.random() < 0.5) {
      await espera(entre(300, 900))
      if (!parar && !memPesq.has(chave(palavra))) { memPesq.add(chave(palavra)); await pesquisar(palavra) }
      return
    }
  }
  await espera(400)
  const fimT = palavra
  if (!parar && !memPesq.has(chave(fimT))) { memPesq.add(chave(fimT)); await pesquisar(fimT) }
}

async function pessoa(fim) {
  const memSug = new Set() // memória de 10 min (o teste dura menos)
  const memPesq = new Set() // memória de 5 min
  while (Date.now() < fim && !parar) {
    await lupa(Math.random() < 0.5 ? null : sorte(LOJAS), memSug, memPesq)
    await espera(entre(3000, 8000)) // olha para o ecrã
  }
}

const pct = (a, p) => (a.length ? a[Math.min(a.length - 1, Math.floor(p * a.length))] : null)

function resumo(lista) {
  const ms = lista.map((r) => r.ms).sort((a, b) => a - b)
  const falhas = lista.filter((r) => !(typeof r.estado === 'number' && r.estado < 400))
  return { pedidos: lista.length, p50: pct(ms, 0.5), p95: pct(ms, 0.95), max: ms.at(-1) ?? null, falhas: falhas.length,
    erros_5xx: lista.filter((r) => typeof r.estado === 'number' && r.estado >= 500).length,
    estados: Object.fromEntries([...new Set(falhas.map((r) => String(r.estado)))].map((e) => [e, falhas.filter((r) => String(r.estado) === e).length])) }
}

const inicio = Date.now()
const fim = inicio + SEGUNDOS * 1000
const vigia = setInterval(() => {
  const janela = reg.filter((r) => r.t > Date.now() - 15000)
  if (janela.length < 10) return
  const r = resumo(janela)
  if (r.p95 > 4000) { parar = true; motivoParagem = `p95 ${r.p95} ms nos últimos 15 s` }
  if (r.falhas / r.pedidos > 0.05) { parar = true; motivoParagem = `${r.falhas}/${r.pedidos} falhas nos últimos 15 s` }
  const s = resumo(janela.filter((x) => x.tipo === 'lupa_sugestoes'))
  process.stdout.write(`[${Math.round((Date.now() - inicio) / 1000)} s] 15 s: ${r.pedidos} pedidos (sugestões ${s.pedidos}, p95 ${s.p95} ms), p95 total ${r.p95} ms, falhas ${r.falhas}\n`)
}, 15000)

// as pessoas chegam ao longo dos primeiros 20 s
await Promise.all(Array.from({ length: PESSOAS }, async (_, i) => {
  await espera((i / PESSOAS) * 20000)
  await pessoa(fim)
}))
clearInterval(vigia)

const porTipo = {}
for (const t of new Set(reg.map((r) => r.tipo))) porTipo[t] = resumo(reg.filter((r) => r.tipo === t))
const sug = reg.filter((r) => r.tipo === 'lupa_sugestoes')
const out = {
  pessoas: PESSOAS, segundos_pedidos: SEGUNDOS, segundos_reais: Math.round((Date.now() - inicio) / 1000),
  inicio: new Date(inicio).toISOString(), parou: parar, motivo: motivoParagem,
  total: resumo(reg), sugestoes: resumo(sug),
  sugestoes_vazias: sug.filter((r) => r.n === 0).length,
  alvo_p95_sugestoes_300ms: (resumo(sug).p95 ?? 0) < 300,
  por_tipo: porTipo,
}
writeFileSync(saida, JSON.stringify(out, null, 2))
console.log(JSON.stringify(out))
