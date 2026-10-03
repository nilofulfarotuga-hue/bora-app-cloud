---
id: memoria-claude-ai-digest-2026-09-21-mbway-desligado
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-21
zona: verde
confianca: alta
estado: atual
---

# MB Way desligado temporariamente (21/09/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-21-mbway-desligado`, origem `claude-ai`, atualizada em 2026-09-21T12:24:45.375849+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 21 mbway desligado · memoria claude.ai · claude_ai_memoria

ORDEM do Danilo 21/09: o MB Way dele bateu no limite e as pessoas nao conseguem transferir. MB Way passa a temporariamente indisponivel — opcao a CINZENTO, ao clicar diz que nao e permitido, cliente resolve em DINHEIRO ou CARTAO. Temporario: religar sem build novo.

PROVA da falha (MCP): corrida 12d63341-3d25-4e73-90af-8be45624be49, 21/09 12:05, payment_method=mbway, payment_status=requires_payment_method -> cancelada_cliente, sem motorista. O MESMO cliente (13921978) pagou por MB Way sem problema a 18/09. Nos 30 dias antes: 20 corridas e 4 pedidos pagos por MB Way.

DISTINCAO IMPORTANTE (nao confundir): o MB Way do checkout e STRIPE (payment_method_types:[mb_way]), nao e transferencia para o numero pessoal. O numero pessoal (platform_settings.bora_mbway_phone = 931992662) so aparece como TEXTO no fecho semanal (partner_weekly_closeout_card.dart, Edge settlement-receipt e weekly-closeout-digest). Esse ficou como estava — se o limite for de recebimento, os parceiros que devem tambem nao conseguem transferir para la; decisao do Danilo por tomar.

FEITO POR MCP (Claude.ai, 21/09):
1. migration mbway_kill_switch_2026_09_21 -> platform_settings.mbway_enabled=false + mbway_disabled_message (PT-PT). Religar = por a true.
2. Edge create-mbway-payment-intent v29 — guarda que devolve 503 {error:mbway_disabled, message}. ARMADILHA: o deploy por MCP poe verify_jwt=true por omissao; esta funcao era false, a v28 saiu errada e a v29 repos. Verificar SEMPRE o verify_jwt depois de deploy por MCP.
3. migration mbway_guard_triggers_orders_rides_2026_09_21 -> public.guard_mbway_disabled() + triggers trg_guard_mbway_orders (orders) e trg_guard_mbway_tvde_rides (tvde_rides), BEFORE INSERT OR UPDATE OF payment_method, levantam MBWAY_DISABLED com a mensagem no HINT. Escolhido trigger em vez de reescrever tvde_request_ride/tvde_schedule_ride (RPCs grandes de dinheiro) — mesmo padrao do trg_payment_draft_coming_soon. Provado por teste transaccional: bloqueou=t, nada gravado.

PROMPT ENTREGUE (por rodar): PROMPT_mbway_desligado_2026-09-21.md, MOTOR OPUS, sessao NOVA no Claude Code em bora-app-cloud. Blocos: A interruptor lido pela app (falha fechada, padrao remote_fees_service.dart; platform_settings tem RLS so para autenticados e devolve [] sem erro sem sessao); B MB Way a cinzento nos 8 ecras de escolha (payment_method_screen, tvde_payment_selector, reservation_payment_method_sheet partilhada por reservas/marcacoes/planos, cleaning_payment_flow, carwash_payment_flow, pay_debt_modal) — em reservas/marcacoes/planos nao ha dinheiro, sobra o cartao; C guardas nas Edge que faltam (create-mbway-reservation-payment-intent, create-mbway-appointment-payment-intent, confirm-mbway-appointment-payment, tvde-payment, tvde-plan-payment, cleaning-checkout, carwash-checkout, pay-debt-standalone), mantendo o verify_jwt de cada uma; D interruptor + mensagem no admin_platform_settings_screen.dart (PT-BR). Prova pela web em app.boraguarda.com.
