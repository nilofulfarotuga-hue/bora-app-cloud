-- Favores (08/10/2026, pedido real 74dd4ecc da Cristina): o passo em que o estafeta está
-- não ficava gravado em lado nenhum. A coluna antiga `errand_leg` (migração 20260718004000)
-- tem outro significado (0=por-iniciar, 1=em-casa, 2=no-favor, 3=de-volta) e nunca foi
-- escrita por nenhuma app — fica como legado, com comentário. Nasce `errand_passo`:
--   0 = casa da cliente (só quando há paragem em casa)
--   1 = tratar do favor (ir ao local, comprar, talão)
--   2 = entrega à cliente
--
-- Quem escreve: o gatilho `trg_orders_errand_passo`, a cada mudança de estado que os botões do
-- estafeta fazem (recolha confirmada, talão fechado, a caminho, entregue). Assim vale para
-- qualquer caminho (folha do favor, botões do mapa, painel) sem depender da app.
-- O admin pode mudar o passo à mão (`admin_favor_mudar_passo`) e corrigir a morada da paragem
-- em casa (`admin_favor_editar_paragem`). Nenhuma destas peças mexe em valores do pedido.

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS errand_passo smallint;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'orders_errand_passo_check'
                    AND conrelid = 'public.orders'::regclass) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_errand_passo_check
      CHECK (errand_passo IS NULL OR errand_passo BETWEEN 0 AND 2);
  END IF;
END $$;

COMMENT ON COLUMN public.orders.errand_passo IS
  'Favor: passo atual do estafeta. 0=casa da cliente, 1=tratar do favor, 2=entrega. '
  'Escrito pelo gatilho trg_orders_errand_passo a cada mudança de estado; o admin muda à mão '
  'com admin_favor_mudar_passo. NULL = pedido antigo (a app deduz pelo estado).';

COMMENT ON COLUMN public.orders.errand_leg IS
  'LEGADO (18/07/2026): 0=por-iniciar, 1=em-casa, 2=no-favor, 3=de-volta. Nunca foi escrito por '
  'nenhuma app. Não usar: o passo do favor vive em errand_passo (08/10/2026).';

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
        CASE WHEN coalesce(NEW.errand_home_stop, false) THEN 0 ELSE 1 END
      -- pickedUp: saiu de casa da cliente. Se ainda há compra por fechar, vai tratar do favor;
      -- senão (sem compra, ou talão já fechado) segue para a entrega.
      WHEN 'pickedUp' THEN
        CASE WHEN coalesce(NEW.errand_has_purchase, false)
                  AND NOT coalesce(NEW.is_purchase_finalized, false) THEN 1 ELSE 2 END
      WHEN 'onTheWay'  THEN 2
      WHEN 'delivered' THEN 2
      ELSE NEW.errand_passo
    END;
  ELSIF coalesce(NEW.is_purchase_finalized, false)
        AND NOT coalesce(OLD.is_purchase_finalized, false) THEN
    -- Talão fechado: o que falta é a entrega.
    NEW.errand_passo := 2;
  ELSIF NEW.errand_home_stop IS DISTINCT FROM OLD.errand_home_stop
        AND NEW.status IN ('created', 'preparing', 'callingDriver', 'driverAccepted')
        AND coalesce(OLD.errand_passo, 0) <= 1 THEN
    -- Paragem em casa ligada/desligada antes de o estafeta lá ir.
    NEW.errand_passo := CASE WHEN coalesce(NEW.errand_home_stop, false) THEN 0 ELSE 1 END;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.fn_orders_errand_passo() FROM PUBLIC, anon;

CREATE OR REPLACE TRIGGER trg_orders_errand_passo
  BEFORE INSERT OR UPDATE OF status, is_purchase_finalized, errand_home_stop
  ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_errand_passo();

-- Painel admin: mudar o passo à mão (o estafeta ficou preso, carregou no botão errado, etc.).
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
  v_tipo text;
  v_old  smallint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_passo IS NULL OR p_passo NOT BETWEEN 0 AND 2 THEN
    RAISE EXCEPTION 'passo_invalido: %', p_passo USING ERRCODE = '22023';
  END IF;

  SELECT service_type, errand_passo INTO v_tipo, v_old
    FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;
  IF v_tipo IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'nao_e_favor: %', v_tipo USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders SET errand_passo = p_passo WHERE id = p_order_id;

  PERFORM public.log_admin_action(
    'favor_mudar_passo', 'order', p_order_id,
    jsonb_build_object('de', v_old, 'para', p_passo, 'motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id, 'errand_passo', p_passo);
END
$function$;

REVOKE ALL ON FUNCTION public.admin_favor_mudar_passo(text, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_mudar_passo(text, integer, text) TO authenticated;

-- Painel admin: corrigir a morada da paragem em casa (a app gravou-a vazia, a cliente mudou de
-- sítio...). Só mexe na morada e nas coordenadas: não liga nem desliga a paragem (isso mudaria
-- o valor do pedido).
CREATE OR REPLACE FUNCTION public.admin_favor_editar_paragem(
  p_order_id text,
  p_address  text,
  p_lat      double precision,
  p_lng      double precision,
  p_motivo   text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tipo  text;
  v_casa  boolean;
  v_antes text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF nullif(trim(coalesce(p_address, '')), '') IS NULL THEN
    RAISE EXCEPTION 'morada_vazia' USING ERRCODE = '22023';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'coordenadas_invalidas' USING ERRCODE = '22023';
  END IF;

  SELECT service_type, coalesce(errand_home_stop, false), errand_home_stop_address
    INTO v_tipo, v_casa, v_antes
    FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found: %', p_order_id USING ERRCODE = 'P0002';
  END IF;
  IF v_tipo IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'nao_e_favor: %', v_tipo USING ERRCODE = '22023';
  END IF;
  IF NOT v_casa THEN
    RAISE EXCEPTION 'sem_paragem_em_casa' USING ERRCODE = '22023';
  END IF;

  UPDATE public.orders SET
    errand_home_stop_address = trim(p_address),
    errand_home_stop_lat     = p_lat,
    errand_home_stop_lng     = p_lng
  WHERE id = p_order_id;

  PERFORM public.log_admin_action(
    'favor_editar_paragem', 'order', p_order_id,
    jsonb_build_object('antes', v_antes, 'depois', trim(p_address),
                       'lat', p_lat, 'lng', p_lng, 'motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id);
END
$function$;

REVOKE ALL ON FUNCTION public.admin_favor_editar_paragem(text, text, double precision, double precision, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_favor_editar_paragem(text, text, double precision, double precision, text) TO authenticated;
