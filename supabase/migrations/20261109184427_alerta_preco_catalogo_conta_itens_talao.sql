-- 20261109184427_alerta_preco_catalogo_conta_itens_talao: aplicada em produção a 09/11/2026 e escrita no repo a partir de
-- supabase_migrations.schema_migrations.statements (missão pendencias-2026-11-09).
-- 09/11/2026 (pedido da Dona Isabel, Continente b2261d50; Danilo: "Sim, eu autorizo" 18:44):
-- o aviso "Preco desatualizado" comparava o talao com a lista ORIGINAL do pedido. Quando o
-- estafeta acrescenta produtos a pedido do cliente ou marca "Nao ha", o aviso dizia que o
-- preco estava errado (2,64 EUR) quando estava certo (4 centimos). Agora compara o talao com
-- o que foi MESMO comprado (comprados ao preco de balcao do catalogo + substituidos +
-- acrescentados, sem os que faltaram). O gatilho passa a correr no fim da transacao
-- (deferred), depois de finalizar_talao_nao_parceiro gravar os itens.
CREATE OR REPLACE FUNCTION public._trg_alerta_preco_catalogo_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order         RECORD;
  v_talao_cents   integer;
  v_cobrado_cents integer;
  v_base_cents    integer;
  v_gap           integer;
  v_produtos      text;
  v_markup        numeric;
  v_n_itens       integer := 0;
  v_peso_cents    integer := 0;
BEGIN
  v_talao_cents := COALESCE(NEW.reimbursement_amount_cents, NEW.driver_typed_total_cents);
  IF v_talao_cents IS NULL OR v_talao_cents <= 0 THEN RETURN NEW; END IF;

  SELECT o.* INTO v_order FROM public.orders o WHERE o.id = NEW.order_id::text;
  IF NOT FOUND THEN RETURN NEW; END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN RETURN NEW; END IF;

  SELECT COALESCE((SELECT (value #>> '{}')::numeric FROM public.platform_settings WHERE key = 'non_partner_markup_pct'), 0.15)
    INTO v_markup;
  IF v_markup IS NULL OR v_markup < 0 OR v_markup > 1 THEN v_markup := 0.15; END IF;

  SELECT count(*) INTO v_n_itens FROM public.order_purchase_items_v2 WHERE order_id = v_order.id;

  IF v_n_itens > 0 THEN
    SELECT
      COALESCE(SUM(CASE
        WHEN pi.status IN ('purchased','pending') THEN
          COALESCE(ROUND(b.base * 100)::int, ROUND(pi.original_price_cents / (1 + v_markup))::int)
            * COALESCE(pi.original_qty, 1)
        WHEN pi.status = 'replaced' THEN
          COALESCE(pi.actual_price_cents, pi.original_price_cents, 0) * COALESCE(pi.actual_qty, pi.original_qty, 1)
        WHEN pi.status = 'added' THEN
          COALESCE(pi.actual_price_cents, 0) * COALESCE(pi.actual_qty, 1)
        ELSE 0 END), 0)::int,
      COALESCE(SUM(CASE
        WHEN pi.status IN ('purchased','pending') THEN COALESCE(pi.original_price_cents, 0) * COALESCE(pi.original_qty, 1)
        WHEN pi.status = 'replaced' THEN COALESCE(pi.actual_price_cents, pi.original_price_cents, 0) * COALESCE(pi.actual_qty, pi.original_qty, 1)
        WHEN pi.status = 'added' THEN ROUND(COALESCE(pi.actual_price_cents, 0) * COALESCE(pi.actual_qty, 1) * (1 + v_markup))::int
        ELSE 0 END), 0)::int,
      string_agg(CASE WHEN pi.status <> 'unavailable'
                      THEN COALESCE(pi.actual_name, pi.original_name) ||
                           CASE WHEN pi.status = 'added' THEN ' (acrescentado)' ELSE '' END
                 END, ', ')
      INTO v_base_cents, v_cobrado_cents, v_produtos
      FROM public.order_purchase_items_v2 pi
      LEFT JOIN LATERAL (
        SELECT NULLIF(i->>'basePrice', '')::numeric AS base
          FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb)) i
         WHERE i->>'name' = pi.original_name
         LIMIT 1
      ) b ON true
     WHERE pi.order_id = v_order.id;

    SELECT COALESCE(SUM(COALESCE(a.real_base_cents, 0) - COALESCE(a.est_base_cents, 0)), 0)::int
      INTO v_peso_cents
      FROM public.order_weight_adjustments a
     WHERE a.order_id = v_order.id
       AND COALESCE(a.settled_via, '') <> 'ignorado_nao_ha';
    v_base_cents := v_base_cents + v_peso_cents;
  ELSE
    v_cobrado_cents := ROUND(COALESCE(v_order.subtotal, 0)::numeric * 100)::int;
    SELECT COALESCE(ROUND(SUM(COALESCE(NULLIF(i->>'basePrice','')::numeric,
                                       NULLIF(i->>'price','')::numeric / (1 + v_markup))
                              * COALESCE(NULLIF(i->>'quantity','')::numeric, 1)) * 100)::int, 0),
           string_agg(i->>'name', ', ')
      INTO v_base_cents, v_produtos
      FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb)) i;
    IF COALESCE(v_base_cents, 0) <= 0 THEN
      v_base_cents := ROUND(COALESCE(v_order.subtotal, 0)::numeric * 100 / (1 + v_markup))::int;
    END IF;
  END IF;

  v_gap := v_talao_cents - v_base_cents;

  UPDATE public.orders SET catalog_price_gap_cents = v_gap WHERE id = v_order.id;

  IF v_gap >= 20 THEN
    PERFORM public.notify_admin_event(
      'catalog_price_gap',
      CASE WHEN v_gap >= 200 THEN 'high' ELSE 'medium' END,
      'Preco desatualizado em ' || COALESCE(v_order.vendor_name, 'loja') ||
        ': na loja custou ' || to_char(v_talao_cents/100.0, 'FM990.00') ||
        ' EUR, o app tinha ' || to_char(v_base_cents/100.0, 'FM990.00') ||
        ' EUR ao balcao para o que foi comprado (diferenca ' || to_char(v_gap/100.0, 'FM990.00') ||
        ' EUR). Cliente pagou ' || to_char(v_cobrado_cents/100.0, 'FM990.00') ||
        ' EUR pelos produtos. Produtos: ' || COALESCE(v_produtos, 'n/d'),
      'order',
      v_order.id,
      jsonb_build_object(
        'order_id', v_order.id,
        'vendor_name', v_order.vendor_name,
        'talao_cents', v_talao_cents,
        'preco_base_app_cents', v_base_cents,
        'cobrado_cliente_cents', v_cobrado_cents,
        'gap_cents', v_gap,
        'itens_do_talao', v_n_itens,
        'produtos', COALESCE(v_produtos, '')
      ),
      '/admin/orders/' || v_order.id
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_alerta_preco_catalogo ON public.order_receipts_v2;
CREATE CONSTRAINT TRIGGER trg_alerta_preco_catalogo
  AFTER INSERT OR UPDATE OF driver_typed_total_cents, reimbursement_amount_cents
  ON public.order_receipts_v2
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public._trg_alerta_preco_catalogo_fn();
