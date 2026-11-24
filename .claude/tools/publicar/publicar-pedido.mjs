#!/usr/bin/env node
// =============================================================================
// publicar-pedido.mjs — o único caminho de um agente para o ramo principal.
//
// Ordem do Danilo (24/11/2026, 07:47): "quero que o Claude Code publique. Ele faz toda a
// missão, verifica toda a missão e publica, quando tiver certeza que está tudo certo.
// O Claude Code, o Hermes e o Dipsy têm de publicar também."
//
// Para ter a certeza, este script só junta um pedido de revisão quando:
//   1. o pedido está aberto e aponta para o ramo principal;
//   2. TODOS os testes automáticos (check-runs) do último commit acabaram verdes;
//   3. a junção normal (sem forçar) não tem conflitos.
// Depois envia (push normal) e acompanha a publicação: Android, web e iPhone.
//
// Uso:
//   node .claude/tools/publicar/publicar-pedido.mjs <numero> [--repo dono/repo]
//        [--esperar-ci]            espera os testes que ainda correm (até 150 min)
//        [--nao-esperar-publicacao] envia e sai sem esperar pelas 3 plataformas
//        [--simular]               faz tudo menos enviar
//        [--sem-ci-testado-local]  só para repositórios SEM testes no GitHub: o agente
//                                  declara que testou localmente (fica escrito no commit)
//   node .claude/tools/publicar/publicar-pedido.mjs --ver-publicacao <sha> [--repo dono/repo]
//
// Saída: 0 publicado e verde · 2 recusado antes de juntar · 3 publicação falhou · 1 erro.
// Fala com o GitHub pelo `gh` quando existe; senão pela API com GITHUB_TOKEN/GH_TOKEN, ou
// sem token num repositório público. Nunca mostra tokens.
// =============================================================================
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const VERDE = new Set(['success', 'neutral', 'skipped'])
const args = process.argv.slice(2)
const tem = n => args.includes(n)
const valor = n => {
  const k = args.indexOf(n)
  return k >= 0 ? args[k + 1] : undefined
}
// Só os testes mudam a escala do tempo (PUBLICAR_ESCALA_TEMPO=0.001): nunca para saltar esperas a sério.
const ESCALA = Number(process.env.PUBLICAR_ESCALA_TEMPO ?? 1) || 1
const dormir = ms => new Promise(r => setTimeout(r, ms * ESCALA))
const diz = t => console.log(`[publicar] ${t}`)
const falha = (codigo, t) => {
  console.log(`[publicar] PAROU: ${t}`)
  process.exit(codigo)
}

function git(cwd, ...a) {
  return execFileSync('git', ['-C', cwd, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 28 }).trim()
}

