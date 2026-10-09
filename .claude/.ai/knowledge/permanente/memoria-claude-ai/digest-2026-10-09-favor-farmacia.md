---
id: memoria-claude-ai-digest-2026-10-09-favor-farmacia
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-09
zona: verde
confianca: alta
estado: atual
---

# Claude Code 08-09/10 — Favor da farmácia: passos do estafeta, valor único, receita por foto, botões do Android

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-09-favor-farmacia`, origem `claude-code`, atualizada em 2026-10-09T04:41:16.177169+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 09 favor farmacia · memoria claude.ai · claude_ai_memoria

O que funciona agora (pedido real 74dd4ecc, Cristina). Estafeta: o Favor aparece em passos (casa da cliente se pedida, local do favor, entrega) com nome do sítio, morada, distância e Navegar do passo atual; mapa com pontos 1/2/3; a oferta mostra a rota toda; nunca mostra o pickup_address herdado. O passo vive em orders.errand_passo (0 casa, 1 favor, 2 entrega), escrito pelo gatilho trg_orders_errand_passo a cada mudança de estado; errand_leg é legado. A folha trancada do favor abre pela FolhaFavor (lib/widgets/folha_favor.dart): pedido vivo, arranca no passo gravado, folga para a barra do Android; o patch para dentro está em .claude/.ai/missoes/favor-08-10/pronto/ à espera do vai. Uma só conta para cobrar/devolver na entrega (contaDaEntregaFavor + totalToCollectCash). Fotos: BoraFotoEcraInteiro (fundo preto, inteira, zoom 5x) ao tocar em qualquer foto privada e nos ecrãs que tinham visualizador próprio. Cliente: a morada da paragem em casa grava-se outra vez em dinheiro/MB Way/saldo (a sessão era limpa antes); ajuda da receita por foto, aviso sem foto, linha do passar em casa com valores de platform_settings. ~25 ecrãs com BoraBottomActionBar.folgaInferior. Admin: passos, fotos receita/talão, estimado×talão×total, editar parada, mudar passo (admin_favor_mudar_passo recusa saltos que prendem o estafeta). Provas: transação desfeita 12,00 → talão 1,88 → 9,88 em todos os campos; 14 capturas Android 15 (3 botões e gestos); 41 testes; commits 0f601a23 e 1c819378; Android versionCode 659 publicado; web 203 com 1c819378 nos dois domínios; iPhone build 176 em curso. Falta: patch da folha trancada (vai do Danilo); cópia de finalize_errand_purchase no repo (tranca recusou); gatilho demo atribui a drivers.id …0002 em vez de …0001 (estafeta demo não vê pedidos demo). Relatório: .claude/.ai/reports/favor-farmacia-2026-10-08.md.
