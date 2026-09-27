---
id: memoria-claude-ai-digest-2026-09-27-agente-comando
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-27
zona: verde
confianca: alta
estado: atual
---

# Claude Code 27/09 — agente de comando único (tool/qa)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-27-agente-comando`, origem `claude-code`, atualizada em 2026-09-27T18:24:26.569462+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 27 agente comando · memoria claude.ai · claude_ai_memoria

Fechada a missão que o OpenCode deixou a meio: bora_app/tool/qa/agente_comando.py é o ponto único de contacto do framework de automação web (WebAutomator, PageAnalyzer, InteractionEngine, IntentOrchestrator). Uso: python -m tool.qa.agente_comando "resolva a questão na tela" --url https://... . A IA planeia uma vez (url, modo navegar/clicar/ler/resolver, seletores, critério de sucesso); com ordem vaga abre a página e lê o ecrã e o inventário antes de planear; seletores inventados são conferidos contra a página e deitados fora se não batem; o loop perceber-decidir-agir corre no IntentOrchestrator com tecto de passos e replaneamento. Novo hoje: --sucesso "frase" (critério declarado pelo utilizador, ganha ao da IA) e --provedor auto|openai|claude (Claude via camada compatível OpenAI da Anthropic, modelo claude-haiku-4-5). Corrigido um teste que contradizia o desenho. Prova: test_agente_comando 19/19, test_executor_mock 11/11, test_refs_opcoes 4/4. Falta: nenhuma chave de IA configurada no PC (sem .env), por isso nunca correu contra IA real; a pasta tool/qa não está no git; sem verificador independente. Relatório: QG/relatorios/agente-comando-2026-09-27.md.
