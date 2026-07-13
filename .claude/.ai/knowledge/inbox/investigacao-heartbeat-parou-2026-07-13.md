---
tipo: investigacao
data: 2026-07-13
autor: Sonnet (executor autonomo, read-only)
estado: aberta
---

# Investigação: por que o heartbeat-desktop parou de madrugada (2026-07-13)

**Read-only. Nada foi corrigido — só diagnóstico + propostas.**

## CAUSA (com prova)

Não foi (A) Windows a desativar a tarefa, nem (C) rate-limit da conta. Foi uma combinação de
**(B) cada ciclo travou** + **(D) causa raiz = RAM insuficiente do portátil (3,9 GB total)**,
agravada por um **reinício auto-infligido** a meio da noite e por um **bug que esconde a falha
do Task Scheduler**.

### Prova 1 — o reinício foi o próprio sistema a tentar curar-se
```
Get-WinEvent Id=1074 (13/07 23:34:42, LAPTOP-2Q09VQA1\danil):
"O processo C:\WINDOWS\system32\shutdown.exe iniciou reiniciar do computador...
 Comentário: Bora App: reinicio para limpar processos zombies (heartbeat travado).
 Cancela com: shutdown /a"
```
Isto **não foi o Windows Update nem uma queda** — foi um comando `shutdown /r` disparado por
uma corrida anterior deste mesmo loop autónomo (ou pelo Danilo seguindo a sugestão dele), que
diagnosticou "heartbeat travado" e decidiu reiniciar o PC para limpar zombies. Boot completo às
23:37:24 (`Kernel-General Id=12`, `EventLog Id=6005/6009`).

### Prova 2 — o watchdog que existe hoje não estava lá na maior parte da noite
`desktop-send.py` tem uma função `_start_watchdog(timeout=45)` que mata o processo ao fim de 45s
preso. **Esta função está no working tree mas NÃO está commitada** (`git diff` mostra-a como
adição pendente; o último commit tocado no ficheiro, `0d04ea0` de 12/07 08:33, não a tem). Ou
seja: foi um patch ao vivo aplicado a meio desta mesma madrugada por uma corrida anterior do
loop, para conter o sintoma — mas nunca foi comitado nem corrigiu a causa raiz (só transforma
"hang infinito" em "hang de 45s + kill").

### Prova 3 — o .cmd nunca reporta falha ao Windows (por isso a task nunca foi desativada)
`run-heartbeat-desktop.cmd` linha 14-15:
```bat
"%PY%" "%OP%" >> "%LOG%" 2>&1
echo [%DATE% %TIME%] exit=%ERRORLEVEL% >> "%LOG%"
```
O último comando executado no batch é `echo`, que devolve sempre 0. `schtasks /query /v` mostra
**"Status: Pronto" / "Estado de tarefa agendada: Habilitado" / "Último resultado: 0"** mesmo
agora, às 06:26, com o log a mostrar `exit=9` (watchdog kill) em TODOS os ciclos desde as 02:56.
O Windows nunca vê a falha — não há telemetria nenhuma que dispare auto-desativação.

### Prova 4 — o hang está a acontecer literalmente agora, ciclo a ciclo, sem interrupção
Log (`heartbeat-desktop.log`), últimas linhas lidas às 06:35 (schtask corre a cada 10 min,
próxima às 06:36):
```
[13/07/2026 6:26:01,94] --- ciclo heartbeat-desktop ---
STEP 0 OK: trigger lido, frase 370 chars
STEP 1 OK: app Claude ja aberto (1 janela(s)) -> trazer p/ frente
STEP X FAIL: watchdog matou o processo (>45s sem terminar)
[13/07/2026 6:26:47,84] exit=9
```
Isto é **idêntico** em cada um dos ciclos desde as 02:56:01 até agora (3h39min seguidas, ~22
ciclos). O hang acontece sempre no mesmo ponto: depois de encontrar a janela do Claude aberta,
antes de conseguir trazê-la para primeiro plano / tirar o screenshot (`_foreground()` +
`pyautogui.screenshot()`). Isso bate com uma janela/monitor que não responde a
`SetForegroundWindow`/captura de ecrã — sintoma clássico de **memória crítica** (o mesmo padrão
já registado em `[[project_ponte_ram_root_cause_2026-07-12]]` e
`[[project_e2e_loop_ram_stall]]`).

### Prova 5 — RAM crítica confirmada agora, e há fuga a acumular-se
```
Get-CimInstance Win32_OperatingSystem: FreeMB=269 / TotalMB=3902  (~6,9% livre)
```
Processos `python.exe` a correr `tail_e2e_log.py` (do loop e2e-vigia) foram relançados sem
matar os anteriores às 01:23, 02:52, 03:27, 04:38, 05:19, 06:27 — 6 gerações acumuladas ainda
vivas agora, cada uma a par (venv + sistema). Não são a causa principal (poucos MB cada), mas
somam-se ao Chrome/PWA + MCP servers (`graphify-mcp`) + o resto da stack Hermes num portátil
de 3,9 GB — motivo estrutural para a degradação.

