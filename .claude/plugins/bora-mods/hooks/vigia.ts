// =============================================================================
// bora-mods · MOD 2 · bora-vigia — missão presa, automático.
//  - turno a correr e 15 min sem ferramenta nem texto novo -> aviso + log local
//    + e2e_log + Telegram (se houver credencial no PC)
//  - a mesma chamada 5 vezes seguidas -> aviso + lembrete ao Claude (1x / 10 min)
//  - /vigia mostra o estado
// Os ganchos partilhados usam o filtro TUDO: o motor só deixa um gancho sem
// filtro por evento, e esse é o da tranca.
// =============================================================================
import type { EngineInterface, On } from 'claude-code'

import { argsDe, caminhoLog, juntarLinha, pedidoE2e, pedidoTelegram, raizDe, telegramEntrou } from './comum'

export const PARADO_MS = 15 * 60_000
const CIRCULO = 5
const CIRCULO_INTERVALO_MS = 10 * 60_000
const TUDO = /[\s\S]*/

export const estado = {
  aCorrer: false,
  ultimoAvanco: 0,
  alertadoNestaParagem: false,
  alertas: 0,
  ultimaChave: '',
  repeticoes: 0,
  ultimoCirculo: -Infinity,
  ultimoTelegram: '—',
  ultimoE2e: '—',
}

let filaLog: Promise<void> = Promise.resolve()

function chave(tool: string, args: Record<string, unknown>): string {
  return `${tool}?${Object.keys(args)
    .sort()
    .map(k => `${k}=${JSON.stringify(args[k])}`)
    .join('&')}`
}

function anotar($: EngineInterface, registo: Record<string, unknown>): Promise<void> {
  const caminho = caminhoLog($.plugin.root, 'vigia.log')
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

async function avanco($: EngineInterface): Promise<void> {
  estado.ultimoAvanco = await $.clock.now()
  estado.alertadoNestaParagem = false
}

async function avisarFora($: EngineInterface, texto: string): Promise<void> {
  // e2e_log pela chave anon do .dart_defines (só insere)
  try {
    const defines = JSON.parse(await $.fs.read(`${raizDe($.plugin.root)}/.dart_defines`)) as Record<string, string>
    const p = pedidoE2e(defines, { passo: 'vigia-parada', estado: 'alerta', detalhe: texto })
    estado.ultimoE2e = p ? ((await $.http.fetch(p.url, p.init)).ok ? 'ok' : 'falhou') : 'sem chave'
  } catch {
    estado.ultimoE2e = 'falhou'
  }
  // Telegram só com credencial no PC; o token nunca é escrito em lado nenhum
  try {
    const token = await $.env.get('BORA_TELEGRAM_BOT_TOKEN')
    const chat = await $.env.get('BORA_TELEGRAM_CHAT_ID')
    if (!token || !chat) {
      estado.ultimoTelegram = 'sem credencial no PC'
    } else {
      const p = pedidoTelegram(token, chat, `⚠️ ${texto}`)
      const r = await $.http.fetch(p.url, p.init)
      estado.ultimoTelegram = telegramEntrou(r.ok, r.text) ? 'enviado' : 'falhou'
    }
  } catch {
    estado.ultimoTelegram = 'falhou'
  }
}

async function verificar($: EngineInterface): Promise<void> {
  if (!estado.aCorrer || estado.alertadoNestaParagem) return
  const parado = (await $.clock.now()) - estado.ultimoAvanco
  if (parado < PARADO_MS) return
  estado.alertadoNestaParagem = true
  estado.alertas++
  const texto = `bora-vigia: missão parada há ${Math.round(parado / 60_000)} min (sem ferramenta nem texto novo).`
  $.ui.toast(texto, { timeoutMs: 15_000 })
  $.ui.log(texto)
  await avisarFora($, texto)
  await anotar($, { evento: 'parada', minutos: Math.round(parado / 60_000), e2e_log: estado.ultimoE2e, telegram: estado.ultimoTelegram })
}

export function registarVigia(on: On): void {
  on('session.start', { cwd: TUDO }, async ($, e, next) => {
    try {
      await $.command.register({ name: 'vigia', description: 'bora-vigia: último avanço, tempo parado e alertas enviados' })
    } catch {
      // segue sem o comando
    }
    estado.ultimoAvanco = await $.clock.now()
    $.clock.every(60_000, () => {
      void verificar($).catch(() => undefined)
    })
    return next(e)
  })

  on('turn.start', { turnId: TUDO }, async ($, e, next) => {
    estado.aCorrer = true
    await avanco($)
    return next(e)
  })

  on('turn.step', { turnId: TUDO }, async function* ($, e, next) {
    const r = yield* next(e)
    await avanco($)
    return r
  })

  on('turn.complete', { turnId: TUDO }, async ($, e, next) => {
    estado.aCorrer = false
    if (e.isAborted) await anotar($, { evento: 'turno-interrompido', turnId: e.turnId })
    return next(e)
  })

  on('tool.call', { tool: TUDO }, async ($, e, next) => {
    await avanco($)
    const k = chave(e.tool, argsDe(e))
    estado.repeticoes = k === estado.ultimaChave ? estado.repeticoes + 1 : 1
    estado.ultimaChave = k
    if (estado.repeticoes >= CIRCULO) {
      const agora = await $.clock.now()
      if (agora - estado.ultimoCirculo >= CIRCULO_INTERVALO_MS) {
        estado.ultimoCirculo = agora
        $.ui.toast(`bora-vigia: a andar em círculos (${e.tool} repetido ${estado.repeticoes}x)`, { timeoutMs: 10_000 })
        await anotar($, { evento: 'circulos', tool: e.tool, vezes: estado.repeticoes })
        void $.prompt
          .submit({
            text: 'bora-vigia: estás a repetir o mesmo passo 5 vezes. Pára, escreve no e2e_log o que está preso e muda de abordagem.',
          })
          .catch(() => undefined)
      }
    }
    return next(e)
  })

  on('command.run', { command: 'vigia' }, async $ => {
    const parado = Math.round(((await $.clock.now()) - estado.ultimoAvanco) / 60_000)
    return {
      text: [
        `bora-vigia · turno a correr: ${estado.aCorrer ? 'sim' : 'não'} · último avanço há ${parado} min`,
        `alertas de paragem nesta sessão: ${estado.alertas} · e2e_log: ${estado.ultimoE2e} · Telegram: ${estado.ultimoTelegram}`,
        'log: .claude/.ai/mods/vigia.log',
      ].join('\n'),
    }
  })
}
