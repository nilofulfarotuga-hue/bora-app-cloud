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
import * as criador from './criador.js'
import { libertarMemoria } from './ram.js'

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
  'CREATOR MODE: quando o Danilo pedir "faz-me/cria uma ferramenta que...", cria-a tu com criar_ferramenta (uma receita:',
  'consulta_sql = um SELECT só de leitura à base do Bora; leitura_web = um GET a um sítio nosso). Ela nasce no laboratório e é',
  'testada logo; se o teste passar, promove-a com promover_ferramenta, usa-a com usar_ferramenta_criada para responder ao',
  'pedido, e explica ao Danilo numa frase o que criaste. Se o teste falhar, corrige a receita. listar_ferramentas_criadas',
  'mostra as que existem; as promovidas aparecem como fc_<nome> nos pedidos seguintes.',
  'Se o Danilo pedir para libertar memória do PC (o PC está lento ou sem memória), usa libertar_memoria.',
  'A rede tem uma lista branca: só sítios do Bora (boraguarda.com, o nosso Supabase, o Córtex, o nosso GitHub). Outros sítios',
  'são barrados pela guarda; para pesquisar na internet, passa ao Claude Code.',
].join(' ')

const PROMPT_PLANEAR = [
  'MODO PLANEAR (o Danilo mandou /planear): agora NÃO mudes nada. Lê, procura e investiga o que precisares (ficheiros, SELECT,',
  'Córtex) e devolve UM plano numerado, curto, em português simples: o que vais fazer, por que ordem, que ficheiros ou tabelas',
  'tocas, o que pode correr mal, e como provas que ficou feito. A guarda barra qualquer escrita neste modo. Acaba com a frase:',
  '"Se aprovares, manda /aprovar; para mudar o plano, manda /corrigir e o que queres diferente."',
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

function lerValores(v) {
  if (v && typeof v === 'object') return v
  const s = String(v ?? '').trim()
  if (!s) return {}
  try { const o = JSON.parse(s); return o && typeof o === 'object' ? o : {} } catch { throw new Error('valores tem de ser JSON, por exemplo {"dia":"2026-10-31"}.') }
}
const erroEmTexto = (f) => async (...a) => { try { return await f(...a) } catch (e) { return `Não deu: ${String(e?.message ?? e)}` } }

export function apply(ctx) {
  const MODO = String(process.env.DIPSY_MODO ?? '').toLowerCase()
  ctx.systemPrompt.section({ name: 'bora:dipsy', order: 116, text: PROMPT })
  if (MODO === 'planear') ctx.systemPrompt.section({ name: 'bora:planear', order: 118, text: PROMPT_PLANEAR })

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

  // ---------- Creator Mode (31/10): o Dipsy cria, testa e promove as próprias ferramentas (receitas, não código) ----------
  ctx.tools.register(defineTool({
    name: 'criar_ferramenta',
    description: 'CREATOR MODE: cria uma ferramenta nova do Dipsy a partir de um pedido do Danilo. É uma receita, não código: tipo consulta_sql (UM SELECT só de leitura à base do Bora; corre numa transação só de leitura) ou leitura_web (UM GET a um sítio nosso da lista branca). Parâmetros opcionais entram no SQL ou no endereço como {{nome}}. Nasce no laboratório e é TESTADA logo (devolve o resultado do teste). Exemplo: nome pedidos_hoje, tipo consulta_sql, sql: select count(*) as pedidos from public.orders where (created_at at time zone \'Europe/Lisbon\')::date = (now() at time zone \'Europe/Lisbon\')::date',
    parameters: {
      nome: { type: 'string', required: true, description: '3 a 40 letras minúsculas, números ou _ (ex.: pedidos_hoje).' },
      descricao: { type: 'string', required: true, description: 'O que a ferramenta faz, numa frase (8 a 300 letras).' },
      tipo: { type: 'string', enum: ['consulta_sql', 'leitura_web'], required: true, description: 'consulta_sql ou leitura_web.' },
      sql: { type: 'string', description: 'Para consulta_sql: UM SELECT (ou WITH ... SELECT), sem ponto e vírgula no meio.' },
      url: { type: 'string', description: 'Para leitura_web: endereço https de um sítio nosso.' },
      parametros: {
        type: 'array',
        description: 'Até 5 parâmetros (opcional).',
        items: {
          type: 'object',
          properties: {
            nome: { type: 'string', description: 'Nome do parâmetro (minúsculas).' },
            tipo: { type: 'string', enum: ['texto', 'numero', 'data'], description: 'texto, numero ou data (AAAA-MM-DD).' },
            descricao: { type: 'string', description: 'Para que serve.' },
            padrao: { type: 'string', description: 'Valor por omissão (opcional).' },
          },
          additionalProperties: false,
        },
      },
      valores_teste: { type: 'string', description: 'JSON com os valores dos parâmetros para o teste (opcional), ex.: {"dia":"2026-10-31"}.' },
    },
    output: TEXTO,
    execute: erroEmTexto(async (args, exec) => criador.criar({ ...args, valores_teste: lerValores(args.valores_teste) }, exec.signal)),
  }))

  ctx.tools.register(defineTool({
    name: 'promover_ferramenta',
    description: 'Promove uma ferramenta criada (que já passou no teste do laboratório) para os perfis do dia a dia (Telegram e página): a partir do pedido seguinte aparece como fc_<nome>.',
    parameters: { nome: { type: 'string', required: true, description: 'O nome da ferramenta criada.' } },
    output: TEXTO,
    execute: erroEmTexto(async (args) => criador.promover(args.nome)),
  }))

  ctx.tools.register(defineTool({
    name: 'usar_ferramenta_criada',
    description: 'Corre uma ferramenta criada pelo Dipsy (ativa, ou do laboratório com o teste a passar) e devolve o resultado. valores = JSON com os parâmetros (opcional).',
    parameters: {
      nome: { type: 'string', required: true, description: 'O nome da ferramenta criada.' },
      valores: { type: 'string', description: 'JSON com os valores dos parâmetros, ex.: {"dia":"2026-10-31"}.' },
    },
    output: TEXTO,
    execute: erroEmTexto(async (args, exec) => criador.usar(args.nome, lerValores(args.valores), exec.signal)),
  }))

  ctx.tools.register(defineTool({
    name: 'listar_ferramentas_criadas',
    description: 'Lista as ferramentas que o Dipsy criou (ativas e do laboratório, com o estado do teste).',
    parameters: {},
    output: TEXTO,
    execute: async () => criador.listar(),
  }))

  ctx.tools.register(defineTool({
    name: 'apagar_ferramenta',
    description: 'Retira UMA ferramenta criada pelo Dipsy (o ficheiro fica guardado com o sufixo .retirada). Só se estiver errada ou o Danilo pedir.',
    parameters: { nome: { type: 'string', required: true, description: 'O nome da ferramenta criada.' } },
    output: TEXTO,
    execute: erroEmTexto(async (args) => criador.apagar(args.nome)),
  }))

  for (const r of criador.carregar(criador.perfilAtual())) {
    const params = {}
    for (const p of r.parametros) params[p.nome] = { type: p.tipo === 'numero' ? 'number' : 'string', required: p.padrao === undefined, description: p.descricao || p.tipo }
    try {
      ctx.tools.register(defineTool({
        name: `fc_${r.nome}`,
        description: `[ferramenta criada pelo Dipsy] ${r.descricao}`,
        parameters: params,
        output: TEXTO,
        execute: erroEmTexto(async (args, exec) => criador.usar(r.nome, args, exec.signal)),
      }))
    } catch { /* uma receita má nunca impede o arranque do Dipsy */ }
  }

  ctx.tools.register(defineTool({
    name: 'libertar_memoria',
    description: 'Liberta memória (RAM) do PC do Danilo: corre o script seguro ~/.dsh/limpar-ram.ps1 em modo normal (só atua quando a memória está mesmo baixa e nunca fecha o Remote Control, as sessões do Claude, o Chrome, a ponte do Telegram nem os pythonw). Devolve os MB livres antes e depois.',
    parameters: {},
    output: TEXTO,
    execute: async (_args, exec) => libertarMemoria(exec.signal),
  }))

  ctx.tools.guard((execucao) => {
    try {
      const r = avaliar(execucao.name, execucao.arguments, { modo: MODO })
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
