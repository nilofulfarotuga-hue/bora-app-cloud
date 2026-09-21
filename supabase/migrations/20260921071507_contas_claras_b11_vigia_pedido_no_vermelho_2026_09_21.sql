-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) — version 20260921071507 · contas_claras_b11_vigia_pedido_no_vermelho_2026_09_21.
-- Espelho exacto de supabase_migrations.schema_migrations, puxado por REST a 21/09/2026 (Claude Code, missão contas-claras-20260921).
-- CONTAS CLARAS B11 (21/09/2026)
-- O QUE ESTOU A CRIAR: gatilho novo public._trg_alerta_pedido_no_vermelho_fn em
-- public.orders, que dispara quando um pedido passa a 'delivered'.
--
-- PORQUE: a 14/09 o pedido Wells (197a6d93) fechou com a Bora a PERDER 1,82 EUR
-- — o cliente pagou 18,32, a mercadoria custou 14,73 e o estafeta levou 5,41.
-- O preco do catalogo estava desatualizado (12,81 quando na loja custava 14,63),
-- e os 15% de margem foram todos comidos pela diferenca. O alerta de preco
-- desatualizado (catalog_price_gap) chegou a disparar, mas ninguem avisa que o
-- PEDIDO em si ficou negativo. Passou despercebido ate hoje.
--
-- O QUE FAZ: so nos NAO-PARCEIROS, onde a conta e simples e completa
-- (o que o cliente pagou, menos a mercadoria, menos o estafeta). Se der
-- negativo ou zero, escreve um aviso ao admin com os numeros. NAO corrige
-- nada e NAO mexe em precos — so aponta.

CREATE OR REPLACE FUNCTION public._trg_alerta_pedido_no_vermelho_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente   numeric;
  v_mercado   numeric;
  v_estafeta  numeric;
  v_bora      numeric;
BEGIN
  IF COALESCE(NEW.is_partner_store, false) THEN RETURN NEW; END IF;

  v_cliente  := COALESCE(NEW.final_total, NEW.price, 0);
  IF v_cliente <= 0 THEN RETURN NEW; END IF;

  v_mercado  := COALESCE(public.order_driver_reimbursement(NEW.id), 0);
  v_estafeta := COALESCE(NEW.driver_earnings, 0);
  v_bora     := ROUND(v_cliente - v_mercado - v_estafeta, 2);

  IF v_bora > 0 THEN RETURN NEW; END IF;

  PERFORM public.notify_admin_event(
    'pedido_no_vermelho',
    CASE WHEN v_bora < 0 THEN 'high' ELSE 'medium' END,
    'Pedido em ' || COALESCE(NEW.vendor_name, 'loja nao-parceira') ||
      ' fechou sem lucro para a Bora: sobraram ' ||
      to_char(v_bora, 'FM990.00') || ' EUR. Cliente pagou ' ||
      to_char(v_cliente, 'FM990.00') || ', a mercadoria custou ' ||
      to_char(v_mercado, 'FM990.00') || ' e o estafeta levou ' ||
      to_char(v_estafeta, 'FM990.00') ||
      '. Ver se o preco do catalogo desta loja esta desatualizado.',
    'order',
    NEW.id,
    jsonb_build_object(
      'order_id', NEW.id,
      'vendor_name', NEW.vendor_name,
      'cliente_pagou', v_cliente,
      'mercadoria', v_mercado,
      'estafeta', v_estafeta,
      'sobrou_para_a_bora', v_bora,
      'catalog_price_gap_cents', NEW.catalog_price_gap_cents,
      'small_order_fee', NEW.small_order_fee),
    '/admin/orders/' || NEW.id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS orders_zz_alerta_no_vermelho ON public.orders;
CREATE TRIGGER orders_zz_alerta_no_vermelho
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
EXECUTE FUNCTION public._trg_alerta_pedido_no_vermelho_fn();
