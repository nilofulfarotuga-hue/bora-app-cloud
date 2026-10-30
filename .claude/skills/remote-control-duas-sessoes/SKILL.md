---
name: remote-control-duas-sessoes
description: "Como ligar, retomar e vigiar o servidor de Remote Control do Claude Code no PC do Danilo para duas ou mais missões ao mesmo tempo sem se derrubarem (modo servidor, uma worktree por sessão). Usar quando uma sessão remota cair, quando o PC do Danilo aparecer offline em claude.ai/code, ou antes de abrir uma missão nova."
---

# Remote Control no PC do Danilo: várias sessões ao mesmo tempo

## O problema que isto resolve
Fora do modo servidor, cada processo do Claude Code segura UMA sessão remota (`claude rc --name bora-app`). Duas missões
a pedir o mesmo PC derrubam-se. O modo servidor (`claude remote-control`) serve até 32 sessões num só processo e, com
`--spawn worktree`, cada sessão nova trabalha na sua cópia do repo.

## Como se liga
- **Primeira vez (visível):** abrir `Desktop\PC-DO-DANILO.cmd`. Aceitar UMA vez os avisos Enable/Trust. Se pedir, carregar
  em Autorizar no navegador (é o `claude auth login`). Não fechar a janela.
- **Sempre (escondido):** a tarefa agendada `Bora Remote Control` arranca no início de sessão do utilizador `danil` e
  repete de 3 em 3 minutos com "ignorar se já estiver a correr", sem janela e sem parar com a bateria. Sem sessão iniciada,
  só regista e sai. (A opção "reiniciar em caso de falha" do Agendador NÃO levantou o servidor: provado a 30/10; por isso a
  repetição.) Provado: servidor morto às 06:53:18, levantado sozinho às 06:58:22.
- O comando por baixo é:
  `claude remote-control --capacity 32 --spawn worktree --permission-mode bypassPermissions --name "PC do Danilo" --chrome`
- Registo: `C:\BoraLocal\QG\claude-rc-servidor.log`. Script: `C:\BoraLocal\QG\pc-do-danilo.ps1`.

## Se o PC aparecer offline
1. `claude auth status` — se disser `"loggedIn": false`, o servidor nunca arranca: `claude auth login` (clique do Danilo).
   Foi exatamente isto que aconteceu na noite de 28/10/2026: o vigia `ClaudeRC-bora` registou "não encontrado" de meia
   em meia hora e `claude rc` falhava com "You must be logged in to use Remote Control".
2. Ver o fim de `claude-rc-servidor.log` e de `claude-rc-bora-watchdog.log`.
3. Retomar uma sessão que caiu (até ~4 h depois): `claude remote-control --session-id <id>` ou `--continue`.
4. O servidor cai ao fim de ~10 min sem rede: a tarefa agendada volta a levantá-lo.

## Um servidor por pasta
O `claude rc --name bora-app` (uma sessão por processo) e o servidor não convivem na mesma pasta. Texto exato do erro:
"This folder is already served by a terminal `claude remote-control` on this device. Stop it first." Por isso, com o servidor
a correr, as tarefas antigas `ClaudeRC-bora` falham de 30 em 30 minutos (inofensivo, mas ruído no
`claude-rc-bora-watchdog.log`). A decisão de as desligar é do Danilo. A do Em Dia (pasta `em_dia`) não colide.

## O que nunca fazer
- Abrir uma sessão "Este computador" solta na app enquanto o servidor corre: apanha o mesmo PC e derruba as outras.
- Correr dois servidores com o mesmo nome. O `LIGAR-CONTROLO-REMOTO-CLAUDE.cmd` antigo também usa "PC do Danilo":
  não usar os dois.
- Mexer na `ClaudeRC-bora` / `ClaudeRC-emdia` à pressa: a sessão da Bora vive nelas.
- Meter `ANTHROPIC_API_KEY` ou `CLAUDE_CODE_OAUTH_TOKEN` no ambiente do servidor (o script tira-as de propósito).

## Estado de 30/10/2026 (missão dsh-harness-2026-10-29)
Login do Danilo feito às 06:48 (`loggedIn: true`). Servidor levantado pela tarefa e confirmado como filho do PowerShell
escondido: `claude remote-control --capacity 32 --spawn worktree --permission-mode bypassPermissions --name "PC do Danilo"
--chrome` (flags aceites; sem avisos Enable/Trust, a pasta já estava confiada). Num teste anterior o ecrã mostrou
`Connected · Capacity: 0/32 · New sessions will be created in an isolated worktree`. Reinício provado. Falta provar duas
sessões ao mesmo tempo (S.3): só vi uma sessão anexada, vazia; precisa de o Danilo abrir duas em claude.ai/code.
Cada sessão anexada é um processo filho `claude.exe --print --sdk-url …`: contá-los dá a ocupação.
