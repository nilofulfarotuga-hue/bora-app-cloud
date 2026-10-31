// Guarda do Dipsy (dsh): decide, ANTES de cada chamada de ferramenta, se ela pode correr.
// Código nosso (missão C-liga, 30/10/2026). É a "bora-tranca" do dsh: o dsh não tem hooks, tem este gancho (ctx.tools.guard).
// Funções puras: avaliar(nome, argumentos) devolve null (deixa passar) ou { regra, porque } (barra).
// Limite honesto: lê o TEXTO do comando. Quem esconde o comando (junta letras, codifica) pode escapar; por isso o
// Dipsy também corre com o sandbox de escrita do dsh e com as regras escritas em ~/.agents/AGENTS.md.

import fs from 'node:fs'
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
  const rede = avaliarRedeShell(t)
  if (rede) return rede
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

// ---------- rede: LISTA BRANCA (decisão do Danilo de 31/10, "2 sim"): o Dipsy só fala com sítios nossos ----------
// Fora desta lista nada sai pelo web_fetch nem por comandos de rede na shell (curl, iwr, fetch, git clone...).
// Para acrescentar um sítio: uma linha (dominio ou dominio/caminho) em ~/.dsh/rede-permitida.txt — ficheiro na casa do
// Dipsy, que ele próprio não pode escrever (regra 'ficheiro-protegido'). Quem acrescenta é o Claude Code ou o Danilo.
const REDE_HOSTS = [
  /^(www\.)?boraguarda\.com$/, /^[a-z0-9-]+\.boraguarda\.com$/,
  /^bora-app-web\.pages\.dev$/, /^[a-z0-9-]+\.bora-app-web\.pages\.dev$/,
  /^ojykpzwqrtusfeakzrna\.supabase\.co$/, /^(api\.|www\.)?supabase\.com$/,
  /^srv1786862\.hstgr\.cloud$/, /^[a-z0-9-]+\.srv1786862\.hstgr\.cloud$/,
  /^play\.google\.com$/, /^(apps|itunes)\.apple\.com$/,
  /^localhost$/, /^127\.0\.0\.1$/,
]
// GitHub: só o nosso repositório
const REDE_CAMINHOS = [
  [/^(www\.)?github\.com$/, /^\/nilofulfarotuga-hue\//i],
  [/^raw\.githubusercontent\.com$/, /^\/nilofulfarotuga-hue\//i],
  [/^api\.github\.com$/, /^\/repos\/nilofulfarotuga-hue\//i],
]
const REDE_EXTRA = `${HOME}/.dsh/rede-permitida.txt`
function redeExtra() {
  try {
    return fs.readFileSync(REDE_EXTRA, 'utf8').split(/\r?\n/).map((l) => l.trim().toLowerCase()).filter((l) => l && !l.startsWith('#'))
  } catch { return [] }
}
export function urlPermitida(texto) {
  let u
  try { u = new URL(String(texto)) } catch { return false }
  if (!/^https?:$/.test(u.protocol)) return false
  const h = u.hostname.toLowerCase().replace(/\.$/, '')
  if (REDE_HOSTS.some((re) => re.test(h))) return true
  if (REDE_CAMINHOS.some(([hre, pre]) => hre.test(h) && pre.test(u.pathname))) return true
  for (const e of redeExtra()) {
    const [eh, ...resto] = e.split('/')
    const ep = resto.length ? '/' + resto.join('/') : ''
    if ((h === eh || h.endsWith('.' + eh)) && (!ep || u.pathname.toLowerCase().startsWith(ep))) return true
  }
  return false
}
const REDE_VERBO = /\b(curl|wget|iwr|irm|invoke-webrequest|invoke-restmethod|start-bitstransfer|certutil|bitsadmin|downloadstring|downloadfile|net\.webclient|httpclient|urllib|requests\.(get|post|put)|httpx|aiohttp|fetch\s*\(|axios|https?\.(get|request)\s*\(|git\s+(clone|fetch|pull|ls-remote|remote\s+add|submodule)|npx|pip3?\s+install|python\s+-m\s+pip)\b/
function avaliarRedeShell(t) {
  if (!REDE_VERBO.test(t)) return null
  for (const m of t.matchAll(/https?:\/\/[^\s"'<>`|;)]+/gi)) {
    if (!urlPermitida(m[0])) {
      let h = m[0]
      try { h = new URL(m[0]).hostname } catch { /* fica o texto */ }
      return { regra: 'rede-fora-da-lista', porque: `${h} não está na lista dos sítios do Bora; o Dipsy só fala com sítios nossos (para abrir outro, o Claude Code acrescenta-o a ~/.dsh/rede-permitida.txt).` }
    }
  }
  return null
}

// ---------- saídas para a web (web_fetch, web_search): nada de levar dados para fora no endereço ----------
const SUMIDOUROS =/(^|\.)(api\.telegram\.org|graph\.facebook\.com|pastebin\.com|webhook\.site|requestbin\.[a-z]+|ngrok(-free)?\.(app|io|dev)|transfer\.sh|file\.io|0x0\.st|hooks\.slack\.com|discord(app)?\.com|ifttt\.com|pipedream\.net|burpcollaborator\.net|oast\.[a-z]+|interact\.sh)$/i
function avaliarSaidaWeb(args) {
  for (const s of strings(args)) {
    if (/(sbp_[A-Za-z0-9_-]{12,}|eyJ[A-Za-z0-9_-]{15,}|AIza[0-9A-Za-z_-]{20,}|\bsk-[A-Za-z0-9]{20,}|\b\d{8,10}:[A-Za-z0-9_-]{30,}|-----BEGIN)/.test(s)) {
      return { regra: 'saida-web', porque: 'isto parece uma chave ou um segredo: não sai para a internet.' }
    }
    for (const m of s.matchAll(/https?:\/\/[^\s"'<>]+/gi)) {
      let u
      try { u = new URL(m[0]) } catch { continue }
      if (SUMIDOUROS.test(u.hostname)) return { regra: 'saida-web', porque: `${u.hostname} é um sítio onde se despejam dados ou se mandam mensagens; o Dipsy não lhe fala.` }
      if (/^(169\.254\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(u.hostname) || u.hostname === 'metadata.google.internal') {
        return { regra: 'saida-web', porque: 'endereços da rede interna ou de metadados da cloud não se visitam.' }
      }
      if ((u.search ?? '').length > 160 || /[A-Za-z0-9+/=_-]{60,}/.test(u.search ?? '')) {
        return { regra: 'saida-web', porque: 'o endereço leva dados a mais (uma pergunta comprida ou um bloco codificado): é assim que se tira informação para fora.' }
      }
      if (!urlPermitida(m[0])) {
        return { regra: 'rede-fora-da-lista', porque: `${u.hostname} não está na lista dos sítios do Bora; o Dipsy só fala com sítios nossos (para abrir outro, o Claude Code acrescenta-o a ~/.dsh/rede-permitida.txt).` }
      }
    }
  }
  // o próprio endereço pedido tem de estar na lista (apanha também ftp:, file:, endereços sem esquema...)
  const alvo = args.url ?? args.uri ?? args.href
  if (alvo !== undefined && !urlPermitida(alvo)) {
    return { regra: 'rede-fora-da-lista', porque: 'esse endereço não está na lista dos sítios do Bora (só https/http para sítios nossos).' }
  }
  return null
}

// ---------- SQL só de leitura (Creator Mode e modo Planear) ----------
export function sqlSoLeitura(sql) {
  const q = String(sql ?? '').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*/g, ' ').replace(/'(?:[^']|'')*'/g, "''").replace(/"(?:[^"]|"")*"/g, '"x"').toLowerCase().replace(/\s+/g, ' ').trim().replace(/;\s*$/, '')
  if (!q) return 'a consulta está vazia.'
  if (!/^(select|with|explain(?!\s+analy[sz]e))\b/.test(q)) return 'só se aceitam consultas de leitura (SELECT ou WITH ... SELECT).'
  if (q.includes(';')) return 'uma consulta só: nada de vários comandos separados por ponto e vírgula.'
  if (/\b(insert|update|delete|merge|upsert|create|alter|drop|truncate|grant|revoke|copy|call|do|perform|vacuum|analy[sz]e|refresh|lock|listen|notify|comment|security|prepare|execute|set_config|nextval|setval|pg_sleep|dblink|lo_\w+)\b/.test(q)) {
    return 'a consulta tem uma palavra de escrita ou de sistema: só se aceita leitura.'
  }
  return sqlRisco(q)
}
export function temSegredo(texto) {
  return segredo(textoLimpo(texto))
}

// ---------- modo Planear (/planear no Telegram): só se lê e se planeia; mexer só depois do /aprovar ----------
const PLANEAR_FERRAMENTAS_ESCRITA = new Set(['write', 'run_code', 'agendar_tarefa', 'cancelar_tarefa', 'memorizar', 'esquecer', 'criar_ferramenta', 'promover_ferramenta', 'apagar_ferramenta', 'libertar_memoria'])
const PLANEAR_SHELL = /\b(git\s+(commit|add|checkout|switch|branch|stash|merge|apply|am|restore|reset|rm|mv|tag|worktree)|dsh-commit\.ps1|npm|pnpm|yarn|pip3?|flutter\s+(pub|create|build|clean)|dart\s+(fix|format))\b/
function avaliarPlanear(n, args) {
  const nao = (o) => ({ regra: 'modo-planear', porque: `estás em modo Planear: agora só se lê e se faz o plano (${o} fica para depois de o Danilo mandar /aprovar).` })
  if (PLANEAR_FERRAMENTAS_ESCRITA.has(n)) return nao(`a ferramenta ${n}`)
  if (n === 'str_replace_editor' && EDITOR_ESCRITA.has(String(args.command))) return nao('editar ficheiros')
  if (n === 'passar_ao_claude_code' && String(args.modo) === 'editar') return nao('pôr o Claude Code a editar')
  if (n === 'pwsh' || n === 'bash') {
    const t = textoLimpo(args.command)
    const t2 = t.replace(/\d?>\s*&\d|\d>\s*(\$null|\/dev\/null|nul)\b/g, ' ')
    if (VERBO_ESCRITA.test(t2) || PLANEAR_SHELL.test(t)) return nao('este comando, que muda coisas')
    return null
  }
  const m = /^mcp__([^_]+(?:_[^_]+)*?)__(.+)$/.exec(n)
  if (m) {
    const [, servidor, f] = m
    if (servidor === 'supabase' && (f === 'apply_migration' || f === 'deploy_edge_function' || /^(create_|update_|delete_)/.test(f))) return nao(`a ferramenta ${f}`)
    if (servidor === 'supabase' && f === 'execute_sql' && sqlSoLeitura(args.query ?? args.sql)) return nao('SQL que não é só de leitura')
    if (servidor === 'google' && /(draft|create|update|modify|label)/.test(f)) return nao(`a ferramenta ${f}`)
    if (servidor === 'cortex' && /(escrever|propor|memorizar|reportar|nova_ordem)/.test(f)) return nao(`a ferramenta ${f}`)
  }
  return null
}

// ---------- entrada principal ----------
const FERRAMENTAS_FS_ESCRITA = new Set(['write'])
const EDITOR_ESCRITA = new Set(['create', 'str_replace', 'insert'])

export function avaliar(nome, argumentos, opcoes = {}) {
  const n = String(nome ?? '')
  const args = argumentos && typeof argumentos === 'object' ? argumentos : {}

  if (opcoes.modo === 'planear') {
    const p = avaliarPlanear(n, args)
    if (p) return p
  }

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
  if (n === 'web_search') {
    return { regra: 'rede-fora-da-lista', porque: 'a pesquisa na internet vai a um motor de terceiros, fora da lista dos sítios do Bora; para pesquisar, pede ao Claude Code.' }
  }
  if (n === 'web_fetch') return avaliarSaidaWeb(args)
  if (n === 'captura_ecra' || n === 'working_directory') return null

  // qualquer outra ferramenta (run_code, etc.): lê todos os textos como se fossem comandos
  for (const s of strings(args)) {
    const r = avaliarTextoDeComando(s)
    if (r) return r
  }
  return null
}

export const FERRAMENTAS_DE_RISCO = new Set(['pwsh', 'bash', 'write', 'str_replace_editor', 'run_code'])

// ---------- guarda dos EXECUTORES automáticos do Claude Code (claude -p): decisão 11 do Danilo, 31/10 ----------
// Mais estreita do que a do Dipsy (os executores fazem trabalho real: editam, correm testes, falam com APIs): só barra o
// que é destrutivo ou mexe em segredos — apagar em massa, apagar tabelas, push forçado, reescrever histórico, git add de
// tudo, sistema, código remoto, matar processos, .env e segredos, e as definições/hooks do próprio Claude Code.
const EXEC_SHELL = new Set(['historia', 'git-add-tudo', 'apagar', 'sistema', 'codigo-remoto', 'matar-processos'])
const PUSH_FORCADO = /\bgit\b[^|;&\n]*\bpush\b[^|;&\n]*(\s--force(-with-lease)?\b|\s-f(?=\s|$)|\s\+\S+:)/
const APAGAR_TABELAS = /\b(drop\s+(table|schema|database|view|function|policy|trigger)\b|truncate\s+(table\s+)?["\w]|delete\s+from\b)/
const EXEC_PROTEGIDO = [
  [/[\\/]\.claude[\\/](hooks|settings[^\\/]*\.json|juiz)/, 'hooks e definições do Claude Code'],
  [/(^|[\\/])\.git[\\/](hooks|config|refs|head)/, 'o interior do git'],
  [/[\\/]\.dsh[\\/](secrets|telegram|agenda|ferramentas|cordis)/, 'a casa do Dipsy'],
  [/bora__dsh-bora|[\\/]dsh-bora[\\/]/, 'a guarda (plugin dsh-bora)'],
]
export function avaliarExecutor(nome, argumentos) {
  const n = String(nome ?? '')
  const a = argumentos && typeof argumentos === 'object' ? argumentos : {}
  if (n === 'Bash' || n === 'PowerShell') {
    const t = textoLimpo(a.command)
    if (!t) return null
    if (testa(PUSH_FORCADO, t)) return { regra: 'push-forcado', porque: 'push forçado reescreve o histórico publicado: nunca.' }
    for (const [id, re, porque] of SHELL) if (EXEC_SHELL.has(id) && testa(re, t)) return { regra: id, porque }
    if (APAGAR_TABELAS.test(t)) return { regra: 'apagar-tabelas', porque: 'apagar tabelas ou dados (DROP, TRUNCATE, DELETE FROM) não se faz por um executor automático.' }
    const s = segredo(t)
    if (s) return { regra: 'segredos', porque: `${s} é segredo: um executor automático não lhe mexe.` }
    const t2 = t.replace(/\d?>\s*&\d|\d>\s*(\$null|\/dev\/null|nul)\b/g, ' ')
    for (const [re, nomeP] of EXEC_PROTEGIDO) if (re.test(t2) && VERBO_ESCRITA.test(t2)) return { regra: 'ficheiro-protegido', porque: `${nomeP} não se escreve por um executor automático.` }
    return null
  }
  const caminho = textoLimpo(a.file_path ?? a.path ?? a.notebook_path ?? '')
  if (['Read', 'Grep', 'Glob'].includes(n)) {
    const s = segredo(textoLimpo([a.file_path, a.path, a.pattern, a.glob].filter(Boolean).join(' ')))
    return s ? { regra: 'segredos', porque: `${s} é segredo: um executor automático não o lê.` } : null
  }
  if (['Write', 'Edit', 'MultiEdit', 'NotebookEdit'].includes(n)) {
    const s = segredo(caminho)
    if (s) return { regra: 'segredos', porque: `${s} é segredo: um executor automático não o escreve.` }
    for (const [re, nomeP] of EXEC_PROTEGIDO) if (re.test(caminho)) return { regra: 'ficheiro-protegido', porque: `${nomeP} não se escreve por um executor automático.` }
    return null
  }
  return null
}

export function mensagem(r) {
  return `BLOQUEADO pela guarda do Dipsy (regra ${r.regra}): ${r.porque} Não tentes outro caminho nem contornes: diz ao Danilo o que querias fazer e segue com o resto.`
}
