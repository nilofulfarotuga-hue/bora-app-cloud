-- Bloco C7 (21/09, 10h45–11h35 UTC) — a taxa de pedido pequeno passa a ser COBRADA (autorizado pelo Danilo: "VAI").
-- O QUE MEXI: fn_small_order_fee (gatilho orders_aa_small_order_fee) — migration 20260921112552 (aplicada).
--   Regra nova: quem insere declara em NEW.small_order_fee o que já pôs em price (default 0 = nada); o gatilho soma
--   a price/final_total/payment_buffer_total só o que falta (devida − declarada). Sem suposições, sem dupla contagem.
-- O QUE NÃO MEXI (Trava): a função que cria o pedido (zona vermelha) — PROPOSTA completa em
--   supabase/migrations/20260921112223_PROPOSTA_contas_claras_c7_pedido_nasce_com_taxa_pedido_pequeno.sql e em
--   platform_settings.staged_contas_claras_20260921_c7 (sha256 26903075…, 32030 chars), com o "vai" registado.
-- Valor da taxa (139) e mínimo (1500): intocados. Os 5 pedidos antigos: intocados.

-- A) ANTES DE APLICAR — gatilho novo montado sob nome temporário numa transacção (original desligado só lá dentro),
--    5 INSERTs directos em orders, tudo desfeito (DO + RAISE):
--    1 parceiro<min (Goola 9,22, price 12,48):   price 13,87 · final 13,87 · buffer 13,87 · taxa 1,39 · customer_total 13,87
--    2 não-parceiro<min cash (Wells 4,23, 7,82): price 9,21 · final 9,21 · buffer 8,99→10,38 · taxa 1,39
--    3 acima do mínimo (Wells 21,15, 24,74):    price 24,74 · final 24,74 · buffer 28,45 · taxa 0,00   (nada muda)
--    4 taxa JÁ declarada (price 13,87 + small_order_fee 1,39 — o que a função corrigida fará): 13,87/13,87/13,87/1,39 (delta 0, sem dupla contagem)
--    5 pago com intent, sem declarar: 12,48 → 13,87 (entra a global, que é o que o quote cobrou)
--    Depois do rollback: 0 linhas prova, gatilho original ligado ('O'), função/gatilho temporários inexistentes.

-- B) ANTES DE APLICAR — fotografia do estado real, ponta-a-ponta pela função que cria o pedido (JWT demo@bora.app, rollback):
--    Goola Bowl 9,22 MB Way: quote customer_total 13,87 / buffer 13,87 / taxa 1,39 || linha price 12,48 final 12,48 buffer 12,48 taxa 1,39 || JSON price 12,48
--    Wells 1×3,68 cash:       quote 9,21 / 10,59 / 1,39                             || linha 7,82 / 7,82 / 8,99 / 1,39 || JSON price 7,82
--    (o cliente via 13,87 e 9,21; o pedido nascia com 12,48 e 7,82)

-- C) DEPOIS DE APLICAR — a mesma prova, rollback:
--    1 Goola parceiro<min: linha price 13,87 (= quote ✓) · final 13,87 · buffer 13,87 (= quote) · taxa 1,39 · customer_total 13,87 · is_partner_store true
--      → UM PEDIDO DE PARCEIRO PASSA A COBRAR A TAXA (não passa pelo fecho da compra e mesmo assim nasce com ela).
--    2 Wells<min cash:     linha price 9,21 (= quote ✓) · final 9,21 · taxa 1,39 · buffer 10,38 (quote 10,59: faltam os 15 % do
--      tampão sobre a taxa — só a função que cria o pedido os põe; fecha com a PROPOSTA. O que o cliente paga é price/final_total.)
--    3 Wells acima do min: subtotal 21,15 · price 24,74 (= quote ✓) · taxa 0,00 → nada muda.
--    Depois do rollback: 0 pedidos "Prova C7", 0 pedidos nos últimos 15 min.

-- D) O número que o cliente vê = price: no pagamento a app mostra a taxa do quote_order_pricing e o total = pricing local + taxa;
--    provado servidor-a-servidor que price = quote.customer_total ao cêntimo nos 3 casos. Sem divergência de um cêntimo.

-- E) O que a PROPOSTA (zona vermelha) ainda fecha, e enquanto não entra: tecto da carteira e charge_total/estado de pagamento
--    calculados sem a taxa (só afecta quem paga TUDO com a carteira: ficaria "paid" com a taxa por cobrar); JSON devolvido à
--    app com price antigo até ao refresh; tampão MB Way/cartão dos não-parceiros 0,21 abaixo do quote. Cartão pelo caminho novo
--    (create-payment-intent modo B) cobra o tampão do QUOTE (com taxa) e o pedido nasce do intent já pago → gatilho põe a global.
