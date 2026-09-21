---
id: memoria-claude-ai-digest-2026-09-21-contas-claras-fecho
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-09-21
zona: verde
confianca: alta
estado: atual
---

# Claude Code 21/09 — contas claras, fecho (C0–C6)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-09-21-contas-claras-fecho`, origem `claude-code`, atualizada em 2026-09-21T09:53:26.436087+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 09 21 contas claras fecho · memoria claude.ai · claude_ai_memoria

O que funciona agora. Repo = servidor: as 7 migrations da Claude.ai (20260920235112 a 20260921071507) estão em supabase/migrations com a version exacta; 26 funções comparadas corpo a corpo, todas iguais (prova em .claude/.ai/provas/contas-claras-20260921/). Painel "Dinheiro e acertos" (migration 20260921090657): cada estafeta mostra o acerto vivo (corridas TVDE, ganhos das corridas, dinheiro em mão nas corridas, compras adiantadas) e avisa quando o recibo enviado difere; "Desfazer" passou a "Reabrir" — pede motivo escrito (mínimo 5 letras), grava em driver_weekly_settlements.notes e admin_audit_log (reabrir_acerto), só a semana em curso ou a última fechada (mais antigo diz "Travado"), o recibo da pessoa volta a pendente e a app pede o recálculo ao servidor (compute_driver_settlement, que já aceita o admin). Cartão "Avisos do fecho" com fecho_linha_travada_valor_diferente (audit) e pedido_no_vermelho (notificações, toca para abrir o pedido; rota /admin/orders/{id} criada). "Reenviar recibos" chama admin_resend_weekly_digest, que já manda force:true — provado a sério na semana 24–30/08 (só a linha do Danilo): HTTP 200, emails_sent 1. Extrato do estafeta na app (migration 20260921092110): as parcelas vêm da função única driver_settlement_parcelas (Entregas · Corridas · Compras que adiantou do bolso · Tokens convertidos · Dinheiro que recebeu em mão (devolve à Bora)), a mesma que o recibo por email usa; Valdemir provado ao cêntimo (17,00 = 17,00), Danilo 43,52 = 43,52. Taxa de pedido pequeno: visível no carrinho, no pagamento (valor do quote_order_pricing) e no detalhe — nada a corrigir na app. Publicação: push 0fb40500..6525bc6f; o CI corre o autoteste dos 3 perfis antes do build (run 35585546832, em curso às 09:51 UTC); flutter analyze 0 erros, flutter test 608/608, anti-trapaça limpo.
O que falta (só com o "vai" do Danilo, tudo reportado e não corrigido): (1) a taxa de pedido pequeno é mostrada mas create_order não a soma ao total — 6,95 EUR em 5 pedidos; nos parceiros nunca é cobrada (o fecho de 21/09 só apanha não-parceiros); proposta: create_order somar small_order_fee_calc como o quote faz. (2) Recibos do Valdemir e da Erika da semana 14–20/09 saíram às 01:20 com o HTML antigo (sem a linha Corridas); reenviar = "Reenviar recibos" na semana 13/09 (manda a todos, Goola incluída). (3) Conta do painel (c9fccf85 = nilofulfarotuga@gmail.com, admin + cliente) ganhou a 20/09 15:31 uma candidatura de estafeta acidental (drivers pending + user_roles driver) — sai pela fila de aprovação; public.users.email dela é NULL. A conta que trabalha é 4f61dd31 (boraappbora@gmail.com). Não fundir as duas (plano no relatório). (4) Vigia do vermelho para parceiros: fórmula proposta sobrou = total − order_financials.restaurant_amount − driver_earnings; nos 4 pedidos de parceiro nenhum vermelho (1,02–3,76). Relatório: RELATORIO-contas-claras-fecho-2026-09-21.md (raiz + Desktop\Bora\Projetos).