function temGh() {
  try {
    execFileSync('gh', ['--version'], { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}
const GH = temGh()

async function api(rota) {
  if (GH) {
    const out = execFileSync('gh', ['api', rota], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 26 })
    return JSON.parse(out)
  }
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN
  const r = await fetch(`https://api.github.com/${rota}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'bora-publicar-pedido',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  })
  if (!r.ok) throw new Error(`GitHub ${r.status} em ${rota.split('?')[0]}`)
  return r.json()
}

function repoDoRemoto() {
  const url = git(process.cwd(), 'remote', 'get-url', 'origin')
  const m = url.match(/github\.com[:/]([^/]+\/[^/.]+?)(\.git)?$/)
  if (!m) falha(1, `não percebi o repositório do remoto origin (${url.replace(/\/\/[^@]*@/, '//')}); usa --repo dono/repo`)
  return m[1]
}

async function testesDoCommit(repo, sha) {
  const runs = []
  for (let pagina = 1; pagina <= 5; pagina++) {
    const j = await api(`repos/${repo}/commits/${sha}/check-runs?per_page=100&page=${pagina}`)
    runs.push(...(j.check_runs ?? []))
    if ((j.check_runs ?? []).length < 100) break
  }
  const estado = await api(`repos/${repo}/commits/${sha}/status`)
  const estados = (estado.statuses ?? []).map(s => ({ name: s.context, status: s.state === 'pending' ? 'in_progress' : 'completed', conclusion: s.state }))
  return [...runs.map(r => ({ name: r.name, status: r.status, conclusion: r.conclusion })), ...estados]
}

async function workflowsExistem(repo) {
  try {
    const j = await api(`repos/${repo}/actions/workflows?per_page=1`)
    return (j.total_count ?? 0) > 0
  } catch {
    return true // na dúvida conta como tendo CI: não se publica às cegas
  }
}

async function verPublicacao(repo, sha, esperar) {
  const limite = Date.now() + 200 * 60_000
  let vistos = 0
  for (;;) {
    let corridas = []
    try {
      corridas = (await api(`repos/${repo}/actions/runs?head_sha=${sha}&per_page=50`)).workflow_runs ?? []
    } catch (e) {
      diz(`não consegui ler as corridas (${e.message}); tento outra vez`)
    }
    const porAcabar = corridas.filter(c => c.status !== 'completed')
    if (corridas.length && corridas.length === vistos && !porAcabar.length) {
      const mas = corridas.filter(c => !VERDE.has(c.conclusion))
      for (const c of corridas) diz(`${c.conclusion === 'success' ? 'VERDE' : String(c.conclusion).toUpperCase()} · ${c.name} · ${c.html_url}`)
      if (mas.length) falha(3, `a publicação falhou em: ${mas.map(c => c.name).join(', ')}. Abre o log, encontra a causa, corrige noutro pedido.`)
      diz('Publicação acabada e verde. Confere a app nas 3 (Android, iPhone, web) antes de dizer que está feito.')
      return
    }
    const estaveis = corridas.length && !porAcabar.length
    vistos = corridas.length
    if (!esperar) {
      for (const c of corridas) diz(`${c.status} · ${c.name} · ${c.html_url}`)
      diz(`Ver depois: node .claude/tools/publicar/publicar-pedido.mjs --ver-publicacao ${sha}`)
      return
    }
    if (Date.now() > limite) falha(3, `a publicação ainda corre ao fim de 200 min: ${porAcabar.map(c => c.name).join(', ')}`)
    // tudo acabado: só se confirma que não arrancou mais nenhuma (30 s); senão espera 3 min
    await dormir(estaveis ? 30_000 : corridas.length ? 180_000 : 60_000)
  }
}

async function main() {
  const repo = valor('--repo') ?? repoDoRemoto()
  if (tem('--ver-publicacao')) return verPublicacao(repo, valor('--ver-publicacao'), true)

  const numero = Number(args.find(a => /^\d+$/.test(a)))
  if (!numero) falha(1, 'falta o número do pedido de revisão')

  const pr = await api(`repos/${repo}/pulls/${numero}`)
  if (pr.state !== 'open') falha(2, `o pedido #${numero} não está aberto (${pr.merged ? 'já foi juntado' : pr.state})`)
  const base = pr.base.ref
  const cabeca = pr.head.sha
  const repoPrincipal = (await api(`repos/${repo}`)).default_branch
  diz(`pedido #${numero}: ${pr.head.ref} → ${base} · commit ${cabeca.slice(0, 8)} · "${pr.title}"`)
  if (pr.head.repo?.full_name !== repo) falha(2, 'o pedido vem de outro repositório (fork): não se publica daqui')

  // 1) Testes verdes no commit exato que se vai juntar
  const limiteCi = Date.now() + 150 * 60_000
  for (;;) {
    const testes = await testesDoCommit(repo, cabeca)
    if (!testes.length) {
      if (await workflowsExistem(repo)) {
        if (!tem('--esperar-ci') || Date.now() > limiteCi) falha(2, 'o commit ainda não tem testes automáticos; espera que arranquem (--esperar-ci)')
        await dormir(60_000)
        continue
      }
      if (!tem('--sem-ci-testado-local')) falha(2, 'este repositório não tem testes no GitHub: testa localmente e volta a correr com --sem-ci-testado-local')
      diz('sem testes no GitHub: o agente declarou que testou localmente')
      break
    }
    const vermelhos = testes.filter(t => t.status === 'completed' && !VERDE.has(t.conclusion))
    if (vermelhos.length) falha(2, `testes vermelhos: ${vermelhos.map(t => `${t.name} (${t.conclusion})`).join(', ')}. Corrige a causa e envia outra vez.`)
    const aCorrer = testes.filter(t => t.status !== 'completed')
    if (!aCorrer.length) {
      diz(`testes todos verdes (${testes.length}): ${testes.map(t => t.name).join(', ')}`)
      break
    }
    if (!tem('--esperar-ci')) falha(2, `ainda a correr: ${aCorrer.map(t => t.name).join(', ')}. Volta mais tarde ou usa --esperar-ci`)
    if (Date.now() > limiteCi) falha(2, `os testes ainda correm ao fim de 150 min: ${aCorrer.map(t => t.name).join(', ')}`)
    diz(`à espera de: ${aCorrer.map(t => t.name).join(', ')}`)
    await dormir(180_000)
  }

  // 2) Juntar numa pasta à parte, sem mexer no trabalho de ninguém
  const raiz = git(process.cwd(), 'rev-parse', '--show-toplevel')
  git(raiz, 'fetch', '-q', 'origin', `+refs/heads/${base}:refs/remotes/origin/${base}`, `+refs/pull/${numero}/head:refs/remotes/origin/pr-${numero}`)
  const headLocal = git(raiz, 'rev-parse', `refs/remotes/origin/pr-${numero}`)
  if (headLocal !== cabeca) falha(2, `o pedido mudou durante a verificação (${headLocal.slice(0, 8)} ≠ ${cabeca.slice(0, 8)}): corre outra vez`)
  const pasta = mkdtempSync(join(tmpdir(), `publicar-${numero}-`))
  let novo
  try {
    git(raiz, 'worktree', 'add', '-q', '--detach', pasta, `refs/remotes/origin/${base}`)
    const msg = [
      `Merge pull request #${numero} from ${pr.head.ref}`,
      '',
      pr.title,
      '',
      `Juntado por .claude/tools/publicar/publicar-pedido.mjs depois de os testes do commit ${cabeca.slice(0, 8)} acabarem verdes.`,
      ...(tem('--sem-ci-testado-local') ? ['Repositório sem testes no GitHub: o agente declarou que testou localmente.'] : []),
    ].join('\n')
    try {
      git(pasta, 'merge', '--no-ff', '-q', '-m', msg, cabeca)
    } catch {
      try {
        git(pasta, 'merge', '--abort')
      } catch {}
      falha(2, `a junção de #${numero} com ${base} tem conflitos: põe o ramo em dia com ${base} (merge normal), espera o CI e corre outra vez`)
    }
    novo = git(pasta, 'rev-parse', 'HEAD')
    if (tem('--simular')) {
      diz(`SIMULAÇÃO: junção ${novo.slice(0, 8)} feita localmente e NÃO enviada`)
      return
    }
    // 3) Enviar: push normal, nunca forçado. Se o ramo principal andou entretanto, recusa.
    try {
      git(pasta, 'push', 'origin', `HEAD:refs/heads/${base}`)
    } catch (e) {
      falha(2, `o GitHub recusou o envio (o ramo ${base} mudou entretanto?): corre outra vez. ${String(e.stderr ?? '').split('\n')[0]}`)
    }
  } finally {
    try {
      git(raiz, 'worktree', 'remove', '--force', pasta)
    } catch {
      rmSync(pasta, { recursive: true, force: true })
    }
  }
  diz(`PUBLICADO: #${numero} juntado em ${base} (${novo.slice(0, 8)}).${base === repoPrincipal ? '' : ` Atenção: ${base} não é o ramo por defeito (${repoPrincipal}).`}`)

  // 4) Acompanhar as 3 plataformas
  await dormir(20_000)
  await verPublicacao(repo, novo, !tem('--nao-esperar-publicacao'))
}

main().catch(e => falha(1, e?.message ?? String(e)))
