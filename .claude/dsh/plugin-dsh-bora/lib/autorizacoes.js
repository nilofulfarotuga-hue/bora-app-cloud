// Autorizações do Danilo, uma a uma (missão m3-dipsy-acesso-total-2026-11-08).
// A guarda do dsh é síncrona (não pode esperar): quando uma ação precisa do "sim", a guarda cria aqui o PEDIDO e barra a
// chamada; a ponte do Telegram pergunta ao Danilo (operação, valor, destino, o exato); a ferramenta esperar_autorizacao
// espera a resposta; com "sim", a MESMA chamada repetida passa UMA vez, nos 10 minutos seguintes. Nunca autorização geral.
//
// Ficheiros em ~/.dsh/aprovacoes/ (um escritor por ficheiro, para não haver corridas):
//   <id>.pedido.json      — a guarda (criação)          <id>.explicacao.txt — esperar_autorizacao (o porquê, em português)
//   <id>.enviado.json     — a ponte (pergunta enviada)  <id>.resposta.json  — a ponte (sim/não/expirado, ASSINADO)
//   <id>.usado.json       — a guarda (o sim foi gasto)
// A assinatura (HMAC com ~/.dsh/secrets/aprovacoes.key, que o Dipsy não lê pelas ferramentas) impede um "sim" forjado.

import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { descreverAcao } from './guarda.js'

export const PASTA = process.env.DIPSY_APROVACOES || path.join(os.homedir(), '.dsh', 'aprovacoes')
const CHAVE_FICH = process.env.DIPSY_CHAVE_APROVACOES || path.join(os.homedir(), '.dsh', 'secrets', 'aprovacoes.key')
const MIN = 60 * 1000
export const PRAZO_RESPOSTA_MS = 10 * MIN      // o Danilo tem 10 min para responder
export const PRAZO_USO_MS = 10 * MIN           // e o Dipsy tem 10 min, depois do sim, para fazer
const NAO_REPERGUNTAR_MS = 60 * MIN            // depois de um "não", a mesma ação não se volta a perguntar durante 1 h
const MAX_POR_ACAO_DIA = 3
const MAX_PENDENTES = 6

