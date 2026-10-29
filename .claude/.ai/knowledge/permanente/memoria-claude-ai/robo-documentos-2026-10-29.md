---
id: memoria-claude-ai-robo-documentos-2026-10-29
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Robô fiscal de documentos — relatório (adendo 3, 29/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `robo-documentos-2026-10-29`, origem `claude-code`, atualizada em 2026-10-29T15:26:26.810007+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: robo documentos 2026 10 29 · memoria claude.ai · claude_ai_memoria

ROBÔ "FISCAL DE DOCUMENTOS" — relatório curto (missão final-app-2026-10-29, adendo 3). Estado: PRONTO EM SOMBRA. Só falta o "publica" do Danilo para ligar.

O que é: um robô que olha para cada documento que o candidato envia (comprovativo de atividade das Finanças, documento de identificação, carta, foto e documento do veículo, selfie), diz se é o certo e, só quando ligado, recusa o errado e avisa a pessoa do que falta. NUNCA aprova nada: aprova só o Danilo. Selfie: só vê se há um rosto nítido, sem comparação facial.

Já no ar (servidor, sombra): tabelas documentos_verificacoes e documentos_lembretes_enviados (só admin lê; não guardam nome nem NIF, só se batem); definições robo_documentos_* (ativo=false, modo=sombra, confiança 0,85, limite 200/dia, lembretes 1/3/7, corte vazio); Edge verificar-documento v2 (só servidor) e verificar-documento-previa v1 (com sessão, para a verificação na hora); gatilhos em provider_atividade, drivers, cleaners e washers; cron robo-documentos-lembretes às 10h de Lisboa; funções do painel e da app; política de privacidade v4 com a linha da IA. Migrações 20261029144139, 144631, 144737, 145937 e 150322 (todas no repo, com o SQL exato). Chave: GEMINI_API_KEY, a mesma do Bora Assistente (projeto bora-juiz, pago desde 08/10); nunca a de reserva.

Regra que o Danilo deve saber: ativo=false OU modo=sombra = o robô só olha e regista, não fala com ninguém nem muda estados. Só age com ativo=true E modo=ativo. Ao ligar pela 1.ª vez o painel marca robo_documentos_corte=agora: só entra nos lembretes automáticos quem se registar ou enviar depois disso. Candidatos já parados não recebem nada automático; ao "lembrar este" do painel só vai a quem ele escolher.

Primeira volta em sombra (7 pendentes, 16 análises, 0 mensagens, 0 estados mudados): os 3 casos conhecidos deram certo, 3 em 3. Cartão de cidadão no comprovativo -> errado (cartão de cidadão, confiança 1). Comprovativo de reinício com nome e NIF certos -> ok (e o de alteração de atividade também). Folha do Burger King -> errado (outro, confiança 1). Achados novos para o Danilo confirmar a olho no painel: a foto do veículo de um estafeta foi lida como título de residência; o documento do veículo de outro foi lido como carta de condução. Há um estafeta com tudo certo na lista "Prontos para aprovar".

Provas em ROLLBACK (nada ficou gravado): em sombra nada acontece; com robô ligado a recusa do comprovativo passa por admin_provider_atividade_decidir com bora.agente=robo-documentos, avisa app+push e email; "tudo certo" avisa o Danilo (notify_admin_urgent_push + linha em lembretes_danilo, sem repetir) e o estado continua em análise; lembretes: com corte=agora 0 envios, com corte antigo só vão os recentes, 1 por dia, só às 10h; gatilhos disparam só quando o documento muda.

Painel (PT-BR): veredito ao lado de cada documento em entregadores (lista e ficha), aprovações, limpeza, lavagem, serviços e comprovativo; aviso vermelho e botão Aprovar vermelho quando o robô diz errado; ecrã novo "Robô de documentos" (interruptor, modo, confiança, limite, prontos, histórico, desfazer, lembrar este, analisar pendentes). O 400 do admin_review_cleaner (5 em 29/10 entre 11:15 e 12:26 UTC) passa a mensagem clara antes da chamada. Apps (PT-PT): estado por documento com motivo e "Enviar de novo" só daquele; verificação na hora no comprovativo ("Isto parece um cartão de cidadão, não o comprovativo das Finanças. Escolhe outro ficheiro", com "Enviar mesmo assim" que vai como dúvida).

Falta / ressalvas: (1) entrada de menu "Robô de documentos" em admin_menu_registry.dart (ficheiro de outro agente; rota /admin/documentos-robo já existe e há atalho no ecrã do comprovativo); (2) painel e apps só chegam às pessoas com o "publica" (3 plataformas) — só então se prova que cada pedido de aprovar dá 200; (3) tvde_driver_documents e service_providers sem colunas de documentos ficaram de fora (0 linhas / só têm o comprovativo); (4) o gatilho de drivers só foi provado por estrutura (mexer em drivers à mão é proibido); (5) a Google não diz o nível da chave por API: o "pago" vem do livro e do nome do secret. Testes: 14 Deno + 31 Flutter novos, verdes; juiz anti-trapaça limpo; flutter analyze sem erros meus (1 erro de outro agente em receita_do_dia_screen.dart).
