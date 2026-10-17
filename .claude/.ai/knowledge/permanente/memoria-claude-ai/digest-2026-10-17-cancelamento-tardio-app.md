---
id: memoria-claude-ai-digest-2026-10-17-cancelamento-tardio-app
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-17
zona: verde
confianca: alta
estado: atual
---

# Claude Code 17/10 — cancelamento tardio TVDE na app, no motorista e no painel (publicado nas 3)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-17-cancelamento-tardio-app`, origem `claude-code`, atualizada em 2026-10-17T18:33:43.625957+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 17 cancelamento tardio app · memoria claude.ai · claude_ai_memoria

O cancelamento tardio da corrida (regra do Danilo de 17/10: o cliente cancela mais de 3 minutos depois de o motorista aceitar, paga a corrida inteira e o motorista recebe 3,75 €) já está nas apps e no painel, publicado nas três plataformas. O cliente, ao carregar em cancelar, vê o valor que o servidor vai mesmo cobrar: cancelamento grátis com contador desde o motorista aceitar, custo da corrida inteira com a forma de cobrança (pagamento retido ou carteira), taxa fixa nas corridas de plano, pacote, marcadas ou balcão, ou sem custo. Se a ligação falhar, aparece um aviso sem números. Ao confirmar, a app pergunta outra vez ao servidor e, se o valor subiu, mostra-o antes de cancelar: nunca se cobra mais do que o cliente viu. Depois de cancelar diz o que foi cobrado, e o histórico mostra a taxa ou "Sem custo". O motorista recebe a notificação "Corrida cancelada · recebes 3,75 €" (antes não aparecia), tocar abre o sino, e o ecrã da corrida mostra o aviso. No painel, Cancelamentos de corridas tem o resumo das compensações, o que foi cobrado a cada cliente, o acerto da semana, o botão Compensar motorista e o CSV; a lista de corridas desconta a compensação à Bora; a compensação edita-se nas Definições com motivo. Publicado: web corrida 222 (commit b05c56c9), Android versionCode 676 (internal, alpha, produção), iPhone build 194, versão 1.0.21 à espera da Apple com lançamento automático. Testes 1336 -> 1389, todos verdes. Uma revisão independente apanhou um erro grave antes de publicar (cancelar sem saber o valor quando a ligação falhava) e foi corrigido. Falta: prova visual do painel com sessão de admin; decidir os achados do servidor (no-show não entra no acerto do motorista, dívida da carteira não aplicada no TVDE, motorista recebe dois avisos, descrições antigas nas definições). Relatório: .claude/.ai/reports/cancelamento-tardio-2026-10-17.md.
