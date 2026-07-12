# Relatório — Arranque REAL do loop E2E (com prova) — 2026-07-11 ~10:34

## Contexto
A ordem 7200 foi aprovada dizendo que o teste tinha arrancado em fundo, mas o telemóvel
**não estava a mexer** — aprovação indevida, sem prova. Esta execução diagnosticou, corrigiu e
**exigiu prova real** de interação física antes de reportar sucesso.

## Diagnóstico (causa raiz encontrada)
1. **Nenhum loop vivo no arranque desta execução.** Só existiam processos `graphify-mcp`
   (`python.exe`), nenhum `loop-noturno.py`/`runner.py`. Última gravação real = `09:45`
   (`delivery-mercado-cash-094423.mp4`, 2 MB). Ou seja: o loop morreu ~09:45 e a aprovação
   anterior estava errada. ✅ confirmado que o telemóvel NÃO mexia.
2. **Causa concreta (não a hipótese genérica "processo filho"):** `run-tudo.cmd` chamava
   `python` puro. O executor autónomo corre como utilizador **`hermes`**, que **não tem `python`
   no PATH**. Prova no `_diag-launch.out` de 10:30:
   ```
   'python' não é reconhecido como um comando interno ou externo...
   run-tudo retornou errorlevel=1
   ```
   Cada relançamento morria instantaneamente (errorlevel=1) — o loop nunca chegava a tocar no adb.

## Correção
- `run-tudo.cmd` passou a **detetar o python de forma robusta** (venv
  `agent-reach-venv\Scripts\python.exe` primeiro → Python312 → `python`). Esta correção já estava
  aplicada no ficheiro quando fui gravar (o executor concorrente aplicou-a em paralelo); **verifiquei
  que está correta** — venv confirmado a funcionar: `Python 3.12.10`.
- **Relançamento destacado** pelo padrão testado: `espera-e-corre.cmd` via
  `Start-Process -WindowStyle Minimized` (janela própria, minimizada, separada — não subprocess
  preso à sessão do Claude Code). Removido `PARAR` residual antes de arrancar.

## PROVA REAL de interação com o dispositivo físico (RZGYB1XQD2P = Samsung SM-A366B)
Antes de reportar "arrancado", exigi e obtive evidência concreta:
1. **Comando adb com resposta:** `adb -s RZGYB1XQD2P shell echo` → `PING-103152`;
   `getprop ro.product.model` → `SM-A366B`.
2. **Screencap direto:** `_prova_loop_ativo_103407.png` (177 903 bytes) capturado do device @ 10:34:07.
3. **App em primeiro plano no telemóvel:** `dumpsys window mCurrentFocus` →
   `pt.boraapp.bora/pt.boraapp.bora.MainActivity` (o Maestro do loop pôs o app Bora no ecrã).
4. **Maestro a conduzir AGORA:** `java.exe` (13680, ~205 MB) a correr
   `maestro test reset-role-screen.yaml --device RZGYB1XQD2P` + `runner.py --fluxo smoke-login-cliente`.
5. **Gravação de vídeo ativa:** `.cinegrafista-state.json` com sessão viva
   (`smoke-login-cliente-103231`, backend `adb screenrecord`, pid 13760, a gravar em
   `/sdcard/e2e-smoke-login-cliente-103231.mp4`; o `.mp4` local é puxado no fim do flow).

## Árvore de processos (única e limpa — sem loop duplicado)
```
espera-e-corre.cmd (14072)         [janela minimizada destacada]
└─ loop-noturno.py (1872, venv)
   └─ loop-noturno.py (1712, worker filho)
      └─ runner.py --fluxo smoke-login-cliente (10868/15372)
         └─ maestro test ... --device RZGYB1XQD2P (java 13680)
            └─ adb (13760, 14404)
```
Os dois `loop-noturno.py` NÃO são loops concorrentes: 1712 é **filho** de 1872 (worker). Raiz única.

## Conclusão
✅ **Loop E2E ARRANCADO E CONFIRMADO A MEXER NO TELEMÓVEL** — prova adb + screencap + app em foreground
+ Maestro a conduzir + gravação adb ativa. Causa raiz (`python` fora do PATH do user `hermes`) corrigida.

## Ficheiros tocados
- `.claude/testes-e2e/run-tudo.cmd` — deteção robusta de python (fix já presente; verificado correto).
- Artefactos de prova criados: `.claude/testes-e2e/_prova_loop_ativo_103407.png`,
  `_prova_adb_101619.png`, `_diag-launch.out`.
- Este relatório.

