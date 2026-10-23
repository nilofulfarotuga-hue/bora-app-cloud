---
id: memoria-claude-ai-livro-areas-painel-admin
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Painel admin do Bora — o que o Danilo diz que está confuso, as armadilhas provadas (contadores em UTC, pedidos de demo nas contas, ecrãs de dinheiro duplicados) e o prompt de 14/09 que manda refazer dashboard e menu

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-painel-admin`, origem `claude-ai`, atualizada em 2026-10-23T05:41:51.734424+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas painel admin · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/painel-admin.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: painel-admin
description: Painel admin do Bora — o que o Danilo diz que está confuso, as armadilhas provadas (contadores em UTC, pedidos de demo nas contas, ecrãs de dinheiro duplicados) e o prompt de 14/09 que manda refazer dashboard e menu
sources: [chat]
aliases: [painel administrativo, dashboard admin, menu do painel, cartões de cima, acertos duplicados]
---

- [stated] 14/09: o painel admin está "muito confuso" — tem ecrãs que ele não vai usar, coisas desarrumadas, e os cartões de cima não mostram o que devia. Quer entregas, motorista (TVDE) e serviços SEPARADOS, nunca somados num número só.
- [stated] Sobre a marcação do barbeiro: o barbeiro disse-lhe que fez o corte e ele achou que "só se esqueceu de dar como pronto" — tinha razão.

Armadilhas provadas por MCP a 14/09 (não repetir a investigação)
- "Pedidos hoje 1" era um pedido de DEMO (`36e6812a`, Estafeta Demo, 32,41 € em dinheiro, 13/09 20:49). A semana 07-13/09 real foram 4 entregas feitas (2 Valdemir, 2 ele) e 6 canceladas. O mesmo pedido falso entrou no acerto semanal como pessoa.
- Os contadores de cima contam em UTC: entre a meia-noite e a 1h de Lisboa o painel mostra o dia anterior e a semana aparece a zero.
- "A pagar — drivers" do dashboard não bate com a soma das linhas de `driver_weekly_settlements` da mesma semana.
- Ecrãs de dinheiro duplicados e espalhados: Pagamentos, Acerto semanal por pessoa, Acertos da semana, Fechamento Semanal — Estafetas, Repasses a Parceiros, Acerto reservas parceiros, Fechamento Semanal — Barbearias, Pagamentos Connect. A rota `/admin/acertos-semana` continua não registada em main.dart.
- Falta automática das marcações: `_appointment_cron_auto_no_show()` (job 42, a cada 15 min) marcava falta a qualquer marcação ainda "confirmada" 30 min depois da hora e RETINHA o dinheiro na Bora. Foi o que tirou 12 € ao barbeiro da [[ouro-e-prata]] (marcação `d6772a72`, cliente pagou o preço todo por cartão). Corrigido por MCP: marcação passada a `completed`, barbeiro com 11,50 € na semana (12 € menos 0,50 € de `appointment_booking_fee_cents`), e `appointment_no_show_grace_minutes` subiu de 30 para 180.

- PROMPT REGISTADO: `PROMPT_painel_admin_limpo_2026-09-14.md`, motor OPUS, porta Claude Code, SESSÃO NOVA `painel-admin-limpo` na pasta bora-app-cloud. 8 blocos: (0) levantamento do dashboard/menu/rotas; (1) cartões de cima refeitos — hora de Lisboa, zero demo, verticais separadas, dinheiro que bate com os acertos, alertas com um toque; (2) menu por secções, UM hub "Dinheiro e acertos" em vez dos sete ecrãs, registar a rota, arquivar (não apagar) o que não usa, busca e favoritos; (3) demo fora de acertos, digest e KPIs + `admin_show_demo_data` a false; (4) falta automática nunca retém dinheiro sozinha — pergunta ao parceiro, estado "por confirmar", botão de reverter num toque; (5) autoridade total no painel; (6) provas no emulador + SQL; (7) skill `painel-admin-limpo`; (8) fecho com `/ctx doctor` e `/ctx stats`. Estado: ENTREGUE 14/09, por correr.

