// =============================================================================
// bora-mods · MOD 1 · bora-tranca — a tranca de verdade.
//
//  A) NEGA  (tool.call, sem next): zonas vermelhas, push forçado, git add -A,
//     apagar recursivo, SQL destrutivo em dinheiro, deploy protegido,
//     workflows do CI, segredos. Nunca se desarma por comando.
//  B) PERGUNTA ao Danilo ($.ui.ask): git push, migration, DDL, deploy de
//     Edge Function fora da lista. Sem resposta / `claude -p` = Recusar.
//  C) APROVA sem caixa (tool.check): só leitura e edições em zona verde.
//     /tranca-off N desarma SÓ esta parte por N minutos.
//  D) Falhou? Nega (fail-closed) nos dois ganchos.
//
// Os .sh antigos (.claude/hooks/protege-*.sh) continuam a correr DEPOIS disto.
// =============================================================================
import type { EngineInterface, On } from 'claude-code'

import { argsDe, caminhoLog, juntarLinha, raizDe } from './comum'
import {
  aprovaSemPerguntar,
  avaliaChamada,
  lerVarShell,
  normaliza,
  semSegredos,
  type Contexto,
  type ListasBanco,
  type Veredito,
  type Zonas,
} from './regras'

const LOG = 'tranca.log'
const CHAVE_OFF = 'tranca.allowOffAte'
const FINTABLE_PADRAO = 'orders|wallets|ledger|ledger_entries|bora_tokens'

// contagem desta sessão (recomeça se o módulo recarregar)
const conta = { nega: 0, pergunta: 0, aprova: 0 }
// chamadas que o Danilo autorizou na pergunta: o tool.check não volta a perguntar
const autorizadas = new Set<string>()
// o $.fs.write não é atómico: as escritas do log passam por uma fila
let filaLog: Promise<void> = Promise.resolve()

async function lerZonas($: EngineInterface): Promise<Zonas | null> {
  try {
    const z = JSON.parse(await $.fs.read(`${$.plugin.root}/zonas-vermelhas.json`)) as Zonas
    return Array.isArray(z.ficheiros) && z.migracoes && typeof z.segredos_caminho === 'string' ? z : null
  } catch {
    return null
  }
}

async function lerBanco($: EngineInterface): Promise<ListasBanco> {
  try {
    const sh = await $.fs.read(`${raizDe($.plugin.root)}/.claude/hooks/protege-banco.sh`)
    return {
      protslug: lerVarShell(sh, 'PROTSLUG'),
      moneyfn: lerVarShell(sh, 'MONEYFN') ?? '',
      fintable: lerVarShell(sh, 'FINTABLE') ?? FINTABLE_PADRAO,
    }
  } catch {
    // sem o .sh: deploys bloqueados (protslug null), tabelas mínimas de dinheiro
    return { protslug: null, moneyfn: '', fintable: FINTABLE_PADRAO }
  }
}

async function contexto($: EngineInterface, tool: string, args: Record<string, unknown>): Promise<Contexto> {
  const ctx: Contexto = { zonas: await lerZonas($), banco: await lerBanco($), raiz: raizDe($.plugin.root) }
  const caminho = typeof args.file_path === 'string' ? normaliza(args.file_path) : ''
  if (tool === 'Write' && /(^|\/)pubspec\.yaml$/i.test(caminho)) {
    try {
      ctx.pubspecAtual = await $.fs.read(args.file_path as string)
    } catch {
      ctx.pubspecAtual = null
    }
  }
  return ctx
}

async function raizes($: EngineInterface): Promise<string[]> {
  const lista = [raizDe($.plugin.root)]
  try {
    lista.push((await $.session.root()).replace(/\\/g, '/'))
  } catch {
    // fica só a do plugin
  }
  return [...new Set(lista)]
}

function resumo(tool: string, args: Record<string, unknown>): string {
  const alvo = args.file_path ?? args.notebook_path ?? args.command ?? args.query ?? args.name ?? ''
  return semSegredos(`${tool} ${String(alvo)}`).slice(0, 200)
}

function anotar($: EngineInterface, registo: Record<string, unknown>): Promise<void> {
  const caminho = caminhoLog($.plugin.root, LOG)
  filaLog = filaLog.then(async () => {
    try {
      const antigo = await $.fs.read(caminho).catch(() => '')
      await $.fs.write(caminho, juntarLinha(antigo, registo, new Date().toISOString()))
    } catch {
      // um log que falha nunca parte a sessão
    }
  })
  return filaLog
}

async function ultimasLinhas($: EngineInterface, n: number): Promise<string[]> {
  try {
    return (await $.fs.read(caminhoLog($.plugin.root, LOG))).split('\n').filter(l => l.trim() !== '').slice(-n)
  } catch {
    return []
  }
}

async function idSessao($: EngineInterface): Promise<string> {
  try {
    return await $.session.id()
  } catch {
    return '?'
  }
}

async function perguntar($: EngineInterface, v: Veredito & { acao: 'pergunta' }): Promise<boolean> {
  try {
    const r = await $.ui.ask(v.pergunta, { header: 'bora-tranca', options: ['Recusar', 'Permitir'] })
    return r === 'Permitir'
  } catch {
    // dispensada, ou `claude -p` (ninguém para responder): Recusar
    return false
  }
}

