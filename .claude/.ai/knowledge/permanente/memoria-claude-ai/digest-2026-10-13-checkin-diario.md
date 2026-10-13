---
id: memoria-claude-ai-digest-2026-10-13-checkin-diario
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-13
zona: verde
confianca: alta
estado: atual
---

# Claude Code 13/10 — Bora Todo Dia n.º 1: check-in diário (app e painel no ar, servidor por aplicar)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-13-checkin-diario`, origem `claude-code`, atualizada em 2026-10-13T10:43:19.72761+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 13 checkin diario · memoria claude.ai · claude_ai_memoria

O que funciona agora: a app do cliente (Android, iPhone e site) tem o cartão "Check-in diário" na home, logo abaixo da pesquisa, e o painel admin tem a página "Check-in diário" na secção Clientes (ligar/desligar, 7 valores e validade com motivo, lembretes 11h/20h, quem está em que dia, custo em €, dar/tirar tokens com registo, CSV). Commits f405bc28, 1f7bf305, ecdd0dcd e c0bf8d2d no ramo autonomous-night-2026-04-29. O cartão ESCONDE-SE sozinho enquanto o servidor não tiver as funções: provado no site (o servidor responde 404 PGRST202 e a home fica inteira) e com respostas simuladas no navegador (o cartão aparece, o toque dá "Ganhaste 10 tokens!" e "Volta amanhã para ganhar 10 tokens.").

O que falta e quem faz: (1) CLAUDE.AI — aplicar a migração sem dinheiro supabase/migrations/20261013060000_checkin_diario_base.sql tal como está no repo; a bora-tranca recusou-a duas vezes no PC (1.ª: platform_settings com token_; 2.ª: caixa). Sozinha não liga nada. (2) DANILO dá o "vai" e a Claude.ai aplica o bloco SQL de .claude/.ai/missoes/bora-todo-dia-checkin-2026-10-13/proposta-credito-checkin.md (client_daily_checkin + checkin_rewards + checkin_token_expiry_days; mexe em bora_tokens). Depois corre-se prova-producao-depois-do-vai.md (tudo revertido) e o check-in fica ligado para todos. Prova local PGlite 62/62; verificador de contexto limpo aceitou com ressalvas (corrigidas).

Decisões do Danilo pendentes: opt-in de marketing está a 0 clientes, por isso com checkin_push_so_opt_in=true os lembretes não chegam a ninguém; não há SMS (telemóvel "confirmado" = número PT válido; 7 números repetidos em 17 contas); lembrete das 20h vai também a quem fez o Dia 7 ontem (regra literal). source_order_id ficou checkin-AAAA-MM-DD-<uid> (índice único em bora_tokens). Outros achados: get_user_tokens deixa ler o saldo de outra pessoa; espelho do Córtex esmagou 6 ficheiros do Cérebro a 07-08/10 (repostos hoje pelo Bibliotecário, causa por corrigir).
