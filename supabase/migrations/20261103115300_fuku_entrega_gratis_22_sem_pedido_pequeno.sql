-- JÁ APLICADA EM PRODUÇÃO pela Claude.ai por MCP a 03/11/2026 ~11:53 (missão boom-hamburguer-mes,
-- autorização do Danilo de 03/11 11:51: "Eu autorizo 1, 2 e o 3."). Espelho no repo; não voltar a correr.
-- Fuku Sushi: entrega grátis a partir de 22 € e sem taxa de pedido pequeno. Preços dos produtos,
-- serviço (0,99) e saco (0,30) ficam como estavam. Backup: bkp_restaurants_fuku_20261103.
-- Orçamento do servidor a 2 km (T10): 1 caixa 15,18 €; 2 caixas 24,07 € (entrega 0); 3 caixas 35,46 €.
update public.restaurants
   set free_delivery_min_cents = 2200,
       small_order_fee_cents_override = 0
 where id = 'fuku-sushi-guarda';
