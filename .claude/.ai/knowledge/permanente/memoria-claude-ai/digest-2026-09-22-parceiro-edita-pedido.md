---
id: memoria-claude-ai-digest-2026-09-22-parceiro-edita-pedido
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-22
zona: verde
confianca: alta
estado: atual
---

# Claude Code 22/09 — parceiro edita pedido (acrescentar / em falta)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-22-parceiro-edita-pedido`, origem `claude-code`, atualizada em 2026-09-22T20:16:17.515726+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 22 parceiro edita pedido · memoria claude.ai · claude_ai_memoria

Feito: base sem dinheiro no ar — tabela order_edits (grupo_id por proposta, RLS parceiro/cliente/estafeta/admin, sem insert directo, tempo real), interruptor platform_settings.order_edit_enabled=false, RPCs admin_list_order_edits e admin_cancel_order_edit (migration 20260922200000). App escrita e escondida atrás do interruptor: parceiro com Acrescentar produto (pesquisa sem acentos + opções como no carrinho) e Marcar em falta, resumo antes/depois do servidor, estados; pesquisa no catálogo do parceiro; cliente aceita/recusa e paga a diferença; estafeta vê o que mudou; admin com lista, filtro, CSV, cancelar/aprovar/forçar estorno e separador Edições. Linha do saco no resumo do acompanhamento do cliente. Por aplicar (dinheiro, espera o vai): 20260922200100_PROPOSTA_parceiro_edita_pedido_dinheiro.sql (inclui wallet_credit_refund_split com p_idempotency_key, porque hoje só aceita um crédito por pedido) e Edge Function order-edit-settle (reembolso parcial Stripe, cobrança off-session com fallback Payment Sheet, MB Way da diferença; PIs sem metadata.order_id para o stripe-webhook os ignorar). Provas: 10/10 na base real em rollback, 4000 pares ao cêntimo numa cópia local, analyze 0 erros, 633 testes verdes, Juiz limpo; provas em provas/parceiro-edita-pedido-2026-09-22/. ATENÇÃO: total e customer_total de orders são colunas geradas (= price). BLOQUEIO: commit 850b812 feito mas o push deu 403 (app Claude sem acesso de escrita ao GitHub) — reconectar e empurrar. Relatório: RELATORIO-parceiro-edita-pedido-2026-09-22.md.
