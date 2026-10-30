// dsh-bora: plugin do Dipsy (dsh) do Bora. Olhos (captura_ecra, ver_imagem) + a guarda de comandos.
// Código nosso, missão C-liga (30/10/2026). Sem dependências de terceiros: só o que o próprio dsh já traz.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { defineTool } from '@deepseek-ai/dsh-tools'
import { avaliar, mensagem, FERRAMENTAS_DE_RISCO } from './guarda.js'
import { capturarEcra, verImagem } from './olhos.js'
import { agendar, listar, cancelar, descrever } from './agenda.js'
import { passarAoClaudeCode } from './claude.js'
import * as mem from './memoria.js'

export const name = 'dsh-bora'
export const inject = ['tools', 'systemPrompt']

const LOG = path.join(os.homedir(), '.dsh', 'guarda.log')
const TEXTO = {
  schema: { type: 'string' },
  render: (_args, value) => [{ type: 'text', text: value }],
}

const PROMPT = [
  'Tens olhos: captura_ecra tira uma fotografia do ecrã do PC (devolve o caminho do PNG) e ver_imagem descreve uma imagem',
  '(origem = "ecra" para o ecrã agora, ou o caminho de um ficheiro de imagem). A imagem sai do PC para a Google (plano grátis,',
  'que pode guardar): só a uses quando a tarefa precisar de ver o ecrã e nunca com janelas de banco, palavras-passe ou chaves.',
  'Há uma guarda antes de cada comando. Se ela barrar algo, não contornes: diz ao Danilo e continua com o resto.',
  'Todo o commit passa pelo Juiz: usa o script C:\\Users\\danil\\.dsh\\dsh-commit.ps1 (nunca git commit à mão) e nunca git push.',
  'Podes agendar tarefas para uma hora marcada com agendar_tarefa (listar_agenda e cancelar_tarefa também existem): a ponte do',
  'Telegram executa-as sozinha e manda o resultado ao Danilo em texto e em voz.',
].join(' ')

function redigir(s) {
  return String(s ?? '').replace(/[A-Za-z0-9_\-]{28,}/g, '[…]').replace(/\s+/g, ' ').slice(0, 140)
}
function registar(nomeFerramenta, r, args) {
  try {
    const amostra = typeof args?.command === 'string' ? args.command : typeof args?.query === 'string' ? args.query : (args?.file_path ?? args?.path ?? args?.origem ?? '')
    fs.mkdirSync(path.dirname(LOG), { recursive: true })
    fs.appendFileSync(LOG, JSON.stringify({ quando: new Date().toISOString(), ferramenta: nomeFerramenta, regra: r.regra, trecho: redigir(amostra) }) + '\n')
  } catch { /* o registo nunca pode parar a guarda */ }
}

