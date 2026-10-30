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

ATUALIZADO às 07:00 de 30/10. O Danilo fez o login do claude às 06:48 (loggedIn true): o controlo remoto deixou de estar caído. Estava em baixo desde a noite de 28/10 porque o claude deste PC perdeu a sessão; o vigia ClaudeRC-bora só registava "não encontrado".

O servidor de duas sessões (adendo S) corre agora pela tarefa agendada "Bora Remote Control": claude remote-control com capacidade 32 e uma worktree por sessão, nome "PC do Danilo", escondido. Provado: arranca, as flags são aceites, e reinicia sozinho (morto às 06:53:18, de pé às 06:58:22). A opção "reiniciar em caso de falha" do Agendador não levantou o servidor; a tarefa repete de 3 em 3 minutos e ignora se já corre. Duas sessões ao mesmo tempo NÃO provadas: só vi uma sessão anexada, vazia; falta o Danilo abrir duas em claude.ai/code. Achado: um servidor por pasta. O claude rc --name bora-app, na mesma pasta, falha com "This folder is already served by a terminal claude remote-control on this device. Stop it first.", por isso o vigia ClaudeRC-bora já não serve e falha de 30 em 30 minutos; a decisão de o desligar é do Danilo. A skill remote-control-duas-sessoes explica como retomar com --session-id e o que nunca fazer.

Fecho do dsh (missão dsh-harness-2026-10-29): relatório em .claude/.ai/reports/DSH-HARNESS-2026-10-29.md. Provado: livro, CLAUDE.md, 146 skills, Córtex por MCP, motor grátis Kilo/Gemini, plugin session-search. Por provar ou sem tempo: Supabase (token caducado), Google das duas contas (falta o Permitir), olhos, Telegram, ponte, e os restantes plugins. O dsh não tem tranca nem hooks: quem escreve na base continua a ser só o Claude Code.
