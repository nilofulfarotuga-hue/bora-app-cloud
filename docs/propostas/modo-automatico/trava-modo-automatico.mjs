#!/usr/bin/env node
// =============================================================================
// Trava do modo automatico - gancho PreToolUse global (todas as pastas).
// Missao modo-automatico-seguro-2026-11-05. Regras: skill modo-automatico.
//
// So nega, nunca aprova: um "deny" de gancho vale em todos os modos, incluindo
// "Ignorar permissoes". Decide pelo AMBIENTE DE DESTINO e pelo comando real:
// texto entre aspas de um echo, de um grep ou de uma mensagem de commit nao conta.
// Destino que nao se consegue identificar conta como producao.
//
// Contrato: JSON do gancho no stdin; bloqueia com permissionDecision "deny" no stdout;
// sem resposta deixa seguir. Se rebentar, bloqueia (fail-closed).
// =============================================================================
import { execFileSync } from 'node:child_process'
import { appendFileSync, readFileSync, writeSync } from 'node:fs'
import { homedir } from 'node:os'
import { isAbsolute, join } from 'node:path'
import { pathToFileURL } from 'node:url'

const PROJETOS_PRODUCAO = new Set(['ojykpzwqrtusfeakzrna', 'tgdmgtmknbwhcqoxtjbs']) // Bora, Em Dia
const RAMO_ENSAIO = /^ai\/\d{4}-\d{2}-\d{2}-[\w.-]+$/
const SO_POR_RPC =
  'orders|tvde_rides|appointments|drivers|client_wallets|wallets|wallet_[a-z_]+|ledger|ledger_[a-z_]+|bora_tokens|driver_balances|payouts'

const CAMINHO_SEGREDO =
  /(^|[\\/])(\.env(?!\.(example|sample|template)$)[^\\/]*|\.dart_defines[^\\/]*|\.credentials\.json|key\.properties|[^\\/]*\.(jks|keystore|pem|p12|pfx)|id_(rsa|ed25519)[^\\/]*|\.supabase-token[^\\/]*|_segredos|\.dsh[\\/]secrets)([\\/]|$)/i
const SEGREDOS = [
  /\b[sr]k_live_[0-9a-zA-Z]{16,}/,
  /\bwhsec_[0-9a-zA-Z]{16,}/,
  /\bsb_secret_[0-9a-zA-Z_-]{16,}/,
  /\bgh[pousr]_[0-9a-zA-Z]{30,}/,
  /\bgithub_pat_[0-9a-zA-Z_]{30,}/,
  /\bAKIA[0-9A-Z]{16}\b/,
  /\bxox[abp]-[0-9a-zA-Z-]{20,}/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
]
const JWT = /\beyJ[0-9a-zA-Z_-]{10,}\.(eyJ[0-9a-zA-Z_-]{10,})\.[0-9a-zA-Z_-]{10,}/g

const A_TRAVA = /(^|[\\/])\.claude[\\/](settings(\.local)?\.json|hooks[\\/]trava-modo-automatico)/i
const INTOCAVEL = /(^|[\\/])(_?backups?|bkp_[^\\/]*|\.git|provas|_QUARENTENA)([\\/]|$)/i
const SCRIPT_PUBLICA = /(^|[\\/])(deploy|publica|publicar|release)[^\\/]*\.(sh|ps1|cmd|bat|py|mjs|js)$/i

const SO_LE_NOMES = new Set([
  'ls', 'dir', 'test', '[', 'test-path', 'get-childitem', 'gci', 'echo', 'printf', 'write-output',
  'write-host', 'flutter', 'dart', 'which', 'where', 'git',
])
const SO_LE = new Set([...SO_LE_NOMES, 'cat', 'type', 'get-content', 'gc', 'head', 'tail', 'grep', 'rg', 'findstr', 'select-string', 'diff', 'fc'])
const PROCURA = new Set(['grep', 'rg', 'egrep', 'fgrep', 'findstr', 'select-string', 'sls'])
const APAGA = new Set(['rm', 'del', 'erase', 'rd', 'rmdir', 'remove-item', 'ri', 'unlink', 'shred'])
const EMBRULHOS = new Set(['sudo', 'env', 'command', 'exec', 'time', 'nohup', 'call', 'start'])
const INTERPRETES = new Set(['bash', 'sh', 'zsh', 'dash', 'powershell', 'pwsh', 'python', 'python3', 'py', 'node', 'bun', 'cmd'])

