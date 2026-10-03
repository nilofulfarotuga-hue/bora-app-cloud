-- Bloco C4 (21/09, 09h50–10h05 UTC) — taxa de pedido pequeno: visível ao cliente? o estafeta cobra o mesmo?
-- Definições: platform_settings small_order_fee_cents=139, small_order_fee_enabled=true, min_order_cents=1500 (lidas no C0).

-- 1) o quote do servidor devolve a taxa e SOMA-A ao total do cliente (JWT do cliente demo por set_config)
--    Wells (não-parceiro), 1 produto a 3,68 puro: {"subtotal":4.23,"delivery_fee":2.50,"service_fee":0.99,"bag_fee":0.10,
--    "small_order_fee":1.39,"customer_total":9.21,"charge_total":9.21,"price":9.21}  → 4,23+2,50+0,99+0,10+1,39 = 9,21 ✓
--    Goola (parceiro), Goola Bowl 9,22: {"subtotal":9.22,"delivery_fee":2.50,"service_fee":0.46,"bag_fee":0.30,
--    "small_order_fee":1.39,"customer_total":13.87} → 13,87 ✓ (a taxa também se aplica a parceiros)

-- 2) app do cliente (fonte): a linha "Taxa de pedido pequeno" existe no carrinho (cart_screen.dart:400), no pagamento
--    (payment_method_screen.dart:460 — valor de cartStore.smallOrderFee, que prefere o small_order_fee do quote; o quote é
--    pedido no initState via _loadDebt) e no detalhe do pedido (order_details_screen.dart:1087, valor gravado em orders).
--    No carrinho, antes de haver moradas (o quote não pode ser chamado), mostra-se a estimativa local (espelho da regra
--    small_order_fee_calc com valores de platform_settings) e "Faltam X € para evitar a taxa de pedido pequeno".
--    Teste: test/contas_claras_c4_taxa_pedido_pequeno_visivel_test.dart 3/3.

-- 3) estafeta a dinheiro: OrderModel.totalToCollectCash = (cash_total_due ?? final_total ?? total) + dívida. Vem do servidor;
--    desde 21/09 07:12 (B10 da Claude.ai) finalize_storeshopping_purchase soma orders.small_order_fee a final_total/cash_total_due
--    (prova dela em rollback: Wells 197a6d93 18,32 → 19,71).

-- 4) ENCONTRADO FORA DO SCOPE (não corrigido — regra do Danilo e Lista Vermelha):
--    create_order (29 KB) e pricing_calculate NÃO mencionam small_order_fee; só quote_order_pricing a soma. O gatilho
--    fn_small_order_fee (BEFORE INSERT em orders) grava small_order_fee mas só ajusta price pela DIFERENÇA entre a taxa da loja e
--    a global — assume que a global já vem em price, e não vem. Resultado: o cliente vê a taxa no checkout e o pedido nasce
--    com total/price/customer_total SEM ela.
select left(id,8) id, created_at::date dia, payment_method, is_partner_store, small_order_fee, total, final_total, cash_total_due,
       round(total - (subtotal+delivery_fee+service_fee+bag_fee), 2) as sobra_no_total,
       (select total_paid from order_financials f where f.order_id::text = orders.id limit 1) as total_pago
from orders where coalesce(small_order_fee,0) > 0 and status = 'delivered' order by created_at desc;
-- SAÍDA (5 pedidos reais desde 27/08, todos entregues): 9cba3644 19/09 mbway não-parceiro McDonald's total 14,99 final 14,99 ·
--   e1078830 16/09 mbway PARCEIRO Goola total 16,16 final 16,16 total_pago 16,16 · 197a6d93 14/09 cash Wells total 18,32 cash_total_due 18,32 ·
--   ae711470 11/09 mbway PARCEIRO Goola 16,16/16,16 pago 16,16 · d30138fa 01/09 cash Auchan 11,73/11,73.
--   sobra_no_total = 0,00 em todos (a taxa não está no total); taxa_entrou_no_final = 0 em todos (anteriores ao fix de 21/09).
--   Soma mostrada e não cobrada: 5 × 1,39 = 6,95 EUR. Nos PARCEIROS não há finalize, logo o fix de 21/09 não os apanha:
--   continuam a mostrar 1,39 no checkout e a cobrar sem ela (MB Way cobra total_paid = 16,16; a dinheiro o estafeta cobra total).
--   Sentido do erro: o cliente paga MENOS do que viu (não é sobre-cobrança); quem perde é a Bora.
--   PROPOSTA (para a Claude.ai / "vai" do Danilo — mexe em create_order, zona vermelha): create_order passa a somar
--   small_order_fee_calc(service_type, subtotal, restaurant_id) a price/customer_total/payment_buffer_total tal como o quote faz,
--   e fn_small_order_fee deixa de assumir que a global já lá está (ou passa a somar a taxa inteira quando price ainda não a tem).
