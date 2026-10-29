---
id: memoria-claude-ai-adendo-harness-servidor-remote-control-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# ADENDO para a missao do Harness (sessao DeepSeek Harness installation): no fim, servidor de Remote Control para duas sessoes ao mesmo tempo

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `adendo-harness-servidor-remote-control-2026-10-29`, origem `claude.ai`, atualizada em 2026-10-29T21:55:41.942402+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: adendo harness servidor remote control 2026 10 29 · memoria claude.ai · claude_ai_memoria

Para a sessao "DeepSeek Harness installation" (session_01HPEpV8oqs9TVRzegSZC8PF) fazer no FIM do seu trabalho (depois do B7 e do adendo do dsh), pedido do Danilo 21:51 ("quando o Hermes acabar, fazer o que ele falou que tinha que fazer para nao acontecer mais isso" = duas missoes nunca mais se derrubarem uma a outra).

Factos documentados (https://code.claude.com/docs/en/remote-control): fora do modo servidor cada processo do Claude Code segura UMA sessao remota; o modo servidor `claude remote-control` serve ate 32 sessoes (--capacity), com --spawn worktree cada sessao nova tem a sua worktree git, --spawn same-dir partilha a pasta; o servidor vive no terminal (sem flag de daemon), cai apos ~10 min sem rede, e sessoes novas criam-se a partir de claude.ai/code ou da app no telemovel; retomar: --continue ou --session-id <id> (ate ~4 h depois de parar); precisa de login claude.ai e pasta confiada (trust).

TAREFAS:
S.1) Lancador C:\Users\danil\Desktop\PC-DO-DANILO.cmd que abre PowerShell em C:\Users\danil\Desktop\projetosflutter\bora_app e corre: claude remote-control --capacity 32 --spawn worktree --permission-mode bypassPermissions --name "PC do Danilo" --chrome. (worktree: cada missao na sua copia do repo, sem se pisarem; se o repo recusar worktree, usar same-dir e registar.) Aceitar uma vez os prompts Enable/Trust.
S.2) Tarefa agendada do Windows "Bora Remote Control" (schtasks) que corre esse lancador no inicio de sessao do utilizador danil, com reinicio automatico se cair (RestartCount) e que NAO abre janela em cima do trabalho dele (minimizada). Testar: parar o servidor, deixar a tarefa reiniciar, provar que claude.ai/code mostra o PC online.
S.3) Provar duas sessoes ao mesmo tempo: criar 2 sessoes a partir de claude.ai/code no PC do Danilo (uma pode ser so "diz ola e sai"), confirmar que as duas ficam online em simultaneo e que a sessao da Bora (session_01HPEpVCfPzS9j8Nzb5E1fRc) e esta nao caem. Registar em e2e_log (fluxo dsh-harness-2026-10-29, passo S-remote-control-servidor) com prova.
S.4) Skill .claude/skills/remote-control-duas-sessoes/SKILL.md (como se lanca, como se retoma uma sessao caida com --session-id, o que nunca fazer: abrir sessao "Este computador" solta na app enquanto o servidor corre) + nota no Obsidian + livro comum no Cortex. Avisar o Danilo pelo Telegram em UMA frase quando estiver provado. Reportar outros erros em vez de os corrigir calado. Terminar com /ctx doctor e /ctx stats.
