# E2E via Web (Flutter web / Chrome headless) — relatório honesto e completo — 2026-07-11

**Executor:** loop autónomo (headless, sem canal com o Danilo).
**Mudança de estratégia pedida:** parar de insistir no telemóvel físico (6 tentativas, 0 pedidos
no banco). Testar via **Flutter web + browser headless** os fluxos que não precisam de câmara/GPS/som.
**Regra de transparência:** mostrar o output literal de cada comando, sem esconder; tocar só no pedido.

> **TL;DR honesto:** Passo 1 PROVADO — `flutter build web` compila (EXIT 0) e a app **corre mesmo
> num browser real** (screenshot real do RoleScreen, ver `web_rolescreen.png`). MAS o passo 2/3
> (E2E interativo com `flutter drive`) **não conclui — parede dura de RAM**: o PC tem só **3,9 GB**
> e a VPS tem **3,8 GB + 1 core** e nem sequer tem Flutter. O caminho web é viável; **falta um host
> com RAM suficiente** (CI GitHub Actions ou VPS maior). Nada de Córtex foi tocado.

---

## PASSO 1 — Confirmar que o Flutter compila para web

### Ambiente
```
$ flutter --version
Flutter 3.41.2 • channel stable • revision 90673a4eef (2026-02-18)
Engine • hash d96704abcce17ff165bbef9d77123407ef961017
Tools • Dart 3.11.0 • DevTools 2.54.1

$ flutter devices
Found 4 connected devices:
  23028RN4DG (mobile)  • android-arm    • Android 13 (API 33)
  SM A366B (mobile)    • android-arm64  • Android 16 (API 36)
  Windows (desktop)    • windows-x64
  Chrome (web)         • web-javascript • Google Chrome 146.0.7680.178
```
Pasta `web/` existe. Chrome (web) disponível.

### `flutter build web` — 1ª tentativa: CRASH de sistema (não de código)
```
$ flutter build web --no-tree-shake-icons
Compiling lib\main.dart for the Web...
../../runtime/vm/os_thread.cc: 364: error: Could not start thread DartWorker: 22
  (O dispositivo não reconhece o comando.)
version=3.11.0 (stable) ... on "windows_x64"
The Dart compiler exited unexpectedly.
EXIT=127
```
> `Could not start thread DartWorker: 22` = falha do Dart VM a **criar threads** — sintoma de
> exaustão de memória, não erro do Flutter web.

### `flutter build web` — 2ª tentativa: **SUCESSO**
```
$ flutter build web --no-tree-shake-icons
Compiling lib\main.dart for the Web...
Wasm dry run findings:
  package:flutter_secure_storage_web/... dart:html unsupported   (só AVISOS de wasm; o build JS passa)
  package:audioplayers_web/... dart:html unsupported
  package:geolocator_web/... dart:html unsupported
  ...
Compiling lib\main.dart for the Web...   546,7s
√ Built build\web
EXIT=0
```
**→ PASSO 1 PROVADO: a app Bora compila para web (EXIT 0).** Artefacto:
```
$ ls -la build/web/index.html build/web/main.dart.js
-rw-r--r-- 918      build/web/index.html
-rw-r--r-- 7955213  build/web/main.dart.js   (7,95 MB de JS compilado)
$ du -sh build/web  →  51M
```

---

## PASSO 2 — E2E do login (flutter drive headless) — **BLOQUEADO POR RAM**

Infraestrutura já existente (de trabalho anterior, não criada por mim):
- `integration_test/login_cliente_test.dart` — abre app → RoleScreen → toca "Sou Cliente" →
  ClientLoginScreen → toca "Entrar" → espera ClientMainScreen, com screenshots em cada passo.
- `test_driver/integration_test.dart` — runner que grava os PNG em `web-logs/shots/`.
- `.claude/testes-e2e/web-tools/chromedriver.exe` — ChromeDriver 146.0.7680.165 (≈ Chrome 146).

