# PROPOSTA — cartão e MB Way na Casa & Manutenção (precisa de "autorizo" do Danilo)

Escrita a 31/10/2026 (missão retoma-geral-2026-10-31, bloco 1). Nada disto foi construído nem
publicado. Hoje a Casa aceita só dinheiro em mão: o servidor recusa cartão e MB Way com o código
`pagamento_cartao_indisponivel` (`casa_criar_pedido`, `casa_aceitar_orcamento`, `casa_responder_extra`)
e `casa_config().pagamento_cartao` devolve sempre `false`.

## O que se propõe (decisão 3 do Danilo de 30/10: retido até o cliente confirmar ou 24 h)

Copiar o caminho que já está provado na Limpeza, sem tocar em nada que já existe:

1. Edge Function própria `casa-checkout`, espelho de `supabase/functions/cleaning-checkout`
   (isolada, `verify_jwt = true`, sem mexer no `stripe-webhook` nem no `create-payment-intent`), com as
   mesmas ações: `create` (cartão, com cartão guardado), `create_mbway`, `mark_held`, `capture`,
   `reverse`. O valor vem SEMPRE do servidor (`casa_pedidos.total_cents`), nunca da app.
2. Estados do pedido que já existem na base: `aguarda_pagamento` → `procura` quando o pagamento fica
   retido (`payment_status = 'held'`); `_casa_confirmar` passa `held` → `released` (já faz isso hoje).
   O `casa_tick` já cancela `aguarda_pagamento` com mais de 30 minutos.
3. Extra com consentimento: cobrança do extra só depois de `casa_responder_extra(..., true)`, pelo
   mesmo caminho da Limpeza.
4. Reembolsos: o painel só marca `reembolso_pendente` (já construído). Devolver dinheiro continua a ser
   decisão do Danilo, pelo caminho manual de hoje.
5. Ligar só com uma chave nova de definições (nome a combinar com a tranca: a chave `casa_stripe_enabled`
   foi recusada a 30/10) e o "autorizo" datado.

## O que fica à espera
- "autorizo" do Danilo para construir e para ligar.
- Teste real de cartão e de MB Way (passo do Danilo, com dinheiro dele, regra dos testes de pagamento).
- Publicar nas 3 lojas junto com a categoria.