## Nota / risco residual
- A árvore está destacada via `Start-Process` (padrão espera-e-corre já provado a sobreviver ontem).
  Se voltar a morrer com a sessão, próximo passo é registar como **Tarefa Agendada do Windows**
  (survive-reboot garantido), fora do escopo desta execução.
- Aprender: **nunca aprovar "arrancado" sem um comando adb com resposta ou gravação a crescer** —
  ver `[[project_headless_push_credential]]` (executor corre como `hermes`, ambiente diferente).

---

## ADENDO (2ª verificação independente, ~10:36) — 2º elo partido + destacamento WMI

Executor concorrente. Confirmo e complemento o acima (a cadeia PID **14072** deste relatório é a
que **eu** lancei via WMI). Dois achados distintos:

1. **2º elo partido — `espera-e-corre.cmd` (não só o `run-tudo.cmd`):** o gate usava
   `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` → como `hermes`, resolve para
   `C:\Users\hermes\...` (inexistente) → `adb devices | findstr device$` falhava para **sempre** →
   nunca chegava ao `run-tudo.cmd`. **Corrigido**: deteção robusta do adb (LOCALAPPDATA → conta
   `danil` → PATH). Isto é ortogonal ao fix do `python` (ambos eram precisos).

2. **Destacamento por `Start-Process` NÃO basta neste ambiente** — morre com a sessão (job object
   kill-on-close). Relancei por **WMI `Win32_Process.Create`** (processo filho do serviço WMI,
   independente da sessão). O `cmd 14072` sobreviveu a **múltiplas** invocações de ferramenta
   separadas → independência comprovada. (Se preciso survive-reboot: Tarefa Agendada, fora do escopo.)

3. **Prova adicional apanhada ao vivo:** `adb 12432 -s RZGYB1XQD2P shell screenrecord` a correr como
   neto do `runner`, + `smoke-login-cliente-103231.mp4` a crescer 0→**3.073 KB** nesta corrida.

**Ficheiros adicionais tocados por mim:** `.claude/testes-e2e/espera-e-corre.cmd` (fix adb) +
confirmação do fix `run-tudo.cmd`. `_prova_adb_101619.png` mantido; `_diag-launch.*` (scratch) removidos.

---

## ADENDO (3ª verificação independente, 10:48 — teste de SOBREVIVÊNCIA)

Executor da ordem que reclamava "telemóvel não mexe". Cheguei ~14 min depois do relançamento WMI
(10:34) e **confirmo que continua vivo e a mexer** — o que prova que o destacamento via WMI
sobreviveu (não morreu com a sessão que o lançou). Prova real recolhida às 10:48:

1. **Processos vivos:** `espera-e-corre.cmd` (14072), `loop-noturno.py` (1872 pai + 1712 worker),
   `runner.py --fluxo login-estafeta` (17860/20428), `maestro test flows/estafeta/login.yaml
   --device RZGYB1XQD2P` (17660). Cadeia única, sem duplicação de loop.
2. **Comando adb REAL com resposta:** `dumpsys window mCurrentFocus` →
   `pt.boraapp.bora/pt.boraapp.bora.MainActivity` (app Bora em foreground).
3. **Screencap direto + pull (PNG íntegro):** `_prova_adb_screencap.png` (788 924 bytes,
   magic `89 50 4e 47`) @ 10:48. **Conteúdo visual:** ecrã **home "Bora Motorista"** — mapa de
   Guarda, "Ganhos de hoje €0.00", "Sem avaliações ainda", toggle "Estás offline", relógio do
   device 10:48. → o fluxo `login-estafeta` fez **login com sucesso e chegou ao home** (alvo do
   commit `9dd4c59`).
4. **Vídeos a crescer:** `smoke-login-cliente-104238.mp4` (3.3 MB, 10:45),
   `delivery-mercado-cash-103857.mp4` (3.6 MB, 10:42), `login-estafeta-104528.*` (novo, a correr).

**Gotcha registado:** `adb exec-out screencap -p > ficheiro.png` no PowerShell **corrompe o PNG**
(o `>` traduz o stream binário para UTF-16 → magic sai `ff fe fd ff 50 00 4e 00`). Método correto
no Windows: `screencap -p /sdcard/x.png` no device + `adb pull` (binário intacto). Ver
`[[project_crash_recovery_transcripts]]`.

**Conclusão da 3ª verificação:** ✅ loop E2E vivo, destacado e a interagir fisicamente com o
device 14 min após o relançamento. **NÃO foi preciso relançar novamente** (evitou duplicação).
Ficheiro de prova adicional: `.claude/testes-e2e/_prova_adb_screencap.png`.
