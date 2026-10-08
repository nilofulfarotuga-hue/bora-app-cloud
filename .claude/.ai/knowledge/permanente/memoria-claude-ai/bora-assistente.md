---
id: memoria-claude-ai-bora-assistente
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-07
zona: verde
confianca: alta
estado: atual
---

# Bora Assistente — assistente de compras do cliente (no ar desde 07/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `bora-assistente`, origem `claude-code`, atualizada em 2026-10-07T23:15:09.64172+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: bora assistente · memoria claude.ai · claude_ai_memoria

No ar desde a noite de 07/10/2026 (Claude Code Fable). Edge Function client-assistant v5 (verify_jwt; Gemini gemini-3.5-flash-lite com reserva gemini-3.5-flash; 14 ferramentas: search_products, basket_quote, propose_cart, get_usual_basket, favor_price, get_orders, get_order_status, get_wallet, get_tokens, get_refund_status, store_hours, remember, forget, report_gap, suggest_action; o modelo nunca escreve preços: totais de quote_order_pricing). Base: tabelas assistant_conversations, assistant_chat_messages (renomeada: assistant_messages já era do assistente WhatsApp), assistant_cart_proposals, assistant_client_memory, assistant_client_stats, assistant_knowledge, assistant_gaps, assistant_quota, canonical_products, product_matches, product_embeddings; view assistant_lojas; RPCs assistant_search_products (FTS portuguese + unaccent + pg_trgm + vector, 1.ª palavra obrigatória), assistant_basket_quote (só supermercados/farmácias, parecido = em falta, divisão em 2 lojas se poupar ≥3 € ou 5 %), assistant_favor_quote, assistant_propose_cart, assistant_mark_proposal, admin_assistant_overview. Settings assistant_* em platform_settings (kill-switch assistant_enabled). Flutter: lib/screens/client/assistant/*, assistant_service.dart, BoraClientFabs, rota /assistente, painel /admin/assistente, memória no perfil; faixa home_banners inativa (tipo categoria/assistente). Provas 07/10: lista de 5 artigos → Intermarché 18,15 / Auchan 18,63 / Pingo Doce 24,45 / Continente 29,75 com entrega; diferença 0,00 vs quote_order_pricing; cheeseburger McDonald's 7,43; tabaco → Favor +18; foto de lista 8 artigos. Custo médio 0,00061 USD/conversa. PENDENTE DO DANILO: a chave Gemini do projeto (bora-juiz, ...FfBA) e todas as da conta Bora estão em nível gratuito (proibido na Europa, quota rebenta): ligar faturação em gen-lang-client-0518472552. Embeddings só 200/56.514 (quota gratuita); correr embed_products.cjs com chave paga. Erro apanhado: a API Gemini v1beta recusa role 'function' (400) — o support-chatbot v27 ainda o usa em 2 sítios. Skill: .claude/skills/bora-assistente.
