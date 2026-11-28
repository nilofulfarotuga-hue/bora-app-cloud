// Teste de carga da missão servidor-busca-leve-2026-11-17 (B3).
// Simula N pessoas SEM login (chave pública da app) durante S segundos, com o comportamento da app
// NOVA (PR #33): a lupa só pergunta quando a pessoa pára 400 ms, a mesma pesquisa em 5 min vem da
// memória, o menu só pesquisa produtos com 3+ letras. Cada pessoa: abre a página inicial, escreve
// na lupa da página inicial (cliente_pesquisar), abre lojas (1.ª página de produtos) e pesquisa
// dentro delas (search_products), abre o Continente (2 páginas). NUNCA cria pedidos nem escreve nada.
// O carrinho sem sessão fica só no telemóvel (cart_store não pergunta ao servidor sem sessão).
//
// Travão: de 15 em 15 s, se o p95 passar 4 s ou mais de 5% dos pedidos falharem, PÁRA.
// Uso: BORA_ANON=<chave pública anon> node busca_leve_carga.mjs <pessoas> <segundos> <saida.json>
import { readFileSync, writeFileSync } from 'node:fs'

const BASE = 'https://ojykpzwqrtusfeakzrna.supabase.co'
const CHAVE = process.env.BORA_ANON
if (!CHAVE) throw new Error('falta BORA_ANON (chave pública anon da app)')
const [, , nTxt = '10', sTxt = '180', saida = 'carga.json'] = process.argv
const PESSOAS = Number(nTxt)
const SEGUNDOS = Number(sTxt)
const H = { apikey: CHAVE, Authorization: `Bearer ${CHAVE}`, 'Content-Type': 'application/json' }

const aqui = new URL('.', import.meta.url)
const palavras = readFileSync(new URL('../../docs/propostas/busca-leve-2026-11-17/consultas_teste.txt', aqui), 'utf8')
  .split('\n').map((s) => s.trim()).filter((s) => s.length >= 3)
// as 5 lojas com mais produtos disponíveis (lido a 17/11: 19997, 8568, 5737, 5006, 1628)
const LOJAS = ['continente-guarda', 'auchan-guarda', 'intermarche-guarda', 'pingodoce-guarda', 'a3-guarda']

const sorte = (a) => a[Math.floor(Math.random() * a.length)]
const espera = (ms) => new Promise((r) => setTimeout(r, ms))
const entre = (a, b) => a + Math.random() * (b - a)

const reg = [] // {t, tipo, ms, estado}
let parar = false
let motivoParagem = null

async function pedir(tipo, url, init = {}) {
  const t0 = Date.now()
  let estado = 0
  try {
    const r = await fetch(url, { ...init, headers: H, signal: AbortSignal.timeout(20000) })
    estado = r.status
    await r.arrayBuffer() // lê a resposta toda, como a app
  } catch (e) {
    estado = e?.name === 'TimeoutError' ? 'timeout' : 'rede'
  }
  reg.push({ t: Date.now(), tipo, ms: Date.now() - t0, estado })
}

const rpc = (nome, corpo) => pedir(nome, `${BASE}/rest/v1/rpc/${nome}`, { method: 'POST', body: JSON.stringify(corpo) })

async function escrever(texto, memoria, chave, aoParar) {
  // letra a letra (120-250 ms por letra); com 3+ letras, 15% das vezes pára 500 ms a meio (sai pedido)
  for (let i = 1; i <= texto.length && !parar; i++) {
    await espera(entre(120, 250))
    if (i >= 3 && i < texto.length && Math.random() < 0.15) {
      await espera(500)
      const parcial = texto.slice(0, i)
      if (!memoria.has(chave(parcial))) { memoria.add(chave(parcial)); await aoParar(parcial) }
    }
  }
  await espera(400) // a pessoa parou: a lupa pergunta (se não estiver na memória)
  if (!parar && !memoria.has(chave(texto))) { memoria.add(chave(texto)); await aoParar(texto) }
}

async function pessoa(fim) {
  const memoria = new Set() // memória de 5 min do telemóvel (o teste dura menos)
  await pedir('pagina_inicial', `${BASE}/rest/v1/restaurants?select=*&is_active_admin=eq.true&approval_status=eq.approved`)
  while (Date.now() < fim && !parar) {
    const x = Math.random()
    if (x < 0.5) {
      const p = sorte(palavras)
      await escrever(p, memoria, (t) => `*|${t}`, (t) => rpc('cliente_pesquisar', { p_q: t, p_limit: 30 }))
    } else if (x < 0.75) {
      const loja = sorte(LOJAS)
      await pedir('loja_pagina1', `${BASE}/rest/v1/products?select=id,name,price,photo_url,category,category_root,sort_order&restaurant_id=eq.${loja}&is_available=eq.true&order=sort_order.asc.nullslast,id.asc&limit=1000`)
      const p = sorte(palavras)
      await escrever(p, memoria, (t) => `${loja}|${t}`, (t) => rpc('search_products', { query_text: t, p_restaurant_id: loja, max_results: 50 }))
    } else if (x < 0.9) {
      for (const off of [0, 1000]) {
        await pedir('continente_pagina', `${BASE}/rest/v1/products?select=id,name,price,photo_url,category,category_root,sort_order&restaurant_id=eq.continente-guarda&is_available=eq.true&order=sort_order.asc.nullslast,id.asc&limit=1000&offset=${off}`)
      }
    }
    await espera(entre(4000, 10000)) // a pessoa olha para o ecrã
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
  process.stdout.write(`[${Math.round((Date.now() - inicio) / 1000)} s] 15 s: ${r.pedidos} pedidos, p95 ${r.p95} ms, falhas ${r.falhas}\n`)
}, 15000)

// as pessoas chegam ao longo dos primeiros 20 s, como na vida real
await Promise.all(Array.from({ length: PESSOAS }, async (_, i) => {
  await espera((i / PESSOAS) * 20000)
  await pessoa(fim)
}))
clearInterval(vigia)

const porTipo = {}
for (const t of new Set(reg.map((r) => r.tipo))) porTipo[t] = resumo(reg.filter((r) => r.tipo === t))
const out = {
  pessoas: PESSOAS, segundos_pedidos: SEGUNDOS, segundos_reais: Math.round((Date.now() - inicio) / 1000),
  inicio: new Date(inicio).toISOString(), parou: parar, motivo: motivoParagem,
  total: resumo(reg), pesquisas: resumo(reg.filter((r) => ['cliente_pesquisar', 'search_products'].includes(r.tipo))),
  por_tipo: porTipo,
}
writeFileSync(saida, JSON.stringify(out, null, 2))
console.log(JSON.stringify(out))
