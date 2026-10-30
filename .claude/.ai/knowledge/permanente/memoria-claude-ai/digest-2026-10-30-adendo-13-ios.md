---
id: memoria-claude-ai-digest-2026-10-30-adendo-13-ios
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Missão publica 30/10 — adendo 13: iPhone relançado, cérebro do WhatsApp alinhado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-30-adendo-13-ios`, origem `claude-code`, atualizada em 2026-10-30T13:59:52.198849+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 30 adendo 13 ios · memoria claude.ai · claude_ai_memoria

O iPhone da 5.ª publicação falhou no teste de guarda das promoções (test/promocoes_logica_test.dart), que ainda exigia a troca de preço só na proposta; depois da migração autorizada 20261030063000 o teste passou a exigir a troca só nessa migração, com a frase do Danilo e o backup (commit a4553416, Juiz limpo contra 230a9bba~1, +62 casos). A 6.ª publicação (merge 43a015a2) só mexeu em test/, e o build_ios.yml só arranca com lib/, ios/, integration_test/, pubspec.yaml ou o próprio workflow, por isso o iPhone não arrancou. Foi lançado à mão por workflow_dispatch (corrida 41020771645, enviar=true, submeter_revisao=true): job A success 08:55, job B success 09:18, IPA 1.0.32 build 219 VALID no App Store Connect. A 1.0.31 (publicação 4) está WAITING_FOR_REVIEW com AFTER_APPROVAL, por isso o ios_publicar.py deixou a 219 no TestFlight sem tocar na submissão. ATENÇÃO: depois de a Apple aprovar a 1.0.31, a 219 (com o agendar nos mercados) só vai a revisão num push novo com lib/ ou relançando o build-ios à mão; o .claude/scripts/relancar_ios.py não o detecta porque o último build acabou em success. Para o caso só-test/ não voltar: a tranca recusou pôr test/** nos paths do workflow (zona vermelha .github/workflows), por isso ficou o relancar_ios.py (relança se o último build-ios falhou ou há lib/ios/test/pubspec novos desde ele) e a regra na skill protocolo-missao-bora §9; a linha no workflow fica para a Claude.ai pelo GitHub. Android e web da publicação 6 verdes (versionCode 701). Cérebro do WhatsApp da loja: repo = VPS = PC (374275d3); o servidor_cerebro.py do PC tem o aquecedor atrás de CEREBRO_AQUECEDOR. Memória do whatsapp-cerebro: os 388 MB eram o pico de vida do processo antigo; o novo está em 15 MB estável em duas medições de 10 min; MemoryHigh 500M e MemoryMax 800M, registo em /var/log/whatsapp-cerebro-mem.log por cron de 10 em 10 min (/usr/local/bin/cerebro-mem.sh). Fotos da Boom reconfirmadas por SELECT. O último push (só relatório e CONTINUAR, commit 821968d3 [skip ci]) foi recusado pela pergunta Permitir/Recusar da tranca e não foi contornado: fica no ramo missao-geral-2026-10-28 (e2e 5444, TRANCAS.md). e2e do fluxo publica-2026-10-29: 5400, 5401, 5406, 5407, 5409, 5430, 5444.
