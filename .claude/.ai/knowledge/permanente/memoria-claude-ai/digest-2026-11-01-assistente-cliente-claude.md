---
id: memoria-claude-ai-digest-2026-11-01-assistente-cliente-claude
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-01
zona: verde
confianca: alta
estado: atual
---

# Digest 01/11 — Bora Assistente com Claude primeiro + 3 melhorias de 10/10; stories em breve

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-01-assistente-cliente-claude`, origem `claude-code`, atualizada em 2026-11-01T21:03:30.236363+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 01 assistente cliente claude · memoria claude.ai · claude_ai_memoria

Missão assistente-cliente-2026-11-01 (Claude Code na nuvem), ordem do Danilo 01/11 19:56.

ASSISTENTE DO CLIENTE (Edge client-assistant v7 → v10, verify_jwt=true, ficheiros no ar iguais ao repo): Claude primeiro pelo _shared/claude.ts (robô edge-assistente, P1, Sonnet 5.5; entrada nova em platform_settings.claude_robos), Gemini de sempre fica de reserva quando o Claude devolve null (sem crédito, porteiro, 429, timeout); as ferramentas que o Claude já correu passam ao Gemini como notas. As 3 melhorias de 10/10 feitas no servidor: (1) várias fotos de uma vez (images[] até 6, uma leitura só); (2) prints do carrinho da Glovo/Uber/iFood: lê artigos + total da outra app, corre basket_quote e devolve `comparacao` calculada em código (total lá, total mais barato no Bora com entrega, loja, diferença); (3) aprende: search_help (manual do suporte, RAG) antes de "não sei" e guarda em assistant_learned; learn_lesson quando o cliente corrige; bloco "LIÇÕES E PERGUNTAS JÁ APRENDIDAS" no prompt. v9: texto que acompanha ferramentas leves (botão/memória) já não se perde. v10: filtro de trechos internos do manual (ganhos de estafetas, comissões, percentagens, código) + regra 18 no prompt.
Provas (demo.cliente@bora.app, sessão por magic link via pg_net): bananas no Continente → Claude, carrinho 4,71 € com entrega; pizza → Claude, DaVinci Margherita 13,81 €; último pedido → Claude, Auchan 7,17 € entregue + botão; reserva Gemini provada ao desligar o robô no painel (motor gemini-3.5-flash-lite, get_orders), depois religado. ia_gastos edge-assistente ids 139-149, 156-160 (0,005-0,019 USD/chamada, cache a funcionar). e2e_log 6018-6022.
FALTA: (a) DDL da tabela assistant_learned na gaveta platform_settings.staged_assistant_learned_20261101 (o conector cancelou a confirmação 2x; a função ignora a tabela enquanto não existir — a Claude.ai aplica); migração no repo supabase/migrations/20261101210000_assistente_aprende_2026_11_01.sql. (b) App Flutter: seletor de várias fotos (SafeImagePicker.pickMultiImage → images[]), cartão `comparacao` no chat, separador "Aprendidas" no /admin/assistente (RLS is_admin). (c) O RAG do suporte (support_knowledge_chunks) é feito de vault/business_rules internos e desatualizados (gorjeta 80/20 "planeada" vs regra atual): rever a fonte — o support-chatbot usa o mesmo RAG para clientes.

STORIES "EM BREVE": o robô vive na VPS (social-story.sh, story_pergunta.py, social-loja-do-dia.sh, formato_extra.py, carrossel.py, proxima_loja.py; escolhedor lojas_permitidas.py desde 27/10). Não editável daqui: patch exato em docs/propostas/stories-em-breve-2026-11-01.md para a missão do PC. Rede no banco já aplicada: RPC public.social_lojas_permitidas() (aberta a anon para o robô) devolve 22 lojas, todas abertas/ativas/aprovadas/com produtos; Amaya, Boom, Mr Kebab, Loja Demo, Lidl, Mercadona, Pizza Hut, Mister Navalha, Ouro e Prata, BeUnique ficam fora. e2e_log 6023-6024.
