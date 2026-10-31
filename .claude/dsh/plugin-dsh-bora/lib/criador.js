// Creator Mode do Dipsy (decisão do Danilo de 31/10, "1 sim"): o Dipsy cria, testa e instala as PRÓPRIAS ferramentas
// a partir de um pedido em conversa ("faz-me uma ferramenta que...").
// Seguro por construção: uma ferramenta criada é uma RECEITA (JSON), nunca código que corre no PC. Há dois tipos:
//   consulta_sql — UM SELECT à base do Bora, corrido numa transação SÓ DE LEITURA no servidor (API do Supabase com
//                  read_only = true) e antes disso pela guarda (sqlSoLeitura + sqlRisco). Nunca escreve.
//   leitura_web  — UM GET a um endereço da lista branca da rede (sítios nossos), sem segredos no endereço.
// Ciclo: criar_ferramenta grava a receita no LAB (~/.dsh/ferramentas/lab) e TESTA-A logo (o juiz da receita: validação +
// uma execução real). Só uma receita com o teste a passar, e sem mudanças desde o teste (hash), pode ser promovida
// (promover_ferramenta) para ~/.dsh/ferramentas/ativas, que os perfis headless e web carregam no arranque seguinte como
// ferramentas fc_<nome>. No perfil lab também carregam as do lab. Tudo fica registado em ~/.dsh/ferramentas/criador.log.

import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { sqlSoLeitura, urlPermitida, temSegredo } from './guarda.js'

const BASE = path.join(os.homedir(), '.dsh', 'ferramentas')
const LAB = path.join(BASE, 'lab')
const ATIVAS = path.join(BASE, 'ativas')
const LOG = path.join(BASE, 'criador.log')
const REPO_BORA = path.join('C:', path.sep, 'BoraLocal', 'projetosflutter', 'bora_app')
const FICH_ACESSO_BD = path.join(REPO_BORA, '.supabase-token.env') // o mesmo ficheiro que o MCP do dsh usa; lido só no momento do pedido
const PROJETO = 'ojykpzwqrtusfeakzrna'
const NOME = /^[a-z][a-z0-9_]{2,39}$/
const NOME_PARAM = /^[a-z][a-z0-9_]{0,19}$/
const TIPOS = ['consulta_sql', 'leitura_web']
const TIPOS_PARAM = ['texto', 'numero', 'data']
const MAX_LINHAS = 50
const MAX_SAIDA = 4000
const MAX_RECEITAS = 40

function registar(o) {
  try {
    fs.mkdirSync(BASE, { recursive: true })
    fs.appendFileSync(LOG, JSON.stringify({ quando: new Date().toISOString(), ...o }) + '\n')
  } catch { /* o registo nunca para o trabalho */ }
}
const hash = (r) => crypto.createHash('sha256').update(JSON.stringify({ t: r.tipo, s: r.sql ?? null, u: r.url ?? null, p: r.parametros })).digest('hex').slice(0, 16)
const ler = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')) } catch { return null } }
function gravar(f, o) {
  fs.mkdirSync(path.dirname(f), { recursive: true })
  const tmp = f + '.tmp'
  fs.writeFileSync(tmp, JSON.stringify(o, null, 2))
  fs.renameSync(tmp, f)
}

