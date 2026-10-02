// =============================================================================
// bora-mods · regras.ts — as regras PURAS da tranca (sem $, sem ficheiros).
// Tudo o que decide "nega / pergunta / aprova" vive aqui, para os testes
// poderem chamar cada regra sem sessão. O tranca.ts só lê as listas, chama
// estas funções e regista o resultado.
// =============================================================================

export type Zona = { padrao: string; motivo: string }

export type Zonas = {
  ficheiros: Zona[]
  migracoes: { padrao_caminho: string; padrao_conteudo: string; motivo: string }
  segredos_caminho: string
  funcoes_sql_extra: string[]
  tabelas_dinheiro_extra: string[]
  tabelas_sem_dml_direto: string[]
}

// Listas tiradas do protege-banco.sh em tempo real (um só sítio de verdade).
export type ListasBanco = {
  protslug: string | null // null = não se conseguiu ler -> fail-closed nos deploys
  moneyfn: string
  fintable: string
}

export type Contexto = {
  zonas: Zonas | null // null = zonas-vermelhas.json ilegível -> fail-closed nas edições
  banco: ListasBanco
  raiz: string // raiz do repositório, com barras '/'
  pubspecAtual?: string | null // conteúdo atual do pubspec.yaml (só para Write nele)
}

export type Veredito =
  | { acao: 'nega'; motivo: string }
  | { acao: 'pergunta'; motivo: string; pergunta: string }
  | { acao: 'segue' }

const SEGUE: Veredito = { acao: 'segue' }
const nega = (motivo: string): Veredito => ({ acao: 'nega', motivo })

// ---------------------------------------------------------------------------
// Utilitários
// ---------------------------------------------------------------------------

export function normaliza(caminho: string): string {
  return caminho.replace(/\\/g, '/').replace(/\/+/g, '/')
}

