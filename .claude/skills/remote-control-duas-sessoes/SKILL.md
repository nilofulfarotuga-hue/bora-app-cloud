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
- **Sempre (escondido):** a tarefa agendada `Bora Remote Control` arranca no início de sessão do utilizador `danil`, sem
  janela, com 5 reinícios de 2 em 2 minutos se cair e sem parar com a bateria. Sem sessão iniciada, só regista e sai.
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

## O que nunca fazer
- Abrir uma sessão "Este computador" solta na app enquanto o servidor corre: apanha o mesmo PC e derruba as outras.
- Correr dois servidores com o mesmo nome. O `LIGAR-CONTROLO-REMOTO-CLAUDE.cmd` antigo também usa "PC do Danilo":
  não usar os dois.
- Mexer na `ClaudeRC-bora` / `ClaudeRC-emdia` à pressa: a sessão da Bora vive nelas.
- Meter `ANTHROPIC_API_KEY` ou `CLAUDE_CODE_OAUTH_TOKEN` no ambiente do servidor (o script tira-as de propósito).

## Estado de 30/10/2026 (missão dsh-harness-2026-10-29)
Lançador e tarefa criados e o caminho escondido provado (sem sessão: regista e sai com código 3). Falta o login do Danilo
para provar duas sessões ao mesmo tempo (S.3).
