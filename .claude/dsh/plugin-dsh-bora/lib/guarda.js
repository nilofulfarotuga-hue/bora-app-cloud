// Guarda do Dipsy (dsh): decide, ANTES de cada chamada de ferramenta, se ela pode correr.
// Código nosso (missão C-liga, 30/10/2026). É a "bora-tranca" do dsh: o dsh não tem hooks, tem este gancho (ctx.tools.guard).
// Funções puras: avaliar(nome, argumentos) devolve null (deixa passar) ou { regra, porque, tipo }.
//   tipo 'barra'    -> nunca corre (regras da casa que nem o "sim" do Danilo levanta, ou que têm outro caminho certo).
//   tipo 'pergunta' -> 08/11/2026 (missão m3-dipsy-acesso-total, ordem do Danilo "Qualquer coisa é só para ele me perguntar:
//                      você permite? Sim."): o plugin pergunta ao Danilo pelo Telegram, com a operação, o valor, o destino e
//                      o comando/SQL exato; só corre com o "sim" dele, uma vez, nos 10 minutos seguintes. Nunca autorização geral.
// Limite honesto: lê o TEXTO do comando. Quem esconde o comando (junta letras, codifica) pode escapar; por isso o
// Dipsy também corre com o sandbox de escrita do dsh, com o proxy de rede e com as regras escritas em ~/.agents/AGENTS.md.

import fs from 'node:fs'
import os from 'node:os'

const HOME = os.homedir().replace(/\\/g, '/').toLowerCase()
const BARRA = 'barra'
const PERGUNTA = 'pergunta'

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
const r = (regra, porque, tipo = BARRA, extra = {}) => ({ regra, porque, tipo, ...extra })

// ---------- segredos (nunca ler; escrever só com o "sim") ----------
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

// ---------- ficheiros que o Dipsy não escreve ----------
// A própria guarda e o que a desliga: nunca (se o Dipsy pudesse mudar a guarda, a pergunta ao Danilo deixava de valer).
const PROTEGIDO_SEMPRE = [
  [/[\\/]\.dsh([\\/]|$)(?![\\/]?(capturas|entrada)([\\/]|$))/, 'a casa do Dipsy (~/.dsh: guarda, lista da rede, aprovações)'],
  [/\.agents[\\/]agents\.md/, 'as regras do Dipsy (~/.agents/AGENTS.md)'],
  [/[\\/]\.claude[\\/](hooks|juiz|plugins|settings|agents|cache|claude\.md)/, 'tranca, juiz ou definições do Claude Code'],
  [/(^|[\\/])\.git[\\/](hooks|config|refs|head)/, 'o interior do git'],
  [/dsh-bora/, 'o próprio plugin da guarda'],
]
// O que mexe em dinheiro, publica ou muda a versão: só com o "sim" do Danilo.
const PROTEGIDO_PERGUNTA = [
  [/\.github[\\/]workflows/, 'o CI (publica sozinho)'],
  [/(pricing_service|dispatch_engine|dispatch-engine|stripe-webhook|create-payment-intent|create-mbway|finalizepurchase|bora_tokens)/, 'zona protegida do dinheiro'],
  [/supabase[\\/]functions[\\/](refund|charge|payout|wallet|token|pricing)/, 'função de dinheiro'],
  [/(^|[\\/])pubspec\.(yaml|lock)$/, 'pubspec (o versionCode é do CI)'],
]
function protegidoEscrita(t) {
  for (const [re, nome] of PROTEGIDO_SEMPRE) if (re.test(t)) return { nome, tipo: BARRA }
  for (const [re, nome] of PROTEGIDO_PERGUNTA) if (re.test(t)) return { nome, tipo: PERGUNTA }
  return null
}
const VERBO_ESCRITA = /(>>?|\b(set-content|add-content|out-file|new-item|remove-item|move-item|copy-item|rename-item|clear-content|tee-object|tee|sed\s+-i|mv|cp|rm|del|ren|attrib|icacls|takeown|chmod|ln|mklink|touch|truncate|writealltext|writeallbytes|appendalltext|writefile|dd)\b)/

