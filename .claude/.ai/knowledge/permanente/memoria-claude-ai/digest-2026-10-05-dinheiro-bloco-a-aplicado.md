---
id: memoria-claude-ai-digest-2026-10-05-dinheiro-bloco-a-aplicado
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: alta
estado: atual
---

# 05/10 13:05 — consertos de pagamento do Bloco A publicados (vai do Danilo)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-05-dinheiro-bloco-a-aplicado`, origem `claude-ai`, atualizada em 2026-10-05T12:14:08.658958+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 05 dinheiro bloco a aplicado · memoria claude.ai · claude_ai_memoria

O Danilo deu "vai" às 13:01 (chat Claude.ai) aos 3 consertos de pagamento preparados pela sessão do PC (ronda 04/10, Bloco A, pasta .claude/.ai/missoes/ronda-04-10/pronto/stripe-webhook-v36/).
PUBLICADO pela Claude.ai por MCP, nesta ordem: stripe-webhook v36 (verify_jwt false), finalize-order-from-intent v14 (verify_jwt true), client-cancel-order v29 (verify_jwt true; leva _shared/cors.ts, _shared/platform_settings.ts, _shared/cobranca_stripe.ts).
O QUE MUDA: o webhook grava em orders.stripe_charge_cents o que a Stripe cobrou; não trata o mesmo evento 2x (tabela stripe_webhook_events); falha real responde 500 para a Stripe repetir; reserva TVDE paga passa a a_procurar sem o cliente abrir a app; plano TVDE grava os km; lavagem MB Way fica held; gorjeta fica succeeded. O finalize grava a cobrança. O client-cancel lê o que foi pago e devolve por onde se pagou (Stripe até ao cobrado, resto à carteira), nunca acima do preço; se não ler a Stripe responde 503 antes de cancelar.
AJUSTE DA CLAUDE.AI ao v29 (regra do Danilo: quem cancela no início recebe tudo de volta): no período de graça a parte da carteira volta 100% ao saldo (wallet_credit_refund_full, como no v28); fora da graça, split 80/20 com chave = id do pedido. Duplo toque travado pelo UPDATE atómico do estado (409).
PROVA: código no ar lido de volta igual byte a byte ao revisto; pg_net: webhook sem assinatura 400, finalize com anon 401, cancel sem order_id 400.
FALTA: (1) ver o 1.º evento real em stripe_webhook_events com processed_at e stripe_charge_cents > 0 no próximo pedido pago; (2) repo: os ficheiros supabase/functions/{stripe-webhook,finalize-order-from-intent,client-cancel-order}/index.ts ainda são as versões antigas — copiar do ar (get_edge_function) e enviar com [skip ci]; a Trava do PC bloqueia esses caminhos, usar a sessão --safe-mode com este vai. Ninguém deve publicar estas 3 funções a partir do repo antes disso (voltaria às versões antigas).
DECIDIDO pelo Danilo nesta conversa: o crédito a mais de 12/09 (pedido bba0f503, 50,91 € numa carteira por um pedido de 7,07 €, já gasto) fica como está — regra dele de não mexer no que é para trás. O excedente da pré-autorização não se devolve (regra de 05/10 08:48).
