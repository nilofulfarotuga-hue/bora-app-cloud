// Ponte oficial dsh -> Claude Code: passa a um Claude Code (o do Danilo, o mesmo CLI oficial, em modo "-p", sem proxy nenhum)
// o trabalho que o Dipsy não deve fazer sozinho. Código nosso (30/10/2026).
//   so_ler : só lê (Read, Grep, Glob). Para diagnosticar, rever e responder. Corre na pasta pedida.
//   editar : pode editar ficheiros (acceptEdits) mas NÃO corre comandos de escrita, não faz push e passa pelo hook bora-tranca do
//            próprio Claude Code. Sem pasta pedida, trabalha numa cópia de trabalho NOVA do repo do Bora (git worktree em ramo
//            dsh-delegado-<id>), nunca na árvore principal.
// Dinheiro, dispatch, carteira, RLS, push e publicação continuam a ser do Claude Code com o "autorizo" do Danilo: o prefixo lembra-o.
// Cada chamada fica registada em ~/.dsh/delegado/AAAA-MM-DD_HHMMSS.json (resposta completa, custo, voltas, sessão).

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawn, execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// Guarda dos executores (decisão 11, 31/10): cada claude -p chamado daqui leva um hook PreToolUse que barra comandos
// destrutivos e segredos antes de correrem (scripts/guarda-claude-hook.mjs, a mesma lista da guarda do Dipsy).
const HOOK = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'guarda-claude-hook.mjs')
function ficheiroDefinicoesGuarda() {
  const f = path.join(os.homedir(), '.dsh', 'delegado', 'guarda-settings.json')
  const conteudo = JSON.stringify({ hooks: { PreToolUse: [{ matcher: 'Bash|PowerShell|Write|Edit|MultiEdit|NotebookEdit|Read|Grep|Glob', hooks: [{ type: 'command', command: `node "${HOOK.replace(/\\/g, '/')}"`, timeout: 20 }] }] } }, null, 2)
  fs.mkdirSync(path.dirname(f), { recursive: true })
  if (!fs.existsSync(f) || fs.readFileSync(f, 'utf8') !== conteudo) fs.writeFileSync(f, conteudo, 'utf8')
  return f
}

const REPO = 'C:\\BoraLocal\\projetosflutter\\bora_app'
const PASTA_REGISTO = path.join(os.homedir(), '.dsh', 'delegado')
const CLAUDE_CMD = path.join(process.env.APPDATA ?? path.join(os.homedir(), 'AppData', 'Roaming'), 'npm', 'claude.cmd')
const MODELOS = ['sonnet', 'opus', 'haiku']
const TIMEOUT_MS = 25 * 60 * 1000

const PREFIXO = [
  'Pedido do Dipsy (o segundo ajudante do Danilo, com motor grátis) ao Claude Code. Segue as regras do repo (CLAUDE.md, PADRAO_BORA.md).',
  'Dinheiro, preços, comissões, Stripe, carteira, tokens, dispatch, RLS e publicação NÃO se aplicam sem o "autorizo" do Danilo:',
  'prepara e descreve, não apliques. Nunca git push. Responde em português simples, com o que fizeste, o que falta e porquê.',
].join(' ')

function pastaPermitida(p) {
  const abs = path.resolve(p)
  return /^c:\\boralocal\\/i.test(abs) && fs.existsSync(abs) && fs.statSync(abs).isDirectory()
}

function criarWorktree(id) {
  const destino = `C:\\BoraLocal\\wt-dsh-delegado-${id}`
  execFileSync('git', ['-C', REPO, 'worktree', 'add', '-q', '-b', `dsh-delegado-${id}`, destino, 'HEAD'], { windowsHide: true, timeout: 180000 })
  return destino
}

