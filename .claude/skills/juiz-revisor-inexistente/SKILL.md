---
name: juiz-revisor-inexistente
description: >
  Usa quando for chamar o agente 'juiz-revisor' e o Agent tool devolver "Agent type 'juiz-revisor' not found" (visto 2x em 2 sessões/2 dias, 15-17/10/2026). Não repetir a chamada: usa um revisor com contexto limpo que exista.
metadata:
  versao: 1.0
  criada: 2026-10-17
  criada_por: vigia-habilidades (corrida 2026-10-17_2330)
  tema: "Agente 'juiz-revisor' não encontrado"
  origem_literal:
  execucoes: 0
  sucessos: 0
  falhas: 0
---

# juiz-revisor-inexistente

> Criada pelo vigia a 17/10/2026 porque o Danilo disse: 

# juiz-revisor não existe como tipo de agente

Erro visto: `Agent type 'juiz-revisor' not found` (2 sessões, 2 dias).

Os documentos pedem o juiz-revisor, mas não é um tipo de agente registado.

## O que fazer
1. Não repitas a chamada.
2. Faz o papel de maker/checker com um agente que existe (ex.: `general-purpose`, `Explore`, `checkout-fixer`, `e2e-test-builder`), em contexto limpo, com o código e sem a tua conclusão, a pedir para tentar derrubar o trabalho.
3. Se a zona for vermelha (dinheiro, dispatch, RLS), não delegues; propõe com `cortex_propor`.
4. Regista no relatório que o juiz-revisor não existe, para o Danilo/Claude.ai poderem criá-lo.
