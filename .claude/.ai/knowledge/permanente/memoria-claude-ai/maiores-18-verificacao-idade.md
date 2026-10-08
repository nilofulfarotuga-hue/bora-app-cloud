---
id: memoria-claude-ai-maiores-18-verificacao-idade
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-07
zona: verde
confianca: alta
estado: atual
---

# Maiores de 18 — tabaco e álcool com verificação de idade na entrega (aplicado 07/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `maiores-18-verificacao-idade`, origem `claude-code`, atualizada em 2026-10-07T23:15:09.64172+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: maiores 18 verificacao idade · memoria claude.ai · claude_ai_memoria

Migração 20261007180000_maiores_18_verificacao_idade.sql aplicada em produção a 07/10/2026 (13 s, via aplicar-gaveta). products.age_restricted marcado pelo classificador produto_e_maior_18; orders.has_age_restricted posto ao nascer por gatilho aditivo; tabela order_age_checks (confirmado/recusado, uma por pedido); driver_confirm_age_check(order_id, ok) é o passo do estafeta (recusa abre cancellation_request pelo caminho existente, sem regra de dinheiro nova); guarda: sem verificação confirmada não há 'delivered'; admin_set_product_age_restricted, admin_set_age_restricted_by_category, admin_list_products_maior_18, admin_maior_18_por_categoria; texto_pede_maior_18 para os Favores. Flutter (commit 6a561727): etiqueta +18 nos cartões, aviso no carrinho/pagamento/Favores, folha obrigatória do estafeta antes da foto e do PIN, painel /admin/maiores-18, selo no detalhe do pedido admin. O Bora Assistente avisa +18 e manda tabaco para Favores.