function lerJson(f) {
  try { return JSON.parse(fs.readFileSync(f, 'utf8')) } catch { return null }
}
function gravarJson(f, o) {
  fs.mkdirSync(path.dirname(f), { recursive: true })
  const tmp = `${f}.${process.pid}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(o, null, 1))
  fs.renameSync(tmp, f)
}
function estavel(v) {
  if (typeof v === 'string') return v.replace(/\s+/g, ' ').trim()
  if (Array.isArray(v)) return v.map(estavel)
  if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map((k) => [k, estavel(v[k])]))
  return v
}
export function chaveDe(nome, args) {
  return crypto.createHash('sha256').update(`${nome}\n${JSON.stringify(estavel(args ?? {}))}`).digest('hex')
}
function chaveSecreta() {
  try {
    const k = fs.readFileSync(CHAVE_FICH, 'utf8').trim()
    return k.length >= 32 ? k : null
  } catch { return null }
}
export function textoAssinado(p, resp) {
  return `aprovacao|${p.id}|${p.chave}|${resp.estado}|${resp.respondido_em}`
}
export function assinaturaOk(p, resp) {
  const k = chaveSecreta()
  if (!k || !resp?.assinatura) return false
  const esperado = crypto.createHmac('sha256', Buffer.from(k, 'utf8')).update(textoAssinado(p, resp)).digest('hex')
  try { return crypto.timingSafeEqual(Buffer.from(esperado), Buffer.from(String(resp.assinatura))) } catch { return false }
}
export function pedidos() {
  let nomes = []
  try { nomes = fs.readdirSync(PASTA).filter((n) => n.endsWith('.pedido.json')) } catch { return [] }
  return nomes.map((n) => lerJson(path.join(PASTA, n))).filter((p) => p && p.id && p.chave)
}
const f = (id, ext) => path.join(PASTA, `${id}.${ext}`)

function criar(nome, args, res, chave) {
  const agora = Date.now() / 1000
  const id = (res.rede ? 'r' : 'a') + crypto.createHash('sha256').update(`${chave}|${agora}|${Math.random()}`).digest('hex').slice(0, 7)
  const d = descreverAcao(nome, args, res)
  const host = res.rede ? (res.dominios ?? [])[0] : null
  const p = {
    id, tipo: res.rede ? 'rede' : 'acao', chave, criado: agora, expira: agora + PRAZO_RESPOSTA_MS / 1000 + 30, origem: 'guarda',
    ferramenta: nome, regra: res.regra, porque: res.porque, dominios: res.dominios ?? [],
    operacao: res.rede ? `Abrir o sítio ${host}` : d.operacao, valor: d.valor, destino: d.destino, detalhe: d.detalhe,
  }
  gravarJson(f(id, 'pedido.json'), p)
  return p
}

function msgPerguntado(p) {
  const depois = p.tipo === 'rede'
    ? 'Se for SIM, o sítio fica aberto (fica na lista) e podes repetir o pedido.'
    : 'Se for SIM, repete EXATAMENTE a mesma chamada, uma vez só, nos 10 minutos seguintes.'
  return `PERGUNTEI ao Danilo pelo Telegram (pedido ${p.id}): ${p.operacao}. Ainda NÃO foi feito. Agora chama a ferramenta ` +
    `esperar_autorizacao com id "${p.id}" e uma explicação curta, em português simples, do que queres fazer e porquê ` +
    `(por exemplo: "Marcar o pedido 56fa… como entregue, motivo: o Divan confirmou por telefone"). ${depois} ` +
    'Se for NÃO ou não houver resposta em 10 minutos, NÃO faças, não contornes, e segue com o resto do trabalho.'
}

// Decide uma chamada que precisa do "sim". Devolve { passa: true, id } ou { estado, mensagem, id }.
export function decidir(nome, args, res) {
  const chave = res.rede ? `rede:${String((res.dominios ?? [])[0] ?? '').toLowerCase()}` : chaveDe(nome, args)
  const agora = Date.now()
  const meus = pedidos().filter((p) => p.chave === chave).sort((a, b) => b.criado - a.criado)
  const p = meus[0]
  if (p) {
    const resp = lerJson(f(p.id, 'resposta.json'))
    const usado = fs.existsSync(f(p.id, 'usado.json'))
    if (resp && resp.estado === 'sim' && !usado && p.tipo !== 'rede') {
      if (!assinaturaOk(p, resp)) return { estado: 'assinatura-ma', id: p.id, mensagem: `BLOQUEADO: a resposta do pedido ${p.id} não tem a assinatura certa da ponte do Telegram (não foi o Danilo). Não faças e diz-lhe.` }
      if (agora - Date.parse(resp.respondido_em) <= PRAZO_USO_MS) {
        gravarJson(f(p.id, 'usado.json'), { quando: new Date().toISOString(), ferramenta: nome })
        return { passa: true, id: p.id }
      }
    }
    if (!resp && !usado && agora < p.expira * 1000) {
      return { estado: 'a-espera', id: p.id, mensagem: `Já perguntei ao Danilo (pedido ${p.id}) e ainda não respondeu. Chama esperar_autorizacao com id "${p.id}". Não repitas a ação antes do sim.` }
    }
    if (resp && resp.estado === 'nao' && agora - Date.parse(resp.respondido_em) < NAO_REPERGUNTAR_MS) {
      return { estado: 'nao', id: p.id, mensagem: `O Danilo disse NÃO a esta ação (pedido ${p.id}). Não a faças nem contornes; segue com o resto e conta-lhe no fim.` }
    }
  }
  if (meus.filter((x) => agora - x.criado * 1000 < 24 * 60 * MIN).length >= MAX_POR_ACAO_DIA) {
    return { estado: 'limite', mensagem: `Já perguntei ${MAX_POR_ACAO_DIA} vezes hoje ao Danilo por esta mesma ação. Não faças; diz-lhe no fim o que querias fazer.` }
  }
  const pend = pedidos().filter((x) => !fs.existsSync(f(x.id, 'resposta.json')) && agora < x.expira * 1000)
  if (pend.length >= MAX_PENDENTES) {
    return { estado: 'muitos', mensagem: `Há ${pend.length} perguntas ao Danilo ainda sem resposta. Espera por elas (esperar_autorizacao) antes de pedir mais.` }
  }
  const novo = criar(nome, args, res, chave)
  return { estado: 'perguntado', id: novo.id, mensagem: msgPerguntado(novo) }
}

const dorme = (ms, signal) => new Promise((ok) => {
  const t = setTimeout(ok, ms)
  signal?.addEventListener?.('abort', () => { clearTimeout(t); ok() }, { once: true })
})

// A ferramenta esperar_autorizacao: guarda a explicação (a ponte junta-a à pergunta) e espera a resposta.
export async function esperar(id, explicacao, signal) {
  const limpo = String(id ?? '').trim()
  if (!/^[ar][0-9a-f]{7}$/.test(limpo)) return `Não conheço o pedido "${limpo}". Usa o id que a guarda te deu (por exemplo a1b2c3d4).`
  const p = lerJson(f(limpo, 'pedido.json'))
  if (!p) return `Não encontrei o pedido ${limpo}.`
  if (explicacao && !fs.existsSync(f(limpo, 'explicacao.txt'))) {
    try { fs.writeFileSync(f(limpo, 'explicacao.txt'), String(explicacao).slice(0, 600)) } catch { /* a pergunta sai na mesma */ }
  }
  const fim = p.expira * 1000 + 15000
  while (Date.now() < fim && !signal?.aborted) {
    const resp = lerJson(f(limpo, 'resposta.json'))
    if (resp?.estado === 'sim') {
      return p.tipo === 'rede'
        ? `SIM: o Danilo deixou abrir ${p.dominios?.[0]} (fica na lista). Podes repetir o pedido.`
        : `SIM: o Danilo autorizou (pedido ${limpo}). Repete AGORA EXATAMENTE a mesma chamada, uma vez só. Depois diz-lhe o resultado.`
    }
    if (resp?.estado === 'nao') return `NÃO: o Danilo não autorizou (pedido ${limpo}). Não faças, não contornes; segue com o resto.`
    if (resp?.estado === 'expirado') break
    await dorme(2000, signal)
  }
  if (signal?.aborted) return 'Paraste de esperar (pedido cancelado). Não faças a ação.'
  return `SEM RESPOSTA: o Danilo não respondeu em 10 minutos ao pedido ${limpo}. Não faças; segue com o resto e diz-lhe no fim o que ficou por autorizar.`
}
