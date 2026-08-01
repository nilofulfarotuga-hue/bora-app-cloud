# Rotina Claude.ai — aviso automático no Telegram (relatório, 2026-08-01)

> Sessão headless (executor autónomo). Regra: prova por ficheiro, log ou SELECT — não pela
> palavra do executor. Nada aqui tocou dinheiro/pagamentos/zona vermelha.

## 1. O que foi pedido

Quando uma missão fecha, uma ordem fica travada de vez, ou o executor perde a autenticação, o
Danilo quer saber na hora, num resumo em português claro no Telegram, sem pagar API extra e sem
sondar de 10 em 10 minutos. Caminho escolhido: as Rotinas do Claude Code (`claude.ai/code/routines`),
com gatilho por chamada HTTP.

## 2. Limite real e formato — confirmado nos docs oficiais (não assumido)

Fontes lidas ao vivo nesta sessão:
[code.claude.com/docs/en/routines](https://code.claude.com/docs/en/routines) e
[platform.claude.com/docs/en/api/claude-code/routines-fire](https://platform.claude.com/docs/en/api/claude-code/routines-fire).

- **Limite diário de corridas:** Pro = **5/dia**, Max = 15/dia, Team/Enterprise = 25/dia. Ao
  esgotar, `429 rate_limit_error` com `Retry-After`.
- **Custo — atenção, isto é importante:** as corridas da rotina **não são um orçamento à parte**.
  Consomem o **mesmo limite semanal de uso da subscrição Claude Code** do Danilo, tal como uma
  sessão interactiva. Não é "5 corridas grátis por dia" — é "até 5 das corridas normais da semana,
  disparadas por evento em vez de à mão". É por isso que o mecanismo construído é avaro por
  desenho (3 gatilhos raros, nunca por tentativa/ordem).
- **Endpoint:** `POST https://api.anthropic.com/v1/claude_code/routines/{routine_id}/fire`,
  headers `Authorization: Bearer sk-ant-oat01-...` + `anthropic-beta: experimental-cc-routine-2026-04-01`
  + `anthropic-version: 2023-06-01`, body `{"text": "..."}` (até 65.536 caracteres).
- **Criar a rotina e gerar o token só existe na UI web** (`claude.ai/code/routines`) — citação
  directa dos docs: *"there is no public API for token management"*.

## 3. Porque a rotina em si NÃO foi criada por mim — bloqueio real, não preguiça

Tentei directamente antes de assumir qualquer coisa: chamei a API de gestão de rotinas
(`GET /v1/code/triggers`) a partir desta sessão headless.

```
HTTP 401
{"type":"error","error":{"type":"authentication_error","message":"Authentication failed"}}
```

Os docs confirmam a causa: *"API accounts aren't supported for routines"* — `/schedule` e a
criação de rotinas exigem uma sessão claude.ai **logada por browser/Desktop/CLI interactivo**.
Este executor usa `CLAUDE_CODE_OAUTH_TOKEN` (`claude setup-token`), que é "inference-only" (mesma
conclusão já registada na memória do watchdog de token da VPS). **Isto só o Danilo consegue
fazer**, uma vez, em ~3 minutos. Passo-a-passo completo + o texto exacto do prompt da rotina:
`.claude/scripts/ROTINA-TELEGRAM-SETUP.md`.

## 4. O que ficou pronto e provado (funciona hoje, mesmo sem a rotina criada)

### Ficheiros

- **NOVO** `.claude/scripts/hermes-notificar-rotina.sh` — dispatcher avaro: conta corridas do dia
  (reset automático por data UTC), decide rotina-vs-fallback, chama `/fire` com o texto do evento,
  trata `429`/erro/timeout, e cai sozinho no Telegram cru quando a rotina não está configurada ou
  o teto do dia já foi gasto.
- `.claude/scripts/hermes-hook-conclusao.sh` — liga 2 dos 3 gatilhos: missão concluída e ordem
  travada com continuações esgotadas (este último **reintroduz** aviso para um caso que a decisão
  I4 de hoje de manhã tinha silenciado por completo — agora passa pela rotina/fallback em vez de
  ir só para o arquivo TSV do daily-pulse; o arquivo TSV continua a ser escrito também, como rede
  de segurança).
- `.claude/scripts/hermes-sonda-auth.sh` — liga o 3.º gatilho: perda de autenticação do executor
  (estado `sem_auth`). `cli_ausente` e a recuperação (`ok`) continuam pelo Telegram cru directo,
  sem gastar rotina — são mais raros/decorativos.
- **NOVO** `.claude/scripts/ROTINA-TELEGRAM-SETUP.md` — os 3 minutos manuais do Danilo + o prompt
  exacto a colar.

Nenhum dos 3 gatilhos dispara por tentativa/ordem individual — só nestes vereditos terminais.

### Achado colateral corrigido: o fallback Telegram cru estava mudo

Ao testar ao vivo na VPS, descobri que a chave real no `.env` do Hermes é
**`TELEGRAM_HOME_CHANNEL`**, não `TELEGRAM_CHAT_ID` — essa segunda nunca existiu ali. O
`hermes-sonda-auth.sh` (escrito hoje de manhã, Fase 1.11 item 5) tinha esse engano desde que
nasceu: o ramo de fallback cru (`cli_ausente`/recuperação `ok`) nunca tinha conseguido entregar
mensagem nenhuma. Corrigido nos dois scripts (era o mesmo padrão copiado).

### Prova mecânica — selftests (headless, sem rede real, curl-stub em PATH)

```
hermes-notificar-rotina.sh --selftest   -> 8 OK, 0 FALHAS  (config ausente / 200 / teto / reset diário / 429)
hermes-hook-conclusao.sh   --selftest   -> 9 OK, 0 FALHAS  (inclui as 2 novas asserções "[ROTINA tipo=...]")
```

Corridos **duas vezes**: no PC (repo canónico) e ao vivo na VPS contra os ficheiros deployados —
mesmo resultado nos dois lados.

### Prova de deploy sem drift (hash idêntico repo ↔ VPS)

```
aa3d85adc4f28a0...  hermes-hook-conclusao.sh   (repo == VPS)
bcc1e44a8fa7944...  hermes-sonda-auth.sh       (repo == VPS)
6c0602d6f335393...  hermes-notificar-rotina.sh (repo == VPS)
```
Backups datados de tudo o que existia antes: `*.bak_20260801T113953Z` e
`*.bak_<segunda-ronda>` em `/usr/local/bin/` na VPS.

### Prova com evento real (não simulado, mensagem chegou ao Telegram do Danilo)

Forcei uma "missão concluída" através do hook **real** (não `--selftest`), numa fila isolada
(`/root/orquestracao/.prova-rotina-fake-fila/`, apagada logo a seguir — nunca tocou a fila de
produção nem o contador real da rotina):

```
[hook.log]   MISSÃO prova-rotina-notificacao: CONCLUÍDA (última parte 1) -> aviso (rotina/fallback).
[rotina.log] evento=missao_concluida ROTINA-NAO-CONFIGURADA (.../.bora-rotina-notificacao.env ausente) -> fallback
[rotina.log] fallback: Telegram enviado directo (sem LLM).
             resposta_api={"ok":true,"result":{"message_id":3914,
             "from":{"first_name":"BoraHermes","username":"BoraHermesbot"},
             "chat":{"id":6731890157,"first_name":"Danilo","last_name":"Fulfaro", ...
```

`"ok":true` + `message_id` real, no chat do próprio Danilo — a mensagem chegou de facto, sem
ninguém ter escrito nada à mão no Telegram. Confirmado depois que a fila de produção e o contador
diário real ficaram intocados (o teste usou caminhos isolados via as variáveis
`HOOK_FILA`/`ROTINA_CONTADOR` que os scripts já suportam para isto).

## 5. O que falta — só o passo do Danilo

1. Abrir `.claude/scripts/ROTINA-TELEGRAM-SETUP.md`, seguir os 8 passos (~3 min): criar a rotina,
   colar o prompt, ligar o Network access a `api.telegram.org`, gerar o token.
2. Colar URL+token em `/root/.bora-rotina-notificacao.env` na VPS (fora do repo, `chmod 600`,
   mesma lógica do token do executor).

Sem esse passo, o sistema **já está a avisar** — só sem o resumo em português escrito por LLM (usa
o Telegram cru, que agora entrega mesmo, ver achado da secção 4).

## 6. Ficheiros tocados

```
NOVO   .claude/scripts/hermes-notificar-rotina.sh
NOVO   .claude/scripts/ROTINA-TELEGRAM-SETUP.md
NOVO   .claude/.ai/reports/ROTINA-TELEGRAM-avisos-automaticos-2026-08-01.md  (este ficheiro)
MOD    .claude/scripts/hermes-hook-conclusao.sh
MOD    .claude/scripts/hermes-sonda-auth.sh
```
Deployado (com backup datado) em `/usr/local/bin/` na VPS. **Não commitei nada** — fica para
publicares quando quiseres, junto com o resto que já estava por publicar nesta branch.
