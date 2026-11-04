---
id: memoria-claude-ai-digest-2026-11-04-checkin-desconto-mercadona
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-04
zona: verde
confianca: alta
estado: atual
---

# Digest 04/11 tarde — check-in desconto e aviso Mercadona

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-04-checkin-desconto-mercadona`, origem `claude-code`, atualizada em 2026-11-04T14:02:54.547922+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 04 checkin desconto mercadona · memoria claude.ai · claude_ai_memoria

Continuação da missão checkin-escada-premios-2026-11-04 com o "eu autorizo." de 12:42. quote_order_pricing passou a aplicar o vale de desconto do check-in quando o pedido traz checkin_vale_id (patch por âncora, migração 20261104125306): valida dono, tipo, validade, loja e mínimo de produtos; tira ao customer_total e à platform_commission; driver_earnings igual; devolve checkin_desconto e checkin_desconto_falta_cents. Provado em DO+RAISE no Continente (7 un.: 35,60 -> 32,60, estafeta 5,35 igual; 4 un.: falta 5,28). A migração do create_order foi BLOQUEADA pela bora-tranca ao escrever o ficheiro ("migration que toca tokens/wallet/pagamentos/ledger") — proibição que só levanta com claude --safe-mode aberto pelo Danilo ou pela Claude.ai por MCP; o desenho está no e2e_log (desconto depois da taxa de pedido pequeno, antes de tokens/saldo; UPDATE do vale para usado com pedido_id logo antes do wallet_debit_for_order; o gatilho de cancelamento já devolve por pedido_id). B (talão e acerto do estafeta) não tentado, mesma zona. 11 degraus continuam desligados. Achado: nos não-parceiros a platform_commission é só a taxa de serviço, com desconto fica negativa. Aviso da loja: widget AvisoDaLoja lê restaurants.about_text e aparece no topo da página de restaurante e da de supermercado (MarketStoreTab); visto na web na Mercadona Beleza. A Mercadona Beleza mostra "Frescura garantida" (não faz sentido). iPhone da missão anterior entregue (Delivery UUID bc1e1b10).
