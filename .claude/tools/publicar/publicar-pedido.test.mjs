// Testes do publicar-pedido.mjs, sem rede e sem GitHub: um remoto local e um `gh` falso.
// Correr: node .claude/tools/publicar/publicar-pedido.test.mjs
import { execFileSync, spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { delimiter, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SCRIPT = fileURLToPath(new URL('./publicar-pedido.mjs', import.meta.url))
const BASE = 'autonomous-night-2026-04-29'
const REPO = 'dono/repo'
let falhas = 0
const verifica = (nome, ok, extra = '') => {
  console.log(`${ok ? 'ok    ' : 'FALHOU'} ${nome}${ok ? '' : ` ${extra}`}`)
  if (!ok) falhas++
}

const raiz = mkdtempSync(join(tmpdir(), 'publicar-teste-'))
const g = (dir, ...a) => execFileSync('git', ['-C', dir, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()

// gh falso: responde a `gh api <rota>` com o ficheiro <respostas>/<rota sem ?>.json
const bin = join(raiz, 'bin')
const respostas = join(raiz, 'respostas')
mkdirSync(bin)
mkdirSync(respostas)
const falso = join(bin, 'gh-falso.mjs')
writeFileSync(
  falso,
  `import { readFileSync } from 'node:fs'
const a = process.argv.slice(2)
if (a[0] === '--version') { console.log('gh falso'); process.exit(0) }
const rota = a[1].split('?')[0].replace(/[/]/g, '_')
try { process.stdout.write(readFileSync(${JSON.stringify(respostas)} + '/' + rota + '.json', 'utf8')) }
catch { console.error('sem resposta para ' + a[1]); process.exit(1) }
`,
)
writeFileSync(join(bin, 'gh'), `#!/bin/sh\nexec node "${falso}" "$@"\n`)
chmodSync(join(bin, 'gh'), 0o755)
writeFileSync(join(bin, 'gh.cmd'), `@node "${falso}" %*\r\n`)
const responde = (rota, corpo) => writeFileSync(join(respostas, `${rota.replace(/[/]/g, '_')}.json`), JSON.stringify(corpo))

const corre = (...a) =>
  spawnSync(process.execPath, [SCRIPT, ...a, '--repo', REPO], {
    cwd: rep,
    encoding: 'utf8',
    env: { ...process.env, PATH: `${bin}${delimiter}${process.env.PATH}`, PUBLICAR_ESCALA_TEMPO: '0.001' },
  })

// Remoto local com o ramo principal e um pedido (refs/pull/7/head)
const remoto = join(raiz, 'remoto.git')
const rep = join(raiz, 'rep')
execFileSync('git', ['init', '--bare', '-q', remoto])
mkdirSync(rep)
g(rep, 'init', '-q', '-b', BASE)
g(rep, 'config', 'user.email', 't@t.t')
g(rep, 'config', 'user.name', 't')
writeFileSync(join(rep, 'a.txt'), 'a\n')
g(rep, 'add', 'a.txt')
g(rep, 'commit', '-q', '-m', 'base')
g(rep, 'remote', 'add', 'origin', remoto)
g(rep, 'push', '-q', 'origin', BASE)
g(rep, 'switch', '-q', '-c', 'ai/2026-11-24-x')
writeFileSync(join(rep, 'b.txt'), 'b\n')
g(rep, 'add', 'b.txt')
g(rep, 'commit', '-q', '-m', 'trabalho')
const cabeca = g(rep, 'rev-parse', 'HEAD')
g(rep, 'push', '-q', 'origin', 'ai/2026-11-24-x', 'HEAD:refs/pull/7/head')
g(rep, 'switch', '-q', BASE)
const baseAntes = g(remoto, 'rev-parse', BASE)

const pedido = (extra = {}) => ({
  state: 'open',
  merged: false,
  title: 'Teste',
  base: { ref: BASE },
  head: { ref: 'ai/2026-11-24-x', sha: cabeca, repo: { full_name: REPO } },
  ...extra,
})
responde(`repos/${REPO}`, { default_branch: BASE })
responde(`repos/${REPO}/actions/workflows`, { total_count: 3 })
responde(`repos/${REPO}/commits/${cabeca}/status`, { statuses: [] })
const testes = lista => responde(`repos/${REPO}/commits/${cabeca}/check-runs`, { check_runs: lista })

try {
  responde(`repos/${REPO}/pulls/7`, pedido({ state: 'closed', merged: true }))
  let r = corre('7')
  verifica('pedido já juntado: recusa', r.status === 2 && /não está aberto/.test(r.stdout), r.stdout)

  responde(`repos/${REPO}/pulls/7`, pedido())
  testes([{ name: 'build-ios', status: 'completed', conclusion: 'failure' }])
  r = corre('7')
  verifica('teste vermelho: recusa e diz qual', r.status === 2 && /build-ios \(failure\)/.test(r.stdout), r.stdout)

  testes([{ name: 'build-ios', status: 'in_progress', conclusion: null }])
  r = corre('7')
  verifica('teste a correr sem --esperar-ci: recusa', r.status === 2 && /ainda a correr/.test(r.stdout), r.stdout)

  testes([])
  r = corre('7')
  verifica('sem testes num repo com CI: recusa', r.status === 2 && /ainda não tem testes/.test(r.stdout), r.stdout)

  testes([
    { name: 'build-ios', status: 'completed', conclusion: 'success' },
    { name: 'olho-golden', status: 'completed', conclusion: 'skipped' },
  ])
  r = corre('7', '--simular')
  verifica('verde + --simular: junta e não envia', r.status === 0 && /SIMULAÇÃO/.test(r.stdout) && g(remoto, 'rev-parse', BASE) === baseAntes, r.stdout + r.stderr)

  responde(`repos/${REPO}/pulls/7`, pedido({ head: { ref: 'ai/2026-11-24-x', sha: 'f'.repeat(40), repo: { full_name: REPO } } }))
  responde(`repos/${REPO}/commits/${'f'.repeat(40)}/check-runs`, { check_runs: [{ name: 'x', status: 'completed', conclusion: 'success' }] })
  responde(`repos/${REPO}/commits/${'f'.repeat(40)}/status`, { statuses: [] })
  r = corre('7', '--simular')
  verifica('pedido mudou depois dos testes: recusa', r.status === 2 && /mudou durante a verificação/.test(r.stdout), r.stdout)

  responde(`repos/${REPO}/pulls/7`, pedido({ head: { ref: 'x', sha: cabeca, repo: { full_name: 'outro/fork' } } }))
  r = corre('7', '--simular')
  verifica('pedido de fork: recusa', r.status === 2 && /fork/.test(r.stdout), r.stdout)

  // A sério: envia para o remoto local e acompanha a publicação (falsa, já verde)
  responde(`repos/${REPO}/pulls/7`, pedido())
  responde(`repos/${REPO}/actions/runs`, {
    workflow_runs: [
      { name: 'Build Android & Deploy to Google Play', status: 'completed', conclusion: 'success', html_url: 'u1' },
      { name: 'Build & Deploy Web (Cloudflare Pages)', status: 'completed', conclusion: 'success', html_url: 'u2' },
    ],
  })
  r = corre('7', '--nao-esperar-publicacao')
  const baseDepois = g(remoto, 'rev-parse', BASE)
  const pais = g(remoto, 'rev-list', '--parents', '-n', '1', BASE).split(' ')
  verifica(
    'verde: junta com merge normal e envia',
    r.status === 0 && /PUBLICADO/.test(r.stdout) && baseDepois !== baseAntes && pais.includes(cabeca) && pais.includes(baseAntes),
    r.stdout + r.stderr,
  )
  verifica('a mensagem diz que os testes estavam verdes', /testes do commit .* acabarem verdes/.test(g(remoto, 'log', '-1', '--format=%B', BASE)))
  verifica('não deixa pastas de trabalho para trás', g(rep, 'worktree', 'list').split('\n').length === 1, g(rep, 'worktree', 'list'))

  // Conflito: o principal mudou o mesmo ficheiro
  g(rep, 'fetch', '-q', 'origin')
  g(rep, 'switch', '-q', '-c', 'ai/2026-11-24-y', `origin/${BASE}`)
  writeFileSync(join(rep, 'a.txt'), 'do pedido\n')
  g(rep, 'commit', '-q', '-am', 'pedido y')
  const y = g(rep, 'rev-parse', 'HEAD')
  g(rep, 'push', '-q', 'origin', 'HEAD:refs/pull/8/head')
  g(rep, 'switch', '-q', '--detach', `origin/${BASE}`)
  writeFileSync(join(rep, 'a.txt'), 'do principal\n')
  g(rep, 'commit', '-q', '-am', 'principal')
  g(rep, 'push', '-q', 'origin', `HEAD:refs/heads/${BASE}`)
  responde(`repos/${REPO}/pulls/8`, pedido({ head: { ref: 'ai/2026-11-24-y', sha: y, repo: { full_name: REPO } } }))
  responde(`repos/${REPO}/commits/${y}/check-runs`, { check_runs: [{ name: 'x', status: 'completed', conclusion: 'success' }] })
  responde(`repos/${REPO}/commits/${y}/status`, { statuses: [] })
  r = corre('8')
  verifica('conflito: recusa sem enviar nada', r.status === 2 && /conflitos/.test(r.stdout), r.stdout)

  // Publicação vermelha: sai com 3
  responde(`repos/${REPO}/actions/runs`, {
    workflow_runs: [{ name: 'build-ios', status: 'completed', conclusion: 'failure', html_url: 'u3' }],
  })
  r = corre('--ver-publicacao', 'abc')
  verifica('publicação vermelha: sai com 3 e diz qual', r.status === 3 && /build-ios/.test(r.stdout), r.stdout)
} finally {
  rmSync(raiz, { recursive: true, force: true })
}
console.log(falhas ? `${falhas} falharam` : 'todos passaram')
process.exit(falhas ? 1 : 0)
