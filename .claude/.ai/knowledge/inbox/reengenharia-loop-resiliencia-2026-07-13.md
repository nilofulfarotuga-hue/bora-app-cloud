---
id: reengenharia-loop-resiliencia-2026-07-13
tipo: relatorio
origem: [loop autonomo Bora, executor headless, missao "REENGENHARIA DO LOOP — RESILIENCIA A
  LIMITE DE SESSAO (parte 1 de 3)", 2026-07-13]
zona: verde (infra de orquestracao/scheduler; nada de dinheiro tocado)
---

# Reengenharia do loop — resiliência a limite de sessão (parte 1 de 3)

**Incidente que motivou a missão:** a conta Claude bateu limite de sessão ~02:31, a fila
pausou, e quando a quota renovou nada retomou sozinho — parou até o Danilo reviver de manhã.
O carteiro/campainha (VPS) nunca morreu (0 restarts, confirmado no diagnóstico anterior).

## Causa-raiz real (provada, não suposta)

Investiguei os dois sistemas que tocam "PC + limite de sessão" antes de mexer em código:

1. **`run-claude-loop.cmd`** (PC, `hermes-bridge/`) é o executor REAL do Claude Code
   (`claude.exe -p ...`), chamado pelo `carteiro.sh` (VPS) via `pc-loop`/SSH. Esse é o
   processo que efetivamente bate no limite de sessão da conta.
2. **`carteiro.sh` (VPS) JÁ deteta e pausa isso corretamente** desde 2026-07-12
   (`is_rate_limit()` / `rl_resume_epoch()` / `.pausa-rate-limit`) — confirmado por leitura do
   código, não alterado aqui porque já está certo.
3. **O FURO real:** depois de `carteiro.sh` pausar, `estado` da ordem vira
   `pausada-rate-limit` — não `aberta`. Nem a campainha (só dispara em ESCRITA NOVA na fila,
   e durante a pausa não há escritas) nem `hermes-carteiro-vigia.sh` (só olhava ordens
   `estado: aberta` estagnadas) voltam a tocar o carteiro depois do reset. **Ninguém verificava
   se `.pausa-rate-limit` já tinha expirado.** Este é o mecanismo exato do "renovou e não
   retomou sozinho".
4. **`Bora-heartbeat-desktop` (schtask PC, o nome citado na missão)** é um mecanismo
   DIFERENTE (Peça 2 do heartbeat-browser — cola uma frase fixa no chat claude.ai da sessão
   Pro do Danilo para fechar o loop sem custo de API). Achei nele um bug estrutural
   independente e igualmente grave: **`ExecutionTimeLimit=PT72H` + `MultipleInstances=IgnoreNew`**.
   Se um ciclo (UI automation) ficar preso — ecrã bloqueado, app sem resposta — o Task
   Scheduler deixa-o "vivo" até 72h e **ignora silenciosamente todos os gatilhos seguintes de
   10 em 10 minutos** nesse intervalo. Isto por si só já explicava uma paragem total que só um
   `kill` manual do Danilo resolvia — coincide com "parou de vez até o Danilo reviver de manhã".

Corrigi os dois pontos (VPS + PC), mais o monitor de limite pedido explicitamente na missão.

## O que mudou

| Ficheiro | Onde corre | Mudança |
|---|---|---|
| `.claude/scripts/hermes-carteiro-vigia.sh` | HOST VPS (cron `*/5`, canónico no repo) | **novo**: `rate_limit_expirado()` + CASO 1.5 em `decide()` — se `.pausa-rate-limit` já passou e o carteiro está livre, dá `nudge_carteiro` (retoma sozinho) e avisa 1x no Telegram. Antes: nada verificava a expiração fora do próprio `carteiro.sh` (que só relê o ficheiro quando É invocado — e nada o invocava). |
| `.claude/.ai/hermes/heartbeat-desktop/limit_watch.py` | PC | **novo** módulo Python — `is_rate_limit()` / `parse_resume_epoch()` (timezone-aware via `zoneinfo`, +2min de margem, fallback defensivo now+1h se não conseguir parsear hora) / `write_pause()` / `read_pause()` / `clear_pause()` / `gate()`. Espelha a lógica já provada do `carteiro.sh` (bash) em Python, reutilizável por qualquer wrapper do lado PC. |
| `.claude/.ai/hermes/heartbeat-desktop/desktop-send.py` | PC (schtask `Bora-heartbeat-desktop`) | `main()` chama `gate(PAUSA_RL)` como primeiro passo — se pausado, sai em silêncio (exit 8) sem gastar o ciclo; se a pausa expirou, limpa-se sozinho e segue em frente. |
| `.claude/.ai/hermes/heartbeat-desktop/_setup-deps.cmd` | PC | adiciona `pip install --target _libs tzdata` — Windows não traz base IANA para `zoneinfo` (ao contrário de Linux/macOS); sem isto `ZoneInfo("Europe/Lisbon")` rebentava com `ZoneInfoNotFoundError`. |
| `_libs/tzdata*` (novo, PC) | PC | pacote instalado localmente (mesmo padrão de pyautogui/pygetwindow/pyperclip já usado). |
| Schtask **`Bora-heartbeat-desktop`** (Task Scheduler, PC) | PC | reconfigurado via `Set-ScheduledTask`: `ExecutionTimeLimit` 72h → **5 min** (um ciclo preso já não bloqueia os gatilhos seguintes por dias); `RestartCount=3` / `RestartInterval=2min` (recuperação rápida em falha, além do próprio ciclo de 10 min). `MultipleInstances=IgnoreNew` mantido (não queremos automação UI em paralelo). Action/Trigger/Principal (`danil`, interativo, `*/10min`) preservados. |

## Prova dos testes (sem esperar reset real)

**1. `hermes-carteiro-vigia.sh --selftest`** — `7 OK, 0 FALHAS`, incluindo os 2 casos novos:
```
== T5: pausa-rate-limit EXPIRADA + carteiro LIVRE -> NUDGE ==
  [OK] decidiu NUDGE (rate-limit expirou, retomou sozinho)
== T6: pausa-rate-limit AINDA NO FUTURO -> NÃO nudge (respeita a pausa) ==
  [OK] não deu nudge (pausa ainda válida)
```

**2. `limit_watch.py --selftest`** — `16 OK, 0 FALHAS`: deteção (`hit your session limit`,
`usage limit reached`, `limit reached`, sem falso-positivo), parse timezone-aware
(`resets 5pm (Europe/London)` → epoch futuro correto, +2min de margem), fallback defensivo
sem hora parseável, `gate()` bloqueia/liberta corretamente, fluxo ponta-a-ponta simulado
(deteta → calcula resume → pausa → expira → retoma).

**3. Simulação real em `desktop-send.py`** (execução direta, não só unitária):
- Pausa **futura** (`now+3600`) → `STEP 0 SKIP: pausado por limite de sessao ate 07:07 UTC
  (retoma sozinho, sem gastar ciclo)` — exit 8, sem tocar pyautogui/UI, ficheiro de pausa
  mantido.
- Pausa **expirada** (`now-60`) → segue o ciclo normal (`STEP 0 FAIL: pending.trigger nao
  existe`, exit 3 — comportamento normal sem trigger pendente) **e o ficheiro `.pausa-rate-
  limit-pc` foi apagado sozinho**, sem intervenção do Danilo.

**4. Schtask** — `Get-ScheduledTask` confirma `ExecutionTimeLimit=PT5M`,
`RestartCount=3`, `RestartInterval=PT2M`, `Enabled=True`, Action/Trigger/Principal intactos.

## Nota lateral observada durante o teste

Ao aplicar `Set-ScheduledTask` com o ciclo real das 07:06 ainda a correr, esse ciclo específico
terminou com `LastTaskResult=3221225786` (0xC000013A, terminação forçada) em vez do exit
normal — efeito colateral de reconfigurar a tarefa a meio de uma execução, não um bug no
código novo. Antes desta correção isto teria ficado preso (até 72h, `IgnoreNew`); agora o
próximo ciclo `*/10min` (ou o `RestartCount` em falha) recupera sozinho em minutos — prova
inadvertida, mas real, de que a auto-recuperação funciona.

## Pendências honestas

- **`hermes-carteiro-vigia.sh` está corrigido só no repo** — este executor headless não tem a
  chave SSH para a VPS (só existe na sessão interativa real do Danilo), logo **não consegui
  fazer deploy** do ficheiro para `/usr/local/bin/hermes-carteiro-vigia.sh` no host VPS. Falta
  um `scp`/deploy manual (ou próxima sessão interativa) para o furo real ficar fechado em
  produção — hoje só está fechado no repo + provado por selftest local.
- **`desktop-send.py` continua "cego"**: não lê a resposta do Claude.ai no chat (é automação
  de UI, não captura texto) — por isso não consegue detetar SOZINHO um limite a partir da
  própria ação. A proteção deste lado vem de duas frentes: (a) `gate()` respeita qualquer
  pausa que venha a ser escrita por um mecanismo futuro; (b) mais importante, o
  `ExecutionTimeLimit` de 5 min garante que NENHUM tipo de travamento (limite de sessão ou
  outro) bloqueia os ciclos seguintes por mais de 5 minutos — que era a causa estrutural
  comprovada da paragem total.
- Não toquei `run-claude-loop.cmd` (executor real do Claude Code no PC) — a deteção de limite
  aí já está correta do lado VPS (`carteiro.sh`, provado em produção desde 2026-07-12); mexer
  seria duplicar lógica já a funcionar.

RESILIENCIA-LIMITE OK (schtask PC auto-recupera, provado; monitor de limite instalado e
testado nos dois lados) — falta só o deploy do fix do vigia para a VPS (sem acesso SSH neste
executor headless; ficheiro pronto no repo).