// ---------- SQL ----------

// Tira comentarios e literais. Os corpos $$ ficam: um DO corre ja.
function limpaSql(sql) {
  let out = ''
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i]
    const d = sql[i + 1]
    if (c === '-' && d === '-') {
      while (i < sql.length && sql[i] !== '\n') i++
      out += ' '
    } else if (c === '/' && d === '*') {
      const f = sql.indexOf('*/', i + 2)
      i = f < 0 ? sql.length : f + 1
      out += ' '
    } else if (c === "'") {
      i++
      while (i < sql.length) {
        if (sql[i] === "'") {
          if (sql[i + 1] === "'") i++
          else break
        }
        i++
      }
      out += "''"
    } else out += c
  }
  return out.toLowerCase()
}

function avaliaSql(sql, ambiente) {
  if (ambiente !== 'producao') return null
  const s = limpaSql(sql)
  if (/\btruncate\b/.test(s)) return 'TRUNCATE em producao'
  if (/\bdrop\s+[a-z]/.test(s) && !/\balter\s+table\b[^;]*\bdrop\b/.test(s)) return 'DROP em producao'
  if (/\bdelete\s+from\b/.test(s)) return 'DELETE em producao: nunca se apagam dados de producao'
  const direto = new RegExp(`\\b(insert\\s+into|update|merge\\s+into)\\s+(only\\s+)?("?public"?\\s*\\.\\s*)?"?(${SO_POR_RPC})"?(?![\\w])`)
  const m = s.match(direto)
  if (m) return `escrita direta em ${m[4]}: usa as funcoes/RPC que ja existem no banco`
  if (/\bdo\s+(language\s+\w+\s+)?\$[a-z_]*\$[\s\S]*\bexecute\b/.test(s)) return 'DO com EXECUTE em producao: nao da para ler o que corre'
  const semBackup = s
    .replace(/\bcreate\s+table\s+(if\s+not\s+exists\s+)?("?public"?\.)?"?bkp_[a-z0-9_]+"?/g, ' ')
    .replace(/\balter\s+table\s+("?public"?\.)?"?bkp_[a-z0-9_]+"?\s+enable\s+row\s+level\s+security/g, ' ')
    .replace(/\bcreate\s+temp(orary)?\s+table\b/g, ' ')
  if (/\b(create|alter|grant|revoke|reindex)\b/.test(semBackup)) return 'mudanca de estrutura em producao: migration so em local/dev; publica a Claude.ai'
  return null
}

function ambienteConexao(texto) {
  if (/(supabase\.co|supabase\.com|pooler\.|rds\.amazonaws|neon\.tech)/i.test(texto)) return 'producao'
  if (/(localhost|127\.0\.0\.1|\[::1\]|host\.docker\.internal|:54322\b)/i.test(texto)) return 'local'
  return 'producao'
}

// ---------- ler o comando ----------

