---
id: memoria-claude-ai-livro-areas-tvde-pagamento-mbway
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Regra do Danilo para o pagamento MB Way nas corridas TVDE (tocar ao motorista assim que o cliente paga) e o prompt entregue a 06/09

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-tvde-pagamento-mbway`, origem `claude-ai`, atualizada em 2026-10-23T05:40:25.497254+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas tvde pagamento mbway · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/tvde-pagamento-mbway.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: tvde-pagamento-mbway
description: Regra do Danilo para o pagamento MB Way nas corridas TVDE (tocar ao motorista assim que o cliente paga) e o prompt entregue a 06/09
sources: [chat]
aliases: [MB Way, mbway TVDE, pagamento da corrida, cliente desiste, demora a tocar]
---

- [stated] REGRA (06/09, disse chateado): assim que o cliente faz o pagamento, tem de tocar IMEDIATAMENTE a um motorista. O cliente não pode ficar num ecrã "a processar / à procura de motorista" à espera, porque desiste da corrida. "Não pode acontecer mais isso."

Prompts entregues
- [stated] 06/09 — PROMPT_mbway_cliente_nao_fica_no_escuro_2026-09-06.md, motor OPUS, sessão NOVA no Claude Code na pasta bora-app-cloud. Scope: só Flutter do lado do cliente (ecrã diz "confirma na app MB Way" em vez de procurar motorista, realtime na linha da corrida, janela de espera por platform_settings, saída com tentar de novo/pagar em dinheiro, chave nova editável no painel admin). Proibido tocar em dispatch, stripe-webhook, Edge tvde-payment, preços e wallet. Estado: por rodar. Ver [[tvde-vertical]].

MB Way DESLIGADO temporariamente (21/09/2026)
- [stated] ORDEM do Danilo (21/09): o MB Way dele bateu no limite e as pessoas não conseguem transferir. Mandou pôr a função "temporariamente indisponível" — a opção fica A CINZENTO, ao clicar diz que não é permitido, e o cliente resolve em DINHEIRO ou CARTÃO. É temporário; tem de dar para religar sem build novo.
- PROVA da falha (MCP): corrida 12d63341-3d25-4e73-90af-8be45624be49, 21/09 12:05, payment_method=mbway, payment_status=requires_payment_method → cancelada_cliente, sem motorista. O MESMO cliente (13921978) tinha pago por MB Way sem problema a 18/09. Nos 30 dias antes: 20 corridas e 4 pedidos pagos por MB Way.
- DISTINÇÃO que custou tempo a apurar (não voltar a confundir): o MB Way do checkout é **Stripe** (`payment_method_types:['mb_way']`), não é transferência para o número pessoal dele. O número pessoal (`platform_settings.bora_mbway_phone` = 931992662) só aparece como TEXTO no fecho semanal ("Pague por MB Way para …"), em `partner_weekly_closeout_card.dart` e nas Edge `settlement-receipt`/`weekly-closeout-digest` — esse ficou como estava.
- FEITO por MCP 21/09: (1) migration `mbway_kill_switch_2026_09_21` → `platform_settings.mbway_enabled=false` + `mbway_disabled_message` (PT-PT); (2) Edge `create-mbway-payment-intent` **v29** com guarda que devolve 503 `{error:'mbway_disabled'}` — deployada duas vezes porque o deploy por MCP põe `verify_jwt=true` por omissão e a função era `false` (v28 saiu errada, v29 repôs; ARMADILHA a lembrar em todo deploy por MCP); (3) migration `mbway_guard_triggers_orders_rides_2026_09_21` → `public.guard_mbway_disabled()` + triggers BEFORE INSERT OR UPDATE OF payment_method em `orders` e `tvde_rides`, levanta `MBWAY_DISABLED` com a mensagem no HINT. Escolhi trigger em vez de reescrever `tvde_request_ride`/`tvde_schedule_ride` (RPCs grandes de dinheiro) — mesmo padrão do `trg_payment_draft_coming_soon`. Provado por teste transaccional (bloqueou=t, nada gravado).
- RELIGAR = `platform_settings.mbway_enabled = true`. Não é preciso build nem reverter nada.
- [stated] PROMPT REGISTADO: `PROMPT_mbway_desligado_2026-09-21.md`, entregue 21/09, MOTOR OPUS, sessão NOVA no Claude Code na pasta bora-app-cloud. Scope: A interruptor lido pela app (falha fechada, padrão do `remote_fees_service.dart`); B MB Way a cinzento nos 8 ecrãs de escolha (checkout de pedidos, seletor TVDE, sheet partilhada reservas/marcações/planos, limpeza, lavagem, pagar dívida) — em reservas/marcações/planos não há dinheiro, sobra o cartão; C guardas nas 8 Edge Functions de MB Way que faltam, mantendo o `verify_jwt` de cada uma; D interruptor + mensagem no `admin_platform_settings_screen.dart` (PT-BR). Prova pela web em app.boraguarda.com. Estado: entregue como ficheiro; nada disparado.

