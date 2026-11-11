---
id: memoria-claude-ai-digest-2026-11-11-farmacias
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Digest 11/11 — farmácias da Sé e Teixeira (receita, lojas escondidas)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-11-farmacias`, origem `claude-code`, atualizada em 2026-11-11T18:34:59.717129+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 11 farmacias · memoria claude.ai · claude_ai_memoria

Missão farmacias-2026-11-11 (PC, Claude Code Opus 5.5, worktree C:\BoraLocal\wt-farmacias-2026-11-11, ramo ai/2026-11-11-farmacias, pedido de revisão #11 juntado em 8f3c9f2d). Lojas farmacia-se-guarda e farmacia-teixeira-guarda criadas (pharmacy, parceiras, billing client como a Boom, entrega grátis acima de 30 €), donas: contas de demonstração demo.farmacia.se@bora.app e demo.farmacia.teixeira@bora.app (palavras-passe só no Ambiente de Trabalho do Danilo). Dados públicos reais (morada, telefone, horário, coordenadas, logótipo do Facebook, capa da Glovo sem selo); email real não gravado de propósito (o resumo mensal escreveria à farmácia). Na Glovo as duas são da GRIPHARMA S.A. Catálogo da Glovo: Sé 867 e Teixeira 511 produtos com foto no nosso Storage (9 sem foto na própria Glovo ficaram de fora), 16/15 secções de farmácia, preço = Glovo (preco_provisorio), partner_shelf_price = price*0,90/1,05. Servidor (aplicado pela Claude.ai: 01-04 e 06): lista de permissão por loja (restaurants.so_lista_permissao + loja_lista_permissao + lojas_escondidas_para_mim + RLS restrictive + filtro nas funções dos clientes, Amigo e redes); modo demonstração (só pedidos de teste em dinheiro, despacho só ao estafeta demo, cartão/MB Way recusados); pedidos_prescricao com bucket privado prescricoes, RPCs prescricao_*, vigia 15/30 min, limpeza 30 dias, lembrete mensal que só avisa, admin Farmácias e Pedidos de receita. A 05 (comissão extra 10 % no fecho semanal depois de abertura + 3 meses) está em docs/propostas, não aplicada. Provas: PGlite 65/65; API pública — anónimo e cliente comum veem 0 lojas/produtos/pesquisa/redes, a conta boraappbora vê as 2 lojas e 1378 produtos; preços pelo quote_order_pricing iguais ao modelo da Boom (A 9,95 €, B >30 € com entrega 0); receita em transação desfeita (aceita 23,50 → total 29,50, demonstração, push na fila do notify-partner). Web publicada com a app nova. Falta: provar ecrãs com sessão (o PC não pode escrever palavras-passe em produção), ligar o pedido real de receita numa loja aberta (RECEITA_REAL_POR_LIGAR), o painel do parceiro mostrar pedidos de loja (order_store.dart trancado), traduções EN dos ecrãs novos. Armadilhas: o gancho do context-mode faz o classificador recusar os agentes; a trava recusa migrações (vão pela Claude.ai); cliente_pesquisar não filtrava aprovação nos produtos — nunca carregar produtos de loja escondida antes do filtro.