function segmentos(cmd) {
  const segs = []
  let toks = []
  let corpos = []
  let pend = []
  let cur = ''
  let tem = false
  let q = null
  const fechaTok = () => {
    if (tem) toks.push(cur)
    cur = ''
    tem = false
  }
  const fechaSeg = () => {
    fechaTok()
    if (toks.length) segs.push({ toks, corpos })
    toks = []
    corpos = []
  }
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i]
    const d = cmd[i + 1]
    if (q) {
      if (c === q) q = null
      else if (c === '\\' && q === '"' && (d === '"' || d === '\\')) {
        cur += d
        i++
      } else cur += c
      continue
    }
    if (c === '"' || c === "'") {
      q = c
      tem = true
      continue
    }
    if (c === '<' && d === '<') {
      const m = /^<<-?\s*(['"]?)([\w.-]+)\1/.exec(cmd.slice(i))
      if (m) {
        pend.push(m[2])
        i += m[0].length - 1
        continue
      }
    }
    if (c === '\n') {
      for (const tag of pend) {
        const resto = cmd.slice(i + 1)
        const fim = new RegExp(`^\\s*${tag}\\s*$`, 'm').exec(resto)
        corpos.push(fim ? resto.slice(0, fim.index) : resto)
        i += fim ? fim.index + fim[0].length : resto.length
      }
      pend = []
      fechaSeg()
      continue
    }
    if (c === '#' && !tem) {
      while (i + 1 < cmd.length && cmd[i + 1] !== '\n') i++
      continue
    }
    if (c === ';' || c === '|' || (c === '&' && cmd[i - 1] !== '>')) {
      fechaSeg()
      if (d === c) i++
      continue
    }
    if (/\s/.test(c)) {
      fechaTok()
      continue
    }
    cur += c
    tem = true
  }
  fechaSeg()
  return segs
}

const programa = t =>
  t.replace(/\\/g, '/').split('/').pop().replace(/@[\w.^~-]*$/, '').replace(/\.(exe|cmd|bat|ps1)$/i, '').toLowerCase()

function semPrefixos(toks) {
  const t = toks.slice()
  while (t.length) {
    if (/^\$env:/i.test(t[0])) {
      t.splice(0, t[1] === '=' ? 3 : 1)
      continue
    }
    if (/^[A-Za-z_]\w*=/.test(t[0]) || t[0].startsWith('-')) {
      t.shift()
      continue
    }
    const p = programa(t[0])
    if (EMBRULHOS.has(p) && t.length > 1) {
      t.shift()
      continue
    }
    if (p === 'npx' || p === 'bunx') {
      t.shift()
      while (t[0]?.startsWith('-')) t.shift()
      continue
    }
    if (/^(pnpm|yarn)$/.test(p) && /^(dlx|exec)$/.test(t[1] ?? '')) {
      t.splice(0, 2)
      continue
    }
    break
  }
  return t
}

function semRedir(args) {
  const out = []
  for (let k = 0; k < args.length; k++) {
    if (/^\d?>>?$/.test(args[k])) k++
    else if (!/^\d?>/.test(args[k])) out.push(args[k])
  }
  return out
}

function alvosRedir(args) {
  const out = []
  args.forEach((a, k) => {
    if (/^\d?>>?$/.test(a)) out.push(args[k + 1] ?? '')
    else {
      const m = a.match(/^\d?>>?(.+)$/)
      if (m && !m[1].startsWith('&')) out.push(m[1])
    }
  })
  return out
}

function valor(args, nome) {
  const k = args.indexOf(nome)
  if (k >= 0) return args[k + 1]
  const a = args.find(x => x.startsWith(`${nome}=`))
  return a ? a.slice(nome.length + 1) : undefined
}

