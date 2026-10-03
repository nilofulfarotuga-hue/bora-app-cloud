---
id: schtasks-e2e-2026-07-11
tipo: relatorio
origem: [executor loop autonomo — agendamento E2E via Windows Task Scheduler]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: prova-real
---

# Loop E2E via Tarefa Agendada do Windows — VIVO e a correr (2026-07-11 13:38)

**Decisão:** abandonado o caminho VPS-web (`flutter build web` pesado demais, estourava o tempo).
Voltámos ao telemóvel físico + Tarefa Agendada do Windows como mecanismo de sobrevivência à sessão.

## 1. Estado encontrado (`schtasks /query`)
Já existia a tarefa `\BoraE2E_LoopNoturno` → `schtask-loop.cmd` → `loop-noturno.py`, mas:
- **Nunca tinha corrido** (Último resultado `267011` = HAS_NOT_RUN; última execução `30/11/1999`).
- Agendada **só diária às 02:00** — não arrancava agora.
- `loop-noturno.py` é um **lote limitado** (MAX_CICLOS=10): corre a suite e **sai** (não é daemon).
  Logo, faz sentido re-lançar periodicamente → mudei para **HORÁRIA**.

## 2. Ação (rápida, sem nada pesado)
Recriada como horária, mantendo run-as SYSTEM (sobrevive ao fim da sessão do Claude Code):
```
schtasks /create /tn "BoraE2E_LoopNoturno" /tr "...\.claude\testes-e2e\schtask-loop.cmd" ^
         /sc HOURLY /mo 1 /ru SYSTEM /rl HIGHEST /f      → ÊXITO
schtasks /run    /tn "BoraE2E_LoopNoturno"               → ÊXITO
```
Status pós-run: **Em execução** · próxima execução **11/07/2026 14:38** (a cada 1h).

## 3. Confirmação em <2 min (output real)
**Log `_schtask_loop.log`** (mtime 13:38:11):
```
[schtask-loop] arranque 11/07/2026 13:38:11
autoridade nt\sistema
[13:38:11] loop noturno Fase 7 — 4 fluxos no registry
[13:38:11] ── CICLO 1: 3 fluxos → ['smoke-login-cliente', 'login-estafeta', 'delivery-mercado-cash']
```
**Árvore de processos viva:**
```
6860  cmd.exe     :: schtask-loop.cmd
5612  python.exe  :: loop-noturno.py
12716 python.exe  :: runner.py --fluxo smoke-login-cliente
```
**Atividade real no device (adb logcat -d):**
```
07-11 13:38:46  io_stats: Write_top(KB): pt.boraapp.bora ...   (device RZGYB1XQD2P)
```

## 4. Achados
- ✅ **A app `pt.boraapp.bora` está ativa no telemóvel**, conduzida pela tarefa SYSTEM — prova real.
- ✅ **SYSTEM vê o device**: o `garante_device` passou sem evento de reconexão e o CICLO 1 arrancou
  o runner diretamente. (A preocupação teórica "adb do SYSTEM não vê devices do user" **não** se
  confirmou nesta máquina.)
- ✅ Arranca o `smoke-login-cliente` primeiro — o fluxo que passou ontem (214.6s, prova real).
- Devices no adb: `N75LTG5X5DSKDMV4`, `RZGYB1XQD2P`. O runner (single-device) está a usar o RZGYB1XQD2P.
- **NÃO** toquei em 500,500 no ecrã: o teste estava a conduzir o device ao vivo e um tap iria
  perturbar o `smoke-login-cliente`. A prova de vivacidade veio do logcat + árvore de processos.

## 5. Como parar / observar
- **Parar já:** criar ficheiro `PARAR` em `.claude/testes-e2e/`.
- **Ver progresso:** `.claude/.ai/knowledge/inbox/e2e-resultados-2026-07-11.md` (escrito por ciclo)
  + `loop-noturno-2026-07-11.json`.
- **Log do wrapper:** `.claude/testes-e2e/_schtask_loop.log`.

## Ficheiros tocados
- Tarefa Agendada Windows `BoraE2E_LoopNoturno` (diária 02:00 → **horária**, run-as SYSTEM). Reversível.
- Relatório: este ficheiro.
- (Gerados pelo loop em runtime: `_schtask_loop.log`, `e2e-resultados-2026-07-11.md`, `loop-noturno-2026-07-11.json`.)

---

## RE-CONFIRMAÇÃO (2026-07-11 ~13:42 — outro executor, prova real)
A tarefa **continua viva e nada foi recriado** (já estava horária + SYSTEM, ver §1-2 acima). Só verifiquei.
- `schtasks /query`: `Status = Em execução`, `Último resultado = 267009` (STILL_ACTIVE, a correr agora),
  `última execução 11/07/2026 13:38:10`, `próxima 14:38`, `Repetir a cada 1 hora`, `Usuário = SISTEMA`.
- adb (device **RZGYB1XQD2P**): foreground = `pt.boraapp.bora/pt.boraapp.bora.MainActivity`;
  `logcat -d` @ **13:42:49** → `GestureDetector: handleMessage TAP` (input a ser conduzido AO VIVO).
- Device `N75LTG5X5DSKDMV4` no launcher (`com.gogo.launcher`) — esperado (runner single-device usa 1).
- Não corri nada pesado; sem build. Confirmação em <2 min. ✅ Loop sobrevive à sessão via Windows.
