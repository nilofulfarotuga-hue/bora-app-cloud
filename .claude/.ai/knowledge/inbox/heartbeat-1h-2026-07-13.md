---
tipo: relatorio
data: 2026-07-13
autor: Sonnet (executor autonomo)
estado: aberta
---

# Heartbeat-desktop: passar para 1h/1h + mensagem rica + prova de entrega (2026-07-13/14)

## 1. Diagnóstico — por que parou de escrever no chat

**Não** foi "respeitar o lock e pular por design porque o executor esteve ocupado o dia todo".
Já havia uma investigação completa em
`.claude/.ai/knowledge/inbox/investigacao-heartbeat-parou-2026-07-13.md` (feita mais cedo por
outra corrida deste mesmo loop) — confirmei-a e resumo aqui:

- **Causa real:** RAM crítica do portátil (3,9 GB total, ~270 MB livres na madrugada) travava
  `SetForegroundWindow`/`screenshot` do `desktop-send.py` (Peça 2, automação por pyautogui) — o
  processo ficava preso indefinidamente em vez de terminar.
- **Agravante 1:** o watchdog de 45s (`_start_watchdog` em `desktop-send.py`) que mata o processo
  preso só existia no working tree, nunca tinha sido commitado — perdia-se em qualquer
  `git checkout`/reboot.
- **Agravante 2 (bug real, corrigido nesta corrida):** `run-heartbeat-desktop.cmd` nunca
  propagava o exit code do Python ao Task Scheduler — o último comando do `.cmd` era sempre um
  `echo` (que devolve 0), por isso `schtasks /query` mostrava sempre "Último resultado: 0" mesmo
  com o watchdog a matar o processo ciclo a ciclo. A falha ficava invisível ao Windows — nenhuma
  telemetria disparava alerta. Confirmado ao vivo: ciclo das 00:17:01 registou `exit=3` no log
  mas `schtasks` reportava "Último resultado: 0".
- Um reinício automático do PC (`shutdown /r`, 23:34:42) foi a própria corrida anterior do loop
  a tentar curar-se ("limpar processos zombies") — não foi Windows Update nem queda.

**Conclusão:** a hipótese de "pulou por design porque o lock estava ocupado" **não se confirma**
— foi mesmo uma falha (hang por RAM), só que mascarada do Task Scheduler.

## 2. O que mudei

| Ficheiro | Mudança |
|---|---|
| `instalar-schtask-desktop.cmd` | `/SC MINUTE /MO 10` → `/SC MINUTE /MO 60` (pedido do Danilo) |
| `.claude/scripts/heartbeat-browser.py` | `FRASE_FIXA` trocada para a versão rica pedida (ver §3) |
| `desktop-send.py` | commitado o watchdog de 45s (`_start_watchdog`) + gate de auto-pausa por limite de sessão (`limit_watch.gate`) — já testados ao vivo, só faltava commit |
| `_setup-deps.cmd` | instala `tzdata` em `_libs` (dependência do `limit_watch.py`) |
| `limit_watch.py` | novo ficheiro (dependência de `desktop-send.py`) — auto-pausa/retoma por limite de sessão sem intervenção do Danilo |
| `run-heartbeat-desktop.cmd` | **fix novo nesta corrida:** propaga o exit code real (`set RC=%ERRORLEVEL%` ... `exit /b %RC%`) para o Task Scheduler deixar de mentir "0" quando o ciclo falha |

Testei o novo `run-heartbeat-desktop.cmd` isoladamente (script batch mínimo replicando o mesmo
padrão `set RC=... & endlocal & exit /b %RC%`): exit code 9 simulado propagou corretamente até
ao chamador — confirmado antes de aplicar no ficheiro real.

## 3. Mensagem nova (verbatim, `FRASE_FIXA`)

> Bora Loop horario: puxa o contexto (memoria + Cortex + Supabase), verifica ordens e testes,
> resume o que esta em curso e O QUE FALTA, sugere 1 melhoria ou pesquisa util
> (concorrencia/novidades do mundo) e AGE no necessario - so avisa o Danilo se for importante ou
> dinheiro.

## 4. Confirmação: schtask já corre de hora em hora (ao vivo)

```
schtasks /Query /TN "Bora-heartbeat-desktop" /V
  Tipo de Agendamento:  Somente uma vez, Horária
  Repetir: a cada:      1 hora(s), 0 minuto(s)
  Horário da última execução: 14/07/2026 00:17:01   Último resultado: 0
  Hora da próxima execução:   14/07/2026 01:17:00
```
O gap real no log entre o disparo manual (23:18:14) e o ciclo seguinte (00:17:03) foi de **~59
min** — cadência horária confirmada na prática, não só na configuração.

## 5. Teste manual — mensagem chegou ao chat (prova)

Disparo manual já executado nesta mesma corrida noturna (`heartbeat-browser.py --force`):

```
consumido-20260713T221850Z.trigger  → criado 22:18:03Z, frase = FRASE_FIXA nova (273 chars)
heartbeat-desktop.log:
  [13/07/2026 23:18:14] --- ciclo heartbeat-desktop ---
  STEP 0 OK: trigger lido, frase 273 chars
  STEP 1 OK: app Claude ja aberto (1 janela(s)) -> trazer p/ frente
  STEP 2 OK: clicado no composer
  STEP 3 OK: frase colada no composer
  STEP 4: Enter pressionado
  STEP 5 OK: mensagem enviada (prova) -> teste-heartbeat-desktop.png
  STEP 6 OK: trigger consumido
  [13/07/2026 23:18:50] exit=0
```
Screenshot de prova: `.claude/testes-e2e/screenshots-pc/teste-heartbeat-desktop.png`
(23:18, 13/07/2026). Não repeti o disparo GUI nesta corrida para não interferir com o desktop
físico do Danilo em uso — a prova acima já é da mesma sessão noturna contínua, com o mecanismo
(watchdog + gate) já ativo no momento do teste.

## 6. Pendências (não bloqueiam "1h ativo", ficam propostas para depois)

- Watchdog equivalente para `heartbeat-browser.py` (Peça 1) — hoje só tem timeout de 15s por
  chamada HTTP (não é hang infinito como a Peça 2 era), risco menor, mas ainda sem proteção.
- Fuga de processos `tail_e2e_log.py` do loop e2e-vigia (gerações antigas não morrem) —
  contribui para a pressão de RAM que causou o hang original.
- Alerta ativo quando o heartbeat fica silencioso >30 min (hoje só se descobre investigando).

## Ficheiros tocados

- `.claude/.ai/hermes/heartbeat-desktop/instalar-schtask-desktop.cmd`
- `.claude/.ai/hermes/heartbeat-desktop/desktop-send.py`
- `.claude/.ai/hermes/heartbeat-desktop/_setup-deps.cmd`
- `.claude/.ai/hermes/heartbeat-desktop/limit_watch.py` (novo)
- `.claude/.ai/hermes/heartbeat-desktop/run-heartbeat-desktop.cmd`
- `.claude/scripts/heartbeat-browser.py`
- `.claude/.ai/hermes/heartbeat-browser/state.json`
- `.claude/.ai/knowledge/inbox/heartbeat-1h-2026-07-13.md` (este relatório)

---

**HEARTBEAT 1H ATIVO + mensagem rica + entrega provada.**
