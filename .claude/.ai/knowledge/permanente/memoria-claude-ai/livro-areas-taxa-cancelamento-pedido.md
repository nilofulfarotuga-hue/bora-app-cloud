---
id: memoria-claude-ai-livro-areas-taxa-cancelamento-pedido
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regras do Danilo para cancelamento de pedidos de entrega do bora-app — taxa de cancelamento, reembolso ao MB Way/cartão e chamada persistente ao estafeta

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-taxa-cancelamento-pedido`, origem `claude-ai`, atualizada em 2026-10-23T05:34:06.23654+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas taxa cancelamento pedido · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/taxa-cancelamento-pedido.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: taxa-cancelamento-pedido
description: Regras do Danilo para cancelamento de pedidos de entrega do bora-app — taxa de cancelamento, reembolso ao MB Way/cartão e chamada persistente ao estafeta
sources: [chat]
aliases: [taxa de cancelamento, cancel_fee, cancelamento de pedido]
---

- [stated] Regra pra taxa de cancelamento em pedidos de entrega do [[bora-app]]: só cobra a taxa se tiver estafeta atribuído ao pedido no momento exato em que o cliente cancela. Se o cliente pediu, um estafeta aceitou e depois soltou (sem estafeta atribuído no momento do cancelamento), o cliente não paga a taxa.
- [stated] Regra (07/10, "tem que ser assim sempre"): pedido pago por MB Way/cartão que o sistema cancela (ex.: nenhum estafeta aceitou) devolve o dinheiro COMPLETO, automaticamente, ao MB Way/cartão do cliente — igual ao TVDE — nunca para a carteira
- [stated] Regra (10/10, todas as categorias, incluindo Favores): pedido cancelado devolve SEMPRE ao cliente pelo meio original. MB Way: devolve logo, automático (já provado que chega na hora). Cartão: se a devolução ao cartão não for imediata, o cliente escolhe entre carteira (já) ou cartão, com aviso bem claro do prazo ("até X dias úteis"). Caso que gerou a regra: Favor do Divan (09/10, 6 € MB Way) foi para a carteira em vez do MB Way
- [stated] A oferta de pedido tem de chamar de forma persistente (tocar em loop) no telemóvel do estafeta, para todos, não só um toque
- [stated] 13/10/2026 20:24 disse "vai" para corrigir: com dívida de cancelamento + pedido em dinheiro, o ecrã do pedido do cliente mostra só o total (24,03 €) e o estafeta vê "RECEBER 26,53 €, inclui dívida anterior". PROMPT: Claude Code no PC (Controlo Remoto), sessão session_01NJ6iS2H39zduoSUMeChcRJ "Dívida anterior no ecrã do pedido", motor Opus 5.5, scope só ecrã (order_details_screen + outros ecrãs do cliente + admin_order_detail_screen), publicar nas 3, run_id e2e divida-anterior-cliente-2026-10-13. Estado: a correr

