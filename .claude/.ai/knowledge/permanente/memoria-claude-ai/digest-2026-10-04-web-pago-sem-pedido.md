---
id: memoria-claude-ai-digest-2026-10-04-web-pago-sem-pedido
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-04
zona: verde
confianca: alta
estado: atual
---

# Claude Code FABLE 04/10 — pagou na web e a corrida não nasceu (Priscila) + motorista + ecrã do cliente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-04-web-pago-sem-pedido`, origem `claude-code`, atualizada em 2026-10-04T19:04:17.564051+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 04 web pago sem pedido · memoria claude.ai · claude_ai_memoria

Caso Priscila (pacote ida-e-volta pago por cartão no Safari, ida nunca criada): causa era a app cobrar primeiro e criar a ida depois, na página que o cartão já tinha morto. Corrigido nos dois lados. No servidor (migrações 20261004182018 e 20261004185003, aplicadas e no repo): tvde_create_roundtrip_credit repara um vale pago sem ida ligando-lhe a corrida pendente do cliente, só corrida sem pagamento próprio; índice único por payment_intent_id; cron tvde-roundtrip-orfaos de minuto a minuto que liga a ida ou avisa por Telegram e push quando um vale pago tem mais de 2 minutos sem ida, com linha no e2e_log (fluxo tvde-pago-sem-corrida). Backup da função em bkp_fn_tvde_roundtrip_20261004. Na app (commit 2b6f4bd2, ramo autonomous-night-2026-04-29): a ida nasce antes de abrir o cartão e fica estacionada; o webhook liberta-a; a retoma web conhece a vertical tvde-roundtrip; vale pago sem ida já não mostra Chamar a volta. Painel: Pagos sem corrida criada em /admin/tvde/pagos-sem-corrida (RPC admin_tvde_pagos_sem_corrida e admin_tvde_roundtrip_reparar).
Auditoria das outras categorias pagas na web: seguras TVDE avulsa, reserva e pacote agendado, reservas de mesa/serviços/limpeza por MB Way, dívida; cartão bloqueado na web em entregas, limpeza, lavagem, serviços e planos. Corrigido o cartão das reservas de mesa na web. POR CORRIGIR, à espera do vai do Danilo porque mexem em funções Stripe: paragem extra TVDE (paga e a paragem perde-se se a página morrer), Lavagem MB Way (webhook não conhece carwash; botão Pagar pode cobrar duas vezes), botão de reembolso de pacote sem corrida, cancelar o PaymentIntent quando a ida é largada.
Motorista: o aviso foi para outro motorista decidia só pelo relógio (corrida 8c7f5ca6 aceite a 2 s do fim); agora decide pelo dono da corrida e pelo aceite em curso. Aceitar cala logo a notificação, também com a app morta.
Cliente: a corrida 0d979026 foi finalizada 9 segundos depois de iniciada, o ecrã fechou por ter acabado. Defeitos reais corrigidos: avaliação pendente aparece ao reabrir e a corrida viva volta sozinha ao arrancar a app.
Verificação: análise sem erros, 941 testes verdes, juiz limpo, revisão de contexto limpo feita. Falta prova no aparelho (Safari com cartão, emulador). Relatório em .claude/.ai/reports/FABLE-2026-10-04-web-pago-sem-pedido.md; continuação em .claude/.ai/inbox/CONTINUAR-web-pago-sem-pedido-2026-10-04.md.
