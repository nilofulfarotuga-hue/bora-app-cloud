---
id: memoria-claude-ai-embeddings-supabase-2026-11-03
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-04
zona: verde
confianca: alta
estado: atual
---

# Motor grátis de vetores com Gemini de reserva — 03-04/11 Claude Code

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `embeddings-supabase-2026-11-03`, origem `claude-code`, atualizada em 2026-11-04T07:15:25.549589+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: embeddings supabase 2026 11 03 · memoria claude.ai · claude_ai_memoria

Missão embeddings-supabase-2026-11-03 (ordem do Danilo 03/11 19:21 e 19:22: trocar para o motor grátis do Supabase só se passar na prova em português, sempre com reserva). Feito e no ar: a pesquisa por significado do Bora Assistente (search_products, basket_quote, search_help) e do chat de ajuda (support-chatbot) usa agora dois motores, gte-small grátis dentro da Edge Function (384) e Gemini gemini-embedding-001 (768), um de reserva do outro; sem nenhum, segue só por texto. Código único em supabase/functions/_shared/embeddings.ts; a ordem vem de platform_settings por assunto. Prova com 40 perguntas reais em português (critério escrito antes, ESPEC.md nas provas): nos produtos o gte acertou 35/40, o Gemini 32/40 e o texto 32/40, por isso embeddings_motor_primario_produtos = gte; no manual de ajuda o gte acertou 7/12 contra 10/12 do Gemini, por isso embeddings_motor_primario_ajuda continua gemini. Reserva provada com pedidos reais (conta e2e_client_a por link mágico) nos três casos: gte a falhar → Gemini; Gemini a falhar → gte; os dois → só texto, sem erro; e uma volta real pela app web app.boraguarda.com (motor_vetores gte). Vetores gte: tabela nova product_embeddings_gte (47745/47745), coluna support_knowledge_chunks.embedding_gte (605/605), cache embedding_cache_gte; as colunas de 768 ficaram intactas e assistant_search_products/match_knowledge mantêm a assinatura, escolhendo pelo tamanho do vetor. Manutenção: agendamentos embeddings-gte-manter (2 min) e embeddings-gemini-novos (hora a hora, 20). Armadilhas novas: o gte gasta processador da própria função (~115 ms por texto) e a Edge Function morre com 546 "CPU Time exceeded" acima de ~2 s, por isso há um orçamento de 6 vetores gte por pedido (embeddings_gte_max_por_pedido) e o enchimento foi feito em ~5400 pedidos pequenos; os LOTES do Gemini deram 429 de quota diária ao fim de ~900 textos (as perguntas simples continuam a passar). Reportado sem corrigir: o Gemini só tinha vetor de 213 dos 47745 produtos; o assistente disse que os tokens dão "até 50% do valor do pedido" (choca com a regra da metade do valor dos tokens — dinheiro, precisa de revisão); pergunta sobre MB Way no assistente caiu em "não consegui montar o carrinho"; reindex-knowledge e _shared/claude.ts no repo estão à frente do ar (commit 634ba274, não publicado por mim). Voltar atrás: embeddings_motor_primario_produtos = gemini. Código: commit 1fffcdfb ([skip ci]). Aviso: a reserva Gemini só funciona enquanto o cartão do projeto bora-juiz estiver válido.
