---
id: memoria-claude-ai-prompt-publica-e-fecha-2026-10-29-adendo-3
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Adendo 3 (29/10 19:08): escolha do reembolso bem clara para o cliente na app

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-publica-e-fecha-2026-10-29-adendo-3`, origem `claude-ai`, atualizada em 2026-10-29T18:45:10.711799+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt publica e fecha 2026 10 29 adendo 3 · memoria claude.ai · claude_ai_memoria

ADENDO 3 ao prompt-publica-e-fecha-2026-10-29 (Claude.ai, 29/10 19:08). Ordem literal do Danilo (18:34): "isso daí é só se o cliente quiser nessa opção, o reembolso. Vai ter que aparecer para ele bem claro: você quer na carteira Bora, que aí você já pode utilizar do jeito que você quiser na mesma hora, ou você quer o reembolso para a sua conta."

Entra no BLOCO B como (k), app do cliente (PT-PT), ecrã de cancelamento de pedido pago (MB Way ou cartão): quando há dinheiro a devolver, o cliente ESCOLHE sempre, com duas opções grandes e claras, nenhuma pré-selecionada por defeito escondido:
1) "Carteira Bora — fica já disponível, podes usar na mesma hora no próximo pedido" (refund_method = wallet, 100% em saldo);
2) "Devolver para a minha conta — MB Way (chega normalmente na hora) ou cartão (5 a 10 dias úteis)" (refund_method = stripe).
Mostra o valor que volta em cada opção (igual nas duas, sem 80/20) e, se o pedido usou tokens, a linha "Os teus N tokens voltam como tokens, com a mesma validade". Pedido a dinheiro ou ainda não pago: não mostra escolha (não há reembolso), só a taxa se houver. O botão Confirmar só ativa depois de escolher. Testes de widget para as duas escolhas e para o caso sem escolha. Painel admin: no detalhe do pedido mostrar a escolha feita pelo cliente. Regista 'B.2k-escolha-reembolso' no e2e_log. Isto é só o ECRÃ; a conta do servidor é a do pacote de reembolsos (Bloco D) e não se toca aqui.