// ---------- shell (pwsh, bash, run_code e qualquer código) ----------
// [id, expressão, porque, tipo]
const SHELL = [
  ['push', /\bgit\b[^|;&\n]*\bpush(?=\s|$)/, 'enviar código para o servidor (git push) publica nas lojas e na web: só com o "sim" do Danilo.', PERGUNTA],
  ['historia', /\bgit\b[^|;&\n]*\b(reset\s+--hard|clean\s+-\S*f|rebase(?=\s|$)|filter-branch|filter-repo|commit\s+--amend|reflog\s+(expire|delete)|gc\s+--prune|update-ref\s+-d|branch\s+-d(?=\s|$)|tag\s+-d(?=\s|$)|stash\s+(drop|clear)|checkout\s+--(?=\s)|restore\s+\.(?=\s|$)|worktree\s+(remove|prune))/, 'mexer ou apagar histórico do git não se faz (nunca reescrever histórico publicado), nem com "sim".', BARRA],
  ['git-add-tudo', /\bgit\b[^|;&\n]*\badd\s+(-a(?=\s|$)|--all|\.(?=\s|$)|\*)/, 'git add de tudo apanha o trabalho de outras sessões: adiciona só os ficheiros da tarefa, pelo caminho.', BARRA],
  ['apagar', /(^|[\s;&|(])rm\s+(-[a-z-]*[rf]|[^|;&\n]*\*)|\brmdir\s+\/s|(^|[\s;&|(])rd\s+\/s|\bdel\s+[^|;&\n]*\/[sfq]|(^|[\s;&|(])erase\s|\bremove-item\b[^|;&\n]*(-recurse|-r(?=\s)|-force|-fo(?=\s)|\*)|(^|[\s;&|(])ri\s+[^|;&\n]*-(recurse|force)|shutil\.rmtree|os\.removedirs|fs\.rm(sync)?\([^)]*recursive|find\s[^|;&\n]*-delete|\bgit\s+rm(?=\s)/, 'apagar ficheiros em massa ou à força: só com o "sim" do Danilo.', PERGUNTA],
  ['sistema-disco', /\b(format-volume|format\s+[a-z]:|diskpart|cipher\s+\/w|clear-disk|remove-partition|bcdedit|set-executionpolicy)\b/, 'formatar, apagar discos ou mexer no arranque do Windows nunca é do Dipsy.', BARRA],
  ['sistema', /\b(stop-computer|restart-computer)\b|\bshutdown(\.exe)?\s+\/|\breg(\.exe)?\s+(add|delete|import|load)\b|\bschtasks(\.exe)?\s+\/(create|delete|change)|register-scheduledtask|unregister-scheduledtask|new-service|\bsc(\.exe)?\s+(create|delete|config)\b|netsh\s+advfirewall|set-itemproperty\s+[^|;&\n]*hk(lm|cu)/, 'mexer no sistema (registo, tarefas marcadas, serviços, firewall, desligar o PC): só com o "sim" do Danilo.', PERGUNTA],
  ['codigo-remoto', /\b(curl|wget|iwr|invoke-webrequest|irm|invoke-restmethod)\b[^\n]*\|\s*(sh|bash|iex|invoke-expression|powershell|pwsh|python|node)\b|(^|[\s;|(])iex\s*[(\s]|\binvoke-expression\b|-encodedcommand|\s-enc\s/, 'descarregar e correr código à pressa (curl | sh, iex, comandos codificados) não se faz: a guarda não consegue ler o que vai correr.', BARRA],
  ['instalar', /\b(npm|pnpm|yarn)\s+(i|install|add)\s[^|;&\n]*(-g|--global)\b|\b(winget|choco|scoop)\s+install\b|\bdsh\s+plugin\b|\bnpx\s+(-y\s+)?(degit|create-)/, 'instalar programas ou plugins no PC: só com o "sim" do Danilo.', PERGUNTA],
  ['npm-config', /\bnpm\s+(config\s+(set|delete|edit)|cache\s+(clean|rm))\b|\bnpm\s+set\b/, 'mexer na configuração ou na cache do npm: só com o "sim" do Danilo.', PERGUNTA],
  ['supabase-cli', /\bsupabase(\.exe)?\s+(db|functions|secrets|projects|branches|migration|link|login|logout|start|stop)\b|\bpsql(\.exe)?\b|\bpg_(dump|restore)\b/, 'mexer na base de produção pela linha de comandos: só com o "sim" do Danilo (o normal é o MCP do Supabase).', PERGUNTA],
  ['dinheiro-stripe', /\bstripe(\.exe)?\s/, 'Stripe é dinheiro: só com o "sim" do Danilo.', PERGUNTA],
  ['matar-processos', /\btaskkill\b|\bstop-process\b|\bpkill\b|(^|[\s;&|(])kill\s+-9/, 'matar processos pode derrubar sessões do Danilo (Claude Code, controlo remoto): só com o "sim" dele.', PERGUNTA],
  ['mensagens-fora', /api\.telegram\.org|graph\.facebook\.com|\bsend-mailmessage\b|\bsendmail\b|\bsmtp(lib|client)?\b|wa\.me\/|whatsapp.*send/, 'enviar mensagens ou publicar para fora: só com o "sim" do Danilo.', PERGUNTA],
]
const PUSH_FORCADO = /\bgit\b[^|;&\n]*\bpush\b[^|;&\n]*(\s--force(-with-lease)?\b|\s-f(?=\s|$)|\s\+\S+:|\s--mirror\b|\s--delete\b|\s-d(?=\s|$))/

// ---------- REA (engenharia reversa): só nas NOSSAS coisas (regra do Danilo de 19/10 e 13/10) ----------
const REA_CHAMADO = /\brea-agents\b|rea-bora\.ps1|scripts[\\/]rea\.mjs|(^|[\s;&|(])rea(\.cmd|\.exe)?\s+[a-z]/
const REA_HOSTS = [/^(www\.)?boraguarda\.com$/, /^[a-z0-9-]+\.boraguarda\.com$/, /^ojykpzwqrtusfeakzrna\.supabase\.co$/, /^localhost$/, /^127\.0\.0\.1$/]
function avaliarRea(t) {
  if (!REA_CHAMADO.test(t)) return null
  if (/\brea-agents(@\S+)?\s+(setup|mcp|install|update)\b/.test(t)) {
    return r('rea-config', 'o setup do REA mexe nas configurações dos agentes do Danilo: não é do Dipsy (o REA já está instalado).')
  }
  if (/\b(observe-native-calls|instrument-with-frida|start-frida-session|load-frida-script|debug-with-gdb|debug-with-rizin|capture-process|capture-native-ui-scenario|capture-electron-scenario|start-gdb-session|trace-native-values|observe-native-ui)\b/.test(t)) {
    return r('rea-processos', 'espiar ou instrumentar processos do PC (podem ser apps do Danilo) não se faz: o REA só serve para o nosso APK, os nossos sites e as nossas Edge Functions.')
  }
  for (const m of t.matchAll(/https?:\/\/([^\/\s"'?#:]+)/g)) {
    if (!REA_HOSTS.some((re) => re.test(m[1]))) return r('rea-terceiros', `o REA só se aponta ao que é nosso (boraguarda.com, a nossa API do Supabase, o nosso APK); ${m[1]} é de terceiros.`)
  }
  for (const m of t.matchAll(/[^\s"']+\.(apk|aab|ipa|xapk)\b/g)) {
    if (!/bora/.test(m[0]) || /ifood|glovo|uber|bolt/.test(m[0])) return r('rea-terceiros', `só o nosso APK (pt.boraapp.bora): ${m[0].slice(-60)} não parece ser.`)
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
    return r('commit-sem-juiz', 'todo o commit do Dipsy passa pelo Juiz: usa o script dsh-commit.ps1 (corre o anti-trapaça e só então faz o commit).')
  }
  if (testa(PUSH_FORCADO, t)) return r('push-forcado', 'push forçado ou a apagar ramos reescreve o histórico publicado: nunca, nem com "sim".')
  const rea = avaliarRea(t)
  if (rea) return rea
  // primeiro o que nunca corre; depois o que pergunta (a pergunta mais séria ganha)
  for (const [id, re, porque, tipo] of SHELL) if (tipo === BARRA && testa(re, t)) return r(id, porque, tipo)
  const semRegisto = avaliarRedeSemRegisto(t)
  if (semRegisto) return semRegisto
  const s = segredo(t)
  if (s) return r('segredos', `${s} é segredo: o Dipsy não o lê nem o escreve pela shell (o que lê vai para o motor de IA).`)
  const p = protegidoEscrita(t2)
  if (p && p.tipo === BARRA && VERBO_ESCRITA.test(t2)) return r('ficheiro-protegido', `${p.nome} não se escreve pelo Dipsy.`)
  const rede = avaliarRedeShell(t)
  if (rede && rede.tipo === BARRA) return rede
  for (const [id, re, porque, tipo] of SHELL) if (tipo === PERGUNTA && testa(re, t)) return r(id, porque, tipo, dominiosDoComando(id, t))
  if (p && VERBO_ESCRITA.test(t2)) return r('ficheiro-protegido', `${p.nome}: escrever aqui só com o "sim" do Danilo.`, PERGUNTA)
  if (rede) return rede
  return null
}

function dominiosDoComando(id, t) {
  const doms = new Set()
  for (const m of t.matchAll(/https?:\/\/([^\/\s"'?#:]+)/g)) doms.add(m[1])
  if (id === 'push') doms.add('github.com')
  if (id === 'dinheiro-stripe') doms.add('api.stripe.com')
  if (id === 'mensagens-fora' && /api\.telegram\.org/.test(t)) doms.add('api.telegram.org')
  if (id === 'mensagens-fora' && /graph\.facebook\.com/.test(t)) doms.add('graph.facebook.com')
  return doms.size ? { dominios: [...doms] } : {}
}

// ---------- SQL (MCP do Supabase) ----------
const TABELAS = ['orders', 'tvde_rides', 'appointments', 'drivers', 'client_wallets', 'wallets', 'ledger_entries', 'bora_tokens', 'driver_balances', 'payouts', 'platform_settings']
const T = `(?:public\\.)?"?(?:${TABELAS.join('|')})"?(?![\\w])`
const FUNCOES_DINHEIRO = '(?:admin_|finalize|credit_|debit_|refund|payout|settle|award|apply_|wallet|ledger|create_order|place_order|cancel_order|ops_(?!reassign_order\\b|release_order_driver\\b))'
const TEM_BACKUP = /create\s+table\s+(if\s+not\s+exists\s+)?(public\.)?"?bkp_\w+"?\s+as\s+select/

// devolve { porque, tipo } ou null
export function sqlAvaliar(sql) {
  let q = String(sql ?? '').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--[^\n]*/g, ' ').toLowerCase().replace(/\s+/g, ' ')
  const comBackup = TEM_BACKUP.test(q)
  // backup antes de corrigir (regra bkp_<nome>_AAAAMMDD) é permitido: copiar não altera nada
  q = q.replace(/create\s+table\s+(if\s+not\s+exists\s+)?(public\.)?"?bkp_\w+"?\s+as\s+select[^;]*/g, ' ')
  if (!q.trim()) return null
  const apagaDados = (porque) => comBackup
    ? { porque: `${porque} Há backup bkp_ no mesmo SQL: só com o "sim" do Danilo.`, tipo: PERGUNTA }
    : { porque: `${porque} Nunca se apagam dados de produção sem backup: faz primeiro, no MESMO SQL, create table bkp_<nome>_AAAAMMDD as select ...; aí pergunta-se ao Danilo.`, tipo: BARRA }
  const regras = [
    [/\b(pg_terminate_backend|pg_cancel_backend|pg_reload_conf|lo_import|lo_export|pg_read_file|pg_ls_dir|copy\s+[^;]*\bprogram)\b/, () => ({ porque: 'funções de sistema perigosas (matar ligações, ler ficheiros do servidor) nunca.', tipo: BARRA })],
    [/\bdrop\s+(table|schema|database|materialized|sequence|column)\b/, () => apagaDados('Apagar tabelas ou colunas (DROP) apaga dados.')],
    [/\btruncate\b/, () => apagaDados('Esvaziar tabelas (TRUNCATE) apaga dados.')],
    [/\bdelete\s+from\b/, () => apagaDados('DELETE apaga dados.')],
    [/\balter\s+table\b[^;]*\bdrop\s+(column\s+)?(?!constraint|policy|trigger|index|default|not\s+null|identity)\w/, () => apagaDados('Apagar colunas (ALTER TABLE ... DROP COLUMN) apaga dados.')],
    [/\bdrop\s+(function|policy|trigger|view|index|extension|role|user|type|publication|constraint)\b|\balter\s+table\b[^;]*\bdrop\b/, () => ({ porque: 'apagar estrutura (funções, regras, gatilhos, vistas): só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\b(disable|no\s+force)\s+row\s+level|\balter\s+table\b[^;]*\b(disable\s+row|no\s+force)/, () => ({ porque: 'desligar a segurança por linha (RLS): só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [new RegExp(`\\b(update|insert\\s+into|merge\\s+into|upsert\\s+into)\\s+(only\\s+)?${T}`), () => ({ porque: 'escrever nas tabelas de pedidos, estafetas, carteiras, tokens ou preços: só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [new RegExp(`\\b(create|alter|drop|comment\\s+on)\\b[^;]*\\b(table|policy|trigger|function|view|index)\\b[^;]*${T}`), () => ({ porque: 'estrutura das tabelas de dinheiro e pedidos: só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\b(bora_tokens|award_tokens|finalize_?purchase|dispatch_engine|pricing_service)\b/, () => ({ porque: 'zona protegida do dinheiro e do despacho: só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\b(grant|revoke)\b/, () => ({ porque: 'dar ou tirar permissões (GRANT/REVOKE): só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\balter\s+(role|user|system|database)\b|\bcreate\s+(role|user|extension)\b/, () => ({ porque: 'papéis, extensões e definições do servidor: só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\bcron\.(schedule|unschedule|alter_job)\b/, () => ({ porque: 'tarefas agendadas (pg_cron): só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\bauth\.users\b[^;]*\b(update|delete|insert)\b|\b(update|delete\s+from|insert\s+into)\s+auth\.users\b/, () => ({ porque: 'contas de utilizadores (auth.users): só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [/\bstorage\.(objects|buckets)\b[^;]*\b(update|delete|insert)\b|\b(update|delete\s+from|insert\s+into)\s+storage\./, () => ({ porque: 'ficheiros guardados (storage): só com o "sim" do Danilo.', tipo: PERGUNTA })],
    [new RegExp(`\\b(select|perform|call)\\s+(public\\.)?${FUNCOES_DINHEIRO}`), () => ({ porque: 'função que mexe em dinheiro ou pedidos: só com o "sim" do Danilo (sem pergunta: ops_reassign_order e ops_release_order_driver).', tipo: PERGUNTA })],
  ]
  for (const [re, f] of regras) if (re.test(q)) return f()
  return null
}
// compatibilidade: o texto do porquê, ou null
export function sqlRisco(sql) {
  return sqlAvaliar(sql)?.porque ?? null
}

// ---------- MCP ----------
function avaliarMcp(servidor, ferramenta, args) {
  const a = args && typeof args === 'object' ? args : {}
  if (servidor === 'supabase') {
    if (/^(delete_|reset_|merge_|rebase_|create_branch|create_project|pause_|restore_|create_edge_function_secret|update_.*(auth|config|setting))/.test(ferramenta)) {
      return r('supabase-ferramenta', `a ferramenta ${ferramenta} apaga, repõe, publica ramos, gasta dinheiro ou mexe em segredos e definições: só com o "sim" do Danilo.`, PERGUNTA)
    }
    if (ferramenta === 'execute_sql' || ferramenta === 'apply_migration') {
      const s = sqlAvaliar(a.query ?? a.sql)
      if (s && s.tipo === BARRA) return r('sql', s.porque, BARRA)
      if (ferramenta === 'apply_migration') return r('migracao', `aplicar uma migração muda a base de produção para sempre: só com o "sim" do Danilo.${s ? ' ' + s.porque : ''}`, PERGUNTA)
      if (s) return r('sql', s.porque, PERGUNTA)
      return null
    }
    if (ferramenta === 'deploy_edge_function') {
      return r('publicar-funcao', `publicar a Edge Function ${String(a.name ?? '').slice(0, 60)} em produção: só com o "sim" do Danilo.`, PERGUNTA)
    }
    return null
  }
  if (servidor === 'google') {
    if (/(send|delete|trash|empty|share|transfer|permission|batch_modify|forward)/.test(ferramenta)) {
      return r('google', `a ferramenta ${ferramenta} envia, apaga ou partilha: só com o "sim" do Danilo.`, PERGUNTA)
    }
    return null
  }
  if (servidor === 'cortex') {
    if (/aprovar|rejeitar|nova_ordem/.test(ferramenta)) {
      return r('cortex', `a ferramenta ${ferramenta} decide ou manda em nome do Danilo: só com o "sim" dele.`, PERGUNTA)
    }
    return null
  }
  return null
}

// ---------- rede: CATEGORIAS (08/11, m3) — a mesma lista que o proxy usa (~/.dsh/rede-categorias.yml) ----------
// O proxy (Python) compila a lista para ~/.dsh/proxy/politica.json; a guarda lê esse ficheiro. Sem ele, só passam os
// sítios do Bora e o resto pergunta (falha fechada).
const POLITICA = process.env.DIPSY_POLITICA || `${os.homedir()}/.dsh/proxy/politica.json`
const POLITICA_RESERVA = {
  categorias: { bora: { estado: 'aberta', so_leitura: false, dominios: ['boraguarda.com', 'bora-app-web.pages.dev', 'ojykpzwqrtusfeakzrna.supabase.co', 'supabase.com', 'srv1786862.hstgr.cloud', 'localhost', '127.0.0.1'] } },
  sempre_bloqueado: {}, aprovados: [], recusados: [],
}
let cachePolitica = { mtime: null, pol: null }
function politica() {
  try {
    const m = fs.statSync(POLITICA).mtimeMs
    if (cachePolitica.pol && cachePolitica.mtime === m) return cachePolitica.pol
    const pol = JSON.parse(fs.readFileSync(POLITICA, 'utf8'))
    if (!pol || typeof pol.categorias !== 'object') throw new Error('politica sem categorias')
    cachePolitica = { mtime: m, pol }
    return pol
  } catch {
    return cachePolitica.pol ?? POLITICA_RESERVA
  }
}
function bate(h, d) {
  d = String(d ?? '').toLowerCase().replace(/\.$/, '')
  if (!d) return false
  if (d.endsWith('.*')) return h.startsWith(d.slice(0, -1))
  return h === d || h.endsWith('.' + d)
}
// { decisao: 'permitido'|'barrado'|'pergunta', categoria, motivo, com_sim }
export function decidirHost(host) {
  const h = String(host ?? '').toLowerCase().replace(/\.$/, '').replace(/^\[|\]$/g, '')
  if (!h) return { decisao: 'barrado', motivo: 'endereço vazio' }
  const pol = politica()
  const leitura = Object.entries(pol.categorias ?? {}).find(([n]) => n === 'stripe_leitura')?.[1]
  for (const [nome, g] of Object.entries(pol.sempre_bloqueado ?? {})) {
    if ((g.dominios ?? []).some((d) => bate(h, d))) {
      if (leitura && (leitura.dominios ?? []).some((d) => bate(h, d))) break
      return { decisao: 'barrado', categoria: `sempre_bloqueado:${nome}`, motivo: `${h} está na lista do que fica sempre bloqueado (${nome})`, com_sim: !!g.com_sim }
    }
  }
  if ((pol.recusados ?? []).some((d) => bate(h, d))) return { decisao: 'barrado', categoria: 'recusado', motivo: `o Danilo já disse que não a ${h}` }
  let fechada = null
  for (const [nome, c] of Object.entries(pol.categorias ?? {})) {
    if ((c.dominios ?? []).some((d) => bate(h, d))) {
      if (String(c.estado ?? 'aberta') !== 'aberta') { fechada = nome; continue }
      return { decisao: 'permitido', categoria: nome }
    }
  }
  if (fechada) return { decisao: 'barrado', categoria: fechada, motivo: `a categoria ${fechada} está fechada (o Danilo abre-a com /rede abrir ${fechada})` }
  if ((pol.aprovados ?? []).some((d) => bate(h, d))) return { decisao: 'permitido', categoria: 'aprovado' }
  return { decisao: 'pergunta', motivo: `${h} não está em nenhuma categoria` }
}
function avaliarUrl(texto) {
  let u
  try { u = new URL(String(texto)) } catch { return r('rede-endereco', 'esse endereço não é um endereço da web válido (só https e http).') }
  if (!/^https?:$/.test(u.protocol)) return r('rede-endereco', 'só se abrem endereços https e http.')
  const d = decidirHost(u.hostname)
  if (d.decisao === 'permitido') return null
  if (d.decisao === 'pergunta') return r('rede-fora-da-lista', `${u.hostname} não está em nenhuma categoria da rede: pergunta-se ao Danilo se pode abrir (e a resposta fica na lista).`, PERGUNTA, { dominios: [u.hostname], rede: true })
  if (d.com_sim) return r('rede-com-sim', `${d.motivo}: abre 10 minutos só com o "sim" do Danilo a esta ação concreta.`, PERGUNTA, { dominios: [u.hostname] })
  return r('rede-bloqueada', `${d.motivo}.`, BARRA)
}

// Lista ANTIGA dos sítios do Bora (31/10): fica para o Creator Mode, cujas ferramentas criadas só leem sítios nossos.
const REDE_HOSTS = [
  /^(www\.)?boraguarda\.com$/, /^[a-z0-9-]+\.boraguarda\.com$/,
  /^bora-app-web\.pages\.dev$/, /^[a-z0-9-]+\.bora-app-web\.pages\.dev$/,
  /^ojykpzwqrtusfeakzrna\.supabase\.co$/, /^(api\.|www\.)?supabase\.com$/,
  /^srv1786862\.hstgr\.cloud$/, /^[a-z0-9-]+\.srv1786862\.hstgr\.cloud$/,
  /^play\.google\.com$/, /^(apps|itunes)\.apple\.com$/,
  /^localhost$/, /^127\.0\.0\.1$/,
]
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

// 08/11 (m3): na shell do Dipsy só há o PowerShell 5.1, cujo Invoke-WebRequest/Invoke-RestMethod e o WebClient do .NET
// IGNORAM o HTTPS_PROXY e iam direto à internet, sem registo (provado: "Não foi possível resolver o nome remoto").
const REDE_PS_DIRETO = /\b(net\.webclient|system\.net\.http\.httpclient|downloadstring|downloadfile|start-bitstransfer|bitsadmin)\b|\bcertutil\b[^|;&\n]*-urlcache/
const REDE_PS_CMDLET = /\b(invoke-webrequest|iwr|invoke-restmethod|irm)\b/
const PROXY_DIPSY = /-proxy\s+["']?http:\/\/(127\.0\.0\.1|localhost):47900/
function avaliarRedeSemRegisto(t) {
  if (REDE_PS_DIRETO.test(t)) return r('rede-sem-registo', 'isto liga à internet por fora do proxy com registo do Dipsy: usa web_fetch ou pesquisar_internet (ou python/node, que passam pelo proxy).')
  if (REDE_PS_CMDLET.test(t) && /https?:\/\//.test(t) && !PROXY_DIPSY.test(t)) {
    return r('rede-sem-registo', 'o Invoke-WebRequest/Invoke-RestMethod do PowerShell 5.1 ignora o proxy com registo do Dipsy e iria direto: acrescenta -Proxy http://127.0.0.1:47900, ou usa web_fetch.')
  }
  return null
}
const REDE_VERBO = /\b(curl|wget|iwr|irm|invoke-webrequest|invoke-restmethod|start-bitstransfer|certutil|bitsadmin|downloadstring|downloadfile|net\.webclient|httpclient|urllib|requests\.(get|post|put)|httpx|aiohttp|fetch\s*\(|axios|https?\.(get|request)\s*\(|git\s+(clone|fetch|pull|ls-remote|remote\s+add|submodule)|npx|pip3?\s+install|python\s+-m\s+pip)\b/
function avaliarRedeShell(t) {
  if (!REDE_VERBO.test(t)) return null
  let pergunta = null
  for (const m of t.matchAll(/https?:\/\/[^\s"'<>`|;)]+/gi)) {
    const x = avaliarUrl(m[0])
    if (x && x.tipo === BARRA) return x
    if (x && !pergunta) pergunta = x
  }
  return pergunta
}

// ---------- saídas para a web (web_fetch, pesquisa): nada de levar dados para fora no endereço ----------
const SUMIDOUROS = /(^|\.)(api\.telegram\.org|graph\.facebook\.com|pastebin\.com|webhook\.site|requestbin\.[a-z]+|ngrok(-free)?\.(app|io|dev)|transfer\.sh|file\.io|0x0\.st|hooks\.slack\.com|discord(app)?\.com|ifttt\.com|pipedream\.net|burpcollaborator\.net|oast\.[a-z]+|interact\.sh)$/i
const PARECE_SEGREDO = /(sbp_[A-Za-z0-9_-]{12,}|eyJ[A-Za-z0-9_-]{15,}|AIza[0-9A-Za-z_-]{20,}|\bsk-[A-Za-z0-9]{20,}|\b\d{8,10}:[A-Za-z0-9_-]{30,}|-----BEGIN)/
function avaliarSaidaWeb(args) {
  let pergunta = null
  for (const s of strings(args)) {
    if (PARECE_SEGREDO.test(s)) return r('saida-web', 'isto parece uma chave ou um segredo: não sai para a internet.')
    for (const m of s.matchAll(/https?:\/\/[^\s"'<>]+/gi)) {
      let u
      try { u = new URL(m[0]) } catch { continue }
      if (SUMIDOUROS.test(u.hostname)) return r('saida-web', `${u.hostname} é um sítio onde se despejam dados ou se mandam mensagens; o Dipsy não lhe fala pelo web_fetch.`)
      if (/^(169\.254\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(u.hostname) || u.hostname === 'metadata.google.internal') {
        return r('saida-web', 'endereços da rede interna ou de metadados da cloud não se visitam.')
      }
      if ((u.search ?? '').length > 160 || /[A-Za-z0-9+/=_-]{60,}/.test(u.search ?? '')) {
        return r('saida-web', 'o endereço leva dados a mais (uma pergunta comprida ou um bloco codificado): é assim que se tira informação para fora.')
      }
      const x = avaliarUrl(m[0])
      if (x && x.tipo === BARRA) return x
      if (x && !pergunta) pergunta = x
    }
  }
  if (pergunta) return pergunta
  // o próprio endereço pedido tem de ser válido (apanha também ftp:, file:, endereços sem esquema...)
  const alvo = args.url ?? args.uri ?? args.href
  if (alvo !== undefined) return avaliarUrl(alvo)
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
  const nao = (o) => r('modo-planear', `estás em modo Planear: agora só se lê e se faz o plano (${o} fica para depois de o Danilo mandar /aprovar).`)
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
    const x = avaliarBase(n, args)
    // em modo Planear não se pergunta nada ao Danilo: o que precisaria do sim fica para depois do /aprovar
    return x && x.tipo === PERGUNTA ? r('modo-planear', `estás em modo Planear: ${x.porque} Fica para depois de o Danilo mandar /aprovar.`) : x
  }
  return avaliarBase(n, args)
}

function avaliarBase(n, args) {

  const m = /^mcp__([^_]+(?:_[^_]+)*?)__(.+)$/.exec(n)
  if (m) return avaliarMcp(m[1], m[2], args)

  if (n === 'pwsh' || n === 'bash') return avaliarTextoDeComando(args.command)

  if (n === 'read') {
    const t = textoLimpo(args.file_path)
    const s = segredo(t)
    return s ? r('segredos', `${s} é segredo: o Dipsy não o lê (o que lê vai para o motor de IA).`) : null
  }
  if (n === 'grep' || n === 'glob') {
    const t = textoLimpo([args.path, args.glob, args.pattern].filter(Boolean).join(' '))
    const s = segredo(t)
    return s ? r('segredos', `${s} é segredo: o Dipsy não o procura.`) : null
  }
  if (FERRAMENTAS_FS_ESCRITA.has(n) || (n === 'str_replace_editor' && EDITOR_ESCRITA.has(String(args.command)))) {
    const t = textoLimpo(args.file_path ?? args.path)
    const p = protegidoEscrita(t)
    if (p && p.tipo === BARRA) return r('ficheiro-protegido', `${p.nome} não se escreve pelo Dipsy.`)
    const s = segredo(t)
    if (s) return r('segredos', `escrever em ${s}: só com o "sim" do Danilo.`, PERGUNTA)
    if (p) return r('ficheiro-protegido', `${p.nome}: escrever aqui só com o "sim" do Danilo.`, PERGUNTA)
    return null
  }
  if (n === 'str_replace_editor') {
    const s = segredo(textoLimpo(args.path))
    return s ? r('segredos', `${s} é segredo: o Dipsy não o lê.`) : null
  }
  if (n === 'ver_imagem') {
    const o = String(args.origem ?? '')
    if (o && o.toLowerCase() !== 'ecra') {
      const s = segredo(textoLimpo(o))
      if (s) return r('segredos', `${s} é segredo: o Dipsy não o envia a ninguém.`)
    }
    return null
  }
  // 08/11 (m3): a pesquisa na internet passou a ser permitida (categoria "pesquisa", tudo registado no proxy)
  if (n === 'web_search' || n === 'pesquisar_internet') {
    for (const s of strings(args)) if (PARECE_SEGREDO.test(s)) return r('saida-web', 'isto parece uma chave ou um segredo: não sai para a internet.')
    return null
  }
  if (n === 'web_fetch') return avaliarSaidaWeb(args)
  if (n === 'captura_ecra' || n === 'working_directory' || n === 'esperar_autorizacao') return null

  // qualquer outra ferramenta (run_code, etc.): lê todos os textos como se fossem comandos
  let pergunta = null
  for (const s of strings(args)) {
    const x = avaliarTextoDeComando(s)
    if (x && x.tipo === BARRA) return x
    if (x && !pergunta) pergunta = x
  }
  return pergunta
}

export const FERRAMENTAS_DE_RISCO = new Set(['pwsh', 'bash', 'write', 'str_replace_editor', 'run_code'])

// ---------- o que se mostra ao Danilo na pergunta (operação, valor, destino, o exato) ----------
const OPERACAO_REGRA = {
  push: 'Enviar código para o servidor (git push: publica nas lojas e na web)',
  apagar: 'Apagar ficheiros em massa',
  sistema: 'Mexer no sistema do PC',
  instalar: 'Instalar um programa ou plugin no PC',
  'npm-config': 'Mexer na configuração do npm',
  'supabase-cli': 'Mexer na base de produção pela linha de comandos',
  'dinheiro-stripe': 'Comando da Stripe (dinheiro)',
  'matar-processos': 'Fechar programas à força',
  'mensagens-fora': 'Enviar mensagem ou publicar para fora',
  'ficheiro-protegido': 'Escrever num ficheiro protegido',
  segredos: 'Escrever num ficheiro de segredos',
  'rede-com-sim': 'Abrir um sítio que fica sempre bloqueado (só para esta ação)',
  'supabase-ferramenta': 'Ferramenta do Supabase que apaga, repõe ou mexe em segredos',
  google: 'Enviar, apagar ou partilhar no Google',
  cortex: 'Decidir no Córtex em nome do Danilo',
}
function corta(s, n) {
  s = String(s ?? '').replace(/\s+/g, ' ').trim()
  return s.length > n ? s.slice(0, n - 1) + '…' : s
}
export function tapar(s) {
  return String(s ?? '')
    .replace(/\b\d{8,10}:[A-Za-z0-9_-]{30,}/g, '[segredo tapado]')
    .replace(/\bsbp_[A-Za-z0-9_-]{12,}/g, '[segredo tapado]')
    .replace(/\beyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_.-]{10,}/g, '[segredo tapado]')
    .replace(/\bAIza[0-9A-Za-z_-]{20,}/g, '[segredo tapado]')
    .replace(/\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]{10,}/g, '[segredo tapado]')
    .replace(/\bsk-[A-Za-z0-9_-]{20,}/g, '[segredo tapado]')
    .replace(/\bgh[pousr]_[A-Za-z0-9]{30,}/g, '[segredo tapado]')
    .replace(/-----BEGIN[\s\S]*?-----END[^-]*-----/g, '[segredo tapado]')
}
function partesSql(sql) {
  const q = String(sql ?? '').replace(/\s+/g, ' ').trim()
  const op = /^\s*(update|insert\s+into|delete\s+from|merge\s+into|truncate|drop|alter|create|grant|revoke|select|with)\b\s*(only\s+)?("?[\w.]+"?)?/i.exec(q)
  const verbo = op ? op[1].replace(/\s+/g, ' ').toUpperCase() : 'SQL'
  const tabela = op && op[3] && !/^(select|with)$/i.test(op[1]) ? op[3].replace(/"/g, '') : ''
  const set = /\bset\s+([\s\S]+?)(\bwhere\b|\breturning\b|;|$)/i.exec(q)
  const values = /\b(values\s*\([\s\S]+?\))(\s*on\s+conflict|\s*returning|;|$)/i.exec(q)
  const where = /\bwhere\s+([\s\S]+?)(\breturning\b|;|$)/i.exec(q)
  const semWhere = /^(update|delete)/i.test(verbo) && !where
  return {
    operacao: `${verbo}${tabela ? ' em ' + tabela : ''}`,
    valor: set ? corta(set[1], 300) : values ? corta(values[1], 300) : '-',
    destino: where ? corta(where[1], 300) : semWhere ? 'TODAS as linhas da tabela (não há WHERE!)' : (tabela || '-'),
  }
}
export function descreverAcao(nome, argumentos, res) {
  const n = String(nome ?? '')
  const a = argumentos && typeof argumentos === 'object' ? argumentos : {}
  const base = { operacao: OPERACAO_REGRA[res?.regra] ?? 'Ação que precisa do teu sim', valor: '-', destino: '-', detalhe: '', dominios: res?.dominios ?? [] }
  const m = /^mcp__([^_]+(?:_[^_]+)*?)__(.+)$/.exec(n)
  if (m && m[1] === 'supabase') {
    if (m[2] === 'execute_sql' || m[2] === 'apply_migration') {
      const sql = String(a.query ?? a.sql ?? '')
      const p = partesSql(sql)
      return { ...base, ...p, operacao: (m[2] === 'apply_migration' ? `Aplicar a migração ${corta(a.name, 60)} em produção: ` : 'Na base de produção: ') + p.operacao, detalhe: corta(tapar(sql), 1500) }
    }
    if (m[2] === 'deploy_edge_function') {
      const fich = Array.isArray(a.files) ? a.files : []
      const tam = fich.reduce((s, f) => s + String(f?.content ?? '').length, 0)
      return { ...base, operacao: `Publicar a Edge Function ${corta(a.name, 60)} em produção`, destino: 'Supabase de produção (ojykpzwqrtusfeakzrna)', valor: `${fich.length} ficheiro(s), ${tam} letras`, detalhe: corta(`entrada: ${a.entrypoint_path ?? 'index.ts'}; ficheiros: ${fich.map((f) => f?.name).filter(Boolean).join(', ')}`, 600) }
    }
    return { ...base, operacao: `Supabase: ${m[2]}`, detalhe: corta(tapar(JSON.stringify(a)), 800) }
  }
  if (m) return { ...base, operacao: `${m[1]}: ${m[2]}`, destino: corta(a.to ?? a.recipient ?? a.user_google_email ?? '-', 160), valor: corta(a.subject ?? a.title ?? '-', 200), detalhe: corta(tapar(JSON.stringify(a)), 800) }
  if (n === 'pwsh' || n === 'bash') return { ...base, detalhe: corta(tapar(a.command), 1500) }
  if (n === 'web_fetch') return { ...base, operacao: res?.rede ? `Abrir o sítio ${base.dominios[0] ?? ''}` : base.operacao, destino: corta(a.url, 300), detalhe: corta(tapar(a.url), 600) }
  if (n === 'write' || n === 'str_replace_editor') {
    const conteudo = a.content ?? a.file_text ?? a.new_str ?? ''
    return { ...base, destino: corta(a.file_path ?? a.path, 300), valor: `${String(conteudo).length} letras`, detalhe: corta(tapar(conteudo), 600) }
  }
  return { ...base, detalhe: corta(tapar(JSON.stringify(a)), 1000) }
}

// ---------- guarda dos EXECUTORES automáticos do Claude Code (claude -p): decisão 11 do Danilo, 31/10 ----------
// Mais estreita do que a do Dipsy (os executores fazem trabalho real: editam, correm testes, falam com APIs): só barra o
// que é destrutivo ou mexe em segredos — apagar em massa, apagar tabelas, push forçado, reescrever histórico, git add de
// tudo, sistema, código remoto, matar processos, .env e segredos, e as definições/hooks do próprio Claude Code.
const EXEC_SHELL = new Set(['historia', 'git-add-tudo', 'apagar', 'sistema', 'sistema-disco', 'codigo-remoto', 'matar-processos'])
const PUSH_FORCADO_EXEC = /\bgit\b[^|;&\n]*\bpush\b[^|;&\n]*(\s--force(-with-lease)?\b|\s-f(?=\s|$)|\s\+\S+:)/
const APAGAR_TABELAS = /\b(drop\s+(table|schema|database|view|function|policy|trigger)\b|truncate\s+(table\s+)?["\w]|delete\s+from\b)/
const EXEC_PROTEGIDO = [
  [/[\\/]\.claude[\\/](hooks|settings[^\\/]*\.json|juiz)/, 'hooks e definições do Claude Code'],
  [/(^|[\\/])\.git[\\/](hooks|config|refs|head)/, 'o interior do git'],
  [/[\\/]\.dsh[\\/](secrets|telegram|agenda|ferramentas|cordis|aprovacoes|proxy|rede-categorias)/, 'a casa do Dipsy'],
  [/bora__dsh-bora|[\\/]dsh-bora[\\/]/, 'a guarda (plugin dsh-bora)'],
]
export function avaliarExecutor(nome, argumentos) {
  const n = String(nome ?? '')
  const a = argumentos && typeof argumentos === 'object' ? argumentos : {}
  if (n === 'Bash' || n === 'PowerShell') {
    const t = textoLimpo(a.command)
    if (!t) return null
    if (testa(PUSH_FORCADO_EXEC, t)) return r('push-forcado', 'push forçado reescreve o histórico publicado: nunca.')
    for (const [id, re, porque] of SHELL) if (EXEC_SHELL.has(id) && testa(re, t)) return r(id, porque)
    if (APAGAR_TABELAS.test(t)) return r('apagar-tabelas', 'apagar tabelas ou dados (DROP, TRUNCATE, DELETE FROM) não se faz por um executor automático.')
    const s = segredo(t)
    if (s) return r('segredos', `${s} é segredo: um executor automático não lhe mexe.`)
    const t2 = t.replace(/\d?>\s*&\d|\d>\s*(\$null|\/dev\/null|nul)\b/g, ' ')
    for (const [re, nomeP] of EXEC_PROTEGIDO) if (re.test(t2) && VERBO_ESCRITA.test(t2)) return r('ficheiro-protegido', `${nomeP} não se escreve por um executor automático.`)
    return null
  }
  const caminho = textoLimpo(a.file_path ?? a.path ?? a.notebook_path ?? '')
  if (['Read', 'Grep', 'Glob'].includes(n)) {
    const s = segredo(textoLimpo([a.file_path, a.path, a.pattern, a.glob].filter(Boolean).join(' ')))
    return s ? r('segredos', `${s} é segredo: um executor automático não o lê.`) : null
  }
  if (['Write', 'Edit', 'MultiEdit', 'NotebookEdit'].includes(n)) {
    const s = segredo(caminho)
    if (s) return r('segredos', `${s} é segredo: um executor automático não o escreve.`)
    for (const [re, nomeP] of EXEC_PROTEGIDO) if (re.test(caminho)) return r('ficheiro-protegido', `${nomeP} não se escreve por um executor automático.`)
    return null
  }
  return null
}

export function mensagem(res) {
  return `BLOQUEADO pela guarda do Dipsy (regra ${res.regra}): ${res.porque} Não tentes outro caminho nem contornes: diz ao Danilo o que querias fazer e segue com o resto.`
}
