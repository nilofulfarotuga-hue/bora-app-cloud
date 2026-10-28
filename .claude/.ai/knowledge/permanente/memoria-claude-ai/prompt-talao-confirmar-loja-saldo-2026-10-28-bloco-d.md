---
id: memoria-claude-ai-prompt-talao-confirmar-loja-saldo-2026-10-28-bloco-d
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-28
zona: verde
confianca: alta
estado: atual
---

# Adenda 18:30 ao prompt de 28/10 (talão Auchan/Divan): Bloco D novo — reembolso no cancelamento

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-talao-confirmar-loja-saldo-2026-10-28-bloco-d`, origem `claude-ai`, atualizada em 2026-10-28T18:32:24.956497+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt talao confirmar loja saldo 2026 10 28 bloco d · memoria claude.ai · claude_ai_memoria

Substitui o BLOCO D do prompt `prompt-talao-confirmar-loja-saldo-2026-10-28`.

BLOCO D — Reembolso quando um pedido é cancelado (regra nova do Danilo, 28/10 18:24)
- Regra: quem paga com MB Way ou cartão recebe o dinheiro de volta pelo mesmo meio, e é isso que vem marcado por defeito. MB Way volta na hora; cartão demora uns dias úteis e o texto tem de o dizer. O cliente pode escolher, em vez disso, receber 100% em saldo Bora, já, para usar como quiser. Acabou o 80% saldo + 20% tokens.
- Já feito por MCP (18:27): platform_settings.wallet_split_free_pct 0.8 -> 1.0 (backup bkp_platform_settings_wallet_split_20261028).
- Já estava ligado: trg_reembolso_cancelado_pelo_sistema (cancelado pelo sistema devolve 100% ao MB Way/cartão via auto-refund-order). Confirmar com pedido de teste.
- App: order_tracking_screen.dart (diálogo Cancelar pedido, ~linha 1260), refund_choice_dialog.dart, strings_en.dart e qualquer texto com 80%/20%/pontos: opções "Devolver ao MB Way — volta na hora" ou "Devolver ao cartão — até X dias úteis" (conforme o meio) e "Saldo Bora, já — 100% do valor".
- Servidor: confirmar client-cancel-order, cancel-order-with-choice, execute-cancellation, admin-cancel-order, reprocess-refund, auto-refund-order. Tokens pagos voltam como tokens (com a validade que tinham), nunca como saldo; tokens não gastos não se devolvem. Hoje tokens_applied_count fica 0 mesmo quando gastos (f293752c: 146 gastos, contagem 0) e o client-cancel-order v29 perde-os.
- Referência de 10/10 nunca aplicada: .claude/.ai/missoes/chamada-grita-2026-10-10/pronto-dinheiro/.
- Painel admin: rótulo PT-BR de wallet_split_free_pct; no detalhe do cancelamento, para onde foi o reembolso e quanto.
- Provas com pedidos de teste: MB Way cancelado -> volta ao MB Way e, noutro, saldo 100%; dinheiro com tokens cancelado -> tokens voltam; cancelado pelo sistema -> MB Way.

Bloco C, tarefa 2: finalize_errand_purchase (Favores) JÁ corrigido por MCP às 18:28 (migração favor_dinheiro_respeita_saldo_e_tokens_20261028, backup bkp_fn_finalize_errand_purchase_20261028) — só gravar no repo.

Bloco C, tarefa 5 (18:31, o Danilo viu-o: o cliente tinha o saldo descontado mas o ecrã do estafeta mandava cobrar o valor cheio): o valor a cobrar no ecrã do estafeta tem de vir SEMPRE do cash_total_due do servidor. Hoje OrderModel.totalToCollectCash (lib/models/order_model.dart ~412) usa finalTotal (bruto) nos Favores depois da compra, e order_store.dart (~1815 e ~1940) e driver_map_screen.dart (~3839) põem order.cashTotalDue = null depois do talão (comentário antigo "cash_total_due = final_total", já falso). Corrigir para usar sempre o cash_total_due (resposta da RPC ou tempo real) e mostrar ao estafeta a conta curta quando há saldo/tokens: "Total 14,35 € · já pago com saldo/tokens 11,04 € · RECEBER 3,31 €".
