---
id: memoria-claude-ai-digest-2026-11-11-editar-perfil
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-11
zona: verde
confianca: alta
estado: atual
---

# Digest 11/11 — Editar perfil do cliente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-11-editar-perfil`, origem `claude-code`, atualizada em 2026-11-11T18:18:49.170777+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 11 editar perfil · memoria claude.ai · claude_ai_memoria

A missão editar-perfil-2026-11-11 (ordem do Danilo às 16:54 e 17:00) nasceu de uma cliente a quem o robô mandou para "Perfil → Editar perfil", que não existia. O texto do robô já está corrigido em produção: GENERAL_FAQ passou à versão 2 com a navegação real da app (menu Início, Entrega, Reservas, Perfil; Histórico de pedidos, Saldo Bora, Meus Cartões, As minhas moradas, Dados de faturação, Suporte) e, para nome ou telemóvel, diz que ainda não há botão e abre o ACCOUNT_UPDATE; DRIVER_FAQ passou à versão 2 sem o "Histórico de entregas" inventado; um chunk do RAG deixou de dizer "Os meus pedidos". Os três têm backup bkp_*_20261111. O botão Editar perfil, o ecrã, a sincronização do nome e o histórico no painel estão feitos e testados no ramo ai/2026-11-11-editar-perfil (PR #12), mas NÃO publicados: a bora-tranca recusou aplicar as duas migrações (e até a prova em rollback) com "publica o Claude.ai". O SQL foi provado no PGlite com 25 cenários verdes. A entrega, com a ordem (migração 1, migração 2, só depois juntar o ramo) e os md5, está na página entrega-editar-perfil-2026-11-11. Armadilha nova e importante: a app do cliente lê o nome do metadata do login (bora_name/bora_phone), não de public.users; mudanças feitas à mão só em users não chegam ao telemóvel — foi o que aconteceu hoje à mudança manual. O núcleo novo grava nos dois sítios e a app passa a sincronizar ao abrir. Reportado sem corrigir: o painel web não tem lista de emails (só o papel admin), nilofulfaro@gmail.com é admin no banco mas não na app; o Fuku tem 12h-23h seguido; "Hambúrguer do mês" é o default em 31 lojas e no Fuku não aparece; a Caixa Mix 36 aparece a 24,73 € na web (captura), Android/iOS sem captura. Fica por fazer: aplicar, publicar nas 3, provar com conta de teste e o Bloco 4 do robô. Relatório em .claude/.ai/reports/editar-perfil-2026-11-11.md.
