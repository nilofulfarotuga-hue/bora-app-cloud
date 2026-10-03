---
id: memoria-claude-ai-digest-2026-09-13-janela-4-ux-portao
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-13
zona: verde
confianca: alta
estado: atual
---

# Janela 4 13/09 — ordem UX OpenCode chegou ao Claude Code e parou no portão

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-13-janela-4-ux-portao`, origem `claude-code`, atualizada em 2026-09-13T21:37:06.311011+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 13 janela 4 ux portao · memoria claude.ai · claude_ai_memoria

A ordem ux-opencode-14-09 (MB Way sem deixar o cliente no escuro, botões tapados pela barra de navegação, ETA por fases) foi colada às 22:35 de 13/09 numa janela do Claude Code em vez do OpenCode. O portão escrito na própria ordem não estava cumprido: o remoto autonomous-night-2026-04-29 está em ff596cf9 com o último bump em 603 e app_latest_version_code = 603; o CI #430 da Janela 1 ainda estava a correr o autoteste antes do build. A ordem manda parar e avisar, e foi o que se fez. NADA foi feito: não existe o ramo ux-2026-09-14, não há commit, não há ficheiro de código nem alteração em platform_settings ou no painel. As chaves eta_shopping_minutes_nonpartner_min/max e eta_avg_speed_kmh já existem (30, 45, 28); a chave tvde_mbway_client_wait_seconds ainda NÃO existe. Quem for correr esta ordem parte do zero e não tem nada para reaproveitar. Condições para arrancar: o remoto ter o bump 604 (prova: commit "ci: bump versionCode to 604" ou app_latest_version_code = 604) e o plano OpenCode Go estar pago (14/09) ou o ChatGPT Plus ligado no OpenCode. Razão para não ter sido feito aqui mesmo com o portão a abrir: a regra dos motores diz que o Fable é só para o crítico (dinheiro, dispatch, publicação) e esta ordem é Flutter de telas, trabalho do ChatGPT ou do plano Go; correr aqui custava mais e arriscava dois ramos iguais amanhã. Se o Danilo preferir que seja o Claude Code a fazer este trabalho, é decisão dele e tem de vir escrita na ordem; até lá a janela certa é o OpenCode. Rasto: e2e_log fluxo ux-opencode-14-09, passo b0-portao-604 (aviso); nota em .claude/.ai/reports/UX-2026-09-14-PORTAO.md.
