---
id: memoria-claude-ai-sql-modo-demo-2026-10-27
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-27
zona: verde
confianca: alta
estado: atual
---

# SQL do modo demonstracao (Boom! Burger) para o Claude.ai aplicar

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `sql-modo-demo-2026-10-27`, origem `claude-code`, atualizada em 2026-10-27T17:12:12.805647+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: sql modo demo 2026 10 27 · memoria claude.ai · claude_ai_memoria

# SQL do modo demonstracao — para o Claude.ai rever e aplicar (27/10/2026)

Missao boom-burger-2026-10-27, adendo 2 bloco B. Escrito pelo Claude Code. Fonte no repo bora-site:
sites-parceiros/boom-burger/fonte/sql/para-claude-ai-mover-pedidos-demo.sql (e modo_demo_2026-10-27.sql).

## O que JA esta aplicado no servidor (provado nos ensaios de 27/10 17:02-17:13, pedidos dbc61271 e bb322980)
- platform_settings 'modo_demo_loja' (is_secret): loja, inicio, fim, cliente_user_id, estafeta_user_id. Desliga-se sozinho no fim.
- _modo_demo_def / _modo_demo_loja / _modo_demo_estafeta / _e_pedido_demo_loja: ajudantes SECURITY DEFINER, fechados a anon e authenticated (verificado: todas as funcoes que os chamam sao definer).
- _pedido_demo_em_caixa_fechada, _coming_soon_guard_orders, _store_closed_guard_orders: deixam passar SO o pedido em dinheiro do cliente demo, na loja, dentro da janela (fica is_test_order). Prova: cliente normal e cartao -> STORE_COMING_SOON.
- notify_new_order_admin, notify_admin_urgent_push, notify_admin_event: calados para o pedido demo. Prova: 0 linhas em admin_notifications do pedido.
- dispatch_candidatos_entrega: pedido demo -> so o estafeta demo; pedido normal -> nunca o estafeta demo. Prova: oferta e tried_driver_ids so com o estafeta demo; candidatos dos 30 pedidos recentes iguais aos de antes.
- GUARDA DA ENTREGA: gatilho a0_trg_demo_loja_sem_entrega (BEFORE UPDATE OF status, so quando passa a delivered) -> _demo_loja_sem_entrega(): o pedido demo nao fica 'delivered' (isso correria ganhos, tokens, livro e acerto semanal); fica cancelled, cancel_fee 0, motivo 'Demonstracao concluida: entrega simulada, sem custo'. Prova: estado final cancelled, taxa 0; 0 linhas em ledger_entries, bora_tokens, driver_transactions, driver_token_transactions, driver_weekly_settlements, partner_weekly_settlements, payouts, settlement_receipts, order_financial_transactions, wallet_transactions, bora_invoices_pending, driver_monthly_invoices, daily_checkins.
- demo_boom_criar_pedido(p_itens, p_notas): RPC do cliente demo (so authenticated, so esse uid, so dentro da janela) que chama create_order em dinheiro.
- _notify_on_order_cancel (27/10 17:12): nao manda "Pedido cancelado" quando o motivo comeca por 'Demonstracao' (o fim da demonstracao nao e um cancelamento para o cliente).

## O que FALTA aplicar (a bora-tranca do PC recusou: o texto mexe em public.orders)
Bloco unico: nova versao de public.mover_pedidos_demo() (cron de minuto a minuto das contas demo). Texto completo no ficheiro do repo bora-site acima (para-claude-ai-mover-pedidos-demo.sql).
- (1) os 3 blocos antigos ganham "and not public._e_pedido_demo_loja(id)": na demonstracao e o estafeta no telemovel que carrega em Levantei / A caminho, nao o cron. Os outros pedidos demo (Apple) ficam como hoje.
- (2) bloco novo, a seguir ao das 6 h: fora da janela (antes do inicio ou depois do fim) os pedidos demo abertos dessa loja fecham-se: status cancelled, cancelled_at now(), cancel_fee 0, cancel_reason 'Demonstracao terminada (fim da janela): sem custo', onde is_test_order e status fora de (delivered, cancelled, rejected) e public._e_pedido_demo_loja(id) e not public._modo_demo_loja(public._modo_demo_def()->>'restaurant_id'). O retorno ganha ' fim_janela=' || contagem.
Como se prova (tudo dentro de begin ... rollback): (a) janela ativa, pedido demo da loja em driverAccepted fica driverAccepted depois de select public.mover_pedidos_demo(); (b) janela acabada -> cancelled, taxa 0; (c) pedido demo de outra loja continua a avancar.
Ler a definicao atual antes de aplicar. Sem este bloco a demonstracao funciona na mesma: o cron avanca sozinho levantado -> a caminho em 1-2 min depois de o estafeta aceitar, e o fecho no fim da janela fica pela regra das 6 h ou pela entrega com PIN.

