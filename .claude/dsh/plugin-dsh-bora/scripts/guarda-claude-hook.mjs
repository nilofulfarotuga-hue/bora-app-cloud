#!/usr/bin/env node
// Hook PreToolUse para os EXECUTORES automáticos do Claude Code (claude -p): decisão 11 do Danilo (31/10/2026).
// Reaproveita a guarda do Dipsy (lib/guarda.js, função avaliarExecutor): barra, ANTES de correr, comandos destrutivos
// (rm -rf, apagar tabelas, push forçado, reescrever histórico, git add de tudo, matar processos, sistema, código remoto)
// e mexer em .env/segredos ou nas definições/hooks do Claude Code. O resto passa sem mudar nada.
// Ligar: claude -p --settings <ficheiro com hooks.PreToolUse a chamar "node <este ficheiro>">  (ver guarda-claude-settings.json)
// Regista cada recusa em ~/.dsh/guarda-executores.log (sem segredos: só a regra e 120 letras do comando).
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { avaliarExecutor } from '../lib/guarda.js'

const LOG = path.join(os.homedir(), '.dsh', 'guarda-executores.log')
const redigir = (s) => String(s ?? '').replace(/[A-Za-z0-9_\-]{28,}/g, '[…]').replace(/\s+/g, ' ').slice(0, 120)

let entrada = ''
process.stdin.setEncoding('utf8')
process.stdin.on('data', (d) => { entrada += d })
process.stdin.on('end', () => {
  let ev
  try { ev = JSON.parse(entrada || '{}') } catch { ev = {} }
  const nome = ev.tool_name ?? ''
  const args = ev.tool_input ?? {}
  let r = null
  try {
    r = avaliarExecutor(nome, args)
  } catch (e) {
    if (nome === 'Bash' || nome === 'PowerShell') r = { regra: 'erro-interno', porque: 'a guarda não conseguiu avaliar este comando, por isso não corre.' }
  }
  if (!r) process.exit(0)
  try {
    fs.mkdirSync(path.dirname(LOG), { recursive: true })
    fs.appendFileSync(LOG, JSON.stringify({ quando: new Date().toISOString(), ferramenta: nome, regra: r.regra, cwd: ev.cwd ?? '', trecho: redigir(args.command ?? args.file_path ?? args.path) }) + '\n')
  } catch { /* o registo nunca impede a recusa */ }
  const motivo = `BLOQUEADO pela guarda dos executores (regra ${r.regra}): ${r.porque} Não contornes: regista e segue com o resto.`
  // Resposta em JSON com "deny" e código 0 (a forma que o Claude Code junta com os outros hooks: um "deny" ganha a um
  // "allow"). Com o código 2 o Read de um ficheiro protegido ainda correu a 31/10 (visto no teste da isca .pem).
  process.stdout.write(JSON.stringify({ decision: 'block', reason: motivo, hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: motivo } }))
  process.exit(0)
})
