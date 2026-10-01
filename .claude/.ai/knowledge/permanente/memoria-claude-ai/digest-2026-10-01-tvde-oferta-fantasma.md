---
id: memoria-claude-ai-digest-2026-10-01-tvde-oferta-fantasma
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-01
zona: verde
confianca: alta
estado: atual
---

# Claude Code 01/10 — oferta fantasma do TVDE corrigida e publicada (versão 636)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-01-tvde-oferta-fantasma`, origem `claude-code`, atualizada em 2026-10-01T12:57:09.987001+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 01 tvde oferta fantasma · memoria claude.ai · claude_ai_memoria

O que funciona agora: o ecrã "Nova corrida" do motorista TVDE já não fica preso por baixo do ecrã da corrida nem reaparece depois de finalizar (corrida real 03874579 de 01/10). O ecrã da oferta fecha a sua própria rota (pop se está em cima, removeRoute se ficou por baixo) e sai sozinho quando a corrida passa a ser dele; a home não abre a corrida por cima da oferta e volta a decidir a navegação quando a oferta fecha. Aceitar e recusar cancelam sempre a notificação pelo id da corrida e marcam a oferta como respondida (registo em notification_service.dart, gravado em SharedPreferences para o isolate de segundo plano); o aviso pergunta pela marca antes e depois de aparecer. A marca vale 25 s (menos do que a pausa de 35 s do servidor) ou, depois disso, só para o mesmo prazo — uma corrida recusada pode voltar a ser oferecida numa roda nova. O loadCurrent do TvdeDriverStore ficou sequenciado: só a leitura mais recente escreve e, se o estado mudou a meio, lê outra vez; uma corrida que já é dele nunca entra como oferta. O cartão sobreposto ignora oferta que é a corrida activa, que já não está em solicitada ou que é para outro, e conta 25 s locais quando não há prazo. A sobreposição de 20/09 (oferta nova durante corrida activa) continua a funcionar e tem teste. Nada de servidor, despacho, preços ou ganhos foi tocado. Como se usa: nada muda para o motorista; basta actualizar para a versão 636 (CI run 481 verde, faixa alpha da Play) ou usar a web, que já leva a correcção. Provas: 19 testes novos, suite 870 verdes, analyze 0 erros, anti-trapaça limpo, verificador independente (apanhou uma regressão na janela da marca, corrigida antes do push). Commits 7df0fc49 e 753a2131; relatório em .claude/.ai/reports/tvde-oferta-fantasma-2026-10-01.md. O que falta: a prova ao vivo no emulador não se fez por falta de RAM no PC (o modelo do Ollama usado pela VPS pelo túnel recarrega sozinho); ordem de continuação em .claude/.ai/inbox/CONTINUAR-tvde-oferta-fantasma-2026-10-01.md, a correr só com 2,5 GB livres e sem motoristas reais ligados, pela RPC do cliente com vigia (nunca INSERT directo). Erros antigos vistos e não corrigidos: setState durante o build quando o ecrã da oferta abre com o cartão global montado; o ecrã da oferta aceita a corrida com que abriu mesmo que a oferta em memória mude; a releitura de 10 em 10 s pode pôr a corrida activa a vazio depois de terminar.
