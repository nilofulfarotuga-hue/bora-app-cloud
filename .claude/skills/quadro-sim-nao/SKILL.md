---
name: quadro-sim-nao
description: "Tudo o que espera por uma decisão do Danilo vai para o quadro Sim/Não do painel admin (/admin/caixa-guardados), não para o chat. Usar quando uma tarefa precisa do aprovar/rejeitar dele."
---

# Quadro Sim/Não — um sítio só para o que espera pelo Danilo

> Esqueleto criado a 14/11/2026 (missão `sistema-conteudo-14-11`, bloco 2-bis), a partir da
> ideia do "AR Board" (aprovar/rejeitar). Ainda **não está completo**: a migração
> `supabase/migrations/PROPOSTA_20261114_quadro_sim_nao_painel_admin.sql` espera ser aplicada
> pelo Claude.ai. Antes de usar, confirmar por SELECT que o estado `aprovado` já existe.

## Regra

- O Danilo não lê relatórios para achar o que tem de decidir. Cada decisão dele é **uma linha
  no quadro**, com título curto, o que acontece no Sim e o que acontece no Não.
- Onde vive: tabela `public.caixa_guardados` (ecrã "Caixa de guardados" do painel admin,
  rota `/admin/caixa-guardados`). O Sim cria a tarefa no `despacho` (origem `evento`,
  título com "(painel admin)"); o Não fecha a linha.
- Uma linha por decisão. Nada de "aprovas tudo?".
- Dinheiro (preços, comissões, Stripe, carteira) entra no quadro como pedido de "autorizo"
  com o valor e o âmbito escritos; o Sim no quadro **não** substitui o "autorizo" literal.

## Como pôr uma decisão no quadro

1. Ver se já há linha igual (não duplicar).
2. Inserir com o título, o resumo em português simples (para ouvir em voz alta) e o que o
   Sim faz. Nunca dados de clientes nem segredos.
3. No relatório da missão, apontar só "pus N decisões no quadro".

## Falta (por fazer)

- Aplicar a migração proposta e provar o Sim e o Não por SELECT.
- Aviso no Telegram (skill `falar-com-o-danilo`) quando entra uma linha nova.