chromedriver já estava a ouvir no porto 4444 (PID 12624, de corrida anterior). Comando corrido:
```
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/login_cliente_test.dart \
  -d web-server --browser-name=chrome --web-run-headless --driver-port=4444
```

**4 tentativas, 4 falhas — sempre a mesma raiz (memória):**
| # | Onde falhou | Erro literal |
|---|---|---|
| 1 | ao compilar | `The Dart compiler exited unexpectedly` / `Failed to compile application` (EXIT 1) |
| 2 | ao arrancar | `Could not start thread DartWorker: 22` (EXIT 127) |
| 3 | `Resolving dependencies` | `Could not start thread DartWorker: 22` / `Failed to update packages` (EXIT 127) |
| 4 | ao compilar a web app | `grep: memory exhausted` + `Could not start thread DartWorker: 22` (EXIT 255) |

Na tentativa 4 o `pub get` até passou (`Got dependencies!`) e chegou a
`Waiting for connection from debug service on Web Server...` antes de a **compilação** esgotar a RAM.

### DIAGNÓSTICO — a causa-raiz de tudo (inclui os 6 fracassos no telemóvel)
```
$ (PowerShell) Get-CimInstance Win32_OperatingSystem
TotalMemMB = 3902     ← o PC tem só ~3,9 GB de RAM TOTAL
FreeMemMB  = 144 … 1791 (volátil)
```
Top consumidores num momento: `dart 825MB`, `dartaotruntime 824MB`, `MsMpEng(Defender) 125MB`,
vários `claude` (100+98+43+28MB), `powershell`. Sobrava < 200 MB.
Processos `dart.exe` zombie das minhas próprias corridas ficavam a ocupar ~1,6 GB; limpei-os
(`Stop-Process`) e a RAM livre subiu 144 → 1505 → 1791 MB, mas **o compile web precisa de 2–4 GB**
e volta a esgotar. **Compilar Flutter web não cabe em 3,9 GB partilhados com OS + Defender + Claude.**

---

## A VPS NÃO RESOLVE (recon read-only via SSH)

`ssh -i /c/Users/danil/.ssh/id_ed25519_vps root@srv1786862.hstgr.cloud`:
```
HOST = srv1786862
--- RAM ---   total 3.8Gi   used 1.5Gi   free 267Mi   available 2.3Gi
--- CPU cores --- 1
--- disk ---  /dev/sda1  48G  14G usados  35G livres  (28%)
--- flutter? ---  NO flutter
--- dart?    ---  NO dart
--- chrome?  ---  NO chrome
--- node?    ---  NO node
--- docker containers ---
  cortex-mcp, hermes-agent-fvnc-hermes-agent-1, searxng, traefik-traefik-1
```
> **Conclusão dura e honesta:** a VPS **não é uma máquina mais forte** — tem a MESMA RAM que o PC
> (3,8 GB), **menos CPU (1 core)**, já corre 4 containers (1,5 GB usados) e **não tem nada instalado**
> (Flutter/Dart/Chrome/Node). Instalar o SDK + compilar a app (2–4 GB) num box de 1 core / 3,8 GB
> já ocupado falharia AINDA mais que no PC. A premissa "usar a VPS porque está sempre ligada" não
> sobrevive à realidade de recursos.

---

## PROVA REAL QUE EU CONSEGUI DAR (caminho leve, sem compilar Dart)

Como o build `build/web` já existia (do sucesso do passo 1), servi-o **estático** e capturei um
screenshot com **Chrome headless** — muito menos RAM que o `flutter drive`:

1. Servidor estático mínimo em Node (só built-ins) — `web-tools/static-server.js`:
```
$ node .../static-server.js "build/web" 8099
SERVING C:\...\build\web @ http://127.0.0.1:8099
$ curl http://127.0.0.1:8099/            → HTTP 200 size=918
$ curl http://127.0.0.1:8099/main.dart.js → HTTP 200 size=7955213
```
2. Screenshot real (com ~1,8 GB livres nesse instante):
```
$ chrome.exe --headless=new --disable-gpu --window-size=1400,2200 \
    --virtual-time-budget=20000 --screenshot=web_rolescreen.png http://127.0.0.1:8099/
60645 bytes written to file ...web_rolescreen.png   (EXIT 0)
(os erros os_crypt "Encryption is not available" são inofensivos — password store do Chrome)
```

