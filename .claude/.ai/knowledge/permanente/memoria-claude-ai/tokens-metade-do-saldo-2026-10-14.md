---
id: memoria-claude-ai-tokens-metade-do-saldo-2026-10-14
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-14
zona: verde
confianca: alta
estado: atual
---

# Tokens do cliente: metade do saldo + desconto chega à cobrança (14/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `tokens-metade-do-saldo-2026-10-14`, origem `claude-ai`, atualizada em 2026-10-14T21:57:04.962195+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: tokens metade do saldo 2026 10 14 · memoria claude.ai · claude_ai_memoria

REGRA DO DANILO (14/10/2026): em cada pedido/corrida o cliente só usa METADE do valor dos tokens que tem (tem 5 EUR -> usa 2,50 EUR). platform_settings.token_balance_max_use_pct = 50 (editável no painel, Configurações). O tecto antigo token_payment_max_pct (máx. 50% do valor do pedido) continua por cima.

CASO QUE ORIGINOU: Ana Cláudia Cunha (Goola Açaí) 14/10 — 6 tentativas MB Way recusadas: app mostrava 11,65 e o MB Way pedia 15,29.

3 ERROS ACHADOS E CORRIGIDOS:
1) create_order gravava tokens_applied_value_cents mas não o tirava do valor a cobrar (MB Way/cartão/dinheiro cobravam cheio). Agora: charge = total - carteira - crédito - tokens; dinheiro grava cash_total_due já descontado (sem a dívida antiga, que a app do estafeta soma à parte); corta tokens à metade do saldo; acima do tecto corta em vez de rebentar.
2) Cartão: a app não mandava os tokens no rascunho e quote_order_pricing ignorava-os -> cobrava cheio e a app gastava os tokens. Agora a app manda token_discount_cents e o quote aplica-os (mesma conta do create_order no finalize).
3) quote_order_pricing sem restaurant_id somava taxa de pedido pequeno (1,39) a lojas PARCEIRAS -> ecrã mostrava 16,68 num pedido de 15,29. Agora o servidor acha a loja pelos produtos e a app manda restaurant_id/vendor_name; cálculo local também isenta parceiras.
TVDE: tvde_request_ride corta à metade do saldo e conta só os tokens que deram desconto.

ONDE: migration supabase/migrations/20261014221500_tokens_metade_do_saldo.sql (aplicada por MCP); commits 9edb164 (app) e c4a55f1 (painel) na branch autonomous-night-2026-04-29; publicado web + Play + iPhone.
FICA A SABER: apps antigas (antes da atualização) ainda podem mostrar o desconto antigo e gastar tokens a mais; no cartão a app antiga cobra cheio. Pedidos antigos com tokens não descontados (possível reembolso, precisa do vai do Danilo): Divan 03/10 5,51; Leticia Cosmo 24/09 5,02; Rosa Costa 11/09 5,24; Cristina Batista 14/09 2,80.
