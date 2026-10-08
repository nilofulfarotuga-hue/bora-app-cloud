-- Favores (08/10/2026, revisão de contexto limpo da migração 20261008220000):
--  1. Favor SEM compra e COM paragem em casa: a folha vai da recolha direta à
--     entrega (sem estado intermédio) e o passo saltava o local do favor — o
--     mapa e o "Navegar" nunca passavam por lá. Fica no passo 1 até entregue.
--  2. Reatribuído depois do talão fechado: voltava a 0/1 e a folha oferecia a
--     compra outra vez (segundo finalize_errand_purchase). Passa a 2.
--  3. admin_favor_mudar_passo: recusa saltos que deixam o estafeta preso —
--     passo 2 com talão por fechar, passo 0 sem paragem em casa.
-- Nada disto mexe em valores do pedido.

CREATE OR REPLACE FUNCTION public.fn_orders_errand_passo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF coalesce(NEW.service_type, '') <> 'errand' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.errand_passo IS NULL THEN
      NEW.errand_passo := CASE WHEN coalesce(NEW.errand_home_stop, false) THEN 0 ELSE 1 END;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.errand_passo := CASE NEW.status
      WHEN 'driverAccepted' THEN
        CASE
          WHEN coalesce(NEW.is_purchase_finalized, false) THEN 2
          WHEN coalesce(NEW.errand_home_stop, false) THEN 0
          ELSE 1
        END
      WHEN 'pickedUp' THEN
        CASE
          -- Saiu de casa / a caminho. Com compra: no favor até fechar o talão.
          -- Sem compra e com paragem em casa: no favor até entregar. Sem
          -- compra nem paragem: recolheu no local do favor e vai entregar.
          WHEN coalesce(NEW.errand_has_purchase, false)
            THEN CASE WHEN coalesce(NEW.is_purchase_finalized, false) THEN 2 ELSE 1 END
          WHEN coalesce(NEW.errand_home_stop, false) THEN 1
          ELSE 2
        END
      WHEN 'onTheWay' THEN
        CASE
          -- Saiu de casa / a caminho. Com compra: no favor até fechar o talão.
          -- Sem compra e com paragem em casa: no favor até entregar. Sem
          -- compra nem paragem: recolheu no local do favor e vai entregar.
          WHEN coalesce(NEW.errand_has_purchase, false)
            THEN CASE WHEN coalesce(NEW.is_purchase_finalized, false) THEN 2 ELSE 1 END
          WHEN coalesce(NEW.errand_home_stop, false) THEN 1
          ELSE 2
        END
      WHEN 'delivered' THEN 2
      ELSE NEW.errand_passo
    END;
  ELSIF coalesce(NEW.is_purchase_finalized, false)
        AND NOT coalesce(OLD.is_purchase_finalized, false) THEN
    NEW.errand_passo := 2;
  ELSIF NEW.errand_home_stop IS DISTINCT FROM OLD.errand_home_stop
        AND NEW.status IN ('created', 'preparing', 'callingDriver', 'driverAccepted')
        AND coalesce(OLD.errand_passo, 0) <= 1 THEN
    NEW.errand_passo := CASE WHEN coalesce(NEW.errand_home_stop, false) THEN 0 ELSE 1 END;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.fn_orders_errand_passo() FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.admin_favor_mudar_passo(
  p_order_id text,
  p_passo    integer,
  p_motivo   text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_passo IS NULL OR p_passo NOT BETWEEN 0 AND 2 THEN
    RAISE EXCEPTION 'passo_invalido: %', p_passo USING ERRCODE = '22023';
  END IF;

  SELECT service_type, errand_passo, coalesce(errand_home_stop, false) casa,
         coalesce(errand_has_purchase, false) compra,
         coalesce(is_purchase_finalized, false) talao
    INTO v
    FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;
  IF v.service_type IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'nao_e_favor: %', v.service_type USING ERRCODE = '22023';
  END IF;
  -- Saltos que deixariam o estafeta preso na folha do favor.
  IF p_passo = 0 AND NOT v.casa THEN
    RAISE EXCEPTION 'sem_paragem_em_casa' USING ERRCODE = '22023';
  END IF;
  IF p_passo = 2 AND v.compra AND NOT v.talao THEN
    RAISE EXCEPTION 'talao_por_fechar' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders SET errand_passo = p_passo WHERE id = p_order_id;

  PERFORM public.log_admin_action(
    'favor_mudar_passo', 'order', p_order_id,
    jsonb_build_object('de', v.errand_passo, 'para', p_passo, 'motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id, 'errand_passo', p_passo);
END
$function$;

REVOKE ALL ON FUNCTION public.admin_favor_mudar_passo(text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_mudar_passo(text, integer, text) TO authenticated;
