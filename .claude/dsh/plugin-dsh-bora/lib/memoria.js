// Memória própria do Dipsy entre sessões. Código nosso (30/10/2026), sem plugins de terceiros.
// Ficheiro: ~/.dsh/memoria/memoria.jsonl (uma linha JSON por memória). Ferramentas: memorizar, lembrar, esquecer.
// No arranque de cada sessão, as memórias fixadas e as mais recentes entram no prompt do Dipsy (secção "Memória do Dipsy").
// Regras: nunca segredos nem chaves (recusa-se à entrada), no máximo 500 memórias de 1000 letras, dados pessoais de clientes só
// se a tarefa precisar (as mesmas regras de ~/.agents/AGENTS.md). O Córtex e o livro continuam a ser a memória do negócio.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const FICHEIRO = path.join(os.homedir(), '.dsh', 'memoria', 'memoria.jsonl')
const MAX = 500
const SEGREDO = /(sbp_[A-Za-z0-9_-]{12,}|eyJ[A-Za-z0-9_-]{15,}|AIza[0-9A-Za-z_-]{20,}|\bsk-[A-Za-z0-9]{20,}|\b\d{8,10}:[A-Za-z0-9_-]{30,}|-----BEGIN|gh[pous]_[A-Za-z0-9]{20,}|(refresh_token|client_secret|password)\s*[:=]\s*\S{8,})/i

function ler() {
  try {
    return fs.readFileSync(FICHEIRO, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
  } catch { return [] }
}
function gravar(lista) {
  fs.mkdirSync(path.dirname(FICHEIRO), { recursive: true })
  const tmp = FICHEIRO + '.tmp'
  fs.writeFileSync(tmp, lista.map((x) => JSON.stringify(x)).join('\n') + (lista.length ? '\n' : ''), 'utf8')
  fs.renameSync(tmp, FICHEIRO)
}
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

export function memorizar({ texto, etiquetas, fixar }) {
  texto = String(texto ?? '').trim()
  if (texto.length < 8 || texto.length > 1000) throw new Error('a memória tem de ter entre 8 e 1000 letras')
  if (SEGREDO.test(texto)) throw new Error('isto parece um segredo ou uma chave: nunca se memoriza')
  const lista = ler()
  if (lista.length >= MAX) throw new Error(`já há ${MAX} memórias; esquece algumas primeiro`)
  const dup = lista.find((x) => norm(x.texto) === norm(texto))
  if (dup) return { ...dup, repetida: true }
  const e = {
    id: 'm' + Date.now().toString(36) + Math.floor(Math.random() * 36 ** 2).toString(36),
    quando: new Date().toISOString(),
    texto,
    etiquetas: (Array.isArray(etiquetas) ? etiquetas : []).map((t) => String(t).slice(0, 30)).slice(0, 8),
    fixar: Boolean(fixar),
  }
  lista.push(e)
  gravar(lista)
  return e
}

export function lembrar({ consulta, limite } = {}) {
  const lista = ler()
  const n = Math.min(Math.max(Number(limite) || 10, 1), 30)
  const palavras = norm(consulta).split(/\s+/).filter((p) => p.length > 2)
  const certas = palavras.length
    ? lista.filter((x) => { const t = norm(x.texto + ' ' + (x.etiquetas ?? []).join(' ')); return palavras.some((p) => t.includes(p)) })
    : lista
  return certas.slice(-n).reverse()
}

export function esquecer(id) {
  const lista = ler()
  const resto = lista.filter((x) => x.id !== String(id))
  if (resto.length === lista.length) throw new Error(`não há memória ${id}`)
  gravar(resto)
  return true
}

export function descrever(x) {
  return `${x.id} | ${String(x.quando).slice(0, 10)} | ${x.fixar ? '[fixa] ' : ''}${x.texto}${x.etiquetas?.length ? ' #' + x.etiquetas.join(' #') : ''}`
}

export function resumoParaPrompt() {
  const lista = ler()
  if (!lista.length) return ''
  const fixas = lista.filter((x) => x.fixar)
  const recentes = lista.filter((x) => !x.fixar).slice(-8)
  const linhas = [...fixas, ...recentes].slice(0, 14).map((x) => `- ${x.texto.slice(0, 180)}`)
  return `Memória do Dipsy (o que já aprendeste, de sessões anteriores; usa a ferramenta lembrar para ver mais):\n${linhas.join('\n')}`
}
