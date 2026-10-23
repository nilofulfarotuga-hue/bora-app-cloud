---
id: memoria-claude-ai-livro-areas-tvde-vertical
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Bora App TVDE ride-hailing vertical — dispatch, pricing, UI, payments (parte 1 de 4 — continua em livro-areas-tvde-vertical-parte2, -parte3, -parte4)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-vertical`, origem `claude-ai`, atualizada em 2026-10-23T05:51:23.729253+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde vertical · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-vertical.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-vertical
description: Bora App TVDE ride-hailing vertical — dispatch, pricing, UI, payments
sources: [backfill]
aliases: [TVDE]
---
- [stated] Ride-hailing vertical of Bora App
- [stated] TVDE card/mbway/€8 rides currently DISPATCH BEFORE payment confirms — unlike delivery, which drafts (payment_drafts) → pays → webhook creates the order. This is the bug behind "corrida despachada sem pagar".
- [stated] DECISION (approved 2026-07-20): card/mbway rides will be born in an `aguarda_pagamento` state the dispatch cron IGNORES, flipping to dispatchable only when payment succeeds; declined/timeout = auto-cancel (cron). Reuses `confirm_ride_payment` for the flip.
- [stated] Kill switch `tvde_card_payments_enabled` awaiting real device test
- [stated] Outstanding TVDE UI fixes: autocomplete cortado na parada adicional; notificação A2 silenciosa em foreground

Dispatch & offer mechanics (May–Jun 2026)
- [stated] Dispatch `bora_dispatch_maintenance()` fixed (COALESCE type mismatch had caused 1,526 failures)
- [stated] Offer TTL, driver rotation, `tvde_dispatch_sweep` cron every 15s
- [stated] Permission onboarding gate: notifications mandatory, overlay/battery optional post-online
- [stated] Foreground service architecture: rich persistent notification with FLAG_INSISTENT, BigText card, Accept/Reject buttons
- [stated] CallKit/ConnectyCube permanently removed — never return
- [stated] Overlay (`flutter_overlay_window`) abandoned due to inter-isolate bug; `system_alert_window` noted as next attempt if needed

Pricing & ride rules (Jun–Jul 2026)
- [stated] Map rotation heading-up continuous bearing for both driver and client
- [stated] Parada adicional: €2/stop, max 2, countdown timer
- [stated] Cancellation policy: free ≤3min, 100% after
- [stated] Ida-e-volta vale-volta: €8 package, 6h expiry, no auto-refund
- [stated] Subscription plan Mon–Fri only: €40/€70/€132 for 10/20/44 rides
- [stated] No-show = €3.50 fixed to driver (RPC `tvde_mark_noshow` still needed)
- [stated] `tvde_expire_roundtrip_credits()` cron still needed
- [stated] CollectBadge unified across delivery/TVDE/cleaning
- [stated] `tvde_finish_ride` columns `tokens_applied_count/value_cents` applied via MCP
- [stated] BUG TOKENS FECHADO (2026-07-22, Claude.ai via MCP): o toggle "Usar Bora Tokens" na corrida era decorativo — `tvde_request_ride` recebia `p_tokens_to_apply` mas NUNCA descontava (só logava como `tokens_requested`), cobrava valor cheio. `tvde_finish_ride` JÁ descontava certo (5 cent/token, teto 50%). Migration `tvde_request_ride_apply_token_discount_2026_07_22` aplicada: request_ride agora desconta no pedido com a MESMA fórmula do finish (paridade), evitando a fórmula errada do 10× (×5 cent, não ×0,5). Provado no DB: tarifa €5 → 10 tokens cobra €4,50; 100 tokens cobra €2,50 (teto 50% segura); 0 tokens cobra €5. NOTA: os 2 .sql que o Claude Code tinha escrito (merge_tokens_payment + reaplica_tokens_dinheiro) NÃO foram aplicados — correção feita direto por MCP; ficheiros locais podem ser descartados.
- [stated] `id` vs `user_id` identity bugs resolved across full TVDE stack

Ida-e-volta €8 — economics (clarified by Danilo 2026-07-20)
- [stated] €8 = client's TOTAL price for the guaranteed round trip (both legs), payable cash OR card/mbway (cash path currently missing — to add)
- [stated] The €8 is NOT the driver's money — the app must show the outbound driver clearly that these €8 aren't his
- [stated] Outbound (1st) driver earns €4 (normal fare); when paid cash the driver collects the €8 in hand on Bora's behalf
- [stated] Return leg is FREE to the client (covered by the €8) and the 2nd driver is called automatically; return driver earns €3.50
- [stated] The €8 the outbound driver collected is reconciled in the weekly settlement: driver owes Bora the excess over his €4, and Bora owes the return driver his €3.50 (net Bora ≈ €0.50)
- [stated] Same principle for PLAN (covered) rides: driver earns his cut and Bora pays it via the weekly settlement (negative balance = Bora owes driver) — CONFIRMED by Danilo 2026-07-20

(Histórico do build de 20/07 — merge dos overloads do request_ride, EF tvde-payment v3, Fases A/B do €8-cash, TvdePayBadge €13 — movido para [[tvde-historico]].)

Paradas (stops) — decisões + backend 2026-07-20 (all verified in DB)
- [stated] DECISION: cash ride → stop pays nothing upfront, driver collects EVERYTHING at the end (€8 pacote + €2 = €10 em mão); card/mbway ride → client pays the €2 AT ONCE and the stop is only added when payment confirms
- [stated] Backend DONE by Claude.ai via MCP: tvde_ride_stops.payment_intent_id column (NULL = cash); tvde_add_stop now 6-arg single version (old 5-arg overload DROPPED before it could 404) + fires driver push; tvde_finish_ride settlement counts only CASH stops as collected-in-hand (v_stops_cash); EF notify-tvde-driver v5 (kind=stop_added, builds correct total per case); EF tvde-payment v4 (charge_stop + confirm_stop_payment with AUTO-REFUND if stop fails after payment)
- [stated] Test-round bugs handed to Claude Code (prompt-tvde-ronda-bugs): botão cortado folha €8; cliente deve ver preço do pacote (€8/€0) nas pernas do vale; totais reativos c/ parada (€10) dos dois lados; fluxo parada-cartão no cliente; folha "Chamar a volta" ≥ meia tela c/ 2 campos; oferta da volta deve mostrar €3,50 (setting, não €0); mapa do motorista trava — otimizar estilo Waze
- [stated] Confirmed working in live test: €8-cash end-to-end, driver notice, return leg free + recognized, vale "válido mais 11h39"

Follow-ups 2026-07-20 (Claude.ai via MCP)
- [stated] Bug 6 FIXED: tvde_request_return_ride now sets driver_earn_cents = tvde_roundtrip_return_driver_cents (350 = €3,50) + extra km, and est_fare_cents = 0 (return is free to client). Offer card/notice now show €3,50 instead of €0. Confirmed: ida €4 + volta €3,50 + Bora €0,50 = €8. (Minor: offer PUSH still reads est_fare so shows €0 for return legs — cosmetic, in-app is correct.)
- [stated] REPO EF SYNC — DONE (Claude Code ran `supabase functions download` for tvde-payment + notify-tvde-driver, committed as 77e2d23). Repo now matches the MCP-deployed EFs; no wipe risk.
- [stated] Claude Code's 7-bug plan reviewed & APPROVED (PLANO-tvde-bugs-testes-reais-2026-07-20): good — bugs 2&3 = one shared TvdeFareView memo (avoids double-counting stops on pacote legs); bug 5 pure UI + GPS-missing silent-fail; bug 7 map root cause = DriverStore anima posição + notifyListeners ~12x/s + realtime echo of own position + 2 GoogleMaps mounted + Directions sem in-flight guard
- [stated] 7-bug round DONE + PUSHED (recovery after terminal closed mid-work — prior terminal had committed, only push was missing). Final push 280e581 (TVDE commits 0479e19 the 7 bugs +1324/−107 across 13 files, + 77e2d23 the EF repo sync). flutter analyze 0 errors; flutter test TVDE 39/39 (27 old + 12 new). Bugs 1-5 fully done; bug 6 untouched (backend already fixed it); bug 7 map ~90% — Claude Code removed the own-position realtime echo (driverId marker no longer animates) + added isTopRoute + _routeFetchInFlight + _afterFrameScheduled + RepaintBoundary, but left the 5-decimal marker cache key and 1s ticker setState as-is on purpose (working code, no proof needed to change); FINAL map-smoothness confirmation must be on device with --profile — if it still stutters, targeted follow-up
- [stated] STILL PENDING (Claude.ai, last backend piece): flip tvde_request_ride so card/mbway rides are born aguarda_pagamento (cron ignores) + add the activate_roundtrip hook to release the €8-ONLINE outbound when the €8 pays. NOTE the €8-online case needs care: the outbound has no PI of its own (the €8 is a separate PI), so confirm_ride_payment can't flip it — activate_roundtrip must. Not blocking: Fase A already cancels card/mbway rides on payment decline, so the worst case (unpaid completed ride) is already prevented; the flip only removes the dispatch-before-payment window. Do it once the newest APK is installed + map confirmed
- [stated] REMINDER: adding a stop on a card/MBWay ride charges €2 REAL (Stripe live) — test stops in CASH to avoid real charges. Uncommitted on the machine (another task, untouched): AndroidManifest/Info.plist password-recovery deep link + 5 PROPOSTA_* migrations

(Categoria por aprovação de 21/07 — superada pelo gate removido a 01/08; mecanismo, receita de revert e pendência do painel em [[tvde-historico]].)

Gate TVDE REMOVIDO de vez (2026-08-01, Claude.ai via MCP)
- [stated] DECISÃO Danilo (2026-08-01, com print do ecrã "Categoria exclusiva / Quero desbloquear" na web): acabou o pedido de desbloqueio. Acesso TOTAL a todos os clientes, quem quiser pede motorista e vai direto.
- [stated] CAUSA REAL do "Sem acesso" (não era o default): `tvde_request_ride` fazia `SELECT tvde_access INTO v_acc FROM users WHERE id=uid; IF v_acc IS NOT TRUE THEN RAISE no_tvde_access` — e METADE das contas de auth NÃO tinha linha em public.users (os 2 clientes reais registados a 01/08 incluídos), logo v_acc ficava NULL → bloqueado. Não havia trigger nenhum a criar o perfil; só o Flutter inseria, e o fluxo web não inseria.
- [stated] FEITO por MCP (migration tvde_remover_gate_acesso_todos_2026_08_01): `tvde_request_ride` recriada sem o check de tvde_access (resto byte-a-byte igual, tokens/tarifa/subscrição intactos). Confirmado: 0 ocorrências de no_tvde_access; grants anon/authenticated/service_role mantidos.
- [stated] FEITO por MCP (migration users_row_auto_no_signup_2026_08_01): função `handle_new_auth_user()` + trigger AFTER INSERT `trg_handle_new_auth_user` em auth.users → cria sempre linha em public.users (id/email/name/phone/role do raw_user_meta_data, role fallback 'client', tvde_access true, ON CONFLICT DO NOTHING). Backfill das contas órfãs (role vinda de user_roles quando existia). Resultado: 14 contas, 0 sem perfil, 14 com tvde_access true. Isto corrige mais que TVDE — perfis em falta afectavam nome/telefone/fcm_token.
- [stated] ✅ FEITO no Flutter (commit `9d20cb4`, push confirmado por API do GitHub): tile "Bora Motorista" aparece sempre em client_home_screen.dart (sem gate tvdeAccess, método _buildTvdeEntry e refreshAccess removidos); tvde_unlock_screen.dart APAGADO; entrada "Pedidos de acesso" comentada no admin_dashboard_screen.dart com nota para reactivar. 3 ficheiros, +31/−258. flutter analyze 0 erros; 45/45 testes TVDE. Relatório em .claude/.ai/reports/tvde-open-access-2026-08-01.md. NOTA: o executor correu a versão do prompt SEM o bloco 7 (preço do pacote) — esse bloco ficou por fazer e foi para um prompt próprio.

BURACO DO PACOTE €8 — sem limite de distância (2026-08-01, 1ª corrida real com cliente de fora)
- [stated] Corrida real: cliente Lucas, Rua Virgílio Ferreira (Guarda) → Rochoso, 18,29 km, dinheiro, motorista = conta de motorista do Danilo, ride 21df2885-101e-489a-bad7-3b29d6de80e0, finalizada 01/08 18:33.
- [stated] Aritmética CONFERIDA e CORRECTA: base 6 km + 13 km extra → cliente €5,00 + 13×€1,00 = €18,00 (est_fare 1800); motorista €4,00 + 13×€0,80 = €14,40 (driver_earn 1440). O ecrã "recebes €14,40" estava certo.
- [stated] BUG REAL: o pacote ida-e-volta de €8 NÃO tinha limite de distância. Foi vendido numa corrida de 18 km → Bora recebe €8 e deve €14,40 ao motorista da ida + €3,50 ao da volta. tvde_driver_balances ficou em -5,90 (Bora deve ao motorista) e o vale da volta continua ativo → prejuízo ~€9,90 na corrida. O pacote foi desenhado para ida €4 + volta €3,50 + Bora €0,50, ou seja SÓ até à distância base.
- [stated] ❌ 1ª tentativa REJEITADA pelo Danilo (migration tvde_roundtrip_limite_km_2026_08_01, limite de 6 km + esconder a opção): ele NÃO quer esconder o pacote nem limitar distância. O setting `tvde_roundtrip_max_km` foi apagado.
- [stated] ✅ REGRA CERTA (Danilo, 2026-08-01): o pacote ida-e-volta é sempre oferecido, a qualquer distância. Preço = tarifa da IDA + tarifa da VOLTA com **20% de desconto**. Aos 6 km dá exactamente os €8 de sempre (5,00+5,00−20%); aos 10 km €14,40; aos 18,29 km €28,80; aos 25 km €38,40.
- [stated] FEITO por MCP (migration tvde_roundtrip_preco_por_distancia_2026_08_01): setting `tvde_roundtrip_discount_pct`=20; função `tvde_roundtrip_price_for_km(km)` (2×tarifa×(100−pct)/100, com piso no tvde_roundtrip_price_cents=800); RPC `tvde_quote_roundtrip(km)` → {one_way_cents, full_cents, discount_pct, price_cents, saving_cents} para o app; `tvde_create_roundtrip_credit_cash` grava esse preço em paid_cents (sem limite de km).
- [stated] FEITO por MCP (migration tvde_finish_ride_usa_valor_real_do_vale_2026_08_01): o acerto do motorista da ida lia o setting FIXO de €8 — passa a ler `tvde_roundtrip_credits.paid_cents` (valor real recolhido em mão). Também grava roundtrip_price_cents no evento.
- [stated] MATEMÁTICA PROVADA no DB (3/6/10/18,29/25 km): motorista da ida = 4,00+0,80/km extra; motorista da volta = 3,50+0,80/km extra; **sobra da Bora = €0,50 fixos em qualquer distância** (o desconto de 20% dá exactamente isso). AVISO por decidir do Danilo: aos 25 km a Bora move €38,40 e fica com €0,50 — se quiser margem proporcional, mexe-se em `tvde_roundtrip_discount_pct` (menos %) ou no `tvde_roundtrip_return_driver_cents`.
- [stated] ⚠️ RISCO DE TRANSIÇÃO: o APK/web antigo mostra €8 hardcoded (lê `tvde_roundtrip_price_cents`), enquanto o servidor já grava o preço real → cliente vê €8, vale vale €28,80 e o acerto cobra a diferença ao motorista. Até o build novo estar no telemóvel, viagens longas devem ir em corrida NORMAL, sem pacote.

