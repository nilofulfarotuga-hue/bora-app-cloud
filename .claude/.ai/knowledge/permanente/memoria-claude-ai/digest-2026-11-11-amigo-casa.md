---
id: memoria-claude-ai-digest-2026-11-11-amigo-casa
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Digest 11/11 — Amigo com a Casa e Manutenção (por publicar)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-11-amigo-casa`, origem `claude-code`, atualizada em 2026-11-11T17:07:15.528221+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 11 amigo casa · memoria claude.ai · claude_ai_memoria

Missão amigo-casa-2026-11-11 (Danilo 12:39, "Conserta o amigo"), Claude Code Opus 5.5 no PC, loop headless. O client-assistant no ar (v24) é igual a origin b8af9bc9 (8 ficheiros conferidos pelo MCP). Causa do defeito: o Amigo não tinha ferramenta da Casa (não sabia preços) e a nota interna ACAO_NUDGE empurrava qualquer "preciso de..." para pedir_favor (daí o botão "Pedir um Favor"); o "quantas pessoas" era improviso do modelo. Conserto: casa.ts + ferramenta casa_servicos (lê casa_config: serviços e preços da casa_servicos, garantia_dias 7, cancel_free_hours 12, ofícios desligados), regra 9e no prompt, sem nudge de Favor nem botões de Favor em trabalho de casa, frases de reserva de mesa cortadas, e a ligação "Abrir a Casa e Manutenção para marcar" como deixa abrir_faixa {categoria casa}, que as apps publicadas já abrem (não precisa de versão nova). deno test 55/55, deno check limpo, anti_trapaca limpo; casa_config real dá roupeiro 80 € por móvel, TV 45 €, torneira 40 €, autoclismo 20 €/h. NÃO PUBLICADO: a trava recusou ler .supabase-token.env (CLI sem login no PC) e o deploy_edge_function pelo MCP ("publica a Claude.ai"); o git push do ramo ai/2026-11-11-amigo-casa falhou sem credencial (wincredman, sessão sem consola). Entrega pelo livro: entrega-amigo-casa-2026-11-11 (instruções e provas) e entrega-amigo-casa-2026-11-11-patch (md5 aa6ddea3 igual ao ficheiro). Achado: em produção a Pintura, Eletricidade, Gás, Pladur, Jardinagem e Mudanças estão desligados, por isso "quero pintar a sala" não tem orçamento de pintura; o Amigo diz que ainda não está disponível. Worktree C:\BoraLocal\wt-amigo-casa (commit local c3fd3033, relatório docs/relatorio-amigo-casa-2026-11-11.md). e2e_log 8236, 8237, 8246, 8247.
