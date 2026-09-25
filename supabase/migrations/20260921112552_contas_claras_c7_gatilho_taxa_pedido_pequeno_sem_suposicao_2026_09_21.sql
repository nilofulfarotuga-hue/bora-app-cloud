-- 2026-09-21 — CONTAS CLARAS · Bloco C7 · o gatilho da taxa de pedido pequeno deixa de assumir.
-- AUTORIZADO pelo Danilo a 21/09 ("VAI": cobrar o que o carrinho já mostra e já está configurado).
--
-- O QUE MEXE E PORQUÊ: fn_small_order_fee (gatilho orders_aa_small_order_fee, BEFORE INSERT em orders).
--   Até aqui gravava small_order_fee mas só somava a price a DIFERENÇA entre a taxa da loja e a global,
--   partindo do princípio de que a global já vinha em price. Não vinha: a função que cria o pedido nunca a
--   somou (só a função do quote, o ecrã do carrinho, a somava). Resultado: o cliente via 1,39 no
--   checkout e o pedido nascia sem ela — 5 pedidos entregues desde 27/08 (6,95 EUR), e nos PARCEIROS
--   nunca era cobrada porque não passam pelo fecho da compra (is_purchase_finalized = false).
--
-- REGRA NOVA, sem suposições: quem insere DECLARA em NEW.small_order_fee o que já pôs em price (o
--   default da coluna é 0 = "não pus nada"). O gatilho calcula a taxa devida (a da loja; a global quando o
--   pedido chega já pago com intent) e soma a price/final_total/payment_buffer_total só o que FALTA:
--   devida − declarada. Assim:
--     · a função de hoje, que não declara nada → o gatilho soma a taxa inteira (fecha o buraco já);
--     · a função corrigida (PROPOSTA irmã, zona vermelha), que soma a global e a declara → o gatilho só
--       acrescenta a diferença da loja — sem dupla contagem, seja qual for a ordem em que as duas entram.
--
-- O QUE NÃO MEXE: o valor da taxa (139) e o mínimo (1500) continuam em platform_settings; os 5 pedidos
--   antigos ficam como estão; total e customer_total são colunas geradas a partir de price e seguem-no.

CREATE OR REPLACE FUNCTION public.fn_small_order_fee()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_global     NUMERIC;
  v_real       NUMERIC;
  v_declarada  NUMERIC;
  v_delta      NUMERIC;
BEGIN
  v_global := public.small_order_fee_calc(NEW.service_type, NEW.subtotal, NULL);
  v_real   := public.small_order_fee_calc(NEW.service_type, NEW.subtotal, NEW.restaurant_id);

  -- Pago à cabeça (cartão/MB Way com intent já confirmado): o que foi cobrado levou a taxa GLOBAL
  -- (a do quote); não se muda o valor de um pagamento que já aconteceu.
  IF NEW.payment_status = 'paid' AND NEW.payment_intent_id IS NOT NULL THEN
    v_real := v_global;
  END IF;

  -- O que quem inseriu diz já ter posto em price. Sem declaração (default 0), entra a taxa inteira.
  v_declarada := COALESCE(NEW.small_order_fee, 0);
  NEW.small_order_fee := COALESCE(v_real, 0);

  v_delta := ROUND((COALESCE(v_real, 0) - v_declarada)::numeric, 2);
  IF v_delta = 0 THEN
    RETURN NEW;
  END IF;

  NEW.price := ROUND((COALESCE(NEW.price, 0) + v_delta)::numeric, 2);
  IF NEW.final_total IS NOT NULL THEN
    NEW.final_total := ROUND((NEW.final_total + v_delta)::numeric, 2);
  END IF;
  IF NEW.payment_buffer_total IS NOT NULL THEN
    NEW.payment_buffer_total := ROUND((NEW.payment_buffer_total + v_delta)::numeric, 2);
  END IF;

  RETURN NEW;
END;
$function$;