export function relativo(caminho: string, raiz: string): string | null {
  const c = normaliza(caminho)
  const r = normaliza(raiz).replace(/\/$/, '')
  if (!/^([a-zA-Z]:)?\//.test(c)) return c.replace(/^\.\//, '')
  if (r !== '' && c.toLowerCase().startsWith(r.toLowerCase() + '/')) return c.slice(r.length + 1)
  return null // fora do repositório
}

/** Lê uma variável `NOME='...'` de um script shell. */
export function lerVarShell(texto: string, nome: string): string | null {
  const m = texto.match(new RegExp(`^${nome}='([^']+)'`, 'm'))
  return m ? m[1] : null
}

/** Esconde segredos de um texto antes de o escrever no log. */
export function semSegredos(texto: string): string {
  return texto
    .replace(/\b(sk[-_](live|test|ant)[-_][A-Za-z0-9_\-]{6,})/g, '***')
    .replace(/\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-\.]+/g, '***')
    .replace(/((authorization|x-api-key|apikey)\s*:\s*)(bearer\s+)?[^\s"']+/gi, '$1***')
    .replace(/(\b[A-Z0-9_]*(SECRET|TOKEN|KEY|PASSWORD)[A-Z0-9_]*\s*[=:]\s*["']?)[^\s"']{6,}/g, '$1***')
    .replace(/\b[A-Za-z0-9_\-]{40,}\b/g, '***')
}

/** Segredo literal num texto novo (ficheiro ou comando). */
export function temSegredoLiteral(texto: string): string | null {
  if (/\bsk_live_[A-Za-z0-9]{10,}/.test(texto)) return 'chave Stripe LIVE (sk_live_) em texto claro'
  if (/\bsk-ant-[A-Za-z0-9_\-]{10,}/.test(texto)) return 'chave Anthropic (sk-ant-) em texto claro'
  if (/\beyJhbGciOi[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}/.test(texto)) return 'token JWT em texto claro'
  const m = texto.match(/\b([A-Z0-9_]*(SECRET|TOKEN|KEY)[A-Z0-9_]*)\s*=\s*["']?([^\s"'$%<{][^\s"']{7,})/)
  if (m && !/^(your|seu|sua|xxx|changeme|example|exemplo|placeholder)/i.test(m[3])) {
    return `${m[1]}= com valor em texto claro`
  }
  return null
}

// ---------------------------------------------------------------------------
// Comandos de terminal (Bash e PowerShell)
// ---------------------------------------------------------------------------

const SHELLS = /^(bash|sh|zsh|pwsh|powershell|cmd)(\.exe)?$/i

/**
 * Parte um comando em segmentos já sem texto citado. Texto entre aspas e corpos
 * de heredoc NÃO contam como comando (é isto que mata o falso positivo do
 * `git commit -F - && git push`), excepto quando são entregues a uma shell
 * (`bash -c "..."`, `... | bash <<EOF`), que voltam a ser analisados.
 */
export function segmentos(comando: string): string[][] {
  const extra: string[] = []
  // heredocs: o corpo sai do comando; se a linha entrega a uma shell, o corpo é comando
  let c = comando.replace(
    /^([^\n]*?)<<-?\s*(['"]?)(\w+)\2([^\n]*)\n([\s\S]*?)\n\s*\3\s*(?=\n|$)/gm,
    (_m, antes: string, _q, _tag, depois: string, corpo: string) => {
      if (/\b(bash|sh|zsh|pwsh|powershell)\b/i.test(antes + depois)) extra.push(corpo)
      return `${antes} HEREDOC ${depois}`
    },
  )
  // `bash -c "..."` / `powershell -Command "..."`: o texto citado é comando
  c.replace(
    /\b(bash|sh|zsh|pwsh|powershell|cmd)(\.exe)?\s+(-c|-command|\/c)\s+(["'])([\s\S]*?)\4/gi,
    (_m, _s, _e, _f, _q, dentro: string) => {
      extra.push(dentro)
      return ''
    },
  )
  // tira texto citado (mensagens de commit, SQL dentro de aspas, etc.)
  c = c.replace(/"(?:[^"\\]|\\.)*"/g, ' Q ').replace(/'[^']*'/g, ' Q ')
  const partes = [c, ...extra]
    .join('\n')
    .split(/&&|\|\||[;\n|&]/)
    .map(s => s.trim())
    .filter(s => s !== '')
  return partes.map(limpaPrefixos)
}

function limpaPrefixos(segmento: string): string[] {
  const t = segmento.split(/\s+/).filter(x => x !== '')
  let i = 0
  while (i < t.length) {
    const x = t[i]
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(x)) i++
    else if (/^(sudo|command|exec|nohup|time|env|call|&)$/i.test(x)) i++
    else if (/^timeout$/i.test(x)) i += /^-/.test(t[i + 1] ?? '') ? 3 : 2
    else break
  }
  return t.slice(i)
}

function nomeCmd(token: string | undefined): string {
  return (token ?? '').replace(/^.*[\/\\]/, '').replace(/\.(exe|cmd|bat|ps1)$/i, '').toLowerCase()
}

/** Subcomando git e os seus argumentos (salta -C dir, -c k=v, --no-pager...). */
export function gitSub(t: string[]): { sub: string; args: string[] } | null {
  if (nomeCmd(t[0]) !== 'git') return null
  let i = 1
  while (i < t.length && t[i].startsWith('-')) {
    i += t[i] === '-C' || t[i] === '-c' ? 2 : 1
  }
  if (i >= t.length) return null
  return { sub: t[i], args: t.slice(i + 1) }
}

export function pushForcado(args: string[]): boolean {
  return args.some(
    a =>
      a === '--force' ||
      a.startsWith('--force-with-lease') ||
      a === '--force-if-includes' ||
      a === '--mirror' ||
      /^-[a-zA-Z]*f[a-zA-Z]*$/.test(a) || // -f, -qf, -fu (bandeira curta, minúscula)
      (!a.startsWith('-') && a.startsWith('+')), // refspec com +
  )
}

const RM_PERMITIDO = /(^|[\/\\])(build|\.dart_tool|node_modules)([\/\\]|$)/

function avaliaApagar(t: string[]): Veredito {
  const cmd = nomeCmd(t[0])
  const args = t.slice(1)
  let recursivo = false
  if (cmd === 'rm') {
    recursivo = args.some(a => /^-[a-zA-Z]*[rR]/.test(a) || a === '--recursive')
  } else if (['remove-item', 'ri', 'del', 'rmdir', 'rd', 'erase'].includes(cmd)) {
    recursivo = args.some(a => /^-(r|re|rec|recu|recurse)$/i.test(a) || /^\/s$/i.test(a))
  }
  if (!recursivo) return SEGUE
  const alvos = args.filter(a => !a.startsWith('-') && !/^\/[a-z]$/i.test(a))
  for (const alvo of alvos) {
    if (alvo === 'Q' || alvo.includes('..') || !RM_PERMITIDO.test(alvo)) {
      return nega(`apagar recursivo fora de build/, .dart_tool/ ou node_modules/ (${alvo})`)
    }
  }
  return SEGUE
}

/** SQL dentro de psql/supabase no terminal? */
function eContextoSql(seg: string[]): boolean {
  const c = nomeCmd(seg[0])
  return /^(psql|pg_dump|pg_restore|supabase)$/.test(c) || seg.some(x => /PGPASSWORD|postgres(ql)?:\/\//.test(x))
}

export function avaliaComando(comando: string, ctx: Contexto): Veredito {
  const segs = segmentos(comando)
  let pedePush = false
  for (const t of segs) {
    if (t.length === 0) continue
    const g = gitSub(t)
    if (g) {
      const { sub, args } = g
      if (sub === 'push') {
        if (pushForcado(args)) return nega('git push forçado (bandeira de força ou refspec com +)')
        pedePush = true
      }
      if (sub === 'add' && args.some(a => ['-A', '--all', '.', ':/', './', '*'].includes(a))) {
        return nega('git add -A / git add . (arrasta trabalho alheio; adiciona por caminho)')
      }
      if (sub === 'reset' && args.includes('--hard')) return nega('git reset --hard')
      if (sub === 'checkout' && args.includes('.')) return nega('git checkout -- . (apaga alterações por gravar)')
      if (sub === 'restore' && args.includes('.')) return nega('git restore . (apaga alterações por gravar)')
      if (sub === 'clean' && args.some(a => /^-[a-zA-Z]*f/.test(a) || a === '--force')) return nega('git clean -f')
    }
    const ap = avaliaApagar(t)
    if (ap.acao === 'nega') return ap
    const c = nomeCmd(t[0])
    if (c === 'supabase') {
      const resto = t.join(' ')
      if (/\bdb\s+reset\b/.test(resto)) return nega('supabase db reset (destrói a base)')
      if (/--linked\b/.test(resto) && /\b(reset|delete|drop|truncate|remove)\b/i.test(resto)) {
        return nega('supabase --linked a apagar na base de produção')
      }
      if (/\bfunctions\s+deploy\b/.test(resto)) {
        const v = avaliaDeploy(t.slice(t.indexOf('deploy') + 1).filter(a => !a.startsWith('-')).join(' '), ctx)
        if (v.acao !== 'segue') return v
      }
    }
    if (eContextoSql(t)) {
      // o SQL costuma ir entre aspas: aqui olha-se para o comando inteiro
      const v = avaliaSql(comando, ctx, false, true)
      if (v.acao === 'nega') return v
    }
    if (/^(curl|wget|invoke-webrequest|iwr|invoke-restmethod|irm|http)$/.test(c)) {
      const s = segredoEmPedidoWeb(comando)
      if (s) return nega(`pedido web com segredo em texto claro (${s}); usa variável de ambiente`)
    }
  }
  if (pedePush) {
    return {
      acao: 'pergunta',
      motivo: 'git push',
      pergunta:
        'bora-tranca: o Claude quer fazer git push. Isto PUBLICA: build Android na Play Store a 100% e deploy web. Deixo seguir?',
    }
  }
  return SEGUE
}

function segredoEmPedidoWeb(comando: string): string | null {
  const literal = temSegredoLiteral(comando)
  if (literal) return literal
  const m = comando.match(/(authorization|x-api-key|apikey)\s*:\s*(bearer\s+)?([^\s"']+)/i)
  if (m && !/^[$%]/.test(m[3])) return `${m[1]}: com valor literal`
  return null
}

// ---------------------------------------------------------------------------
// SQL (MCP Supabase e psql)
// ---------------------------------------------------------------------------

export function limpaSql(sql: string, manterAspas = false): string {
  const semComentarios = sql.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*/g, ' ')
  return manterAspas ? semComentarios : semComentarios.replace(/'(?:[^']|'')*'/g, "''")
}

function alternativas(...listas: (string | string[])[]): string {
  return listas
    .flatMap(l => (Array.isArray(l) ? l : l.split('|')))
    .filter(x => x !== '')
    .join('|')
}

export function avaliaSql(sqlBruto: string, ctx: Contexto, eMigracao: boolean, doTerminal = false): Veredito {
  // no terminal o SQL vem dentro de aspas ('...'): não se pode apagar o texto citado
  const sql = limpaSql(sqlBruto, doTerminal).toLowerCase()
  const z = ctx.zonas
  const fin = alternativas(ctx.banco.fintable, z?.tabelas_dinheiro_extra ?? ['client_wallets', 'tvde_[a-z_]+'])
  const fn = alternativas(ctx.banco.moneyfn, z?.funcoes_sql_extra ?? [])
  const semDml = alternativas(
    z?.tabelas_sem_dml_direto ?? ['orders', 'wallets', 'client_wallets', 'ledger_entries', 'bora_tokens', 'drivers'],
  )
  const tab = (lista: string) => `(only\\s+)?(public\\.)?"?(${lista})"?(?![a-z0-9_])`

  if (new RegExp(`\\bdrop\\s+table\\s+(if\\s+exists\\s+)?[^;]*?${tab(fin)}`).test(sql)) {
    return nega('DROP TABLE de tabela de dinheiro')
  }
  if (new RegExp(`\\btruncate\\s+(table\\s+)?[^;]*?${tab(fin)}`).test(sql)) {
    return nega('TRUNCATE de tabela de dinheiro')
  }
  for (const st of sql.split(';')) {
    const d = st.match(new RegExp(`\\bdelete\\s+from\\s+${tab(fin)}([\\s\\S]*)$`))
    if (d && !/\bwhere\b/.test(d[4] ?? '')) return nega('DELETE sem WHERE em tabela de dinheiro')
  }
  if (new RegExp(`\\b(update|insert\\s+into|delete\\s+from)\\s+${tab(semDml)}`).test(sql)) {
    return nega(
      'UPDATE/INSERT/DELETE direto numa tabela operacional ou de dinheiro (regra 16/09: usa ops_reassign_order / ops_release_order_driver / admin_*)',
    )
  }
  // a chave vem entre aspas ('commission_pct'): olha-se para o SQL com as aspas
  if (/\b(update|insert\s+into)\s+(public\.)?"?platform_settings\b/.test(sql) && /(stripe|pricing|commission|fee|token)_/.test(limpaSql(sqlBruto, true).toLowerCase())) {
    return nega('platform_settings financeiro (stripe_/pricing_/commission_/fee_/token_)')
  }
  if (/\b(alter|drop)\s+policy\b[^;]*\bon\s+(public\.)?"?(orders|wallets|client_wallets|ledger[a-z_]*)\b/.test(sql)) {
    return nega('ALTER/DROP POLICY em orders/wallets/ledger (RLS de dinheiro)')
  }
  if (new RegExp(`\\bdisable\\s+row\\s+level\\s+security\\b`).test(sql) && new RegExp(`\\b(${fin})\\b`).test(sql)) {
    return nega('DISABLE ROW LEVEL SECURITY em tabela de dinheiro')
  }
  if (
    fn !== '' &&
    new RegExp(`\\b(create\\s+or\\s+replace|create|drop|alter)\\s+(function|trigger|procedure)\\s+(if\\s+exists\\s+)?(public\\.)?"?(${fn})\\b`).test(sql)
  ) {
    return nega('DDL sobre função/trigger de dinheiro')
  }
  if (eMigracao) {
    return {
      acao: 'pergunta',
      motivo: 'migration',
      pergunta: 'bora-tranca: o Claude quer aplicar uma migration na base de PRODUÇÃO. Deixo seguir?',
    }
  }
  if (/\b(create|alter)\s+(table|index|type|view|materialized\s+view|function|trigger|policy|schema)\b|\b(grant|revoke)\b/.test(sql)) {
    return {
      acao: 'pergunta',
      motivo: 'DDL em produção',
      pergunta: 'bora-tranca: o Claude quer mudar a estrutura da base de PRODUÇÃO (tabela/índice/função). Deixo seguir?',
    }
  }
  return SEGUE
}

const FUNCOES_LEITURA = new Set(
  (
    'count sum avg min max coalesce nullif greatest least now current_date current_timestamp date_trunc date_part ' +
    'extract to_char to_date to_timestamp age lower upper length char_length octet_length substring substr left right ' +
    'trim btrim ltrim rtrim lpad rpad replace split_part concat concat_ws format position strpos round floor ceil ceiling ' +
    'abs mod sqrt power array_agg string_agg json_agg jsonb_agg json_build_object jsonb_build_object json_build_array ' +
    'jsonb_build_array jsonb_array_length jsonb_object_keys jsonb_each jsonb_each_text jsonb_array_elements ' +
    'jsonb_array_elements_text jsonb_typeof jsonb_pretty jsonb_strip_nulls to_jsonb to_json row_to_json bool_or bool_and ' +
    'array_length array_to_string string_to_array unnest cardinality generate_series exists in any all over filter ' +
    'row_number rank dense_rank lag lead first_value last_value cast md5 pg_size_pretty pg_total_relation_size ' +
    'pg_relation_size pg_get_functiondef pg_get_triggerdef pg_get_viewdef pg_get_constraintdef pg_get_indexdef ' +
    'obj_description col_description format_type regexp_replace regexp_match regexp_matches values case when and or ' +
    'not is on as timezone make_interval interval date timestamp timestamptz numeric decimal text int integer bigint ' +
    'smallint uuid varchar char boolean float real percentile_cont percentile_disc within mode array has_table_privilege ' +
    'has_function_privilege current_setting current_user session_user version encode decode initcap reverse translate ' +
    'ascii chr quote_ident quote_literal row array_position jsonb_set jsonb_path_query count_estimate where from select ' +
    'join using with group having order by limit offset union except intersect lateral distinct epoch extract'
  ).split(/\s+/),
)

/** SELECT/WITH/EXPLAIN de uma só instrução, sem escrita nem funções desconhecidas. */
export function sqlSoLeitura(sqlBruto: string): boolean {
  const sql = limpaSql(sqlBruto).toLowerCase().trim()
  const instrucoes = sql.split(';').map(s => s.trim()).filter(s => s !== '')
  if (instrucoes.length !== 1) return false
  const s = instrucoes[0]
  if (!/^(select|with|explain)\b/.test(s)) return false
  if (/\banalyze\b/.test(s) && /^explain/.test(s)) return false
  if (
    /\b(insert|update|delete|merge|drop|alter|create|truncate|grant|revoke|copy|call|do|vacuum|refresh|lock|set|reset|comment|security|listen|notify|into|perform|execute|prepare|nextval|setval|set_config|pg_sleep|dblink|lo_import|pg_read_file|pg_terminate_backend)\b/.test(
      s,
    )
  ) {
    return false
  }
  for (const m of s.matchAll(/([a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)?)\s*\(/g)) {
    const nome = m[1]
    if (nome.includes('.') || !FUNCOES_LEITURA.has(nome)) return false
  }
  return true
}

// ---------------------------------------------------------------------------
// Deploy de Edge Functions
// ---------------------------------------------------------------------------

export function avaliaDeploy(slug: string, ctx: Contexto): Veredito {
  if (ctx.banco.protslug === null) {
    return nega('lista PROTSLUG do protege-banco.sh ilegível: todo o deploy fica bloqueado (fail-closed)')
  }
  if (new RegExp(`(${ctx.banco.protslug})`, 'i').test(slug.trim())) {
    return nega(`deploy de Edge Function protegida (${slug.trim()})`)
  }
  // a pasta da função é zona vermelha no zonas-vermelhas.json? (ex.: client-cancel-order)
  const pasta = `supabase/functions/${slug.trim()}/index.ts`
  const zona = ctx.zonas?.ficheiros.find(z => new RegExp(z.padrao, 'i').test(pasta))
  if (zona) return nega(`deploy de Edge Function em zona vermelha (${zona.motivo})`)
  return {
    acao: 'pergunta',
    motivo: 'deploy edge function',
    pergunta: `bora-tranca: o Claude quer publicar a Edge Function "${slug.trim()}" em PRODUÇÃO. Deixo seguir?`,
  }
}

// ---------------------------------------------------------------------------
// Edições de ficheiros
// ---------------------------------------------------------------------------

function linhasVersao(texto: string): string[] {
  return texto.split(/\r?\n/).filter(l => /^\s*version\s*:/.test(l)).map(l => l.trim())
}

export function avaliaEdicao(caminho: string, textosNovos: string[], textosVelhos: string[], ctx: Contexto, eWrite: boolean): Veredito {
  const n = normaliza(caminho)
  const z = ctx.zonas
  if (z === null) return nega('zonas-vermelhas.json ilegível: edições bloqueadas até o ficheiro voltar (fail-closed)')
  for (const zona of z.ficheiros) {
    if (new RegExp(zona.padrao, 'i').test(n)) return nega(`zona vermelha: ${zona.motivo}`)
  }
  if (new RegExp(z.segredos_caminho, 'i').test(n)) return nega('ficheiro de segredos (.env, keystore, .dart_defines, .pem)')
  if (new RegExp(z.migracoes.padrao_caminho, 'i').test(n)) {
    if (textosNovos.some(t => new RegExp(z.migracoes.padrao_conteudo, 'i').test(t))) {
      return nega(z.migracoes.motivo)
    }
  }
  if (/(^|\/)pubspec\.yaml$/i.test(n)) {
    if (eWrite) {
      if (ctx.pubspecAtual === undefined || ctx.pubspecAtual === null) {
        return nega('pubspec.yaml: não consegui ler a versão atual para comparar (fail-closed)')
      }
      if (linhasVersao(ctx.pubspecAtual).join('|') !== linhasVersao(textosNovos.join('\n')).join('|')) {
        return nega('pubspec.yaml version:/versionCode — o CI incrementa sozinho, nunca à mão')
      }
    } else if (linhasVersao(textosVelhos.join('\n')).join('|') !== linhasVersao(textosNovos.join('\n')).join('|')) {
      return nega('pubspec.yaml version:/versionCode — o CI incrementa sozinho, nunca à mão')
    }
  }
  for (const t of textosNovos) {
    const s = temSegredoLiteral(t)
    if (s) return nega(`segredo no conteúdo novo: ${s}`)
  }
  return SEGUE
}

// ---------------------------------------------------------------------------
// A chamada inteira: decide pela ferramenta
// ---------------------------------------------------------------------------

export type Args = Record<string, unknown>

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

export const SUPABASE_SQL = /^mcp__.*supabase.*__(execute_sql|apply_migration)$/i
export const SUPABASE_DEPLOY = /^mcp__.*supabase.*__deploy_edge_function$/i

export function avaliaChamada(tool: string, args: Args, ctx: Contexto): Veredito {
  if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
    const caminho = str(args.file_path) || str(args.notebook_path)
    const novos: string[] = []
    const velhos: string[] = []
    if (tool === 'Edit') {
      novos.push(str(args.new_string))
      velhos.push(str(args.old_string))
    } else if (tool === 'Write') {
      novos.push(str(args.content))
    } else if (tool === 'NotebookEdit') {
      novos.push(str(args.new_source))
    } else if (Array.isArray(args.edits)) {
      for (const e of args.edits as Args[]) {
        novos.push(str(e?.new_string))
        velhos.push(str(e?.old_string))
      }
    }
    return avaliaEdicao(caminho, novos, velhos, ctx, tool === 'Write')
  }
  if (tool === 'Bash' || tool === 'PowerShell') return avaliaComando(str(args.command), ctx)
  if (SUPABASE_SQL.test(tool)) return avaliaSql(str(args.query), ctx, /apply_migration$/i.test(tool))
  if (SUPABASE_DEPLOY.test(tool)) return avaliaDeploy(str(args.name), ctx)
  return SEGUE
}

// ---------------------------------------------------------------------------
// Parte C: o que se aprova sem caixa de permissão (só leitura)
// ---------------------------------------------------------------------------

const SEMPRE_SIM = new Set(['Read', 'Grep', 'Glob', 'LS', 'WebFetch', 'WebSearch', 'TodoWrite', 'ToolSearch'])

function comandoSoLeitura(comando: string): boolean {
  if (/[`{}]|\$\(|<\(|>\(/.test(comando)) return false
  // redireções: só para o nada ou stderr->stdout
  const semNulos = comando.replace(/\d?>\s*(&\d|\/dev\/null|\$null|nul)\b/gi, ' ')
  if (/[<>]/.test(semNulos.replace(/"(?:[^"\\]|\\.)*"|'[^']*'/g, ' '))) return false
  const segs = segmentos(comando)
  if (segs.length === 0) return false
  return segs.every(segmentoSoLeitura)
}

function segmentoSoLeitura(t: string[]): boolean {
  const c = nomeCmd(t[0])
  const a = t.slice(1)
  const g = gitSub(t)
  if (g) {
    const { sub, args } = g
    if (['status', 'log', 'show', 'fetch', 'rev-parse', 'ls-files', 'blame'].includes(sub)) return true
    if (sub === 'diff') return !args.some(x => x.startsWith('--output') || x === '--ext-diff')
    if (sub === 'branch') return args.every(x => /^(-a|-r|-v|-vv|--list|--all|--remotes|--show-current|--contains|--merged|--no-merged|-l)$/.test(x))
    return false
  }
  if (c === 'flutter') return /^(analyze|test)$/.test(a[0] ?? '') || (a[0] === 'pub' && a[1] === 'get')
  if (c === 'dart') return /^(format|analyze)$/.test(a[0] ?? '')
  if (c === 'rg' && a.some(x => x.startsWith('--pre'))) return false // --pre corre um programa
  if (/^(ls|dir|cat|type|findstr|rg|grep|head|tail|wc|where|which|pwd|echo|get-childitem|gci|get-content|gc|test-path|get-location|select-string|sls|measure-object|select-object|sort-object|format-table|format-list|out-string)$/.test(c)) {
    return true
  }
  if (c === 'node' || c === 'npm') return a.length === 1 && /^(-v|--version)$/.test(a[0])
  if (c === 'claude') return a.length === 1 && /^(-v|--version)$/.test(a[0])
  if (c === 'gh') {
    if (a[0] === 'run') return /^(list|view)$/.test(a[1] ?? '')
    if (a[0] === 'api') return !a.some(x => /^(-X|--method|-f|-F|--field|--raw-field|--input)$/.test(x) || /^--method=/.test(x))
    return false
  }
  if (c === 'adb') return /^(devices|logcat)$/.test(a[0] ?? '')
  return false
}

export function aprovaSemPerguntar(tool: string, args: Args, raizes: string[]): string | null {
  if (SEMPRE_SIM.has(tool)) return 'leitura'
  if (tool === 'Agent' || tool === 'Task') {
    return /^(Explore|Plan)$/.test(str(args.subagent_type)) ? 'agente só de leitura' : null
  }
  if (tool === 'Bash' || tool === 'PowerShell') return comandoSoLeitura(str(args.command)) ? 'comando só de leitura' : null
  if (/^mcp__.*supabase.*__execute_sql$/i.test(tool)) return sqlSoLeitura(str(args.query)) ? 'SELECT só de leitura' : null
  if (/^mcp__.*supabase.*__(get_[a-z_]+|list_[a-z_]+|query_logs|search_docs)$/i.test(tool)) return 'Supabase só de leitura'
  if (/^mcp__.*c_?rtex.*__(cortex_buscar|cortex_ler|cortex_listar)$/i.test(tool)) return 'Córtex só de leitura'
  if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit') {
    // o repositório chega por dois caminhos (C:\BoraLocal e a junção do Desktop)
    for (const raiz of raizes) {
      const rel = relativo(str(args.file_path), raiz)
      if (rel === null || rel.includes('..')) continue
      if (/^(lib|test|docs)\//.test(rel) || /\.md$/i.test(rel)) return 'edição em zona verde'
    }
  }
  return null
}
