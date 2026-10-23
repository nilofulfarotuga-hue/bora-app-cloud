---
id: memoria-claude-ai-livro-areas-tvde-historico
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Histórico detalhado do TVDE já superado/cumprido (builds de jul/2026, categoria por aprovação) — ler só quando for preciso arqueologia; o estado vivo está em tvde-vertical

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-historico`, origem `claude-ai`, atualizada em 2026-10-23T05:43:47.297275+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde historico · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-historico.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-historico
description: Histórico detalhado do TVDE já superado/cumprido (builds de jul/2026, categoria por aprovação) — ler só quando for preciso arqueologia; o estado vivo está em tvde-vertical
sources: [chat]
aliases: [historico TVDE, TVDE julho]
---

Progress 2026-07-20 (backend via Claude.ai MCP + Fase A via Claude Code) — all backend verified in DB
- [stated] tvde_request_ride: the 2 overloads (payment_method vs tokens) were merged into ONE 9-arg function (both params, defaults) — this fixed a PGRST 404 that had blocked ALL ride requests
- [stated] EF tvde-payment v3 deployed: action confirm_ride_payment {ride_id} reads the real Stripe PI status and updates payment_status (will also flip aguarda_pagamento→solicitada)
- [stated] tvde_finish_ride settlement: normal cash unchanged; online/covered(plan)/prepaid(€8-online) credit the driver his earnings via balance (Bora owes = negative). €8-CASH settlement now DONE too — detected via the roundtrip credit having NO payment_intent_id → outbound driver collected the €8 (owes Bora €4); return leg driver gets €3.50 from Bora
- [stated] Fase A DONE (Flutter, committed+pushed): card confirms → confirm_ride_payment (3 tries) → only then tracking; MB Way polls; only cancels when the server confirms NOT paid; orange "aguarda pagamento" chip distinct from searching; written TOLERANT to both worlds (works whether the ride is born solicitada or aguarda_pagamento)
- [stated] PENDING: (2) sync repo's tvde-payment/index.ts with the MCP-deployed v3 so a repo deploy can't drop confirm_ride_payment; (4) Claude.ai flips tvde_request_ride to aguarda_pagamento ONLY after the new APK is on devices. DONE: (1) chip PT-PT fixed (client side was already correct; a checkout snackbar was fixed, commit 2d84956) — but 4 other PT-BR "Aguardando..." strings outside the payment flow remain to convert; (3) €8-CASH backend built+verified: RPC tvde_create_roundtrip_credit_cash(uuid) + the finish settlement branch. Fase B (€8 Flutter) now unblocked
- [stated] Cancel reasons: cron uses `payment_timeout`; Flutter decline uses `payment_failed` (so admin can distinguish)
- [stated] Fase B DONE (Flutter, 27/27 TVDE tests after a clean pull --rebase --autostash, analyze clean, anti-cheat clean), PUSHED as commit 43f40e6 — CI building the alpha/closed-track APK that carries €8-cash to the phone: €8-cash option wired to the new RPC; the €8 is the TOTAL (prepaid legs never charge the fare). Claude Code found + fixed a REAL €13 bug in TvdePayBadge — it was showing "Cobrar €5,00" (the fare) ON TOP of the €8 on a prepaid leg (return too). New TvdeRoundtripDriverNotice shows the driver "recebes €4; os €8 do cliente não são teus — recolhes por conta da Bora, acerto no fim da semana" (values from server: driver_earn_cents + tvde_roundtrip_price_cents; shared memo so badge & notice never differ). STILL PENDING: push (triggers prod build) → then Claude.ai flips aguarda_pagamento + adds the activate_roundtrip hook (release €8-online outbound when €8 paid) once APK is on device; plus the admin panel (vale method = payment_intent_id IS NULL, weekly settlement queue €4 debit/€3.50 credit, alert for cash outbound without vale)

Categoria TVDE ("categoria do motorista") — acesso por pessoa (2026-07-21, Claude.ai via MCP) — SUPERADO pelo gate removido a 01/08
- [stated] DECISÃO Danilo: abrir a categoria TVDE a TODOS os clientes "por enquanto". Plano dele: aberta agora → mais tarde pede pra FECHAR (voltar) → mais tarde ainda pede pra voltar ao modo COM APROVAÇÃO. Quer que a Claude.ai faça direto por MCP, sem prompt.
- [stated] Mecanismo REAL (confirmado no DB): gate por pessoa na coluna users.tvde_access (bool, era default false). Cliente pede via RPC tvde_request_access → notifica admin ("Novo motorista TVDE a aguardar aprovação", link /admin/tvde/access-requests) → grava em tvde_access_requests (status pendente/aprovado/recusado) → admin decide via admin_set_tvde_access(client_id,'aprovar'|'recusar'|'revogar') que seta users.tvde_access. tvde_request_ride TAMBÉM checa tvde_access (não é só UI).
- [stated] FEITO (migration tvde_open_category_to_all_clients_temp_2026_07_21): users.tvde_access default → true + UPDATE deixou os 19 clientes com true. Cobre existentes E quem baixar novo. Funciona com o app atual (já lê tvde_access), sem tocar Flutter.
- [stated] RECEITA DE REVERT (quando pedir pra fechar): ALTER users.tvde_access SET DEFAULT false; depois UPDATE users SET tvde_access=false WHERE id NOT IN (SELECT client_id FROM tvde_access_requests WHERE status='aprovado'). Restaura só quem foi genuinamente aprovado (eram 2) e volta ao modo com-aprovação.
- [stated] Tentativa anterior ERRADA: criei platform_settings tvde_enabled=true achando ser o interruptor — ninguém lê essa chave, era inerte; JÁ APAGUEI. Interruptor real = users.tvde_access.
- [stated] PENDENTE (regra painel admin): o painel /admin/tvde/access-requests já existe (aprovar/recusar/revogar por pessoa). Falta um controlo "abrir/fechar pra todos" no painel pra o Danilo virar o modo sozinho. Ele disse pra NÃO montar agora.

Categoria TVDE volta a ser "por descobrir" (30/09) — SUPERA o gate removido a 01/08
- [stated] DECISÃO Danilo 30/09: esconder de novo a categoria TVDE, como no início — o cliente vê as outras categorias e um cartão "Descobre uma categoria nova"; carrega, põe nome/dados e pede; o Danilo aprova/libera no painel
- [stated] REGRA: quem JÁ tem cadastro/app fica COM a categoria (não tirar a ninguém); só os NOVOS cadastros nascem sem ela e têm de descobrir/pedir

Caso Beatriz (06/10) — a regra de 30/09 estava só meio feita
- [stated] Danilo 06/10: a Beatriz (cadastro 06/10) conseguiu pedir corrida direto; não era para ver o Bora Motorista — só as funções de delivery; o Motorista só aparece depois de ela pedir "descobrir uma nova categoria" e ele autorizar. Mandou deixar a Beatriz com acesso e fechar para os próximos
- CAUSA achada: a 30/09 só se mudou o banco (default tvde_access=false + trigger handle_new_auth_user a pôr false); o app continuava com o ladrilho para todos (código de 01/08) e tvde_request_ride não verificava nada. Ela fez 1 corrida MB Way finalizada (52f4633a). Outros 7 cadastros novos desde 30/09 estão sem acesso (certo)
- FEITO por MCP: Beatriz tvde_access=true; migration tvde_porta_fechada_no_servidor_so_com_acesso_2026_10_06 — função _tvde_exige_acesso (admin passa) injetada nas 4 portas (tvde_request_ride, tvde_schedule_ride, tvde_schedule_roundtrip, tvde_request_plan) → erro no_tvde_access. Provado com JWT simulado: conta nova recusada nas 3, Beatriz passa
- App (branch tvde-categoria-por-descobrir-2026-10-06, PR #4 para verificação): ladrilho "Bora Motorista" só com acesso; sem acesso aparece "Nova categoria" → TvdeEntradaScreen pede nome+telefone → tvde_request_access → painel "Pedidos de acesso TVDE" (já existia) aprova. Pesquisa e faixas passam pela mesma porta