## Linha do tempo (12/13-07-2026)

| Hora | Evento |
|---|---|
| até 21:38 | Heartbeat normal — ciclos completos, `exit=0`/`exit=3` em <1s |
| 21:47:13 | Ciclo arranca, **nunca escreve `exit=`** (hang total — código sem watchdog ainda) |
| 22:40, 22:47, 23:07 | Mais 3 ciclos iguais: só o cabeçalho, sem output nenhum |
| 23:34:42 | `shutdown.exe` reinicia o PC — comentário próprio: "limpar processos zombies (heartbeat travado)" |
| 23:37:24 | Boot completo |
| 00:27–00:51 | PC a estabilizar / app Claude reaberto (por quem/o quê não é possível confirmar via logs locais) |
| 00:51:29 | **1º ciclo pós-reboot com sucesso real** (`exit=0`, mensagem enviada) |
| 00:51–01:36 | Ciclos normais, 2 mensagens entregues (`00:51`, `00:56`, `01:26`) |
| 01:43–01:48 | Windows Update começa a descarregar atualizações (dezenas de eventos `Id=44`) em paralelo |
| 01:47–02:52 | Ciclos "sem trigger" (`exit=3`, normal) mas cada vez mais lentos: 27s → 72s → 3min21s → 15min — sinal de degradação a acumular |
| 02:52 e 02:56 | Watchdog (`_start_watchdog`, patch não commitado) começa a aparecer nos logs — 1ª vez que mata um processo preso |
| 02:56:01 → 06:26:47 (agora) | **TODOS** os ciclos: encontra a janela, trava >45s, watchdog mata (`exit=9`). Nenhuma mensagem chegou ao chat neste intervalo — **~5h de silêncio real**, mascarado porque o schtask continua a reportar sucesso |

## Como está programado hoje

- `Bora-heartbeat-desktop`: repete a cada 10 min, `/RU danil /IT` (token interativo — só corre
  se a sessão do Danilo estiver desbloqueada). Corre `run-heartbeat-desktop.cmd`.
- O `.cmd` corre Peça 1 (`heartbeat-browser.py`, detetor — **sem watchdog nenhum**, pode travar
  para sempre e ninguém mata) e Peça 2 (`desktop-send.py`, operador via pyautogui/pygetwindow —
  **tem watchdog de 45s, mas só no working tree, não commitado**).
- O `.cmd` **não propaga o exit code real** para o Windows Task Scheduler (último comando é
  `echo`), então o schtask nunca vê a falha, nunca é desativado, nunca alerta ninguém.

## O que mudar (SÓ PROPOSTA — nada aplicado)

1. **Commitar o watchdog de `desktop-send.py`** (já testado ao vivo, já provou que funciona)
   para não se perder no próximo `git checkout`/reboot.
2. **Adicionar watchdog equivalente a `heartbeat-browser.py` (Peça 1)** — hoje é o único elo
   sem proteção nenhuma contra hang.
3. **Corrigir o `.cmd` para propagar o exit code real** ao Task Scheduler (ex.:
   `exit /b %ERRORLEVEL%` como última linha, capturado antes do `echo`), para que falhas
   repetidas fiquem visíveis no `schtasks /query` e possam disparar alerta.
4. **Investigar a causa do hang em si** (não só conter com watchdog): provável saturação de
   RAM impede `SetForegroundWindow`/captura de ecrã da janela do Chrome/PWA. Portátil de 3,9 GB
   é pouco para a stack toda (Chrome+PWA, MCP servers, múltiplos loops Python) — considerar
   reduzir processos residentes ou subir RAM.
5. **Limpar a fuga de `tail_e2e_log.py`** do loop e2e-vigia (mata a instância anterior antes de
   lançar a nova, ou usa lock de instância única como já foi feito para `loop-noturno.py` em
   `0d04ea0`).
6. **Alertar quando o heartbeat fica silencioso >30 min** — hoje não há nenhum sinal que avise
   o Danilo que a "prova de vida" parou; só se descobre investigando manualmente (como agora).

## Nota sobre a campainha (Hermes/carteiro)

Esta ordem de investigação chegou e foi processada de ponta a ponta — **prova viva de que o
canal carteiro/Hermes que entrega ordens a este Claude Code está a funcionar**, mesmo enquanto
o heartbeat-desktop (mecanismo diferente: simulação de clique no PWA visível do Danilo) está
preso desde as 02:56. São dois mecanismos distintos e não partilham falha.

---

**HEARTBEAT PAROU POR: RAM insuficiente do portátil (3,9 GB) trava a interação com a janela do
Chrome/PWA (SetForegroundWindow/screenshot) — sintoma contido mas não resolvido por um watchdog
não commitado; a falha fica invisível ao Windows Task Scheduler porque o `.cmd` sempre reporta
exit 0 · CAMPAINHA: funciona (esta ordem chegou e foi executada)**
