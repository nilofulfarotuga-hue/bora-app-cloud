// =============================================================================
// bora-mods · MOD 4 · bora-ci — a app a construir, dentro da sessão.
//  /ci abre o painel; 30 s depois de um git push da sessão abre sozinho.
//  Lê os últimos runs de Android, web e iOS. Caminho: gh (se existir) ->
//  API do GitHub com GITHUB_TOKEN/GH_TOKEN -> credencial do Git do PC ->
//  API sem chave -> "sem acesso ao GitHub".
// =============================================================================
import type { EngineInterface, On } from 'claude-code'

const REPO = 'nilofulfarotuga-hue/bora-app-cloud'
const RAMO = 'autonomous-night-2026-04-29'
const PAINEL = 'bora-ci'
export const WORKFLOWS = [
  { ficheiro: 'build_android.yml', nome: 'Android (Play Store)' },
  { ficheiro: 'build_web_deploy.yml', nome: 'Web' },
  { ficheiro: 'build_ios.yml', nome: 'iPhone' },
]

export type Run = {
  id: number
  workflow: string
  estado: string // queued / in_progress / success / failure / ...
  criado: string
  url: string
  titulo: string
}

export const ci = {
  runs: [] as Run[],
  versionCode: '?' as string,
  erro: '' as string,
  via: '' as string,
  atualizado: 0,
  ateQuando: 0, // atualiza sozinho até esta hora (depois de um push ou de /ci)
}