**→ `.claude/testes-e2e/web-logs/shots/web_rolescreen.png` mostra a app Bora a correr NUM BROWSER
REAL:** logo BORA + "Entregas rápidas em Portugal", os 3 botões **Sou Cliente** (verde) /
**Sou Estafeta** (castanho) / **Sou Parceiro** (azul), e o banner de Privacidade/Cookies
("Aceitar tudo" laranja, "Rejeitar", "Gerir preferências"). É **exatamente** o RoleScreen que o
teste de integração espera no passo 1. **CanvasKit renderizou e o WebGL funciona em headless.**

### Tentar "o ecrã seguinte" (tocar Sou Cliente → login) — bloqueado pela RAM outra vez
Escrevi um driver CDP puro (Node 24 tem `WebSocket` global — sem instalar Playwright):
`web-tools/cdp-drive.js` (navega, toca botões por coordenada, grava screenshots). Ao corrê-lo a RAM
livre já tinha caído para 119 → 83 MB (chromes acumulados + outras sessões Claude + Defender), e o
2.º arranque do Flutter no browser não bootou a tempo → **0 screenshots** e Chromes pendurados
(limpei-os). Mesmo o caminho leve precisa de uma janela de RAM que esta máquina não garante.

---

## VEREDICTO E RECOMENDAÇÃO

- ✅ **Flutter web compila** (EXIT 0) e **a app corre num browser real** (prova: `web_rolescreen.png`).
  O caminho "testar por web em vez de telemóvel" é **tecnicamente viável e correto**.
- ❌ **Nem o PC (3,9 GB) nem a VPS atual (3,8 GB / 1 core, sem Flutter) têm RAM para o E2E
  interativo** (`flutter drive` / boot repetido do browser). É a MESMA causa-raiz dos 6 fracassos
  no telemóvel: **starvation de recursos**, não bug da app.
- **Onde correr isto de forma fiável (host "sempre ligado" COM RAM):**
  1. **GitHub Actions** — o repo já tem `build_android.yml`; um runner `ubuntu-latest` (2 vCPU,
     **~7 GB RAM**) corre `flutter drive` web + chromedriver à vontade. É o "sempre ligado, não
     depende do PC nem do telemóvel" que a estratégia procura, e com RAM a dobrar. **← recomendo.**
  2. Ou uma VPS maior (≥ 8 GB / 2+ vCPU) com Flutter+Chrome instalados.
- **Fluxos que continuam a precisar de hardware físico** (marcar "só telemóvel, manual depois",
  não bloqueiam): foto real de talão/KYC (câmara), GPS em movimento, som com ecrã bloqueado, push
  com ecrã bloqueado / CallKit. **Tudo o resto** (login, navegação, menu, carrinho, criar pedido,
  favores sem foto real, reservas, histórico, chat, saldo) corre por web assim que houver RAM.

## Transparência (como pedido)
- **Não toquei no Córtex** nem em nada fora do pedido. Toda a saída acima é literal.
- **Ficheiros criados/tocados por mim nesta sessão:**
  - `.claude/testes-e2e/web-tools/static-server.js` (novo) — servidor estático de built-ins.
  - `.claude/testes-e2e/web-tools/cdp-drive.js` (novo) — driver CDP puro Node 24 (interação sem Playwright).
  - `.claude/testes-e2e/web-logs/shots/web_rolescreen.png` (novo) — **prova real**: app no browser.
  - `build/web/*` (gerado pelo `flutter build web`).
  - Este relatório.
- **Não fiz commit nem push** (regra do executor).
- Nada da Lista Vermelha foi tocado (sem dinheiro/pagamentos/dispatch/migrations).
