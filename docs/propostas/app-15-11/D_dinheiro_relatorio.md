# Letra D — dinheiro: só relatório (missão app-15-11, 15/11/2026)

Pedido da Claude.ai 11:55: "Dinheiro (21, 22, 23): só relatório com os ids, não mexer". Nada foi alterado.
Tudo lido por SELECT a 15/11/2026 ~12:50. Ids encurtados aos 8 primeiros caracteres.

## N.º 21 — cancelamentos a dinheiro que ficam "pagamento pendente"

29 pedidos com `status = cancelled`, `payment_method = cash` e `payment_status = pending`, desde 16/08/2026.
Os 15 mais recentes: abf43748, 379c09ec, e36096e8, 18aa96ed, c6908bfe, 07f28b1e, de321009, de07d3de,
4f155794, 6d275a92, 38c7533b, 077bea04, bf63a8de, 073f2543, 05a51dc1.
O abf43748 é o pedido real de 14/11 cancelado pelo sistema (`dispatch_max_total_with_drivers_exceeded`, varredura 9166 n.º 12).
O que falta decidir: que estado deve ficar num cancelamento a dinheiro feito pelo painel ou pelo sistema
(não houve cobrança: "cancelled"/"not_charged"?) e quem fica em `cancelled_by`. Mexe em estados de pagamento
de pedidos: só com o "autorizo".

## N.º 22 — achados críticos antigos do vigia de pagamentos e pagamentos a prestadores parados

Críticos por resolver (5):
- pago_sem_cobranca — 6c102c39 (desde 05/10), 0 €;
- pi_sem_entidade — a78990d1 (desde 03/10), 6,74 €;
- refund_prometido_sem_refund — e3a6cc36 (desde 16/08);
- vigia_parceiro_arcas — sabores-brasil (desde 20/09), 10,29 €;
- vigia_tvde_saldo — 4f61dd31 (desde 29/09), −11,57 €.

Pagamentos a prestadores parados (vigia_payout_parado, aviso): 8, total 142,96 € —
b744f4c6 15,90 €; e530243b 21,80 €; 59333081 19,80 €; 0d814273 10,90 €; 6cbbf6e7 12,95 €;
c5aca108 30,28 €; 2c171b9c 10,26 €; 496b083d 21,07 €.

## N.º 23 — limpezas a dinheiro presas em "cash_pending"

2: 30857d34 (31/10) e e7cc0ba4 (11/10). (A varredura 9166 dizia 19/10; o SELECT dá 11/10.)

## Quem decide

Tudo isto é dinheiro: precisa do "autorizo" do Danilo para cada correção (regra das zonas protegidas).
