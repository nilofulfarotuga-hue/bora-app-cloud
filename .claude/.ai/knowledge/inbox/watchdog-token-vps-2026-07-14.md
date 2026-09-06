---
title: Watchdog do token OAuth headless da VPS instalado (2026-07-14)
tipo: relatorio
estado: atual
data: 2026-07-14
---

## Contexto

A VPS foi autenticada hoje (2026-07-14) com um token OAuth headless via `claude setup-token`,
guardado em `/root/.claude-vps-token` (`export CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."`).
Risco: se este token expirar ou for invalidado, o Claude Code na VPS morre com 401 e ninguém
percebe até horas depois. Missão: watchdog automático + alerta Telegram, standalone (não ligado
ainda ao loop principal/carteiro).

## O que foi construído

- **`/root/claude-token-watchdog.sh`** (chmod 700, root:root) — cópia local em
  `.claude/.ai/hermes/heartbeat-desktop/_libs/claude-token-watchdog.sh`.
- **Cron instalado:** `*/30 * * * * /root/claude-token-watchdog.sh >/dev/null 2>&1 # claude-token-watchdog`.
- **Log:** `/var/log/claude-token-watchdog.log` — 1 linha por verificação (timestamp + OK/FALHA),
  dá histórico real de quanto tempo o token dura.

## Lógica

1. `source /root/.claude-vps-token` + `claude -p "responde apenas: ok"` com `timeout 30`.
2. Se OK → só regista heartbeat no log, não faz mais nada.
3. Se falhar → espera 20s e tenta de novo (cobre falhas transitórias de rede/API).
4. Se falhar outra vez → alerta Telegram (mesmo canal/mecanismo do `hermes-heartbeat.sh`: lê
   `TELEGRAM_BOT_TOKEN` de dentro do container via `docker exec` + `curl` para o chat do Danilo)
   com instrução curta: correr `claude setup-token` na VPS e substituir o ficheiro.

## Achado importante — NÃO existe refresh automático real

A missão pedia para testar se "re-correr com o OAUTH_TOKEN regenera o access token sozinho".
Investigação em `claude doctor` + inspeção de `~/.claude/` confirma que **não existe**:
não há `credentials.json`/cache de access-token na VPS — cada invocação do CLI usa o
`CLAUDE_CODE_OAUTH_TOKEN` diretamente como bearer. `claude doctor` avisa explicitamente que
tokens longos (`setup-token`/`CLAUDE_CODE_OAUTH_TOKEN`) são **"inference-only"**, sem scope de
Remote Control/refresh. Ou seja: o passo 4 do watchdog ("tentar renovação automática") foi
implementado como **retry de falha transitória** (rede/API), não como refresh de token de facto —
se o token em si expirar/for revogado, a ÚNICA recuperação é o Danilo gerar um novo via
`claude setup-token` (interativo). O watchdog cobre exatamente esse caso com o alerta.

## Testes feitos (todos na VPS, sem tocar o token real)

1. **Token válido (real):** `EXIT=0`, log = `OK`, sem alerta. ✅
2. **`--test-alert`** (só testa a plumbing Telegram, sem tocar claude/token): enviado com sucesso
   (mensagem prefixada 🧪 TESTE ao Danilo). ✅
3. **Falha completa simulada:** token forjado inválido em ficheiro à parte
   (`WATCHDOG_TOKEN_FILE=/root/.claude-vps-token-TESTE`, apagado logo a seguir), `WATCHDOG_TEST_MODE=1`
   → detectou `401 Invalid bearer token` na 1ª tentativa, retry falhou também, alerta Telegram
   enviado (prefixado 🧪 TESTE). `EXIT=1`. ✅
4. Confirmado no fim: `/root/.claude-vps-token` real intacto (`sk-ant-oat01-v6v08Dh...`), ficheiro
   de teste removido, cron instalado sem duplicar (20 linhas no crontab, 1 nova).

## Não fiz (fora do escopo pedido)

- Não liguei o watchdog ao `carteiro.sh`/loop principal — ficou standalone como pedido.
- Não alterei o token real nem `~/.claude/` da VPS.

## Próximo passo sugerido (não aplicado)

Se o Danilo quiser, dá para o `carteiro.sh` chamar este watchdog antes de cada corrida (barato,
30s no pior caso) em vez de esperar pelo cron de 30min — mas isso é decisão dele, não apliquei.

RESULTADO: watchdog do token da VPS instalado (cron 30min, `/root/claude-token-watchdog.sh`),
testado end-to-end (válido/alerta/falha), sem refresh automático real disponível para tokens
headless — por isso alerta Telegram é a rede de segurança; ficheiros tocados:
`.claude/.ai/hermes/heartbeat-desktop/_libs/claude-token-watchdog.sh` (novo, local) +
`/root/claude-token-watchdog.sh` + crontab (na VPS, fora do git).