async function guarda($: EngineInterface, e: { tool: string; tool_use_id: string }): Promise<{ deny: string } | null> {
  const args = argsDe(e)
  const v = avaliaChamada(e.tool, args, await contexto($, e.tool, args))
  if (v.acao === 'nega') {
    conta.nega++
    const texto = `bora-tranca: BLOQUEADO ${e.tool} — ${v.motivo}. Não contornes: reporta no e2e_log e ao Danilo.`
    $.ui.log(texto)
    $.ui.notice(e.tool_use_id, 'bloqueado pela bora-tranca')
    await anotar($, { sessao: await idSessao($), tool: e.tool, decisao: 'nega', motivo: v.motivo, resumo: resumo(e.tool, args) })
    return { deny: texto }
  }
  if (v.acao === 'pergunta') {
    conta.pergunta++
    const sim = await perguntar($, v)
    await anotar($, {
      sessao: await idSessao($),
      tool: e.tool,
      decisao: sim ? 'pergunta-permitida' : 'pergunta-recusada',
      motivo: v.motivo,
      resumo: resumo(e.tool, args),
    })
    if (!sim) {
      const texto = `bora-tranca: o Danilo não autorizou (${v.motivo}). Não tentes outro caminho; reporta.`
      $.ui.log(texto)
      return { deny: texto }
    }
    autorizadas.add(e.tool_use_id)
  }
  return null
}

export function registarTranca(on: On): void {
  on('session.start', async ($, e, next) => {
    try {
      await $.command.register({ name: 'tranca', description: 'bora-tranca: últimas 20 decisões e contagem desta sessão' })
      await $.command.register({
        name: 'tranca-off',
        description: 'bora-tranca: desliga SÓ as aprovações automáticas por N minutos (as proibições nunca se desligam)',
        argumentHint: '<minutos>',
      })
    } catch {
      // sem comandos não é razão para parar a tranca
    }
    return next(e)
  })

  // ---- A + B: a guarda. É o PRIMEIRO gancho de tool.call do plugin (o
  // register.ts liga a tranca antes dos outros mods). Rebentou antes de deixar
  // correr? Nega.
  on('tool.call', async ($, e, next) => {
    const negado = await guarda($, e)
    return negado ?? next(e)
  }).catch(($, e, next) =>
    next.called ? undefined : { deny: `bora-tranca falhou (${next.error.kind}): comando NÃO corrido. Reporta ao Danilo.` },
  )

  // ---- C: o aprovador ----------------------------------------------------------
  on('tool.check', async ($, e, next) => {
    const args = (e.input && typeof e.input === 'object' ? e.input : {}) as Record<string, unknown>
    // cinto e suspensórios: o que a guarda nega nunca é aprovado aqui
    const v = avaliaChamada(e.tool, args, await contexto($, e.tool, args))
    if (v.acao === 'nega') return { decision: 'deny', reason: `bora-tranca: ${v.motivo}` }
    if (e.tool_use_id !== undefined && autorizadas.delete(e.tool_use_id)) {
      return { decision: 'allow', reason: 'bora-tranca: autorizado pelo Danilo na pergunta' }
    }
    if (v.acao === 'pergunta') return next(e)
    const ate = Number((await $.store.get(CHAVE_OFF).catch(() => 0)) ?? 0)
    if (ate > (await $.clock.now())) return next(e)
    const porque = aprovaSemPerguntar(e.tool, args, await raizes($))
    if (porque !== null) {
      conta.aprova++
      return { decision: 'allow', reason: `bora-tranca: ${porque}` }
    }
    return next(e)
  }).catch(() => ({ decision: 'deny' as const, reason: 'bora-tranca falhou: recusado por segurança' }))

  // ---- E: comandos ---------------------------------------------------------------
  on('command.run', { command: 'tranca' }, async $ => {
    const linhas = await ultimasLinhas($, 20)
    const ate = Number((await $.store.get(CHAVE_OFF).catch(() => 0)) ?? 0)
    const agora = await $.clock.now()
    const off =
      ate > agora
        ? `aprovações automáticas DESLIGADAS mais ${Math.ceil((ate - agora) / 60000)} min`
        : 'aprovações automáticas ligadas'
    return {
      text: [
        `bora-tranca · nesta sessão: ${conta.nega} bloqueadas · ${conta.pergunta} perguntas · ${conta.aprova} aprovadas sem caixa · ${off}`,
        `log: .claude/.ai/mods/${LOG}`,
        ...(linhas.length ? linhas : ['(log vazio)']),
      ].join('\n'),
    }
  })

  on('command.run', { command: 'tranca-off' }, async ($, e) => {
    const min = Math.min(120, Math.max(1, Math.round(Number(e.args.trim() || '15')) || 15))
    await $.store.set(CHAVE_OFF, (await $.clock.now()) + min * 60_000)
    await anotar($, { sessao: await idSessao($), decisao: 'tranca-off', motivo: `${min} min` })
    return { text: `bora-tranca: aprovações automáticas desligadas por ${min} min. As proibições continuam ligadas.` }
  })
}
