---
id: memoria-claude-ai-digest-2026-10-05-ronda-auditoria-04-10-pc
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: alta
estado: atual
---

# Claude Code PC 05/10 — revisão geral 04/10, blocos A/B/C

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-05-ronda-auditoria-04-10-pc`, origem `claude-code`, atualizada em 2026-10-05T09:31:00.782934+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 05 ronda auditoria 04 10 pc · memoria claude.ai · claude_ai_memoria

Ordem do Danilo 05/10 09:30 ("faz tudo o que falta da revisão geral de 04/10; autorizo tudo"). Relatórios em .claude/.ai/missoes/ronda-04-10/feito/pc-A.md, pc-B.md, pc-C.md. Publicado no ramo autonomous-night-2026-04-29 (push 6522348d às 10:30).
BLOCO A (entregas): orders.stripe_charge_cents passa a ser gravado — função registar_cobranca_stripe (só service_role) + payments-reconciler v5 com cron de 10 em 10 min (payments-reconciler-cobrancas); os 7 MB Way pagos ficaram preenchidos. Antes estava a 0 e por isso qualquer reembolso de MB Way pago batia no limite (_enforce_refund_cap). admin-cancel-order v14 devolve só o cobrado na Stripe + carteira/tokens para a carteira; o botão Cancelar pedido estava parado desde 03/10 (admin_cancel_order perdeu o GRANT) — reposto. execute-cancellation v15: admin por is_admin() no servidor (antes aceitava user_metadata, editável pelo utilizador). cancel-order-with-choice v18: trava contra duplo toque. Estado novo refund_status='needs_review' = Stripe devolveu e o resto falhou (o Reprocessar não lhe pega; o reconciliador alerta). carwash-checkout v2 sem reembolso a dobrar. Índice único orders(payment_intent_id). Crédito do estafeta já não duplica. Tabela stripe_webhook_events criada.
TRANCADO pela Trava (só o Danilo abre): stripe-webhook v36 (5xx + idempotência, reserva TVDE MB Way, km do plano, lavagem, gorjeta), finalize v14 e client-cancel v29 — prontos e simulados em pronto/stripe-webhook-v36 (v36 10/10, v35 1/10).
BLOCO B (painel): uma só função de marcar pago (admin_set_settlement_state, decide pelo saldo do acerto), demo fora das contas, barbearias nas Contas claras, semanas pagas congeladas, sem 1.15 cravado, auditoria a gravar de verdade (log_admin_action escrevia numa tabela inexistente), semana de Lisboa, CSV com ;, menu Dinheiro com 5 entradas, confirmação com nome e valor. Trancados: B.6 (barbearia pago na app) e B.8 (tokens semana de Lisboa) — propostas em feito/.
BLOCO C (segurança): 169 funções SECURITY DEFINER fechadas a quem não tem sessão (lista em bkp_anon_execute_20261005); funções novas nascem fechadas a anon (regra no CLAUDE.md); 16 em dúvida ficam abertas até teste a frio.
PARA O DANILO: cliente do pedido bba0f503 (12/09) recebeu 7 vezes o reembolso na carteira (50,91 € por 7,07 €), saldo hoje 0 — decidir. Abrir a Trava para o webhook v36.
