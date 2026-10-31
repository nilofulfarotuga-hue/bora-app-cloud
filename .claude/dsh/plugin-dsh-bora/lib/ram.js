// libertar_memoria: o Danilo pede ao Dipsy (Telegram ou página) para libertar memória do PC.
// Não fecha nada por conta própria: chama o script já provado ~/.dsh/limpar-ram.ps1 (missão retoma-geral, bloco 0) em
// MODO NORMAL (sem -Forcar e sem -Sessoes). O script só atua abaixo do limite dele e nunca fecha o Remote Control, as
// sessões do Claude, o Chrome, o Windows Terminal, a ponte do Telegram nem os pythonw.
import { execFile } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const SCRIPT = path.join(os.homedir(), '.dsh', 'limpar-ram.ps1')
const LOG = path.join(os.homedir(), '.dsh', 'limpar-ram.log')
const mb = () => Math.round(os.freemem() / 1048576)

export function linhasNovasDoLog(antesBytes) {
  try {
    const b = fs.readFileSync(LOG)
    return b.subarray(Math.min(antesBytes, b.length)).toString('utf8').split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
  } catch { return [] }
}

export function libertarMemoria(signal) {
  return new Promise((resolve) => {
    if (!fs.existsSync(SCRIPT)) return resolve('Não encontrei o script de limpeza da memória (~/.dsh/limpar-ram.ps1). Pede ao Claude Code.')
    let tamanho = 0
    try { tamanho = fs.statSync(LOG).size } catch { /* ainda não há registo */ }
    const antes = mb()
    execFile('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT],
      { windowsHide: true, timeout: 120000, signal },
      (erro) => {
        const depois = mb()
        const log = linhasNovasDoLog(tamanho).slice(-3).join(' | ')
        const r = `Memória livre antes: ${antes} MB. Depois: ${depois} MB.` + (log ? ` O que a limpeza fez: ${log}` : '') +
          (erro && !log ? ` (a limpeza não correu: ${String(erro.message ?? erro).slice(0, 120)})` : '')
        resolve(r)
      })
  })
}
