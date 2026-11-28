---
name: pc-sem-travar
description: Usar antes de abrir sessões em paralelo, ligar o emulador, fazer build Flutter/Gradle ou quando o PC do Danilo estiver lento ou com pouca RAM. Diz quanto o PC aguenta, o que o guardião da RAM faz e como não voltar a encher a memória.
---

# PC sem travar (missão pc-sem-travar, 28/11/2026)

O PC tem 16 GB, mas o Windows só vê **14 GB** (a gráfica integrada da AMD reserva 2 GB).
O que enchia a RAM a 28/11 (detalhe em `docs/ram/antes-2026-11-28.md`): as sessões do Claude Code
com os seus servidores MCP (~6 GB juntando a app Claude Desktop), o Chrome (~4 GB) e o kernel do
Windows (~2,4 GB, com o PC ligado há 12 dias). O commit e a paginação estão bem (paginação gerida
pelo sistema): o aperto é de RAM física, não de commit.

## Quanto o PC aguenta (calculado da medição de 28/11)

- Base fixa: Windows + controladores ~3,5 GB, app Claude Desktop ~1,9 GB, ouvintes remote-control
  ~0,6 GB, Chrome ~2,5 GB com a poupança de memória (4 GB sem ela). Sobram ~5 GB.
- Cada sessão do Claude Code: ~0,8 GB + ~0,2 GB de MCP (era ~0,5 GB com o npx). Folga de 2 GB.
- Regra: **2 sessões em paralelo**; 3 só sem emulador e com o Chrome a dormir; **com o emulador
  ligado (2,5 GB), 1 sessão**.

## Regras

1. Medir antes de trabalho pesado: `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`.
   Portões: leve 1 GB; `flutter build/test` 3 GB; emulador 3,5 GB.
2. Emulador só durante a missão: `C:\BoraLocal\ferramentas\guardiao-ram\LIGAR-EMULADOR.cmd` (liga o
   `emdia35` por snapshot; `LIGAR-EMULADOR.cmd emdia` para o Android 34) e, no fim,
   `DESLIGAR-EMULADOR.cmd` (desliga o emulador e pára os daemons do Gradle e do Kotlin).
3. Depois de cada build: `gradlew --stop`. O `~/.gradle/gradle.properties` deste PC limita o Gradle
   a 3 GB e desliga o daemon parado ao fim de 10 min (o CI não lê este ficheiro).
4. Sessão parada há muitas horas fecha-se (retoma com `claude --resume`). Nunca matar sessões de
   outros com actividade nos últimos 15 min: listar e reportar.
5. Servidores MCP: por projeto (`.mcp.json`), não globais, e lançados com `node <caminho do pacote>`,
   nunca `npx -y` (o npx deixa um segundo processo de ~87 MB por servidor e por sessão). Global só o
   `context7`. O `rea` saiu do global (cópia em `~/.claude/mcp-desligados-2026-11-28.json`).
6. Previas web (`vite preview`, `python -m http.server`) fecham-se no fim da missão que as abriu.
7. Chrome: a poupança de memória (política `HighEfficiencyModeEnabled`) adormece separadores
   parados; os sites dos robôs estão na lista `TabDiscardingExceptions` (WhatsApp, Claude, Facebook,
   Instagram, Supabase, localhost, Flow, Gemini, ChatGPT, YouTube Studio, Telegram, AI Studio).
   Site novo de robô: acrescentar à lista (precisa de administrador).

## O guardião da RAM

`C:\BoraLocal\ferramentas\guardiao-ram\guardiao-ram.ps1`, tarefa agendada `GuardiaoRAM` (3 em 3 min,
escondida, corre com bateria). Log `log.txt` (roda a 1 MB), estado `estado.json`, desfazer em
`DESFAZER-2026-11-28.txt`, resumo diário no `e2e_log` (fluxo `guardiao-ram`).

- VERDE (livre > 4 GB e commit < 80 %; entre 3 e 4 GB também conta verde): só regista.
- AMARELO (livre < 3 GB ou commit > 85 %): fecha órfãos node/claude/bash/cmd (pai morto, parados
  15 min), daemons Gradle/Kotlin parados 10 min, servidor do Dart parado 30 min, emulador com o
  ecrã a dormir há 30 min e sem build.
- VERMELHO (livre < 1,5 GB ou commit > 92 %): o do amarelo + Claude Code com mais de 4 GB e parado
  20 min (fuga) + sessão do Claude Code parada há 12 h; e UM aviso pelo porteiro do Telegram
  (`orquestracao/ponte-telegram.sh`, texto + voz; reserva `gritar-do-pc.sh`), no máximo 1 a cada
  30 min, só quando o vermelho é novo, quando fechou alguma coisa, ou de 3 em 3 h.
- Nunca toca: app Claude Desktop, ouvintes `remote-control`, Chrome, WhatsApp, `servidor_cerebro`,
  `motor-bora`, ponte do Dipsy, Tailscale.
- Provar sem matar: `powershell -File guardiao-ram.ps1 -DryRun -ForcarNivel VERMELHO`.

## Armadilhas

- Matar um processo cuja memória já estava no disco quase não sobe o "Available": olhar para a
  memória em RAM (WorkingSet), não só para a privada.
- O Edit do Claude Code parte o hardlink `~/.claude/CLAUDE.md` <-> `~/.dsh/AGENTS.md`: depois de
  editar, `fsutil hardlink list` e, se faltar um, recriar com `fsutil hardlink create`.
- A bora-tranca recusa apagar pastas fora de build/node_modules: o que for preciso apagar vai num
  `.cmd` para o Danilo, com o motivo no `docs/TRANCAS.md`.
