---
id: memoria-claude-ai-pesquisa-assistente-cliente-2026-10-07
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-07
zona: verde
confianca: alta
estado: atual
---

# Pesquisa mundial para o assistente de compras IA do cliente (base da missão que vem depois do +18)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `pesquisa-assistente-cliente-2026-10-07`, origem `claude.ai`, atualizada em 2026-10-07T16:44:37.912688+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: pesquisa assistente cliente 2026 10 07 · memoria claude.ai · claude_ai_memoria

PEDIDO DO DANILO (07/10): assistente IA na home ("Novidade"), cliente escreve/fala ("arroz, leite, ovos", "um cheeseburger", "tabaco"); conversa, procura em todas as lojas, compara, recomenda a loja mais barata PARA O CESTO TODO contando a entrega (ex.: 10 artigos, uns mais baratos no Pingo Doce, mas o total fica mais barato no Continente), enche o carrinho, tabaco/fora do catálogo vai para Favores com preço e pergunta marca; quer "o melhor de todos, melhor que o iFood". Fazer a compra sozinho = com confirmação do cliente.

O QUE OS GRANDES FAZEM: iFood Ailo (WhatsApp+app, texto e áudio, memória "o de sempre", cupões, fecha pedido 1 clique só Pix; só restaurantes). Uber Eats Cart Assistant (fev/2026: lista escrita/foto de lista/receita -> carrinho com "o teu leite de sempre"; 1 loja de cada vez, sem comparar). DoorDash Ask DoorDash (voz, texto, imagem, pergunta o que já há em casa). Instacart (ChatGPT app, Smart Shop 14 preferências; caso negativo: preços diferentes por cliente destruíram confiança). Walmart Sparky (repõe despensa, voz, imagem, memória). Amazon Rufus (histórico de preço, auto-buy com 24h para cancelar). Glovo app no ChatGPT/Claude (paga na Glovo). Just Eat assistente de voz multilíngua. Carrefour Hopla (orçamento + dieta -> carrinho + receitas). NINGUÉM das apps de entrega compara cesto entre lojas com taxa de entrega: só comparadores (Kabaz/KuantoKusta PT: loja mais barata para a lista + opção dividida; Super Save PT; GroceryChop: loja única / por produto / divisão limitada a 3 lojas, penaliza correspondências duvidosas). => DIFERENCIAL DO BORA.

ARQUITETURA RECOMENDADA: 1 agente com function calling na Edge Function (reaproveitar support-chatbot v27). Ferramentas só LER e PROPOR: search_products (pesquisa híbrida Postgres: full-text 'portuguese'+unaccent, pg_trgm, pgvector com embedding Gemini 768d, fusão RRF), basket_quote(items, morada) em SQL (para cada loja: artigos + taxa entrega + serviço + pedido pequeno; ordenar; opção dividir 2 lojas só se poupar > ~3€/5%; artigos sem loja -> Favores por regra fixa no servidor), propose_cart (rascunho). NUNCA ferramenta de pagamento; o LLM nunca escreve preços nem faz contas; abre o checkout normal, servidor recalcula, cliente carrega "Confirmar e pagar". Correspondência entre lojas: normalizar marca/quantidade/unidade (preço por kg/L), candidatos por trigramas+embedding, casos duvidosos o Flash-Lite decide, guardar em canonical_products/product_matches. UI: widget de chat próprio em Flutter, Edge Function devolve JSON fixo {texto, propostas[{loja, artigos, subtotal, taxas, total}], favores[]} -> cartões + botão "Adicionar tudo ao carrinho" (GenUI ainda alpha). Voz: speech_to_text pt_PT para começar, ou áudio direto ao Gemini. Memória do cliente: "o de sempre", marcas preferidas, substituições por produto (trocar/não trocar/perguntar). +18: tabaco/álcool nunca pago sozinho, verificação na entrega. Admin: ver conversas, ligar/desligar, editar conhecimento, métricas (carrinhos criados, conversão).

ATENÇÃO MODELO: termos da Gemini API proíbem o nível GRÁTIS em apps que servem utilizadores no EEE/Suíça/RU -> o assistente do cliente tem de usar Gemini PAGO (~0,005 USD/conversa, Flash-Lite). Reserva: Groq/OpenRouter pagos. A regra "motores grátis com rotação" fica para os automáticos internos. Não usar assinaturas pessoais (Claude/ChatGPT/OpenCode) para servir clientes. Verificar também se o robô de suporte atual (support-chatbot) está em chave paga.

Fontes principais: canaltech (Ailo), techcrunch 11/02/2026 (Uber Cart Assistant), observador 29/01/2024 (Kabaz), supabase.com/docs/guides/ai/hybrid-search, ai.google.dev/gemini-api/terms_preview, genai.owasp.org/llm08.