export function apply(ctx) {
  ctx.systemPrompt.section({ name: 'bora:dipsy', order: 116, text: PROMPT })

  ctx.tools.register(defineTool({
    name: 'captura_ecra',
    description: 'Tira uma captura do ecrã inteiro do PC (todos os monitores) e devolve o caminho do ficheiro PNG. Não envia nada a ninguém.',
    parameters: {},
    output: TEXTO,
    execute: async (_args, exec) => capturarEcra(exec.signal),
  }))

  ctx.tools.register(defineTool({
    name: 'ver_imagem',
    description: 'Descreve uma imagem com o Gemini (envia a imagem à Google, plano grátis). origem = "ecra" para captar e descrever o ecrã agora, ou o caminho de um ficheiro de imagem (png, jpg, webp, gif, bmp, até 8 MB). pergunta opcional: o que queres saber da imagem.',
    parameters: {
      origem: { type: 'string', required: true, description: '"ecra" para o ecrã agora, ou o caminho completo de uma imagem.' },
      pergunta: { type: 'string', description: 'O que queres saber da imagem (opcional; por omissão descreve tudo o que se vê).' },
    },
    output: TEXTO,
    execute: async (args, exec) => verImagem(args.origem, args.pergunta, exec.signal),
  }))

  ctx.tools.register(defineTool({
    name: 'agendar_tarefa',
    description: 'Agenda uma tarefa para o Dipsy fazer sozinho a uma hora marcada. A ponte do Telegram executa-a à hora certa e manda o resultado ao Danilo em texto e em voz. hora = HH:MM (24 h, hora de Lisboa). repetir = uma_vez (precisa de data AAAA-MM-DD, por omissão hoje), todos_os_dias ou dias_uteis. pedido = o que fazer, escrito como se o Danilo o pedisse. Só funciona com o PC ligado.',
    parameters: {
      hora: { type: 'string', required: true, description: 'HH:MM, 24 h.' },
      repetir: { type: 'string', enum: ['uma_vez', 'todos_os_dias', 'dias_uteis'], description: 'Por omissão uma_vez.' },
      data: { type: 'string', description: 'AAAA-MM-DD, só para uma_vez; por omissão hoje.' },
      pedido: { type: 'string', required: true, description: 'O que o Dipsy deve fazer à hora marcada.' },
    },
    output: TEXTO,
    execute: async (args) => `Agendado: ${descrever(agendar({ hora: args.hora, repetir: args.repetir, data: args.data, pedido: args.pedido }))}`,
  }))

  ctx.tools.register(defineTool({
    name: 'listar_agenda',
    description: 'Lista as tarefas agendadas do Dipsy (id | quando | pedido).',
    parameters: {},
    output: TEXTO,
    execute: async () => { const l = listar(); return l.length ? l.map(descrever).join('\n') : 'Não há tarefas agendadas.' },
  }))

  ctx.tools.register(defineTool({
    name: 'cancelar_tarefa',
    description: 'Cancela uma tarefa agendada pelo id (ver listar_agenda).',
    parameters: { id: { type: 'string', required: true, description: 'O id da tarefa, por exemplo t1abc.' } },
    output: TEXTO,
    execute: async (args) => { cancelar(args.id); return `Cancelada a tarefa ${args.id}.` },
  }))

  const resumoMemoria = mem.resumoParaPrompt()
  if (resumoMemoria) ctx.systemPrompt.section({ name: 'bora:memoria', order: 117, text: resumoMemoria })

  ctx.tools.register(defineTool({
    name: 'memorizar',
    description: 'Guarda uma memória própria do Dipsy que sobrevive entre sessões (preferências do Danilo, decisões, lições). Uma ideia por memória, escrita para a leres daqui a semanas. Nunca segredos, chaves ou dados de clientes sem necessidade. fixar = true para o que deve estar sempre à vista no arranque.',
    parameters: {
      texto: { type: 'string', required: true, description: 'A memória, 8 a 1000 letras, em português.' },
      etiquetas: { type: 'array', items: { type: 'string' }, description: 'Até 8 palavras-chave (opcional).' },
      fixar: { type: 'boolean', description: 'Memória fixa, sempre no prompt do arranque.' },
    },
    output: TEXTO,
    execute: async (args) => { const e = mem.memorizar(args); return `${e.repetida ? 'Já existia' : 'Memorizado'}: ${mem.descrever(e)}` },
  }))

  ctx.tools.register(defineTool({
    name: 'lembrar',
    description: 'Procura nas memórias próprias do Dipsy (de sessões anteriores). consulta = palavras a procurar (sem consulta, devolve as mais recentes). limite = quantas (por omissão 10).',
    parameters: {
      consulta: { type: 'string', description: 'Palavras a procurar.' },
      limite: { type: 'number', description: 'Máximo de resultados (1 a 30).' },
    },
    output: TEXTO,
    execute: async (args) => { const r = mem.lembrar(args); return r.length ? r.map(mem.descrever).join('\n') : 'Não encontrei nada na memória.' },
  }))

  ctx.tools.register(defineTool({
    name: 'esquecer',
    description: 'Apaga UMA memória própria do Dipsy pelo id (ver lembrar). Só se estiver errada ou o Danilo pedir.',
    parameters: { id: { type: 'string', required: true, description: 'O id da memória, por exemplo m1abc.' } },
    output: TEXTO,
    execute: async (args) => { mem.esquecer(args.id); return `Esquecida a memória ${args.id}.` },
  }))

  ctx.tools.register(defineTool({
    name: 'passar_ao_claude_code',
    description: 'Passa trabalho difícil ao Claude Code (o CLI oficial do Danilo, modo -p). modo so_ler (por omissão): só lê e responde, para diagnosticar ou rever. modo editar: pode editar ficheiros, sem comandos de escrita e sem push; sem pasta, trabalha numa cópia nova do repo do Bora (ramo dsh-delegado-<id>). modelo: sonnet (por omissão), opus (dinheiro, preços, dispatch, RLS, zonas protegidas) ou haiku. Demora minutos e gasta o plano do Danilo: usa só quando o trabalho for difícil ou delicado. Dinheiro e publicação continuam a precisar do "autorizo" do Danilo.',
    parameters: {
      pedido: { type: 'string', required: true, description: 'O trabalho a fazer, com todo o contexto necessário (o Claude Code não vê esta conversa).' },
      modo: { type: 'string', enum: ['so_ler', 'editar'], description: 'Por omissão so_ler.' },
      pasta: { type: 'string', description: 'Pasta dentro de C:\\BoraLocal onde trabalhar (por omissão o repo do Bora).' },
      modelo: { type: 'string', enum: ['sonnet', 'opus', 'haiku'], description: 'Por omissão sonnet.' },
    },
    output: TEXTO,
    execute: async (args, exec) => passarAoClaudeCode(args, exec.signal),
  }))

  ctx.tools.guard((execucao) => {
    try {
      const r = avaliar(execucao.name, execucao.arguments)
      if (!r) return undefined
      registar(execucao.name, r, execucao.arguments)
      return mensagem(r)
    } catch (e) {
      if (FERRAMENTAS_DE_RISCO.has(execucao.name) || String(execucao.name).startsWith('mcp__supabase__')) {
        registar(execucao.name, { regra: 'erro-interno' }, {})
        return 'BLOQUEADO pela guarda do Dipsy (regra erro-interno): a guarda não conseguiu avaliar esta chamada, por isso não corre. Diz ao Danilo.'
      }
      return undefined
    }
  })
}