// ---------- validação (o que pode e não pode ser uma ferramenta criada) ----------
export function validarReceita(r) {
  const e = (m) => { throw new Error(`Receita recusada: ${m}`) }
  if (!r || typeof r !== 'object') e('falta a receita.')
  const nome = String(r.nome ?? '').trim().toLowerCase()
  if (!NOME.test(nome)) e('o nome tem de ter 3 a 40 letras minúsculas, números ou _ (por exemplo pedidos_hoje).')
  const descricao = String(r.descricao ?? '').trim()
  if (descricao.length < 8 || descricao.length > 300) e('a descrição tem de ter entre 8 e 300 letras.')
  const tipo = String(r.tipo ?? '')
  if (!TIPOS.includes(tipo)) e(`o tipo tem de ser ${TIPOS.join(' ou ')}.`)
  const parametros = Array.isArray(r.parametros) ? r.parametros : []
  if (parametros.length > 5) e('no máximo 5 parâmetros.')
  const ps = parametros.map((p) => {
    const n = String(p?.nome ?? '').trim().toLowerCase()
    if (!NOME_PARAM.test(n)) e(`parâmetro com nome inválido: ${n || '(vazio)'}.`)
    const t = String(p?.tipo ?? 'texto')
    if (!TIPOS_PARAM.includes(t)) e(`o parâmetro ${n} tem de ser ${TIPOS_PARAM.join(', ')}.`)
    return { nome: n, tipo: t, descricao: String(p?.descricao ?? '').slice(0, 200), padrao: p?.padrao === undefined ? undefined : String(p.padrao).slice(0, 100) }
  })
  const declarados = new Set(ps.map((p) => p.nome))
  const corpo = tipo === 'consulta_sql' ? String(r.sql ?? '') : String(r.url ?? '')
  if (!corpo.trim()) e(tipo === 'consulta_sql' ? 'falta o SQL.' : 'falta o endereço (url).')
  if (corpo.length > 2000) e('o SQL ou o endereço é comprido demais (máximo 2000 letras).')
  for (const m of corpo.matchAll(/\{\{\s*([a-z0-9_]+)\s*\}\}/gi)) if (!declarados.has(m[1].toLowerCase())) e(`o marcador {{${m[1]}}} não é um parâmetro declarado.`)
  for (const s of [nome, descricao, corpo]) { const seg = temSegredo(s); if (seg) e(`tem ${seg}, e o Dipsy não mexe em segredos.`) }
  if (/(sbp_[A-Za-z0-9_-]{12,}|eyJ[A-Za-z0-9_-]{15,}|AIza[0-9A-Za-z_-]{20,}|\bsk-[A-Za-z0-9]{20,})/.test(corpo)) e('tem uma chave escrita lá dentro.')
  const receita = { nome, descricao, tipo, parametros: ps }
  if (tipo === 'consulta_sql') receita.sql = corpo.trim().replace(/;\s*$/, '')
  else receita.url = corpo.trim()
  // valida com valores de exemplo (o resultado tem de continuar a ser leitura / um sítio nosso)
  const exemplo = Object.fromEntries(ps.map((p) => [p.nome, p.padrao ?? (p.tipo === 'numero' ? '1' : p.tipo === 'data' ? '2026-01-01' : 'x')]))
  const alvo = preencher(receita, exemplo)
  if (tipo === 'consulta_sql') { const porque = sqlSoLeitura(alvo); if (porque) e(porque) } else if (!urlPermitida(alvo)) e('o endereço não está na lista dos sítios do Bora (lista branca da rede).')
  return receita
}

