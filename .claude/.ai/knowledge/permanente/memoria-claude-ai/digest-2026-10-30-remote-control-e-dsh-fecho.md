---
id: memoria-claude-ai-digest-2026-10-30-remote-control-e-dsh-fecho
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Claude Code 30/10 — Remote Control caído desde 28/10 e fecho do dsh

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-30-remote-control-e-dsh-fecho`, origem `claude-code`, atualizada em 2026-10-30T06:38:57.854873+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 30 remote control e dsh fecho · memoria claude.ai · claude_ai_memoria

O Claude deste PC está sem sessão iniciada desde a noite de 28/10 (claude auth status: loggedIn false). O vigia ClaudeRC-bora viu o controlo remoto em execução até 28/10 21:01 UTC e desde então só regista "não encontrado": claude rc falha com "You must be logged in to use Remote Control". Os controlos remotos da Bora e do Em Dia estão caídos até o Danilo fazer um clique (claude auth login; abrir o PC-DO-DANILO.cmd chega).

Ficou pronto o servidor de duas sessões (adendo S): Desktop PC-DO-DANILO.cmd e C:\BoraLocal\QG\pc-do-danilo.ps1 correm claude remote-control com capacidade 32 e uma worktree por sessão; a tarefa agendada "Bora Remote Control" levanta-o ao iniciar sessão, escondida, com 5 reinícios e sem parar com a bateria. Provado só o caminho escondido sem sessão (regista e sai com código 3). Duas sessões ao mesmo tempo NÃO provadas: faltam o login e os avisos Enable/Trust. A skill remote-control-duas-sessoes explica como retomar com --session-id e o que nunca fazer (abrir sessão "Este computador" solta enquanto o servidor corre). ClaudeRC-bora, ClaudeRC-emdia e o LIGAR-CONTROLO-REMOTO-CLAUDE.cmd antigo não foram tocados.

Fecho do dsh (missão dsh-harness-2026-10-29): relatório em .claude/.ai/reports/DSH-HARNESS-2026-10-29.md no repo. Provado: livro, CLAUDE.md, 146 skills, Córtex por MCP, motor grátis Kilo/Gemini, plugin session-search. Por provar ou sem tempo: Supabase (token caducado), Google das duas contas (falta o Permitir), olhos, Telegram, ponte, e os restantes plugins. Quem escreve na base continua a ser só o Claude Code: o dsh não tem tranca nem hooks.