export async function passarAoClaudeCode({ pedido, modo, pasta, modelo }, sinal) {
  pedido = String(pedido ?? '').trim()
  if (pedido.length < 10) throw new Error('descreve o trabalho (pelo menos 10 letras)')
  modo = modo === 'editar' ? 'editar' : 'so_ler'
  modelo = MODELOS.includes(modelo) ? modelo : 'sonnet'
  if (!fs.existsSync(CLAUDE_CMD)) throw new Error('não encontrei o claude.cmd deste PC')
  const id = Date.now().toString(36)
  let cwd = REPO
  let extra = ''
  if (pasta) {
    if (!pastaPermitida(pasta)) throw new Error('a pasta tem de existir dentro de C:\\BoraLocal')
    cwd = path.resolve(pasta)
  } else if (modo === 'editar') {
    cwd = criarWorktree(id)
    extra = ` Estás numa cópia de trabalho nova (${cwd}, ramo dsh-delegado-${id}); não toques fora dela.`
  }
  const args = ['-p', '--output-format', 'json', '--max-turns', '30', '--model', modelo, '--settings', ficheiroDefinicoesGuarda()]
  if (modo === 'so_ler') {
    args.push('--allowedTools', 'Read', 'Grep', 'Glob')
  } else {
    args.push('--permission-mode', 'acceptEdits', '--allowedTools', 'Read', 'Grep', 'Glob', 'Edit', 'Write',
      'Bash(git status:*)', 'Bash(git diff:*)', 'Bash(git log:*)', 'Bash(flutter analyze:*)', 'Bash(flutter test:*)')
  }
  const entrada = `${PREFIXO}${extra}\n\nTrabalho pedido (${modo === 'editar' ? 'podes editar' : 'só leitura'}):\n${pedido}`
  const t0 = Date.now()
  const saida = await new Promise((resolve, reject) => {
    // 08/11 (m3): o Claude Code NUNCA vai pelo proxy do Dipsy (regra da casa: nada de proxy à frente do Claude Code)
    const env = { ...process.env }
    for (const k of Object.keys(env)) if (/^(https?|all|no)_proxy$/i.test(k)) delete env[k]
    const filho = spawn(process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', CLAUDE_CMD, ...args], { cwd, env, windowsHide: true, signal: sinal })
    let out = ''
    let err = ''
    const relogio = setTimeout(() => { try { filho.kill() } catch { /* já acabou */ } reject(new Error('o Claude Code passou de 25 minutos e foi parado')) }, TIMEOUT_MS)
    filho.stdout.on('data', (d) => { out += d })
    filho.stderr.on('data', (d) => { err += d })
    filho.on('error', (e) => { clearTimeout(relogio); reject(e) })
    filho.on('close', (codigo) => { clearTimeout(relogio); codigo === 0 ? resolve(out) : reject(new Error(`o Claude Code saiu com código ${codigo}: ${err.slice(0, 300)}`)) })
    filho.stdin.end(entrada)
  })
  let j
  try { j = JSON.parse(saida) } catch { throw new Error('resposta do Claude Code ilegível') }
  fs.mkdirSync(PASTA_REGISTO, { recursive: true })
  const nome = new Date().toISOString().replace(/[-:]/g, '').replace('T', '_').slice(0, 15)
  fs.writeFileSync(path.join(PASTA_REGISTO, `${nome}.json`), JSON.stringify({ pedido, modo, modelo, cwd, ms: Date.now() - t0, resposta: j }, null, 2), 'utf8')
  if (j.is_error) throw new Error(`o Claude Code deu erro: ${String(j.result ?? '').slice(0, 300)}`)
  const rodape = `\n\n(Claude Code ${modelo}, modo ${modo}, pasta ${cwd}, ${j.num_turns ?? '?'} voltas, ${Math.round((Date.now() - t0) / 1000)} s, custo ${j.total_cost_usd != null ? '$' + Number(j.total_cost_usd).toFixed(3) : '?'}; registo em ~/.dsh/delegado/${nome}.json)`
  return String(j.result ?? '(sem resposta)') + rodape
}