export function preencher(receita, valores = {}) {
  const sql = receita.tipo === 'consulta_sql'
  return (sql ? receita.sql : receita.url).replace(/\{\{\s*([a-z0-9_]+)\s*\}\}/gi, (_m, n) => {
    const p = receita.parametros.find((x) => x.nome === n.toLowerCase())
    let v = valores?.[p.nome]
    if (v === undefined || v === null || v === '') v = p.padrao
    if (v === undefined) throw new Error(`falta o valor do parâmetro ${p.nome}.`)
    v = String(v)
    if (p.tipo === 'numero' && !/^-?\d{1,12}(\.\d{1,6})?$/.test(v)) throw new Error(`${p.nome} tem de ser um número.`)
    if (p.tipo === 'data' && !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error(`${p.nome} tem de ser uma data AAAA-MM-DD.`)
    if (v.length > 100) throw new Error(`${p.nome} é comprido demais.`)
    if (!sql) return encodeURIComponent(v)
    return p.tipo === 'texto' ? `'${v.replace(/'/g, "''")}'` : (p.tipo === 'data' ? `'${v}'::date` : v)
  })
}

// ---------- execução ----------
function acessoBd() {
  const linha = fs.readFileSync(FICH_ACESSO_BD, 'utf8').split(/\r?\n/)[0]
  return linha.slice(linha.indexOf('=') + 1).trim()
}
function cortar(t) {
  const s = String(t ?? '')
  return s.length > MAX_SAIDA ? s.slice(0, MAX_SAIDA) + ` …(cortado, ${s.length} letras)` : s
}
const sinal = (signal, ms) => AbortSignal.any([signal ?? new AbortController().signal, AbortSignal.timeout(ms)])
async function correrSql(sql, signal) {
  const porque = sqlSoLeitura(sql)
  if (porque) throw new Error(`a guarda recusou o SQL: ${porque}`)
  const consulta = `select * from (\n${sql}\n) as dipsy_q limit ${MAX_LINHAS}`
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJETO}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${acessoBd()}`, 'content-type': 'application/json' },
    body: JSON.stringify({ query: consulta, read_only: true }),   // transação SÓ DE LEITURA no servidor
    signal: sinal(signal, 30000),
  })
  const t = await r.text()
  if (!r.ok) throw new Error(`a base respondeu HTTP ${r.status}: ${t.slice(0, 300)}`)
  return cortar(t)
}
async function lerWeb(url, signal) {
  let atual = url
  for (let i = 0; i < 4; i++) {
    if (!urlPermitida(atual)) throw new Error(`o endereço ${atual.slice(0, 80)} não está na lista dos sítios do Bora.`)
    const r = await fetch(atual, { redirect: 'manual', signal: sinal(signal, 20000) })
    if (r.status >= 300 && r.status < 400 && r.headers.get('location')) { atual = new URL(r.headers.get('location'), atual).toString(); continue }
    const t = await r.text()
    const limpo = /html/i.test(r.headers.get('content-type') ?? '') ? t.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ') : t
    return cortar(`HTTP ${r.status}\n${limpo}`)
  }
  throw new Error('redirecionamentos a mais.')
}
export async function executar(receita, valores, signal) {
  const alvo = preencher(receita, valores)
  return receita.tipo === 'consulta_sql' ? correrSql(alvo, signal) : lerWeb(alvo, signal)
}

// ---------- ciclo de vida ----------
const ficheiro = (onde, nome) => path.join(onde === 'ativas' ? ATIVAS : LAB, `${nome}.json`)
const receitasEm = (d) => { try { return fs.readdirSync(d).filter((f) => f.endsWith('.json') && !f.endsWith('.teste.json')) } catch { return [] } }

export async function criar(args, signal) {
  const receita = validarReceita(args)
  if (fs.existsSync(ficheiro('ativas', receita.nome))) throw new Error(`já existe uma ferramenta ativa chamada ${receita.nome}: escolhe outro nome ou apaga-a primeiro.`)
  if (!fs.existsSync(ficheiro('lab', receita.nome)) && receitasEm(LAB).length + receitasEm(ATIVAS).length >= MAX_RECEITAS) throw new Error(`já há ${MAX_RECEITAS} ferramentas criadas: apaga alguma antes.`)
  const h = hash(receita)
  gravar(ficheiro('lab', receita.nome), { ...receita, hash: h, criada_em: new Date().toISOString(), criada_por: 'dipsy' })
  const teste = { hash: h, quando: new Date().toISOString(), valores: args.valores_teste ?? {} }
  try {
    teste.amostra = (await executar(receita, args.valores_teste ?? {}, signal)).slice(0, 800)
    teste.ok = true
  } catch (e) {
    teste.ok = false
    teste.erro = String(e?.message ?? e).slice(0, 400)
  }
  gravar(path.join(LAB, `${receita.nome}.teste.json`), teste)
  registar({ acao: 'criar', nome: receita.nome, tipo: receita.tipo, hash: h, teste_ok: teste.ok, erro: teste.erro })
  if (!teste.ok) return `Criei a receita ${receita.nome} no laboratório, mas o TESTE FALHOU: ${teste.erro} Corrige a receita (chama criar_ferramenta outra vez com o mesmo nome) antes de a promover.`
  return `Ferramenta ${receita.nome} criada no laboratório e TESTADA com sucesso. Resultado do teste: ${teste.amostra}\n` +
    `Para a usar já nesta conversa: usar_ferramenta_criada com nome=${receita.nome}. Para ficar no dia a dia (Telegram e página): promover_ferramenta com nome=${receita.nome}; a partir do arranque seguinte aparece como fc_${receita.nome}.`
}

export function promover(nome) {
  const n = String(nome ?? '').trim().toLowerCase()
  const r = ler(ficheiro('lab', n))
  if (!r) throw new Error(`não há nenhuma receita ${n} no laboratório (cria-a primeiro com criar_ferramenta).`)
  const t = ler(path.join(LAB, `${n}.teste.json`))
  if (!t?.ok) throw new Error(`a receita ${n} ainda não passou no teste: não pode ser promovida.`)
  if (t.hash !== r.hash || hash(r) !== r.hash) throw new Error(`a receita ${n} mudou depois do teste: testa-a outra vez (criar_ferramenta) antes de promover.`)
  validarReceita(r)
  gravar(ficheiro('ativas', n), { ...r, promovida_em: new Date().toISOString(), teste: { quando: t.quando, hash: t.hash } })
  registar({ acao: 'promover', nome: n, hash: r.hash })
  return `Promovida: ${n} passa a existir nos perfis do dia a dia (Telegram e página) como fc_${n}, a partir do próximo pedido.`
}

export function apagar(nome) {
  const n = String(nome ?? '').trim().toLowerCase()
  if (!NOME.test(n)) throw new Error('nome inválido.')
  const retirados = []
  for (const f of [ficheiro('ativas', n), ficheiro('lab', n), path.join(LAB, `${n}.teste.json`)]) {
    if (fs.existsSync(f)) { fs.renameSync(f, f + `.retirada-${Date.now()}`); retirados.push(path.basename(f)) }
  }
  registar({ acao: 'retirar', nome: n, ficheiros: retirados })
  return retirados.length ? `Retirada a ferramenta ${n} (o ficheiro fica guardado com o sufixo .retirada).` : `Não havia nenhuma ferramenta ${n}.`
}

export function listar() {
  const linhas = []
  for (const [onde, d] of [['ativa', ATIVAS], ['laboratório', LAB]]) {
    for (const f of receitasEm(d)) {
      const r = ler(path.join(d, f))
      if (!r) continue
      const t = onde === 'laboratório' ? ler(path.join(LAB, `${r.nome}.teste.json`)) : null
      linhas.push(`${r.nome} (${onde}${t ? (t.ok ? ', teste ok' : ', teste falhou') : ''}, ${r.tipo}): ${r.descricao}`)
    }
  }
  return linhas.length ? linhas.join('\n') : 'Ainda não há ferramentas criadas pelo Dipsy.'
}

// receitas a registar como ferramentas no arranque: ativas sempre; as do lab só no perfil lab (e só com teste ok)
export function carregar(perfil) {
  const out = []
  const de = (d, soTestadas) => {
    for (const f of receitasEm(d)) {
      const r = ler(path.join(d, f))
      if (!r || hash(r) !== r.hash) continue
      try { validarReceita(r) } catch { continue }
      if (soTestadas && !ler(path.join(LAB, `${r.nome}.teste.json`))?.ok) continue
      if (!out.some((x) => x.nome === r.nome)) out.push(r)
    }
  }
  de(ATIVAS, false)
  if (perfil === 'lab') de(LAB, true)
  return out
}

export async function usar(nome, valores, signal) {
  const n = String(nome ?? '').trim().toLowerCase()
  let r = ler(ficheiro('ativas', n))
  if (!r) {
    r = ler(ficheiro('lab', n))
    if (!r) throw new Error(`não há nenhuma ferramenta criada chamada ${n} (vê listar_ferramentas_criadas).`)
    if (!ler(path.join(LAB, `${n}.teste.json`))?.ok) throw new Error(`a ferramenta ${n} ainda não passou no teste.`)
  }
  if (hash(r) !== r.hash) throw new Error(`a receita ${n} foi mexida à mão e já não bate com o teste: não corre.`)
  validarReceita(r)
  const res = await executar(r, valores ?? {}, signal)
  registar({ acao: 'usar', nome: n })
  return res
}

export function perfilAtual(argv = process.argv) {
  const i = argv.indexOf('--profile')
  if (i >= 0 && argv[i + 1]) return argv[i + 1]
  const p = argv.slice(2).find((a) => ['lab', 'headless', 'web', 'tui'].includes(a))
  return p ?? process.env.DSH_PROFILE ?? 'headless'
}
