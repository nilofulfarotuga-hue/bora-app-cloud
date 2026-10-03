// =============================================================================
// bora-mods · MOD 5 · bora-contexto — o Claude Code entra a saber.
//  - arranque: diz que os mods estão ativos e confere o ceo-ai
//  - prompt que começa por "⚠️ MODO PROTECÇÃO TOTAL": junta ramo, último
//    commit e trabalho por gravar (só o Claude lê)
//  - prompt de missão sem esse cabeçalho: aviso (não bloqueia)
//  - /bora: o mapa curto
// =============================================================================
import type { EngineInterface, On } from 'claude-code'

import { caminhoLog, juntarLinha, raizDe } from './comum'

export const CABECALHO = /^\s*(⚠️\s*)?MODO PROTEC[ÇC][ÃA]O TOTAL/i

async function anotar($: EngineInterface, registo: Record<string, unknown>): Promise<void> {
  try {
    const caminho = caminhoLog($.plugin.root, 'contexto.log')
    const antigo = await $.fs.read(caminho).catch(() => '')
    await $.fs.write(caminho, juntarLinha(antigo, registo, new Date().toISOString()))
  } catch {
    // um log que falha nunca parte a sessão
  }
}

async function git($: EngineInterface, args: string[]): Promise<string> {
  try {
    const r = await $.process.run(['git', ...args], { cwd: raizDe($.plugin.root), timeoutMs: 10_000 })
    return r.exitCode === 0 ? r.stdout.trim() : `(git ${args[0]} falhou)`
  } catch {
    return `(git ${args[0]} indisponível)`
  }
}

export async function notaDeMissao($: EngineInterface): Promise<string> {
  const ramo = await git($, ['branch', '--show-current'])
  const ultimo = await git($, ['log', '-1', '--format=%h %s'])
  const wip = await git($, ['status', '--porcelain'])
  const linhas = wip.startsWith('(') ? wip : `${wip.split('\n').filter(l => l.trim() !== '').length} ficheiros por gravar (WIP alheio fica de fora: git add por caminho)`
  return [
    `bora-contexto: ramo ${ramo} · último commit ${ultimo} · ${linhas}.`,
    'A tranca bora-tranca está ativa: zonas vermelhas e push forçado bloqueiam por código; se um comando for negado, REPORTA no e2e_log, não contornes.',
  ].join('\n')
}

// filtro "apanha tudo": o gancho sem filtro de cada evento é o da tranca
const TUDO = /[\s\S]*/

export function registarContexto(on: On): void {
  on('session.start', { cwd: TUDO }, async ($, e, next) => {
    $.ui.log('bora-mods ativo: tranca · vigia · contador · ci · contexto')
    try {
      await $.command.register({ name: 'bora', description: 'bora-mods: zonas vermelhas, comandos e onde está o log' })
    } catch {
      // segue sem o comando
    }
    const temCeo = await $.fs.exists(`${raizDe($.plugin.root)}/.claude/skills/ceo-ai`).catch(() => false)
    if (!temCeo) {
      $.ui.toast('ceo-ai em falta — missão não deve arrancar', { timeoutMs: 15_000 })
      $.ui.log('bora-contexto: .claude/skills/ceo-ai em falta — missão não deve arrancar')
    }
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    if (CABECALHO.test(e.text)) {
      const nota = await notaDeMissao($)
      return next({ ...e, context: [...(e.context ?? []), nota] })
    }
    if (e.text.length > 1500 && /BLOCO|FASE|e2e_log/.test(e.text)) {
      $.ui.toast('Prompt de missão sem cabeçalho MODO PROTECÇÃO TOTAL', { timeoutMs: 10_000 })
      $.ui.log('bora-contexto: prompt de missão sem cabeçalho MODO PROTECÇÃO TOTAL (não bloqueia)')
    }
    return next(e)
  })

  on('prompt.attachment', ($, e, next) => {
    $.ui.log(`bora-contexto: anexo ${e.type} (${e.text.length} caracteres)`, { to: 'debug' })
    return next(e)
  })

  on('session.compact', async ($, e, next) => {
    await anotar($, { evento: 'compact', gatilho: e.trigger, mensagens: e.messages.length })
    return next(e)
  })

  on('command.run', { command: 'bora' }, async $ => {
    let zonas = '(zonas-vermelhas.json ilegível)'
    try {
      const z = JSON.parse(await $.fs.read(`${$.plugin.root}/zonas-vermelhas.json`)) as { ficheiros: { motivo: string }[] }
      zonas = z.ficheiros.map(f => `  - ${f.motivo}`).join('\n')
    } catch {
      // fica a mensagem de ilegível
    }
    return {
      text: [
        'bora-mods · mapa curto',
        'Zonas vermelhas (a tranca nega):',
        zonas,
        '  - git push forçado, git add -A/., git reset --hard, rm -rf fora de build/.dart_tool/node_modules',
        '  - SQL destrutivo em tabelas de dinheiro, UPDATE/INSERT/DELETE direto em orders/drivers/wallets…, deploy protegido',
        'Comandos: /tranca · /tranca-off N · /vigia · /custo · /ci · /bora',
        'Logs: .claude/.ai/mods/ (tranca.log, vigia.log, contexto.log)',
        'Desligar: claude --safe-mode (uma sessão) · disableAllHooks · tirar CLAUDE_CODE_PLUGIN_DIRS',
      ].join('\n'),
    }
  })
}
