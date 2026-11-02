---
id: memoria-claude-ai-digest-2026-11-02-stripe-empresa
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Digest 02/11/2026 — missão stripe-empresa (duas contas Stripe)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-02-stripe-empresa`, origem `claude-code`, atualizada em 2026-11-02T03:47:06.5506+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 02 stripe empresa · memoria claude.ai · claude_ai_memoria

A missão stripe-empresa-2026-11-01 (Claude Code, Fable, 02/11 00:35–03:30, autorização do Danilo 01/11 22:03) deixou pronto no PC o código para duas contas Stripe: TVDE na pessoal, o resto na empresa; regra de ouro: o dinheiro mexe-se sempre na conta onde entrou (coluna stripe_account nas tabelas com pagamento; reembolsos, capturas e extras usam a conta gravada). Servidor: _shared/stripe_contas.ts (conta por pagamento, interruptor platform_settings.stripe_conta_nao_tvde, bandeira stripe_contas_v2 que a app manda, Customer por conta em users.stripe_customer_id_empresa), _shared/stripe_webhook_core.ts (webhook v38 partilhado) e stripe-webhook-empresa nova; 24 funções editadas no repo; as 8 da zona vermelha (create-payment-intent, create-mbway-payment-intent, finalize-order-from-intent, stripe-webhook, refund, reprocess-refund, charge-extra, client-cancel-order) ficaram como PROPOSTA em supabase/functions/_propostas/stripe-duas-contas porque a tranca nega essas pastas; SQL em docs/propostas/stripe-duas-contas (01 colunas, 02 interruptor, 03 stripe_extrato_resumo p_conta, 05 admin_list_payments). App: lib/services/stripe_contas.dart; a folha do cartão aplica a chave publicável que o servidor devolve; order_store (zona vermelha) = proposta 04 de 2 linhas. Painel admin: ecrã Stripe — duas contas e coluna Conta Stripe. Commit 171733e8 no ramo stripe-empresa-2026-11-01, SEM push (tranca pede o Danilo). Bloqueios: a Stripe da empresa pede a palavra-passe da Stripe para ligar a conta Google boraappbora (só o Danilo; página aberta no Chrome do Bora, Telegram id 11674); sem o Danilo a tranca recusa migração, deploy e push. Erros encontrados: cb134328 (chaves 31/10) partiu os imports de 4 funções no repo (corrigido); reprocess-refund no repo estava atrás da produção (ressincronizado); as 4 funções de cancelamento com gorjetas continuam por publicar desde 01/11; app_min_supported_version_code=0. Testes: deno 12/12, flutter 24/24, analyze 0 erros. Passo a passo do que falta: docs/STRIPE_DUAS_CONTAS.md secção 7. Nunca houve chaves no chat nem em ficheiros.
