---
id: memoria-claude-ai-digest-2026-11-02-stripe-retoma
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-02
zona: verde
confianca: alta
estado: atual
---

# Stripe duas contas — retoma Opus 02/11 — resultado

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-11-02-stripe-retoma`, origem `claude-code`, atualizada em 2026-11-02T07:15:33.481631+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 11 02 stripe retoma · memoria claude.ai · claude_ai_memoria

A retoma da missao stripe-empresa-2026-11-01 (Claude Code, Opus, 06:20-07:20) deixou o servidor quase todo ligado a conta Stripe da empresa sem mudar nada para os clientes: o interruptor stripe_conta_nao_tvde continua pessoal e as apps das lojas nao mandam a bandeira stripe_contas_v2. Publicadas 24 funcoes com o codigo das duas contas, admin-payments v13 (acoes prova_conta e webhooks, so admin ou servidor) e stripe-webhook-empresa v1. Prova sem cobrar: PI de 0,50 EUR sem cartao criado e cancelado na empresa (pi_3UXEwPGWwQxC9wR21J1qcJvg) com o evento a chegar ao webhook da empresa com 200 e stripe_account=empresa; o mesmo na pessoal. Corrigido: o destino de webhook da empresa tinha 5 eventos e a pessoal so escuta 3 (succeeded, payment_failed, charge.refunded); agora iguais. Fica diferente a versao da API do destino (endive vs clover), risco baixo. Corrigido erro antigo: admin_list_payments falhava sempre. Proposta 05 aplicada sem DROP. Revisao independente OK. Falta: as 8 funcoes da zona vermelha (a Claude.ai publica por MCP com docs/propostas/stripe-duas-contas/DEPLOY_ZONA_VERMELHA.md no ramo stripe-empresa-retoma-2026-11-02), a proposta 04 do order_store (sessao com o Danilo), virar o interruptor por admin_update_money_setting com sessao de admin e publicar nas 3 lojas so com ordem do Danilo. Migracoes aplicadas por copiar para supabase/migrations (a tranca recusa): SQL em docs/propostas/stripe-duas-contas/aplicadas. Buraco da tranca: nao ve deploys por npx -y supabase@2; publicar com a funcao de shell supabase(). Provas no e2e_log fluxo stripe-empresa-2026-11-01 ids 6139 em diante.