function caminho(p, base) {
  const unix = p.replace(/^\/([a-zA-Z])\//, '$1:/')
  return isAbsolute(unix) ? unix : join(base, unix)
}

// ---------- segredos ----------

function segredoEm(txt) {
  for (const p of SEGREDOS) {
    const m = txt.match(p)
    if (m) return `${m[0].slice(0, 7)}...`
  }
  for (const m of txt.matchAll(JWT)) {
    try {
      if (Buffer.from(m[1], 'base64url').toString().includes('service_role')) return 'JWT service_role'
    } catch {
      // nao era um JWT a serio
    }
  }
  return null
}

function avaliaSegredoShell(prog, t) {
  const args = t.slice(1)
  for (const a of alvosRedir(args)) if (CAMINHO_SEGREDO.test(a)) return `escrever em ficheiro de segredos (${a})`
  if (prog === 'printenv' && !args.length) return 'mostrar as variaveis de ambiente'
  if (prog === 'env' && !args.length) return 'mostrar as variaveis de ambiente'
  if (/^(get-childitem|gci|dir|ls)$/.test(prog) && args.some(a => /^env:/i.test(a))) return 'mostrar as variaveis de ambiente'
  if (/^(echo|printf|write-output|write-host)$/.test(prog) && args.some(a => /\$(env:)?\{?[A-Z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)\b/i.test(a)))
    return 'mostrar um segredo guardado em variavel'
  if (prog === 'git') {
    const sub = args.find(a => !a.startsWith('-'))
    if (!/^(show|cat-file|diff|log|grep|archive|blame)$/.test(sub ?? '')) return null
  } else if (SO_LE_NOMES.has(prog)) return null
  let lista = semRedir(args)
  if (PROCURA.has(prog)) {
    const k = lista.findIndex(a => !a.startsWith('-'))
    lista = lista.filter((_, i) => i !== k)
  }
  for (const a of lista) {
    const v = a.replace(/^--?[\w-]+=/, '').replace(/^[^:\\/]+:(?![\\/])/, '')
    if (CAMINHO_SEGREDO.test(v)) return `ficheiro de segredos (${v}): usa so variaveis de ambiente`
  }
  return null
}

// ---------- git, gh e publicar ----------

function git(cwd, ...v) {
  return execFileSync('git', ['-C', cwd, ...v], {
    encoding: 'utf8',
    maxBuffer: 1 << 28,
    timeout: 20000,
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim()
}

function destinosDoPushSemRefspec(cwd) {
  const out = [git(cwd, 'rev-parse', '--abbrev-ref', 'HEAD')]
  try {
    out.push(git(cwd, 'rev-parse', '--abbrev-ref', '@{u}').replace(/^[^/]+\//, ''))
  } catch {
    // sem upstream: conta so o ramo atual
  }
  return out
}

function avaliaPush(a, cwd) {
  const pos = []
  for (const x of a) {
    if (/^--(force|force-with-lease|force-if-includes)(=|$)/.test(x) || /^-[a-zA-Z]*f[a-zA-Z]*$/.test(x)) return 'push forcado reescreve a historia'
    if (x === '--delete' || /^-[a-zA-Z]*d[a-zA-Z]*$/.test(x)) return 'push --delete apaga um ramo remoto'
    if (/^--(mirror|all|tags|prune)$/.test(x)) return `push ${x} mexe em mais do que o ramo de ensaio`
    if (!x.startsWith('-')) pos.push(x)
  }
  const especs = pos.slice(1)
  let alvos = []
  for (const e of especs) {
    if (e.startsWith('+')) return 'push forcado (refspec com +)'
    if (e.startsWith(':')) return 'push que apaga um ramo remoto'
    alvos.push(e.includes(':') ? e.split(':').pop() : e)
  }
  try {
    if (!alvos.length) alvos = destinosDoPushSemRefspec(cwd)
    alvos = alvos.map(r => (r === 'HEAD' ? git(cwd, 'rev-parse', '--abbrev-ref', 'HEAD') : r))
  } catch {
    return 'push sem destino escrito e nao consegui ver o ramo: escreve origin ai/AAAA-MM-DD-...'
  }
  for (const r of alvos) {
    const ramo = r.replace(/^refs\/heads\//, '')
    if (!RAMO_ENSAIO.test(ramo)) return `push para '${ramo}': so se empurra para ramo de ensaio ai/AAAA-MM-DD-descricao`
  }
  return null
}

function avaliaCommit(a, cwd) {
  if (a.includes('--no-verify') || a.includes('-n')) return 'commit a saltar os ganchos (--no-verify)'
  const tudo = a.includes('--all') || a.some(x => /^-[a-zA-Z]*a[a-zA-Z]*$/.test(x))
  const base = tudo ? ['diff', 'HEAD'] : ['diff', '--cached']
  let nomes
  let diff
  try {
    nomes = git(cwd, ...base, '--name-only')
    diff = git(cwd, ...base, '-U0', '--no-color')
  } catch {
    return null
  }
  for (const n of nomes.split('\n')) if (n && CAMINHO_SEGREDO.test(n)) return `ficheiro de segredos no commit (${n})`
  const novas = diff.split('\n').filter(l => l.startsWith('+') && !l.startsWith('+++'))
  const s = segredoEm(novas.join('\n'))
  return s ? `segredo no que vai no commit (${s})` : null
}

function avaliaGit(args, dir) {
  let cwd = dir
  let i = 0
  while (i < args.length && args[i].startsWith('-')) {
    if (args[i] === '-C') {
      cwd = caminho(args[i + 1] ?? '.', dir)
      i += 2
    } else if (args[i] === '-c') i += 2
    else i++
  }
  const sub = args[i]
  const a = semRedir(args.slice(i + 1))
  if (sub === 'push') return avaliaPush(a, cwd)
  if (sub === 'commit') return avaliaCommit(a, cwd)
  if (sub === 'filter-branch' || sub === 'filter-repo') return `git ${sub} reescreve a historia`
  if (sub === 'reflog' && a[0] === 'expire') return 'reflog expire apaga pontos de restauro'
  if (sub === 'update-ref' && a.includes('-d')) return 'update-ref -d apaga uma referencia'
  if (sub === 'branch' && (a.includes('-D') || (a.includes('--delete') && a.includes('--force')))) {
    const nomes = a.filter(x => !x.startsWith('-'))
    if (!nomes.every(n => RAMO_ENSAIO.test(n))) return 'branch -D fora dos ramos de ensaio ai/'
  }
  return null
}

function avaliaGh(a) {
  const [g, s] = a
  if (g === 'pr' && s === 'merge') return 'gh pr merge publica: quem junta ao ramo principal e a Claude.ai'
  if (g === 'release' && /^(create|upload|edit|delete)$/.test(s ?? '')) return 'gh release publica'
  if (g === 'workflow' && /^(run|enable|disable)$/.test(s ?? '')) return 'gh workflow mexe no CI que publica'
  if (g === 'repo' && /^(delete|rename|archive|edit)$/.test(s ?? '')) return `gh repo ${s}`
  if ((g === 'secret' || g === 'variable') && /^(set|delete)$/.test(s ?? '')) return `gh ${g} ${s}`
  if (g === 'api') {
    const metodo = valor(a, '-X') ?? valor(a, '--method') ?? ''
    const escreve = (metodo && !/^get$/i.test(metodo)) || a.some(x => /^(-f|-F|--field|--raw-field|--input)$/.test(x))
    if (/^delete$/i.test(metodo)) return 'gh api DELETE'
    const rota = a.slice(1).find(x => /repos\//.test(x)) ?? ''
    if (escreve && /\/(merges?|git\/refs|dispatches|releases|contents)\b/.test(rota)) return 'gh api a escrever no repositorio sem passar pelo ramo de ensaio'
  }
  return null
}

function avaliaWrangler(a) {
  const pos = a.filter(x => !x.startsWith('-'))
  if (pos[0] === 'pages' && /^(deploy|publish)$/.test(pos[1] ?? ''))
    return RAMO_ENSAIO.test(valor(a, '--branch') ?? '') ? null : 'wrangler pages deploy publica o site; pre-visualizacao so com --branch ai/...'
  if (/^(deploy|publish|rollback)$/.test(pos[0] ?? ''))
    return /^(dev|test|teste|staging|preview)$/i.test(valor(a, '--env') ?? '') ? null : 'wrangler deploy publica em producao'
  if (pos[0] === 'secret') return 'wrangler secret mexe nos segredos de producao'
  if (pos[0] === 'd1' && a.includes('--remote')) return 'wrangler d1 --remote mexe na base de producao'
  return null
}

function avaliaSupabase(a) {
  const pos = a.filter(x => !x.startsWith('-'))
  const k = pos.slice(0, 2).join(' ')
  const url = valor(a, '--db-url')
  const local = a.includes('--local') || (url !== undefined && ambienteConexao(url) === 'local')
  if (k === 'functions deploy' || k === 'functions delete') return 'Edge Function em producao: publica a Claude.ai'
  if (k === 'secrets set' || k === 'secrets unset') return 'segredos de producao'
  if ((k === 'db push' || k === 'migration repair') && !local) return 'migration em producao: so em local/dev'
  if ((k === 'db reset' || k === 'migration up') && a.includes('--linked')) return 'supabase --linked mexe na base de producao'
  if (k === 'projects delete') return 'apagar projeto'
  return null
}

function avaliaPsql(a, corpos, dir) {
  if (ambienteConexao(a.join(' ')) !== 'producao') return null
  const sqls = [...corpos]
  for (let k = 0; k < a.length; k++) {
    if (/^(-c|--command)$/.test(a[k])) sqls.push(a[k + 1] ?? '')
    else if (a[k].startsWith('--command=')) sqls.push(a[k].slice(10))
    else if (/^(-f|--file)$/.test(a[k])) {
      try {
        sqls.push(readFileSync(caminho(a[k + 1] ?? '', dir), 'utf8'))
      } catch {
        return 'psql -f em producao com ficheiro que nao consegui ler'
      }
    }
  }
  if (!sqls.length) return a.some(x => /^(-l|--list|-V|--version)$/.test(x)) ? null : 'psql em producao sem SQL visivel'
  for (const s of sqls) {
    const m = avaliaSql(s, 'producao')
    if (m) return m
  }
  return null
}

function avaliaStripe(a) {
  const pos = a.filter(x => !x.startsWith('-'))
  const chave = valor(a, '--api-key')
  const aoVivo = a.includes('--live') || (chave !== undefined && !/^sk_test|TEST/.test(chave))
  if (aoVivo && /^(payouts?|transfers?|topups?)$/.test(pos[0] ?? '') && !/^(list|retrieve)$/.test(pos[1] ?? ''))
    return 'Stripe ao vivo: transferencias, levantamentos e payouts nunca'
  return null
}

function avaliaHttp(a) {
  const txt = a.join(' ')
  if (!/api\.stripe\.com\/v1\/(payouts|transfers|topups)/i.test(txt)) return null
  const escreve = /(^|\s)(-d|--data[\w-]*|-F|--form|-Body)(\s|=)|(-X|--request|-Method)\s+(post|put|delete)/i.test(txt)
  return escreve && !/sk_test|TEST/.test(txt) ? 'Stripe ao vivo: transferencias, levantamentos e payouts nunca' : null
}

function avaliaPublicar(prog, a) {
  if (prog === 'vercel' && (a.includes('--prod') || a.includes('--production') || a[0] === 'promote')) return 'vercel --prod publica'
  if (prog === 'netlify' && a[0] === 'deploy' && a.includes('--prod')) return 'netlify --prod publica'
  if (prog === 'firebase' && a[0] === 'deploy') return 'firebase deploy publica'
  if (prog === 'fastlane' || prog === 'pilot') return 'envio para as lojas: publica a Claude.ai'
  if ((prog === 'flutter' || prog === 'dart') && a[0] === 'pub' && a[1] === 'publish') return 'pub publish'
  if (/^(npm|pnpm|yarn|bun)$/.test(prog)) {
    if (a[0] === 'publish') return 'npm publish'
    if (/^(run|run-script)$/.test(a[0] ?? '') && /deploy|publish|release/i.test(a[1] ?? '')) return `script ${a[1]} publica`
  }
  return null
}

// ---------- o comando inteiro ----------

function avaliaSegmento({ toks, corpos }, dir, fundo) {
  const t = semPrefixos(toks)
  if (!t.length) return { motivo: /^(env|printenv)$/.test(programa(toks[0] ?? '')) ? 'mostrar as variaveis de ambiente' : null }
  const prog = programa(t[0])
  const args = t.slice(1)
  const limpo = semRedir(args)

  if (/^(cd|set-location|sl|pushd)$/.test(prog)) return { dir: caminho(args[0] ?? '.', dir) }
  if (toks.length === 1 && /^(env|printenv|set)$/.test(programa(toks[0]))) return { motivo: 'mostrar as variaveis de ambiente' }

  let dentro = null
  if (/^(bash|sh|zsh|dash)$/.test(prog)) {
    const k = limpo.findIndex(a => /^-[a-z]*c$/.test(a))
    if (k >= 0) dentro = limpo[k + 1] ?? ''
  } else if (/^(powershell|pwsh)$/.test(prog)) {
    const k = limpo.findIndex(a => /^-c(ommand)?$/i.test(a))
    if (k >= 0) dentro = limpo.slice(k + 1).join(' ')
  } else if (prog === 'cmd') {
    const k = limpo.findIndex(a => /^\/c$/i.test(a))
    if (k >= 0) dentro = limpo.slice(k + 1).join(' ')
  } else if (/^(eval|invoke-expression|iex)$/.test(prog)) dentro = limpo.join(' ')
  if (dentro !== null) {
    const m = avaliaShell(dentro, dir, fundo + 1)
    if (m) return { motivo: m }
  }
  if (/^(bash|sh|zsh|dash|powershell|pwsh)$/.test(prog))
    for (const c of corpos) {
      const m = avaliaShell(c, dir, fundo + 1)
      if (m) return { motivo: m }
    }

  const candidatos = INTERPRETES.has(prog) ? limpo.slice(0, 3) : [t[0]]
  const script = candidatos.find(x => SCRIPT_PUBLICA.test(x))
  if (script) return { motivo: `script de publicacao (${script}): publica a Claude.ai` }

  if (APAGA.has(prog) && limpo.some(a => INTOCAVEL.test(a))) return { motivo: 'apagar backups, provas ou .git' }
  if (!SO_LE.has(prog) && t.some(a => A_TRAVA.test(a))) return { motivo: 'mexer nos settings ou na propria trava' }
  for (const a of alvosRedir(args)) if (A_TRAVA.test(a)) return { motivo: 'mexer nos settings ou na propria trava' }
  if (prog === 'setx' && /^CLAUDE/i.test(limpo[0] ?? '')) return { motivo: 'mexer nas variaveis do Claude Code' }
  if (t.some(a => /SetEnvironmentVariable/i.test(a)) && t.some(a => /CLAUDE/i.test(a))) return { motivo: 'mexer nas variaveis do Claude Code' }

  const seg = avaliaSegredoShell(prog, t)
  if (seg) return { motivo: seg }

  const motivo =
    (prog === 'git' && avaliaGit(args, dir)) ||
    (prog === 'gh' && avaliaGh(limpo)) ||
    (prog === 'wrangler' && avaliaWrangler(limpo)) ||
    (prog === 'supabase' && avaliaSupabase(limpo)) ||
    (prog === 'psql' && avaliaPsql(limpo, corpos, dir)) ||
    (prog === 'stripe' && avaliaStripe(limpo)) ||
    (/^(curl|wget|http|invoke-webrequest|iwr|invoke-restmethod|irm)$/.test(prog) && avaliaHttp(limpo)) ||
    avaliaPublicar(prog, limpo)
  return { motivo: motivo || null }
}

function avaliaShell(cmd, cwd, fundo = 0) {
  if (fundo > 4) return 'comando demasiado encadeado para ler'
  let dir = cwd
  for (const seg of segmentos(cmd)) {
    const v = avaliaSegmento(seg, dir, fundo)
    if (v?.motivo) return v.motivo
    if (v?.dir) dir = v.dir
  }
  for (const m of cmd.matchAll(/\$\(([^()]+)\)/g)) {
    const r = avaliaShell(m[1], dir, fundo + 1)
    if (r) return r
  }
  return null
}

function avaliaFicheiro(tool, i) {
  const alvos = [i.file_path, i.notebook_path, i.path, i.glob].filter(x => typeof x === 'string')
  for (const a of alvos) if (CAMINHO_SEGREDO.test(a)) return `ficheiro de segredos (${a}): usa so variaveis de ambiente`
  if (tool === 'Read' || tool === 'Grep') return null
  for (const a of alvos) if (A_TRAVA.test(a)) return 'mexer nos settings ou na propria trava'
  const edits = Array.isArray(i.edits) ? i.edits.map(e => e?.new_string) : []
  const novo = [i.content, i.new_string, i.new_source, ...edits].filter(x => typeof x === 'string').join('\n')
  const s = segredoEm(novo)
  return s ? `segredo em texto claro (${s}): usa variavel de ambiente` : null
}

// Ferramentas MCP que correm comandos contam como terminal.
function avaliaCodigo(codigo, cwd) {
  for (const m of String(codigo).matchAll(/['"`]((?:git|gh|psql|supabase|npx|wrangler|vercel|firebase|stripe)\s[^'"`]*)['"`]/g)) {
    const r = avaliaShell(m[1].replace(/\$\{[^}]*\}/g, 'X'), cwd, 1)
    if (r) return r
  }
  return null
}

function avaliaMcp(nome, i, cwd) {
  const base = nome.split('__').pop()
  if (base === 'execute_sql' || base === 'apply_migration') {
    const ambiente = !i.project_id || PROJETOS_PRODUCAO.has(i.project_id) ? 'producao' : 'teste'
    if (base === 'apply_migration' && ambiente === 'producao') return 'migration em producao: so em local/dev; publica a Claude.ai'
    return avaliaSql(String(i.query ?? ''), ambiente)
  }
  if (/^(deploy|publish)_/.test(base)) return `${base}: publica a Claude.ai`
  if (/^(merge_branch|create_edge_function_secret|pause_project|restore_project|confirm_project_publication_review)$/.test(base))
    return `${base} mexe em producao: publica a Claude.ai`
  if (/stripe/i.test(nome) && /(payout|transfer)/i.test(base) && !/^(list|get|retrieve)/.test(base))
    return 'Stripe: transferencias, levantamentos e payouts nunca'
  if (base === 'ctx_batch_execute') {
    for (const c of Array.isArray(i.commands) ? i.commands : []) {
      const r = avaliaShell(String(c?.command ?? ''), cwd)
      if (r) return r
    }
    return null
  }
  if (base === 'ctx_execute' || base === 'ctx_execute_file')
    return i.language === 'shell' ? avaliaShell(String(i.code ?? ''), cwd) : avaliaCodigo(i.code ?? '', cwd)
  if (typeof i.command === 'string') return avaliaShell(i.command, cwd)
  return null
}

export function avalia(tool, input, ctx = {}) {
  const cwd = ctx.cwd || process.cwd()
  if (tool === 'Bash' || tool === 'PowerShell') return avaliaShell(String(input.command ?? ''), cwd)
  if (/^(Read|Grep|Edit|Write|MultiEdit|NotebookEdit)$/.test(tool)) return avaliaFicheiro(tool, input)
  if (String(tool).startsWith('mcp__')) return avaliaMcp(tool, input, cwd)
  return null
}

// ---------- gancho ----------

function bloqueia(motivo, dados) {
  try {
    const linha = { ts: new Date().toISOString(), sessao: dados?.session_id, tool: dados?.tool_name, motivo }
    appendFileSync(join(homedir(), '.claude', 'trava-modo-automatico.log'), `${JSON.stringify(linha)}\n`)
  } catch {
    // um registo que falha nunca abre a trava
  }
  const texto = `TRAVA do modo automatico: BLOQUEADO - ${motivo}. Nao contornes: regista no e2e_log, reporta e segue com o resto.`
  // Prova de 05/11: com a tranca a aprovar o Read, o exit 2 nao travou a leitura; o deny em JSON e que manda.
  // writeSync porque no Windows um pipe e assincrono e o process.exit cortava a resposta.
  writeSync(1, JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: texto } }))
  process.exit(0)
}

async function main() {
  let raw = ''
  for await (const c of process.stdin) raw += c
  let dados
  try {
    dados = JSON.parse(raw)
    const motivo = avalia(dados.tool_name, dados.tool_input ?? {}, { cwd: dados.cwd })
    if (motivo) bloqueia(motivo, dados)
  } catch (e) {
    bloqueia(`a trava falhou (${e?.message ?? e})`, dados)
  }
  process.exit(0)
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
