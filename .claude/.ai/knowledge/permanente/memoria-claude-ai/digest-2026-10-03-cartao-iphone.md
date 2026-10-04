---
id: memoria-claude-ai-digest-2026-10-03-cartao-iphone
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-03
zona: verde
confianca: alta
estado: atual
---

# Claude Code 03/10 noite — cartão no iPhone + varredura

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-03-cartao-iphone`, origem `claude-code`, atualizada em 2026-10-03T18:47:45.938209+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 03 cartao iphone · memoria claude.ai · claude_ai_memoria

Cartão no iPhone ficava só a rodar (Divan 02/10, Danilo 21/09): causa provada no plugin stripe_ios 11.5 — com UIScene o AppDelegate.window fica vazio e a folha do Stripe era apresentada fora de qualquer janela; presentPaymentSheet nunca devolvia. Corrigido em ios/Runner/AppDelegate.swift (commit 1d731b65). Só fica a funcionar no iPhone quando sair o build iOS novo (TestFlight/App Store).
Toda a abertura da folha do cartão passa por lib/services/folha_cartao.dart: tempo limite platform_settings.payment_sheet_timeout_seconds=20, confirma no iPhone que a folha apareceu, erro real em payment_client_failures via RPC log_payment_failure (Telegram, 1 aviso/cliente/10 min). Painel: Operação → Pagamentos presos (RPC admin_pagamentos_presos). Teste-guarda proíbe Stripe.instance.presentPaymentSheet fora dessa porta.
Prova no simulador iOS pronta (integration_test/folha_cartao_ios_test.dart, passo no build_ios.yml) mas NÃO PROVADA: faltam segredos GitHub STRIPE_TEST_PUBLISHABLE_KEY/STRIPE_TEST_SECRET_KEY.
Limpeza: cleaning_mark_started/done aceitam saltar passos e são idempotentes; uma só notificação por passo; Bora escreve no chat (admin_send_cleaning_message, sender_role 'admin'); lembrete ao cliente 2 h após terminar; admin_set_cleaning_status com motivo (sem dinheiro); crash do botão de chat corrigido.
Também: MB Way sem segundo pedido; PIN do estafeta com trava e tempo limite; horários/online do parceiro já não mentem; tvde chat push com type tvde_chat (edge v4).
Por decidir (dinheiro): gorjeta nunca gravou (0 pedidos); 4 PIs TVDE requires_action abertos; prioridade com tokens não atómica. Continuação completa: vault Bora/missoes/2026-10-03-cartao-iphone-e-varredura.md (33 itens). Córtex MCP estava sem autorização nesta sessão.
