---
id: memoria-claude-ai-decisao-ganho-estafeta-nao-parceiro-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Decisão do Danilo 29/10 17:36: ganho do estafeta em loja não-parceira fica como está (não mexer na fórmula)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `decisao-ganho-estafeta-nao-parceiro-2026-10-29`, origem `claude.ai 29/10 17:40`, atualizada em 2026-10-29T17:37:20.006781+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: decisao ganho estafeta nao parceiro 2026 10 29 · memoria claude.ai · claude_ai_memoria

29/10 (pedido fe453ac1, Pôr do Sol, cliente Divan, 13,65 € em dinheiro, estafeta Valdemir +4,88 €).
A Claude.ai apontou duas diferenças entre a fórmula do sistema e a regra escrita ("não-parceiro: estafeta 3,80 + 0,20/km + 0,80 + 30% do lucro líquido Bora"):
1) Os 0,80 € (driver_surcharge_cents) só são pagos em compras de MERCADO (storeShopping); em restaurante não-parceiro não entram.
2) Os 30% do lucro (pricing_calculate, ramo não-parceiro) são calculados com bora_gross = 15% do subtotal do cliente + entrega + taxa de serviço, SEM a taxa de pedido pequeno nem o saco.
DECISÃO do Danilo 17:36: "a matemática fica desse jeito, do jeito que está, do jeito que paga o Valdemir" — NÃO mexer.
Regra para todos os agentes: não "corrigir" a pricing_calculate para bater com a regra escrita (0,80 nos restaurantes / 30% com outra base) sem ordem nova dele.
Contas do pedido: cliente 13,65; loja 7,00; estafeta 4,88; sobra Bora 1,77 antes de IVA; com IVA 23% sobre os 6,65 que a Bora fatura (1,24) sobra 0,53; tokens ~0,40 (41 cliente + 40 estafeta, 0,5 cêntimo cada).
