---
id: memoria-claude-ai-digest-2026-10-05-fecho-home-dinheiro
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: alta
estado: atual
---

# Claude Code 05/10 noite — fecho da home e da ronda de dinheiro

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-05-fecho-home-dinheiro`, origem `claude-code`, atualizada em 2026-10-05T22:48:40.897541+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 05 fecho home dinheiro · memoria claude.ai · claude_ai_memoria

Missao fecho-home-dinheiro-2026-10-05 (Claude Code, Opus 5.5, PC do Danilo). O que funciona agora: a home nova (faixas clicaveis, mais pedidos, novidades, cozinhas, todas as lojas, lupa) esta nas tres plataformas - Android versionCode 650 e 651 no Play (internal + alpha + producao), web #195 em app.boraguarda.com (main.dart.js 11112632 bytes), iPhone 1.0.11 build 167 submetido a Apple (WAITING_FOR_REVIEW, sai sozinho quando aprovar). A correccao da loja fechada e do "Pedir de novo" com as escolhas do cliente (ronda de dinheiro, commit 311f8371) foi publicada no mesmo envio.
Porque o Android #498/#499 e o iOS #165 cairam: o esqueleto cinzento da home (_RailEsqueleto, 3 cartoes de 140 px numa Row) transbordava 77 px no emulador e 48 px no iPhone. Corrigido para ListView (744fe903) com teste a 320/379/408 px que falha no codigo antigo. O convidado guest@bora.com nao era a causa (senha mudada desde 01/09, igual na #497 que passou). O iOS #166 caiu num teste: o Supabase dos testes ligava o ouvinte de links (app_links) e no macOS o erro caia dentro do teste - corrigido com detectSessionInUri:false nos testes (ac626b95). O workflow do iPhone so arranca com lib/ios/integration_test/pubspec: depois de um conserto so de testes arranca-se a mao (gh workflow run build_ios.yml -f enviar=true).
Provas da home: faixa de Sushi abre os restaurantes de sushi; vistas e cliques gravados em home_banner_eventos; "hamburguer" sem acento da 60 produtos + Burger King/KFC/McDonalds; BEMVINDO = 1000 tokens = 5 EUR e esconde-se a quem ja usou; painel "Faixas da home" cria/desliga/apaga/mostra cliques (provado em transaccao desfeita como admin).
O que falta: tocar ao vivo nas faixas num aparelho (sem emulador no PC e a web pede login); repor a senha de guest@bora.com (acto do Danilo); decidir a hora de Lisboa para aberta/fechada (espera o sim do Danilo); segredos STRIPE_TEST_* no GitHub. A traducao "Como pagaste na app..." estava certa - nada mudado. Relatorio: .claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md; e2e_log fluxo fecho-home-dinheiro-2026-10-05.
