---
id: memoria-claude-ai-digest-2026-10-06-tvde-cartao-preso-apos-aceitar
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-06
zona: verde
confianca: alta
estado: atual
---

# Claude Code 06/10 — cartão "Nova corrida" preso com 0s depois de aceitar: corrigido e publicado nas três (Play 654, Apple 1.0.12, web 198)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-06-tvde-cartao-preso-apos-aceitar`, origem `claude-code`, atualizada em 2026-10-06T20:54:30.81697+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 06 tvde cartao preso apos aceitar · memoria claude.ai · claude_ai_memoria

O que funciona agora: depois de o motorista aceitar uma corrida TVDE, por qualquer caminho (ecrã inteiro, cartão sobreposto ou botão Aceitar da notificação), o cartão "Nova corrida" sai do ecrã e não volta. Caso real: corrida 3835a143 às 18:33 de 06/10, versão 651, volta do pacote do Martim Cruz, aceite pelo botão da notificação com a app em segundo plano; o cartão ficou mais de um minuto a dizer "Nova corrida — agora", "0s". O servidor e o store estavam certos (prova: a releitura de 10 em 10 s da home, que só corre sem oferta no store, correu o minuto todo nos registos). A causa era o desenho: o ecrã "Nova corrida", ao nascer, avisava o cartão global a meio do build; na app publicada o Flutter deixa esse widget de cima congelado para sempre e ele ignorava o store. Em teste isso só aparece como o erro "setState() called during build" (a missão de 01/10 tinha-o visto e anotado). Correcções: o cartão global adia o redesenho para o fim do frame; nunca mostra como oferta a corrida aberta no ecrã da corrida; rede de segurança no cartão (prazo a 0 e "a aceitar" há 4 s: pergunta ao servidor; se é dele fecha em silêncio; aos 16 s fecha em silêncio, nunca "foi para outro" por esse caminho); o realtime tira a oferta e avisa o ecrã quando a corrida deixa de estar à procura ou passa a ser dele; o fecho do cartão só limpa a oferta dele. Como se usa: nada muda para o motorista; actualizar a app. Provas: 17 testes novos (test/tvde_cartao_preso_test.dart), com o comportamento antigo falham 12; suite TVDE 355 verdes; suite completa 1017 verdes e 1 foto do painel com bloqueio de ficheiro do Windows (sozinha passa); analyze 0 erros; anti-trapaça limpo; verificador independente de contexto limpo confirmou a causa no código do Flutter e apanhou 1 erro e 2 riscos, corrigidos antes do push. Publicado: commits b7e529be e 0fc4b0da; Play CI 504 verde, versionCode 654 lido no servidor; Apple CI 171 verde, versão 1.0.12 build 171, upload ok, build VALID, submetida (WAITING_FOR_REVIEW, lançamento automático após aprovação); web CI 198 verde, bora-app-web versao.json = commit 0fc4b0da. Relatório: .claude/.ai/reports/tvde-cartao-preso-2026-10-06.md (commit f24ecdf8). O que falta: aprovação da Apple; prova ao vivo na próxima corrida real (não se fez no emulador porque havia dois motoristas reais ligados). Visto e não corrigido: o cartão de oferta de RESERVA não tem a pergunta ao servidor dos 4 s (com a raiz corrigida já não congela). Nada de servidor, despacho, preços ou ganhos foi tocado.
