// Guarda do Dipsy (dsh): decide, ANTES de cada chamada de ferramenta, se ela pode correr.
// Código nosso (missão C-liga, 30/10/2026). É a "bora-tranca" do dsh: o dsh não tem hooks, tem este gancho (ctx.tools.guard).
// Funções puras: avaliar(nome, argumentos) devolve null (deixa passar) ou { regra, porque } (barra).
// Limite honesto: lê o TEXTO do comando. Quem esconde o comando (junta letras, codifica) pode escapar; por isso o
// Dipsy também corre com o sandbox de escrita do dsh e com as regras escritas em ~/.agents/AGENTS.md.

import os from 'node:os'

const HOME = os.homedir().replace(/\\/g, '/').toLowerCase()

// ---------- utilitários ----------
function textoLimpo(s) {
  return String(s ?? '').replace(/\u0000/g, '').toLowerCase().replace(/\s+/g, ' ')
}
function semAspas(t) {
  return t.replace(/["'`]/g, '')
}
function testa(re, t) {
  return re.test(t) || re.test(semAspas(t))
}
function strings(v, acc = [], prof = 0) {
  if (prof > 4 || acc.length > 60) return acc
  if (typeof v === 'string') acc.push(v)
  else if (Array.isArray(v)) for (const x of v) strings(x, acc, prof + 1)
  else if (v && typeof v === 'object') for (const x of Object.values(v)) strings(x, acc, prof + 1)
  return acc
}

// ---------- segredos (nunca ler, nunca escrever) ----------
const SEGREDO = [
  [/(^|[\\/\s"'=:(])\.env(?![\w-])(?!\.(example|sample|template))/, 'ficheiro .env'],
  [/\.supabase-token/, 'token do Supabase'],
  [/\.dart_defines/, 'chaves da app (.dart_defines)'],
  [/(^|[\\/\s"'=])(secrets|_segredos)([\\/]|$|\s)/, 'pasta de segredos'],
  [/\.credentials(\.yaml|\.json)?(?![\w])/, 'ficheiro de credenciais'],
  [/id_(rsa|ed25519|ecdsa|dsa)/, 'chave SSH'],
  [/[\\/]\.ssh([\\/]|$|\s)/, 'pasta .ssh'],
  [/\.(pem|pfx|p12|jks|keystore)(?![\w])/, 'certificado ou chave'],
  [/aviso\.conf/, 'ficheiro do aviso (token do Telegram)'],
  [/\.claude\.json/, 'ficheiro .claude.json'],
  [/\.(npmrc|netrc|git-credentials|pypirc)(?![\w])/, 'ficheiro de credenciais de ferramentas'],
  [/[\\/]\.aws[\\/]|[\\/]\.config[\\/](gh|gcloud)([\\/]|$)/, 'credenciais da cloud'],
  [/user data[\\/][^\\/\s"']+[\\/](login data|cookies|web data|local state)/, 'dados de login do navegador'],
  [/\b(cmdkey|vaultcmd|mimikatz)\b/, 'cofre de credenciais do Windows'],
  [/\bprintenv\b/, 'listar variáveis de ambiente'],
  [/(^|[\s;|(])(gci|dir|ls|get-childitem|get-item)\s+env:/, 'listar variáveis de ambiente'],
  [/\$env:\w*(key|token|secret|pass|pwd)\w*/, 'variável de ambiente com segredo'],
  [/process\.env\.\w*(key|token|secret|pass|pwd)/, 'variável de ambiente com segredo'],
  [/getenvironmentvariable\([^)]*(key|token|secret|pass|pwd)/, 'variável de ambiente com segredo'],
]
function segredo(t) {
  for (const [re, nome] of SEGREDO) if (testa(re, t)) return nome
  return null
}

// ---------- ficheiros que o Dipsy não escreve (a guarda, o juiz, o CI, as zonas do dinheiro) ----------
const PROTEGIDO_ESCRITA = [
  [/[\\/]\.dsh([\\/]|$)(?![\\/]?(capturas|entrada)([\\/]|$))/, 'a casa do Dipsy (~/.dsh)'],
  [/\.agents[\\/]agents\.md/, 'as regras do Dipsy (~/.agents/AGENTS.md)'],
  [/[\\/]\.claude[\\/](hooks|juiz|plugins|settings|agents|cache|claude\.md)/, 'tranca, juiz ou definições do Claude Code'],
  [/(^|[\\/])\.git[\\/](hooks|config|refs|head)/, 'o interior do git'],
  [/\.github[\\/]workflows/, 'o CI (publica sozinho)'],
  [/dsh-bora/, 'o próprio plugin da guarda'],
  [/(pricing_service|dispatch_engine|dispatch-engine|stripe-webhook|create-payment-intent|create-mbway|finalizepurchase|bora_tokens)/, 'zona protegida do dinheiro'],
  [/supabase[\\/]functions[\\/](refund|charge|payout|wallet|token|pricing)/, 'função de dinheiro'],
  [/(^|[\\/])pubspec\.(yaml|lock)$/, 'pubspec (o versionCode é do CI)'],
]
function protegidoEscrita(t) {
  for (const [re, nome] of PROTEGIDO_ESCRITA) if (re.test(t)) return nome
  return null
}
const VERBO_ESCRITA = /(>>?|\b(set-content|add-content|out-file|new-item|remove-item|move-item|copy-item|rename-item|clear-content|tee-object|tee|sed\s+-i|mv|cp|rm|del|ren|attrib|icacls|takeown|chmod|ln|mklink|touch|truncate|writealltext|writeallbytes|appendalltext|writefile|dd)\b)/

// ---------- shell (pwsh, bash, run_code e qualquer código) ----------
const SHELL = [
  ['push', /\bgit\b[^|;&\n]*\bpush(?=\s|$)/, 'enviar para o servidor (git push) é do Claude Code, nunca do Dipsy.'],
  ['historia', /\bgit\b[^|;&\n]*\b(reset\s+--hard|clean\s+-\S*f|rebase(?=\s|$)|filter-branch|filter-repo|commit\s+--amend|reflog\s+(expire|delete)|gc\s+--prune|update-ref\s+-d|branch\s+-d(?=\s|$)|tag\s+-d(?=\s|$)|stash\s+(drop|clear)|checkout\s+--(?=\s)|restore\s+\.(?=\s|$)|worktree\s+(remove|prune))/, 'mexer ou apagar histórico do git não se faz (nunca reescrever histórico publicado).'],
  ['git-add-tudo', /\bgit\b[^|;&\n]*\badd\s+(-a(?=\s|$)|--all|\.(?=\s|$)|\*)/, 'git add de tudo apanha o trabalho de outras sessões: adiciona só os ficheiros da tarefa, pelo caminho.'],
  ['apagar', /(^|[\s;&|(])rm\s+(-[a-z-]*[rf]|[^|;&\n]*\*)|\brmdir\s+\/s|(^|[\s;&|(])rd\s+\/s|\bdel\s+[^|;&\n]*\/[sfq]|(^|[\s;&|(])erase\s|\bremove-item\b[^|;&\n]*(-recurse|-r(?=\s)|-force|-fo(?=\s)|\*)|(^|[\s;&|(])ri\s+[^|;&\n]*-(recurse|force)|shutil\.rmtree|os\.removedirs|fs\.rm(sync)?\([^)]*recursive|find\s[^|;&\n]*-delete|\bgit\s+rm(?=\s)/, 'apagar em massa ou à força (rm -rf e parecidos) não se faz; só se apaga o que se regenera, e sem asteriscos.'],
  ['sistema', /\b(format-volume|format\s+[a-z]:|diskpart|cipher\s+\/w|clear-disk|remove-partition|bcdedit|set-executionpolicy|stop-computer|restart-computer)\b|\bshutdown(\.exe)?\s+\/|\breg(\.exe)?\s+(add|delete|import|load)\b|\bschtasks(\.exe)?\s+\/(create|delete|change)|register-scheduledtask|unregister-scheduledtask|new-service|\bsc(\.exe)?\s+(create|delete|config)\b|netsh\s+advfirewall|set-itemproperty\s+[^|;&\n]*hk(lm|cu)/, 'mexer no sistema (disco, registo, tarefas, firewall, desligar) é do Danilo.'],
  ['codigo-remoto', /\b(curl|wget|iwr|invoke-webrequest|irm|invoke-restmethod)\b[^\n]*\|\s*(sh|bash|iex|invoke-expression|powershell|pwsh|python|node)\b|(^|[\s;|(])iex\s*[(\s]|\binvoke-expression\b|-encodedcommand|\s-enc\s/, 'descarregar e correr código à pressa (curl | sh, iex, comandos codificados) não se faz.'],
  ['instalar', /\b(npm|pnpm|yarn)\s+(i|install|add)\s[^|;&\n]*(-g|--global)\b|\b(winget|choco|scoop)\s+install\b|\bdsh\s+plugin\b|\bnpx\s+(-y\s+)?(degit|create-)/, 'instalar programas ou plugins de terceiros não se faz pelo Dipsy: passa pelo Claude Code, com auditoria.'],
  ['npm-config', /\bnpm\s+(config\s+(set|delete|edit)|cache\s+(clean|rm))\b|\bnpm\s+set\b/, 'mexer na configuração ou na cache do npm é do Claude Code; o REA corre sem npm (usa rea-bora.ps1).'],
  ['supabase-cli', /\bsupabase(\.exe)?\s+(db|functions|secrets|projects|branches|migration|link|login|logout|start|stop)\b|\bpsql(\.exe)?\b|\bpg_(dump|restore)\b/, 'a base só se mexe pelo MCP do Supabase (que tem as suas regras), nunca por linha de comandos.'],
  ['dinheiro-stripe', /\bstripe(\.exe)?\s/, 'Stripe é dinheiro: prepara e espera o "autorizo" do Danilo.'],
  ['matar-processos', /\btaskkill\b|\bstop-process\b|\bpkill\b|(^|[\s;&|(])kill\s+-9/, 'matar processos pode derrubar sessões do Danilo (Claude Code, controlo remoto).'],
  ['mensagens-fora', /api\.telegram\.org|graph\.facebook\.com|\bsend-mailmessage\b|\bsendmail\b|\bsmtp(lib|client)?\b|wa\.me\/|whatsapp.*send/, 'enviar mensagens para fora não é com o Dipsy (o email sai sempre da conta Bora, pelo Danilo ou pelo Claude Code).'],
]
// ---------- REA (engenharia reversa): só nas NOSSAS coisas (regra do Danilo de 19/10 e 13/10) ----------
const REA_CHAMADO = /\brea-agents\b|rea-bora\.ps1|scripts[\\/]rea\.mjs|(^|[\s;&|(])rea(\.cmd|\.exe)?\s+[a-z]/
const REA_HOSTS = [/^(www\.)?boraguarda\.com$/, /^[a-z0-9-]+\.boraguarda\.com$/, /^ojykpzwqrtusfeakzrna\.supabase\.co$/, /^localhost$/, /^127\.0\.0\.1$/]
function avaliarRea(t) {
  if (!REA_CHAMADO.test(t)) return null
  if (/\brea-agents(@\S+)?\s+(setup|mcp|install|update)\b/.test(t)) {
    return { regra: 'rea-config', porque: 'o setup do REA mexe nas configurações dos agentes do Danilo: não é do Dipsy (o REA já está instalado).' }
  }
  if (/\b(observe-native-calls|instrument-with-frida|start-frida-session|load-frida-script|debug-with-gdb|debug-with-rizin|capture-process|capture-native-ui-scenario|capture-electron-scenario|start-gdb-session|trace-native-values|observe-native-ui)\b/.test(t)) {
    return { regra: 'rea-processos', porque: 'espiar ou instrumentar processos do PC (podem ser apps do Danilo) não se faz: o REA só serve para o nosso APK, os nossos sites e as nossas Edge Functions.' }
  }
  for (const m of t.matchAll(/https?:\/\/([^\/\s"'?#:]+)/g)) {
    if (!REA_HOSTS.some((re) => re.test(m[1]))) return { regra: 'rea-terceiros', porque: `o REA só se aponta ao que é nosso (boraguarda.com, a nossa API do Supabase, o nosso APK); ${m[1]} é de terceiros.` }
  }
  for (const m of t.matchAll(/[^\s"']+\.(apk|aab|ipa|xapk)\b/g)) {
    if (!/bora/.test(m[0]) || /ifood|glovo|uber|bolt/.test(m[0])) return { regra: 'rea-terceiros', porque: `só o nosso APK (pt.boraapp.bora): ${m[0].slice(-60)} não parece ser.` }
  }
  return null
}

const COMMIT_OK = /dsh-commit\.ps1/
const GIT_COMMITA = /\bgit\b[^|;&\n]*\b(commit(?=\s|$)|merge(?=\s|$)|cherry-pick|am(?=\s|$)|revert(?=\s|$)|commit-tree)/

function avaliarTextoDeComando(texto) {
  const t = textoLimpo(texto)
  if (!t) return null
  const t2 = t.replace(/\d?>\s*&\d|\d>\s*(\$null|\/dev\/null|nul)\b/g, ' ')
  if (GIT_COMMITA.test(t) && !COMMIT_OK.test(t)) {
    return { regra: 'commit-sem-juiz', porque: 'todo o commit do Dipsy passa pelo Juiz: usa o script dsh-commit.ps1 (corre o anti-trapaça e só então faz o commit).' }
  }
  const rea = avaliarRea(t)
  if (rea) return rea
  for (const [id, re, porque] of SHELL) if (testa(re, t)) return { regra: id, porque }
  const s = segredo(t)
  if (s) return { regra: 'segredos', porque: `${s} é segredo: o Dipsy não o lê nem o escreve.` }
  const p = protegidoEscrita(t2)
  if (p && VERBO_ESCRITA.test(t2)) return { regra: 'ficheiro-protegido', porque: `${p} não se escreve pelo Dipsy.` }
  return null
}

// ---------- SQL (MCP do Supabase) ----------
const TABELAS = ['orders', 'tvde_rides', 'appointments', 'drivers', 'client_wallets', 'wallets', 'ledger_entries', 'bora_tokens', 'driver_balances', 'payouts', 'platform_settings']
const T = `(?:public\\.)?"?(?:${TABELAS.join('|')})"?(?![\\w])`
const FUNCOES_DINHEIRO = '(?:admin_|finalize|credit_|debit_|refund|payout|settle|award|apply_|wallet|ledger|create_order|place_order|cancel_order|ops_(?!reassign_order\\b|release_order_driver\\b))'

export function sqlRisco(sql) {
  let q = String(sql ?? '').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*/g, ' ').toLowerCase().replace(/\s+/g, ' ')
  // backup antes de corrigir (regra bkp_<nome>_AAAAMMDD) é permitido: copiar não altera nada
  q = q.replace(/create\s+table\s+(if\s+not\s+exists\s+)?(public\.)?"?bkp_\w+"?\s+as\s+select[^;]*/g, ' ')
  if (!q.trim()) return null
  const regras = [
    [/\bdrop\s+(table|schema|database|function|policy|trigger|view|index|extension|role|user|type|publication|materialized|sequence|column|constraint)\b/, 'apagar estrutura (DROP) não se faz.'],
    [/\btruncate\b/, 'esvaziar tabelas (TRUNCATE) não se faz.'],
    [/\bdelete\s+from\b/, 'nunca apagar dados de produção (DELETE).'],
    [/\balter\s+table\b[^;]*\bdrop\b/, 'apagar colunas ou regras (ALTER TABLE ... DROP) não se faz.'],
    [/\b(disable|no\s+force)\s+row\s+level|\balter\s+table\b[^;]*\b(disable\s+row|no\s+force)/, 'desligar a segurança por linha (RLS) não se faz.'],
    [new RegExp(`\\b(update|insert\\s+into|merge\\s+into|upsert\\s+into)\\s+(only\\s+)?${T}`), 'escrever direto nas tabelas de pedidos, estafetas, carteiras, tokens ou preços é proibido (só pelas funções ops_*; dinheiro só com "autorizo").'],
    [new RegExp(`\\b(create|alter|drop|comment\\s+on)\\b[^;]*\\b(table|policy|trigger|function|view|index)\\b[^;]*${T}`), 'estrutura das tabelas de dinheiro e pedidos é zona protegida: prepara e espera o "autorizo".'],
    [/\b(bora_tokens|award_tokens|finalize_?purchase|dispatch_engine|pricing_service)\b/, 'zona protegida do dinheiro e do despacho: prepara e espera o "autorizo".'],
    [/\b(grant|revoke)\b/, 'dar ou tirar permissões (GRANT/REVOKE) é decisão do Claude Code e do Danilo.'],
    [/\balter\s+(role|user|system|database)\b|\bcreate\s+(role|user|extension)\b|\bdrop\s+(extension)\b/, 'papéis, extensões e definições do servidor não se mexem.'],
    [/\bcron\.(schedule|unschedule|alter_job)\b/, 'tarefas agendadas (pg_cron) não se mexem pelo Dipsy.'],
    [/\b(pg_terminate_backend|pg_cancel_backend|pg_reload_conf|lo_import|lo_export|pg_read_file|pg_ls_dir|copy\s+[^;]*\bprogram)\b/, 'funções de sistema perigosas.'],
    [/\bauth\.users\b[^;]*\b(update|delete|insert)\b|\b(update|delete\s+from|insert\s+into)\s+auth\.users\b/, 'contas de utilizadores (auth.users) não se escrevem.'],
    [/\bstorage\.(objects|buckets)\b[^;]*\b(update|delete|insert)\b|\b(update|delete\s+from|insert\s+into)\s+storage\./, 'ficheiros guardados (storage) não se escrevem por SQL.'],
    [new RegExp(`\\b(select|perform|call)\\s+(public\\.)?${FUNCOES_DINHEIRO}`), 'função que mexe em dinheiro ou pedidos: só com o "autorizo" do Danilo (permitidas: ops_reassign_order e ops_release_order_driver).'],
  ]
  for (const [re, porque] of regras) if (re.test(q)) return porque
  return null
}

// ---------- MCP ----------
const FUNCOES_PROTEGIDAS = /^(dispatch-engine|create-payment-intent|stripe-webhook|create-mbway-payment-intent|confirm-mbway-payment|charge-extra|refund.*|payout.*|wallet.*|token.*|pricing.*|robot-b)$/

function avaliarMcp(servidor, ferramenta, args) {
  const a = args && typeof args === 'object' ? args : {}
  if (servidor === 'supabase') {
    if (/^(delete_|reset_|merge_|rebase_|create_branch|create_project|pause_|restore_|create_edge_function_secret|update_.*(auth|config|setting))/.test(ferramenta)) {
      return { regra: 'supabase-ferramenta', porque: `a ferramenta ${ferramenta} apaga, repõe, publica ramos, gasta dinheiro ou mexe em definições: não é do Dipsy.` }
    }
    if (ferramenta === 'execute_sql' || ferramenta === 'apply_migration') {
      const r = sqlRisco(a.query ?? a.sql)
      if (r) return { regra: 'sql', porque: r }
    }
    if (ferramenta === 'deploy_edge_function') {
      const nome = String(a.name ?? '').toLowerCase()
      if (FUNCOES_PROTEGIDAS.test(nome)) return { regra: 'edge-protegida', porque: `a função ${nome} é de dinheiro ou despacho: prepara e espera o "autorizo".` }
    }
    return null
  }
  if (servidor === 'google') {
    if (/(send|delete|trash|empty|share|transfer|permission|batch_modify|forward)/.test(ferramenta)) {
      return { regra: 'google', porque: `a ferramenta ${ferramenta} envia, apaga ou partilha: o Dipsy só lê e faz rascunhos.` }
    }
    return null
  }
  if (servidor === 'cortex') {
    if (/aprovar|rejeitar|nova_ordem/.test(ferramenta)) {
      return { regra: 'cortex', porque: `a ferramenta ${ferramenta} decide ou manda em nome do Danilo: não é do Dipsy.` }
    }
    return null
  }
  return null
}

// ---------- entrada principal ----------
const FERRAMENTAS_FS_ESCRITA = new Set(['write'])
const EDITOR_ESCRITA = new Set(['create', 'str_replace', 'insert'])

export function avaliar(nome, argumentos) {
  const n = String(nome ?? '')
  const args = argumentos && typeof argumentos === 'object' ? argumentos : {}

  const m = /^mcp__([^_]+(?:_[^_]+)*?)__(.+)$/.exec(n)
  if (m) return avaliarMcp(m[1], m[2], args)

  if (n === 'pwsh' || n === 'bash') return avaliarTextoDeComando(args.command)

  if (n === 'read') {
    const t = textoLimpo(args.file_path)
    const s = segredo(t)
    return s ? { regra: 'segredos', porque: `${s} é segredo: o Dipsy não o lê.` } : null
  }
  if (n === 'grep' || n === 'glob') {
    const t = textoLimpo([args.path, args.glob, args.pattern].filter(Boolean).join(' '))
    const s = segredo(t)
    return s ? { regra: 'segredos', porque: `${s} é segredo: o Dipsy não o procura.` } : null
  }
  if (FERRAMENTAS_FS_ESCRITA.has(n) || (n === 'str_replace_editor' && EDITOR_ESCRITA.has(String(args.command)))) {
    const t = textoLimpo(args.file_path ?? args.path)
    const s = segredo(t)
    if (s) return { regra: 'segredos', porque: `${s} é segredo: o Dipsy não o escreve.` }
    const p = protegidoEscrita(t)
    if (p) return { regra: 'ficheiro-protegido', porque: `${p} não se escreve pelo Dipsy.` }
    return null
  }
  if (n === 'str_replace_editor') {
    const s = segredo(textoLimpo(args.path))
    return s ? { regra: 'segredos', porque: `${s} é segredo: o Dipsy não o lê.` } : null
  }
  if (n === 'ver_imagem') {
    const o = String(args.origem ?? '')
    if (o && o.toLowerCase() !== 'ecra') {
      const s = segredo(textoLimpo(o))
      if (s) return { regra: 'segredos', porque: `${s} é segredo: o Dipsy não o envia a ninguém.` }
    }
    return null
  }
  if (n === 'captura_ecra' || n === 'web_search' || n === 'working_directory') return null

  // qualquer outra ferramenta (run_code, etc.): lê todos os textos como se fossem comandos
  for (const s of strings(args)) {
    const r = avaliarTextoDeComando(s)
    if (r) return r
  }
  return null
}

export const FERRAMENTAS_DE_RISCO = new Set(['pwsh', 'bash', 'write', 'str_replace_editor', 'run_code'])

export function mensagem(r) {
  return `BLOQUEADO pela guarda do Dipsy (regra ${r.regra}): ${r.porque} Não tentes outro caminho nem contornes: diz ao Danilo o que querias fazer e segue com o resto.`
}
