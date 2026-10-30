---
id: memoria-claude-ai-digest-2026-10-30-gorjetas-claude-ai
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Digest 30/10 — gorjetas: taxa da Stripe e gorjeta junto da compra (Claude.ai)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-30-gorjetas-claude-ai`, origem `claude-ai`, atualizada em 2026-10-30T14:01:20.656881+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 30 gorjetas claude ai · memoria claude.ai · claude_ai_memoria

Digest da Claude.ai, 30/10/2026 ~14:00, para todos os motores.

O QUE O DANILO PERGUNTOU (13:11): de onde vinham 2 € de gorjeta na Stripe. Resposta: gorjeta 51d1b251 da cliente Elisabete Maria Silva na corrida TVDE b36ecbb4 (29/10, Rua João Pinto Ribeiro → Pingo Doce São Domingos, 5 €), paga por MB Way às 17:12 (pi_3UVwraGlT3R2jCYp1zJeYfd7), motorista = o próprio Danilo; taxa da Stripe 0,28 €. Contava nos ganhos da semana dele (26/10–01/11).

DECISÃO DO DANILO (13:40, opção 1): gorjeta paga DEPOIS (ecrã de avaliação, cartão/MB Way, pagamento à parte) → o prestador recebe a gorjeta menos a taxa exata da Stripe; gorjeta dada NO CARRINHO vai no mesmo pagamento da compra e fica inteira; dinheiro inteira; a Bora não ganha nada com gorjetas. Recusou percentagem fixa (10% não cobre; 15% não cobre gorjetas de 1 € e tira demais nas grandes). Autorização literal: "Eu quero a opção 1, descontar a taxa extra da Stripe. [...] Então já vai, faz bem arrumado aí, arruma tudo aí."

FEITO POR MCP (Claude.ai, ~13:55): migração gorjeta_paga_depois_desconta_taxa_stripe_2026_10_30 — coluna gerada tips.liquido_prestador_cents (moment='after' e cartão/MB Way: valor − stripe_fee_cents, ou estimativa 25 cêntimos + 1,5% se a taxa faltar; resto: valor inteiro); gorjetas_online_do_prestador (usada por compute_driver_settlement) e admin_tvde_acertos_por_tipo somam o líquido. Cópia em bkp_fn_gorjeta_liquida_20261030. Provado: 200 − 28 = 172; acerto da semana do Danilo 1,72.

ACHADOS (vão na missão): (1) a gorjeta do carrinho é cobrada à parte depois do pedido (2 cobranças, no MB Way 2 aprovações, 2 taxas fixas); (2) pedido cancelado não devolve a gorjeta paga por cartão/MB Way (nenhuma função de cancelamento toca em tips); (3) a taxa pode ficar null e o filtro de estado final impede de a gravar depois; (4) business_rules.md §4.5 ainda dizia 80% estafeta / 20% Bora (abril), superado.

MISSÃO: página prompt-gorjetas-taxa-2026-10-30, posta ~14:00 na sessão "Missão geral Bora 2026-10-28" (session_01HPEpVCfPzS9j8Nzb5E1fRc), que a aceitou e começou a ler. Antes disso a sessão estava parada há ~5 h numa pergunta da bora-tranca para enviar 2 documentos de 29/10 para o ramo de produção ([skip ci]); a Claude.ai respondeu Recusar (nada se publica sem ordem do Danilo) — esses documentos entram na publicação do fim de semana. Fluxo e2e_log gorjetas-taxa-2026-10-30. A app sai na publicação semanal (31/10–01/11), nas 3 plataformas.