async function token($: EngineInterface): Promise<string | null> {
  const doAmbiente = (await $.env.get('GITHUB_TOKEN').catch(() => undefined)) || (await $.env.get('GH_TOKEN').catch(() => undefined))
  if (doAmbiente) return doAmbiente
  try {
    const r = await $.process.run(['git', 'credential', 'fill'], {
      stdin: 'protocol=https\nhost=github.com\n\n',
      timeoutMs: 8000,
      env: { GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never' },
    })
    const m = r.stdout.match(/^password=(.+)$/m)
    return r.exitCode === 0 && m ? m[1].trim() : null
  } catch {
    return null
  }
}

async function api($: EngineInterface, caminho: string, chave: string | null): Promise<unknown> {
  const headers: Record<string, string> = { Accept: 'application/vnd.github+json', 'User-Agent': 'bora-mods' }
  if (chave) headers.Authorization = `Bearer ${chave}`
  const r = await $.http.fetch(`https://api.github.com/repos/${REPO}/${caminho}`, { headers })
  if (!r.ok) throw new Error(`GitHub ${r.status}`)
  return JSON.parse(r.text)
}

type RunApi = { id: number; status: string; conclusion: string | null; created_at: string; html_url: string; display_title: string }

function estadoDe(r: RunApi): string {
  return r.status === 'completed' ? (r.conclusion ?? 'completed') : r.status
}

async function viaGh($: EngineInterface): Promise<Run[] | null> {
  try {
    const out: Run[] = []
    for (const w of WORKFLOWS) {
      const r = await $.process.run(
        ['gh', 'run', 'list', '--repo', REPO, '--workflow', w.ficheiro, '--branch', RAMO, '--limit', '3',
          '--json', 'databaseId,status,conclusion,createdAt,url,displayTitle'],
        { timeoutMs: 15_000 },
      )
      if (r.exitCode !== 0) return null
      for (const x of JSON.parse(r.stdout) as { databaseId: number; status: string; conclusion: string; createdAt: string; url: string; displayTitle: string }[]) {
        out.push({ id: x.databaseId, workflow: w.nome, estado: x.status === 'completed' ? x.conclusion : x.status, criado: x.createdAt, url: x.url, titulo: x.displayTitle })
      }
    }
    return out
  } catch {
    return null
  }
}

export async function atualizar($: EngineInterface): Promise<void> {
  ci.atualizado = await $.clock.now()
  const gh = await viaGh($)
  if (gh) {
    ci.runs = gh
    ci.via = 'gh'
    ci.erro = ''
  } else {
    const chave = await token($)
    try {
      const out: Run[] = []
      for (const w of WORKFLOWS) {
        const j = (await api($, `actions/workflows/${w.ficheiro}/runs?branch=${RAMO}&per_page=3`, chave)) as { workflow_runs?: RunApi[] }
        for (const r of j.workflow_runs ?? []) {
          out.push({ id: r.id, workflow: w.nome, estado: estadoDe(r), criado: r.created_at, url: r.html_url, titulo: r.display_title })
        }
      }
      ci.runs = out
      ci.via = chave ? 'API do GitHub (credencial do PC)' : 'API do GitHub (sem chave)'
      ci.erro = ''
      const commits = (await api($, `commits?sha=${RAMO}&per_page=30`, chave)) as { commit: { message: string } }[]
      const bump = commits.map(c => c.commit.message.match(/bump versionCode to (\d+)/)).find(Boolean)
      if (bump) ci.versionCode = bump[1]
    } catch (err) {
      ci.erro = `sem acesso ao GitHub (${(err as Error).message})`
    }
  }
  $.ui.invalidate('ui.render')
}

async function abrirPainel($: EngineInterface): Promise<void> {
  ci.ateQuando = (await $.clock.now()) + 30 * 60_000
  await atualizar($)
  await $.ui.open({ id: PAINEL, title: 'bora-ci' })
}

async function verLog($: EngineInterface, run: Run): Promise<void> {
  try {
    const r = await $.process.run(['gh', 'run', 'view', String(run.id), '--repo', REPO, '--log-failed'], { timeoutMs: 30_000 })
    if (r.exitCode === 0) {
      for (const l of r.stdout.split('\n').slice(-40)) $.ui.log(l)
      return
    }
  } catch {
    // sem gh: cai para a API
  }
  try {
    const j = (await api($, `actions/runs/${run.id}/jobs`, await token($))) as {
      jobs: { name: string; conclusion: string | null; steps?: { name: string; conclusion: string | null }[] }[]
    }
    for (const job of j.jobs.filter(x => x.conclusion === 'failure')) {
      $.ui.log(`bora-ci: ${run.workflow} · falhou o job "${job.name}"`)
      for (const s of (job.steps ?? []).filter(x => x.conclusion === 'failure')) $.ui.log(`  passo que falhou: ${s.name}`)
    }
    $.ui.log(`bora-ci: log completo em ${run.url}`)
  } catch (err) {
    $.ui.log(`bora-ci: não consegui ler o log (${(err as Error).message}). Abre ${run.url}`)
  }
}

function decorrido(iso: string, agora: number): string {
  const min = Math.max(0, Math.round((agora - Date.parse(iso)) / 60_000))
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`
}

const COR: Record<string, string> = { success: 'green', failure: 'red', cancelled: 'gray', in_progress: 'yellow', queued: 'yellow' }

// filtro "apanha tudo": o gancho sem filtro de cada evento é o da tranca
const TUDO = /[\s\S]*/

export function registarCi(on: On): void {
  on('session.start', { cwd: TUDO }, async ($, e, next) => {
    try {
      await $.command.register({ name: 'ci', description: 'bora-ci: estado dos builds Android, web e iPhone' })
    } catch {
      // segue sem o comando
    }
    $.clock.every(120_000, () => {
      void (async () => {
        if ((await $.clock.now()) < ci.ateQuando) await atualizar($)
      })().catch(() => undefined)
    })
    return next(e)
  })

  // depois de um git push que correu, abre o painel 30 s depois
  on('tool.call', { tool: ['Bash', 'PowerShell'] }, async ($, e, next) => {
    const r = await next(e)
    const comando = (e as { command?: unknown }).command
    if (typeof comando === 'string' && /\bgit\s+push\b/.test(comando) && r.deny === undefined && r.isError !== true) {
      $.clock.after(30_000, () => {
        void abrirPainel($).catch(() => undefined)
      })
    }
    return r
  })

  on('command.run', { command: 'ci' }, async $ => {
    await abrirPainel($)
    return { text: ci.erro ? `bora-ci: ${ci.erro}` : `bora-ci: ${ci.runs.length} runs lidos (${ci.via}). Painel aberto.` }
  })

  on('ui.render', { component: 'Pane', requestId: PAINEL }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const agora = await $.clock.now()
    return (
      <Box flexDirection="column">
        <Text bold>Builds · ramo {RAMO} · versionCode {ci.versionCode}</Text>
        {ci.erro !== '' && <Text color="red">{ci.erro}</Text>}
        {ci.runs.length === 0 && ci.erro === '' && <Text dimColor>A ler…</Text>}
        {ci.runs.map(run => (
          <Box key={`r${run.id}`} flexDirection="column">
            <Text color={COR[run.estado] ?? 'white'}>
              {run.workflow}: {run.estado} · há {decorrido(run.criado, agora)} · {run.titulo.slice(0, 50)}
            </Text>
            <Text dimColor>{run.url}</Text>
            {run.estado === 'failure' && (
              <Box>
                <Button key={`log${run.id}`} label="Ver log" onPress={() => verLog($, run)} />
                <Button
                  key={`mandar${run.id}`}
                  label="Mandar ao Claude"
                  onPress={() =>
                    $.prompt.submit({
                      text: `bora-ci: o build ${run.workflow} falhou (${run.url}). Lê o log, encontra a causa e propõe o conserto. Não faças push sem eu dizer.`,
                    })
                  }
                />
              </Box>
            )}
          </Box>
        ))}
        <Text dimColor>Play Store + web + iPhone: as três têm de sair iguais (regra 21/09). · via {ci.via || '—'}</Text>
      </Box>
    )
  })
}
