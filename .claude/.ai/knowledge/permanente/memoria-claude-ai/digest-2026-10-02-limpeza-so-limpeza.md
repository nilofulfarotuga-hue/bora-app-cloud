---
id: memoria-claude-ai-digest-2026-10-02-limpeza-so-limpeza
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-02
zona: verde
confianca: alta
estado: atual
---

# Claude Code OPUS 02/10 — limpeza só limpeza: portão por papel + incidente da API

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-02-limpeza-so-limpeza`, origem `claude-code`, atualizada em 2026-10-02T15:06:03.672812+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 02 limpeza so limpeza · memoria claude.ai · claude_ai_memoria

Missão limpeza-so-limpeza-2026-10-02 (Claude Code, PC do Danilo). O QUE FUNCIONA AGORA: a entrada de quem trabalha no Bora é por papel — entra quem tiver qualquer papel aprovado (drivers, cleaners ou washers); um papel pendente não bloqueia outro aprovado. Widget PortaoDoPrestador + função pura entradaDoPrestador (roles_service.dart), ligados no _RootNavigator, no login do prestador e na troca de perfil. A ficha de estafeta só nasce da candidatura (driver_register_or_update): foi removido o DriverStore._upsertDriverRow, que criava linha em drivers a quem abrisse o ecrã do estafeta. A porta Sou Estafeta > Criar conta abre a escolha de actividade (TrabalharNoBoraScreen). O aparelho fica registado para a limpeza logo na candidatura e o PushTokenService já não deita fora registos concorrentes. Painel admin Papéis, aba Pessoas: estado por papel com Aprovar/Recusar nas pendentes; admin_approve_driver passa a ir com p_force=false (só com o id dava 42725 not unique). Commits 2ff0a0e0 e 0338e887, publicados na WEB (bundle 10697624 bytes). O servidor não precisou de mudar: a limpeza nunca exigiu drivers. PROVADO na web publicada com contas de prova: limpeza aprovada + estafeta pendente entra no painel da limpeza; conta só de limpeza fica com 0 linhas em drivers; oferta de teste a dinheiro com tem_aparelho=true e notify-cleaner enviados 1. 840 testes verdes, juiz limpo. POR FAZER: o build Android NÃO foi para o Play — o autoteste falhou duas vezes por causa da base (loja sem produtos; login com 504), não do código; repetir o job do run 37014873730. Painel admin não foi visto no ecrã. Quem tem limpeza pendente e entra pela porta do estafeta ainda vê textos de estafeta. A ficha de estafeta da Mayra (9a8a5657) foi aprovada à mão e deve ser recusada no painel só depois de ela ter a app nova. Lavagem tem o mesmo buraco do push na candidatura. INCIDENTE: a API caiu das 14:05 às 15:03 UTC (504/522). Causa nos registos: a app Android pede products de todas as lojas ao arrancar (restaurant_id=in.(...)), com timeouts desde as 12:04 UTC; recuperou sem reinício do Postgres. Vai repetir-se: é preciso missão urgente para a app deixar de ler o catálogo inteiro. Deadlocks em drivers/driver_locations são crónicos (20-50 por hora). Contas de prova neutralizadas, não apagadas: 746b98a0 (limpeza suspended, estafeta rejected) e 5a5d2b38 (limpeza rejected). Não usar demo@bora.app em provas manuais enquanto o autoteste do CI corre. Relatório: .claude/.ai/reports/OPUS-limpeza-so-limpeza-2026-10-02.md; provas em .claude/.ai/provas/limpeza-so-limpeza-2026-10-02/.
