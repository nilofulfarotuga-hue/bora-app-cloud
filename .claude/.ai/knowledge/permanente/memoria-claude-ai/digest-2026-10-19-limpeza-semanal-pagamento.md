---
id: memoria-claude-ai-digest-2026-10-19-limpeza-semanal-pagamento
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-19
zona: verde
confianca: alta
estado: atual
---

# Claude Code 19/10 — limpeza semanal só chama depois de pago

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-19-limpeza-semanal-pagamento`, origem `claude-code`, atualizada em 2026-10-19T11:21:00.048054+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 19 limpeza semanal pagamento · memoria claude.ai · claude_ai_memoria

Limpezas: com MB Way ou cartão por pagar, _cleaning_next_offer já não chama ninguém; o gatilho trg_cleaning_paid_offer chama a profissional quando payment_status passa de unpaid a held (webhook ou mark_held). Dinheiro chama logo. Séries semanais/quinzenais: generate_recurring_bookings ancora na 1.ª reserva da série (created_at) em hora de Lisboa e usa GREATEST(conta, nº de reservas) — reagendamento pontual não arrasta, mudança da hora não desloca. MB Way automático: public.cleaning_request_payment(id) (servidor ou admin) chama a Edge cleaning-request-payment (v2, só servidor), que cria o PaymentIntent MB Way com o telefone do último MB Way pago na Stripe (ou users.phone), metadata kind=cleaning/origem=pedido_automatico, e não cria outro se já houver um requires_action ou pago. Cron cleaning-unpaid-retry (:20 de hora a hora): repede de 12 em 12 h até 4 vezes e avisa o admin a <24 h. Painel: "Pagamento: pago / pedido enviado / por pagar" + botão "Pedir pagamento MB Way". App cliente: "Pagar com MB Way". Edge diag-pagamento-limpeza (só leitura) diz o motivo real de um pedido falhado. Divan: df044ec2 passou a sáb 24/10 13:30, sem limpadora até pagar (Mayra preferida); os 2 pedidos MB Way de 19/10 falharam com payment_method_customer_decline. FALTA: 2.ª migração bloqueada pela bora-tranca (palavra Stripe nos comentários) — aviso ao admin se a oferta falhar depois de pago, copiar is_test_order, aviso de cartão por pagar, pedidos só 09-21h. NÃO aplicar 20261010073000_limpeza_duas_voltas_de_ofertas.sql: apaga a trava. Relatório: .claude/.ai/reports/limpeza-semanal-pagamento-2026-10-19.md. Commit 0d2e5960.
