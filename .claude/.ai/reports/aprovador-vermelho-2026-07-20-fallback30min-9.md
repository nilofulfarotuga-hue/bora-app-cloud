---
tema: aprovador-vermelho · corrida: fallback30min-9 · data: 2026-07-20
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-20, corrida pedida por contexto "202+min parado")

## Estado no arranque da corrida
- `robot_suggestions WHERE status='nova'`: **1 item** (o mesmo de sempre) —
  `8ccc09bb-e5b7-458e-89f9-f179df67f942` · categoria `operacao_pedidos` · nivel 3 · severidade 5
  · titulo "Pedido preso sem atribuição" · evidência `order 7aa2e5f7-75d1-4ef4-b854-e69b2e6fa62b`
  · parado ~228min no momento da leitura inicial (criado 2026-07-20 08:07 UTC; a ordem-evidência
  em si criada 05:43:39 UTC, ou seja ~6h08m).
- Confirmado `platform_settings.aprovador_vermelho_auto_baldeA = true`.

## Triagem
- **Balde B (dispatch🔴, zona protegida)** — reatribuição/TTL de pedido preso toca `dispatch_engine`.
  Nunca auto-aprovado, nunca auto-aplicado. Esta era a **10ª reconfirmação** do mesmo item hoje
  (ver `admin_audit_log` ações `robot_suggestion_baldeB_reconfirmado` das 11:33/11:41/11:47/11:52).

## Resolução (encontrada A MEIO desta corrida — concorrência)
Entre a minha leitura inicial e a leitura de confirmação, o item mudou de `status='nova'` para
`status='rejeitada'` (reviewed_at 2026-07-20 11:56:14 UTC, reviewed_by NULL — provável escrita
directa/automação concorrente, não uma sessão de admin humano):

> motivo_rejeicao: "Pedido de teste do próprio Danilo (conta cliente c9fccf85), €30,10 em dinheiro
> nunca pago, parado em created desde 05:43 — não é cliente real. Sem ação necessária."

Esta é a explicação correta e definitiva: a ordem-evidência (`7aa2e5f7`) é um pedido de teste do
Danilo, pagamento cash NUNCA cobrado (`payment_status=pending`), não é cliente real — logo não há
dinheiro real em jogo nem cliente real prejudicado. **Balde B corretamente resolvido sem precisar
do "vai" do Danilo**, porque a resolução foi "não é ação nenhuma", não uma mudança de dispatch/$.

## Estado no fim da corrida
- `robot_suggestions WHERE status='nova'`: **0 itens**. Fila 🔴 vazia.
- Balde A promovidos nesta corrida: **0** (nada na fila para triar — resolvido antes por terceiros).
- Balde B deixados para o Danilo: **0** (o único Balde B foi fechado como "sem ação necessária",
  não uma aprovação de dinheiro).

## Atenção (não urgente, mas vale registar)
1. O mesmo item queimou **10 reconfirmações FALLBACK 30MIN** ao longo de ~6h antes de alguém
   identificar que era um pedido de teste do próprio Danilo. Sugestão de melhoria futura (NÃO
   aplicada agora — é só nota): filtrar pedidos de contas de teste conhecidas (`c9fccf85`) ou com
   `payment_status=pending` + cash nunca cobrado, da fila `operacao_pedidos:pedido-preso-sem-atribuicao`,
   para não gastar 10 ciclos no mesmo falso-alarme.
2. A rejeição final não tem uma entrada correspondente em `admin_audit_log` (ao contrário das 10
   reconfirmações anteriores, todas auditadas). Gap de rastreabilidade — não é urgente, só registo.

## Auto-Balde-A
`ligado` (`platform_settings.aprovador_vermelho_auto_baldeA=true`) — irrelevante nesta corrida
porque não havia nenhum item Balde A na fila.
