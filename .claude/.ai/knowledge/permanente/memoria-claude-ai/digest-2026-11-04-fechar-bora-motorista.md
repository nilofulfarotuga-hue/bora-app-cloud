---
id: memoria-claude-ai-digest-2026-11-04-fechar-bora-motorista
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-04
zona: verde
confianca: alta
estado: atual
---

# Claude Code 04/11 — Bora Motorista fechado nas apps, no painel e no site

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-04-fechar-bora-motorista`, origem `claude-code`, atualizada em 2026-11-04T06:42:45.541238+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 04 fechar bora motorista · memoria claude.ai · claude_ai_memoria

O Bora Motorista (TVDE de passageiros) fechou a 04/11/2026 (sem licença do IMT). O servidor já tinha sido fechado pela Claude.ai às 04:50 (tvde_access=false, backup bkp_users_tvde_access_20261104). Esta missão fechou as apps com UM interruptor: platform_settings.tvde_app_visivel, lido por lib/services/tvde_visibilidade.dart (começa fechado; falha de rede nunca abre; relê ao arrancar e ao voltar à app). Fechado, nada se desenha nem abre: ladrilhos Bora Motorista e Nova categoria, pesquisa, ligações motorista/tvde, botão abrir_tvde do assistente, corridas nas Reservas, retoma de corrida, ganchos de push TVDE, cartão de oferta, cadastro Carro-Passageiros, papel Corridas de passageiros, avisos tvde_/ride_ no sininho. Os 4 motoristas carro_passageiros (work_mode everything) entram na home normal de estafeta. Nenhum código apagado: para reabrir, ligar o interruptor no painel (secção "Arquivo — Bora Motorista (fechado)", primeiro ecrã). Com ele fechado, aprovar acesso TVDE e criar corrida de balcão ficam escondidos no painel. Skills de suporte desligadas: TVDE_RESERVATION_CHANGE, DRIVER_RIDE_EARNINGS, DRIVER_CUSTOMER_NO_SHOW (cópia bkp_support_skills_tvde_20261104). Site boraguarda.com: sem viagens/TVDE, /viagens 301 para / (commit bora-site f89945e, deploy da8f53b2; a página /apagar-conta de 02/11 foi junto). App: commit ee71173f enviado ao ramo de produção; 2879 testes verdes; web conferida no ar com Playwright. Dados intactos: tvde_rides=339, nada de dinheiro tocado. Falta: tirar o Bora Motorista das instruções escritas nas Edge Functions client-assistant e support-chatbot; prova em emulador (PC sem RAM, feita na web). Relatório: .claude/.ai/reports/fechar-bora-motorista-2026-11-04.md.
