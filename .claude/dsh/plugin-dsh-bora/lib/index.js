// dsh-bora: plugin do Dipsy (dsh) do Bora. Olhos (captura_ecra, ver_imagem) + a guarda de comandos.
// Código nosso, missão C-liga (30/10/2026). Sem dependências de terceiros: só o que o próprio dsh já traz.

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { defineTool } from '@deepseek-ai/dsh-tools'
import { avaliar, mensagem, FERRAMENTAS_DE_RISCO } from './guarda.js'
import { capturarEcra, verImagem } from './olhos.js'

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
