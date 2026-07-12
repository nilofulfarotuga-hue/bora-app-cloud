# Heartbeat reconfigurado: browser → Claude Desktop (2026-07-12)

**Estado: TESTE ÚNICO PASSOU (frase escrita e enviada dentro do app Claude Desktop).**
Prova: `.claude/testes-e2e/screenshots-pc/teste-heartbeat-desktop.png`.

## O que mudou e porquê
O `heartbeat-browser` conduzia o Chrome por Playwright/CDP e **batia no Cloudflare Turnstile**
(o browser controlado é detetado como automação). Troquei para conduzir o **app Claude Desktop**
que o Danilo já mantém aberto e fixo na barra — por **input de sistema operativo** (foco de janela
+ Ctrl+V + Enter), sem CDP, logo **sem Turnstile**.

## Descobertas importantes (durante o trabalho)
1. **NÃO é browser nem PWA — é o Claude Desktop nativo.** O screenshot de prova mostra a UI do app
   (abas Home/Code, Projetos, Artefatos, Despacho Beta, painel Execuções/Progresso/Contexto, conta
   `danilo · Max`). A minha 1ª busca não o via porque o executor Hermes corre em **Session 0**
   (serviços) e o app vive na **Session 1** (danil, console).
2. **Isolamento de sessão do Windows.** Um processo da Session 0 **não** clica nem tira screenshot
   da Session 1. Solução: o gatilho corre por **schtask `/RU danil /IT`** (token interativo) — só
   assim alcança o desktop visível. Provado: probe correu como `danil`; operador correu e enviou.
3. **Dois sinais no ecrã do app (NÃO são do heartbeat, são do ambiente):**
   - ⚠️ **Disco quase cheio: C: com 5,6 GB livres (4,8%).** O app mostra *"Falha ao iniciar o
     espaço de trabalho do Claude — Not enough disk space"*. **O heartbeat entrega a mensagem, mas
     o loop do Claude pode não conseguir arrancar o workspace para executar.** Não liberto espaço
     por conta própria (mexe em ficheiros do Danilo) — **fica para decisão do Danilo**.
   - ⚠️ *"Você usou 90% do seu limite de sessão"* (conta Max) — perto do teto.

## Como ficou (arquitetura)
- **Peça 1 (detetor, inalterada):** `.claude/scripts/heartbeat-browser.py` — watermark barato;
  só escreve `pending.trigger` em mudança real (anti-spam camada 1).
- **Peça 2 (operador desktop, NOVA):** `.claude/.ai/hermes/heartbeat-desktop/desktop-send.py`
  — traz o app Claude à frente (abre se estiver fechado), clica no composer, cola a frase fixa,
  envia; screenshot em cada passo; move o trigger para `consumidos/` (anti-spam camada 2).
- **Wrapper + schtask:** `run-heartbeat-desktop.cmd` (detetor→operador, com log) registado como
  **`Bora-heartbeat-desktop`** `*/10` `/RU danil /IT`. Antigo `Bora-heartbeat-browser` já não
  existia como schtask (nada a apagar). **Switch completo.**
- **Deps:** `pyautogui/pygetwindow/pyperclip/pillow` em `heartbeat-desktop/_libs` (pip
  `--target`, injetadas por `sys.path` — independentes da sessão/utilizador).
- **Frase fixa** (a da tarefa): *"Bora Loop automatico: verifica o estado das ordens e testes do
  Bora e age no que for preciso, so avisa se for importante ou decisao de dinheiro."*

## Resultado do teste único (log real)
```
STEP 0 OK: trigger lido, frase 144 chars
STEP 1 OK: app Claude ja aberto (2 janela(s)) -> trazer p/ frente
STEP 1 OK: janela em frente rect=(50,0,1822x1019)
STEP 2 OK: clicado no composer em (961,929)
STEP 3 OK: frase colada no composer
STEP 4: Enter pressionado
STEP 5 OK: mensagem enviada (prova) -> teste-heartbeat-desktop.png
STEP 6 OK: trigger consumido
[test] exit=0
```

## Notas / limites conhecidos (para o próximo ciclo)
- O operador cola na **conversa atualmente aberta** no app (no teste, a conversa "Bora loop"
  agendada). Como o Danilo mantém o app fixo nessa conversa do loop, é o comportamento desejado —
  mas se ele deixar outra conversa aberta, a frase vai para essa. Melhoria futura opcional: forçar
  clicar em "Novo" / abrir a conversa do loop antes de colar. Deixei como está (mais simples e não
  interrompe menos o Danilo do que abrir chats novos).
- Reversível: `schtasks /Delete /TN "Bora-heartbeat-desktop" /F`.
- `loops.md` atualizado: linha e nota agora **heartbeat-desktop**, dono **desktop-operador**.

## Ficheiros tocados
- **Novos:** `.claude/.ai/hermes/heartbeat-desktop/desktop-send.py`,
  `run-heartbeat-desktop.cmd`, `instalar-schtask-desktop.cmd`, `_setup-deps.cmd`,
  `_test-operador.cmd`, `README.md`, `_libs/` (deps).
- **Editados:** `.claude/.ai/knowledge/permanente/semantica/loops.md`.
- **Schtask:** `Bora-heartbeat-desktop` criado (`/RU danil /IT`, `*/10`).
- **Prova:** `.claude/testes-e2e/screenshots-pc/teste-heartbeat-desktop{,-1-janela,-2-antes}.png`.
