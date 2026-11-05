// Liga ou desliga a trava num settings.json.
// Uso: node registar-gancho.mjs <settings.json> <gancho.mjs> [--tirar]
import { readFileSync, writeFileSync } from 'node:fs'

const [, , ficheiro, gancho, modo] = process.argv
const MATCHER = 'Bash|PowerShell|Read|Grep|Edit|Write|MultiEdit|NotebookEdit|mcp__.*'
const barras = p => p.replace(/\\/g, '/')

const cfg = JSON.parse(readFileSync(ficheiro, 'utf8').replace(/^﻿/, ''))
cfg.hooks ??= {}
const outros = (cfg.hooks.PreToolUse ?? []).filter(e => !JSON.stringify(e).includes('trava-modo-automatico'))
if (modo === '--tirar') cfg.hooks.PreToolUse = outros
else {
  const command = `"${barras(process.execPath)}" "${barras(gancho)}"`
  cfg.hooks.PreToolUse = [...outros, { matcher: MATCHER, hooks: [{ type: 'command', command, timeout: 30 }] }]
}
if (!cfg.hooks.PreToolUse.length) delete cfg.hooks.PreToolUse

// Cinto e suspensorios: a aprovacao automatica da tranca passa por cima do deny de um
// gancho nas leituras (prova de 05/11), mas nao passa por cima destas regras.
const LEITURAS = [
  '.env', '.env.local', '.env.production', '.env.development', '.dart_defines', '.dart_defines.*', '*.jks', '*.keystore',
  '*.pem', '*.p12', 'key.properties', '.credentials.json', '.supabase-token*', '_segredos/**',
].map(p => `Read(**/${p})`)
cfg.permissions ??= {}
const deny = (cfg.permissions.deny ?? []).filter(r => !LEITURAS.includes(r))
cfg.permissions.deny = modo === '--tirar' ? deny : [...deny, ...LEITURAS]
if (!cfg.permissions.deny.length) delete cfg.permissions.deny
if (!Object.keys(cfg.permissions).length) delete cfg.permissions
writeFileSync(ficheiro, `${JSON.stringify(cfg, null, 2)}\n`)
