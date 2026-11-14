---
name: ganho-motorista-numero-grande
description: "Usar ao mexer em ecrã, aviso ou notificação do motorista/estafeta que mostre euros: o ganho dele aparece em número grande. Regra de ouro do Danilo."
metadata:
  versao: 1.0
  criada: 2026-09-17
  criada_por: missão uma-porta (continuação) a partir da DECISÃO DA CLAUDE.AI (17/09/2026) na página habilidades-propostas
  origem: regra dita pelo Danilo a 20/08/2026 e aplicada pela ordem ordem-20260820213614-e205 (estado aprovada); a proposta do vigia contava "6 vezes" por erro de fonte (texto da ordem copiado por sessões automáticas) — corrigido
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# ganho-motorista-numero-grande

> Ativada com o texto exato da decisão da Claude.ai (página `habilidades-propostas`, 17/09/2026): "APROVADA COM CORREÇÃO. Ativar como skill global com o texto abaixo e não voltar a propor."

- Origem: regra dita pelo Danilo a 20/08, aplicada pela ordem e205 (agenda de reservas, cartão de oferta, diálogo de cobrança em dinheiro, avisos do notify-tvde-driver) e no push da fila de 14/09 ("Ganhas €x").
- Antes de mexer: o valor em destaque lê o campo de ganho do prestador (driverEarnCents no TVDE, ou o equivalente da vertical), nunca o valor cobrado ao cliente.
- O valor do cliente só em pequeno e só com pagamento em dinheiro; em cartão ou MB Way não aparece.
- É regra de mostrar, não de calcular: não mexe em preço, comissão, carteira nem acertos.
- Só se dá por feito com captura do ecrã real a mostrar os dois números (skill prova-fix-cenario-real).
