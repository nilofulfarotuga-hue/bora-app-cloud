// Agenda do Dipsy: tarefas em horário marcado. Código nosso (30/10/2026).
// O dsh só ESCREVE o pedido aqui (ferramentas agendar_tarefa, listar_agenda, cancelar_tarefa); quem executa à hora certa é a ponte do
// Telegram (ponte.py), que corre no login e responde sempre em texto e em voz. Ficheiro: ~/.dsh/agenda/agenda.json.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const AGENDA = path.join(os.homedir(), '.dsh', 'agenda', 'agenda.json')
const REPETICOES = ['uma_vez', 'todos_os_dias', 'dias_uteis']
const MAX_TAREFAS = 30

function ler() {
  try { return JSON.parse(fs.readFileSync(AGENDA, 'utf8')) } catch { return { tarefas: [] } }
}
function gravar(d) {
  fs.mkdirSync(path.dirname(AGENDA), { recursive: true })
  const tmp = AGENDA + '.tmp'
  fs.writeFileSync(tmp, JSON.stringify(d, null, 2), 'utf8')
  fs.renameSync(tmp, AGENDA)
}
function hojeLocal() {
  const d = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return { data: `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`, hora: `${p(d.getHours())}:${p(d.getMinutes())}` }
}

export function agendar({ hora, repetir, data, pedido }) {
  hora = String(hora ?? '').trim()
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(hora)) throw new Error('a hora tem de ser HH:MM (24 h), por exemplo 07:30')
  repetir = String(repetir ?? 'uma_vez')
  if (!REPETICOES.includes(repetir)) throw new Error(`repetir tem de ser um de: ${REPETICOES.join(', ')}`)
  pedido = String(pedido ?? '').trim()
  if (pedido.length < 5 || pedido.length > 2000) throw new Error('o pedido tem de ter entre 5 e 2000 letras')
  const agora = hojeLocal()
  let dia = null
  if (repetir === 'uma_vez') {
    dia = String(data ?? agora.data)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) throw new Error('a data tem de ser AAAA-MM-DD')
    if (dia < agora.data || (dia === agora.data && hora < agora.hora)) throw new Error(`essa hora já passou (agora são ${agora.hora} de ${agora.data}); diz uma data ou hora futura`)
  }
  const d = ler()
  if (d.tarefas.length >= MAX_TAREFAS) throw new Error(`já há ${MAX_TAREFAS} tarefas agendadas; cancela alguma primeiro`)
  const t = { id: 't' + Date.now().toString(36), hora, repetir, data: dia, pedido, criado: new Date().toISOString(), ultima_execucao: null }
  d.tarefas.push(t)
  gravar(d)
  return t
}

export function listar() {
  return ler().tarefas
}

export function cancelar(id) {
  const d = ler()
  const antes = d.tarefas.length
  d.tarefas = d.tarefas.filter((t) => t.id !== String(id))
  if (d.tarefas.length === antes) throw new Error(`não há tarefa ${id}`)
  gravar(d)
  return true
}

export function descrever(t) {
  const quando = t.repetir === 'uma_vez' ? `${t.data} às ${t.hora}` : `${t.repetir === 'dias_uteis' ? 'dias úteis' : 'todos os dias'} às ${t.hora}`
  return `${t.id} | ${quando} | ${t.pedido.slice(0, 120)}${t.pedido.length > 120 ? '…' : ''}`
}
