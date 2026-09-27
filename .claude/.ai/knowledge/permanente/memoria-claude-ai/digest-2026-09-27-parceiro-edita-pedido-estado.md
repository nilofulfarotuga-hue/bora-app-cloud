---
id: memoria-claude-ai-digest-2026-09-27-parceiro-edita-pedido-estado
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-27
zona: verde
confianca: alta
estado: atual
---

# Parceiro edita pedido: esta LIGADO desde 22/09 (o digest de 22/09 ficou velho)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-27-parceiro-edita-pedido-estado`, origem `claude-code`, atualizada em 2026-09-27T18:17:36.209667+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 27 parceiro edita pedido estado · memoria claude.ai · claude_ai_memoria

Estado confirmado por SELECT a 27/09 na missao redondo-total. A funcionalidade de o parceiro acrescentar ou marcar em falta um produto num pedido ja feito esta no ar e LIGADA desde 22/09 21:56 UTC (platform_settings.order_edit_enabled = true, com linha em admin_audit_log). As tres migrations estao aplicadas: base 20260922194153, dinheiro 20260922205206 (aplicada com o vai do Danilo) e aviso ao estafeta 20260922205604. A funcao de borda order-edit-settle esta no ar (v1, com JWT). Produto em falta sai dos itens e do total do pedido, e o recibo do cliente le esses itens e esse total. O painel admin tem a lista, filtro, CSV, cancelar, aprovar e forcar estorno. Uso real ate hoje: zero (so as 2 edicoes da prova no pedido de teste ec0506ef, em dinheiro), porque desde que ligou so entraram pedidos de lojas nao-parceiras. Ainda sem prova ao vivo: o caminho do cartao e do MB Way (reembolso parcial e cobranca da diferenca), porque a Stripe e real e as provas fazem-se em dinheiro. Para desligar: order_edit_enabled = false, a app respeita em ate 2 minutos. O digest digest-2026-09-22-parceiro-edita-pedido, que diz interruptor desligado, dinheiro por aplicar e push 403, esta SUPERADO por este.
