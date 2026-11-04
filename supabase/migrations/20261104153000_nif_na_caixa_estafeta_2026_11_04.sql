-- 04/11/2026 15:18 — ordem do Danilo ("tem que arrumar isso urgente"), caso Ricardo/Auchan
-- (pedido c53b29ef): o cliente pediu fatura com NIF no checkout, mas o estafeta nunca viu o NIF.
-- Regra (análise fiscal de 03/11, ronda 2, e o Danilo hoje): em compra de loja NÃO-PARCEIRA e em
-- Favor com compra, o estafeta dá SEMPRE um NIF na caixa:
--   - o cliente pediu fatura  -> NIF do cliente (order_invoice_requests);
--   - não pediu               -> NIF da Bora (platform_settings.nif_compras_nao_parceiro);
--   - nunca "consumidor final".
-- Loja parceira: quem fatura é a loja (já vê o NIF no painel dela) -> não se aplica ao estafeta.
-- Não mexe em dinheiro: só mostra o NIF e regista se o estafeta o deu. Nunca trava a entrega.

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('nif_compras_nao_parceiro', to_jsonb('519686233'::text),
        'NIF que o estafeta dá na caixa nas compras de lojas não-parceiras e Favores quando o cliente NÃO pediu fatura com NIF (NIPC da Bora). Nunca "consumidor final".',
        'fiscal')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.order_nif_caixa (
  order_id        text PRIMARY KEY REFERENCES public.orders(id) ON DELETE CASCADE,
  nif             text NOT NULL,
  tipo            text NOT NULL CHECK (tipo IN ('cliente', 'bora')),
  dado            boolean NOT NULL,
  motivo          text,
  confirmado_por  uuid,
  confirmado_em   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT order_nif_caixa_motivo_ck CHECK (dado OR length(btrim(coalesce(motivo, ''))) > 0)
);
ALTER TABLE public.order_nif_caixa ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_nif_caixa_admin_select ON public.order_nif_caixa;
CREATE POLICY order_nif_caixa_admin_select ON public.order_nif_caixa
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE ALL ON public.order_nif_caixa FROM anon;

-- O estafeta do pedido (ou o admin) pode ver o NIF?
CREATE OR REPLACE FUNCTION public._nif_caixa_pode_ver(p_order_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT public.is_admin() OR EXISTS (
    SELECT 1 FROM public.orders o
     WHERE o.id = p_order_id
       AND (o.assigned_driver_id = auth.uid()::text
            OR o.current_driver_offer_id = auth.uid()::text
            OR o.helper_driver_id::text = auth.uid()::text
            OR EXISTS (SELECT 1 FROM public.drivers d
                        WHERE d.user_id = auth.uid() AND d.id::text = o.assigned_driver_id)));
$$;
REVOKE ALL ON FUNCTION public._nif_caixa_pode_ver(text) FROM PUBLIC, anon;

-- O NIF que o estafeta tem de dar na caixa neste pedido.
-- Devolve {aplica, nif, nome, tipo ('cliente'|'bora'), confirmado {dado, motivo, em}}.
CREATE OR REPLACE FUNCTION public.estafeta_nif_para_fatura(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o        record;
  v_parc   boolean;
  v_aplica boolean;
  r        record;
  c        record;
  v_bora   text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF NOT public._nif_caixa_pode_ver(p_order_id) THEN
    RAISE EXCEPTION 'PEDIDO_NAO_E_TEU' USING ERRCODE = '42501';
  END IF;

  SELECT id, service_type, order_type, is_partner_store, restaurant_id, errand_has_purchase
    INTO o FROM public.orders WHERE id = p_order_id;
  SELECT r2.is_partner INTO v_parc FROM public.restaurants r2 WHERE r2.id = o.restaurant_id;
  v_parc := COALESCE(v_parc, o.is_partner_store, false);

  v_aplica := (o.service_type IN ('restaurant', 'storeShopping') AND NOT v_parc)
           OR (o.order_type = 'errand' AND COALESCE(o.errand_has_purchase, false));
  IF NOT v_aplica THEN
    RETURN jsonb_build_object('aplica', false);
  END IF;

  SELECT nif, nome INTO r FROM public.order_invoice_requests WHERE order_id = p_order_id;
  SELECT dado, motivo, confirmado_em INTO c FROM public.order_nif_caixa WHERE order_id = p_order_id;
  v_bora := NULLIF(btrim(COALESCE(public.get_setting('nif_compras_nao_parceiro') #>> '{}', '')), '');

  RETURN jsonb_build_object(
    'aplica', true,
    'tipo',  CASE WHEN r.nif IS NOT NULL THEN 'cliente' ELSE 'bora' END,
    'nif',   COALESCE(r.nif, v_bora),
    'nome',  CASE WHEN r.nif IS NOT NULL THEN r.nome ELSE NULL END,
    'confirmado', CASE WHEN c.confirmado_em IS NULL THEN NULL
                       ELSE jsonb_build_object('dado', c.dado, 'motivo', c.motivo, 'em', c.confirmado_em) END
  );
END $$;
REVOKE ALL ON FUNCTION public.estafeta_nif_para_fatura(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_nif_para_fatura(text) TO authenticated;

-- O estafeta diz se deu o NIF na caixa. "Não dei" exige motivo e avisa o admin.
-- Nunca trava o talão nem a entrega.
CREATE OR REPLACE FUNCTION public.estafeta_confirmar_nif_caixa(p_order_id text, p_dado boolean, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_info  jsonb;
  v_mot   text := left(NULLIF(btrim(COALESCE(p_motivo, '')), ''), 300);
BEGIN
  v_info := public.estafeta_nif_para_fatura(p_order_id);
  IF NOT COALESCE((v_info->>'aplica')::boolean, false) THEN
    RETURN jsonb_build_object('ok', true, 'aplica', false);
  END IF;
  IF p_dado IS NULL THEN RAISE EXCEPTION 'DADO_EM_FALTA'; END IF;
  IF NOT p_dado AND v_mot IS NULL THEN RAISE EXCEPTION 'MOTIVO_EM_FALTA'; END IF;

  INSERT INTO public.order_nif_caixa (order_id, nif, tipo, dado, motivo, confirmado_por, confirmado_em)
  VALUES (p_order_id, v_info->>'nif', v_info->>'tipo', p_dado, CASE WHEN p_dado THEN NULL ELSE v_mot END, auth.uid(), now())
  ON CONFLICT (order_id) DO UPDATE
     SET nif = EXCLUDED.nif, tipo = EXCLUDED.tipo, dado = EXCLUDED.dado, motivo = EXCLUDED.motivo,
         confirmado_por = EXCLUDED.confirmado_por, confirmado_em = now();

  IF NOT p_dado THEN
    BEGIN
      PERFORM public.notify_admin_event(
        'nif_nao_dado_na_caixa', 'medium',
        'Estafeta não deu o NIF ' || CASE WHEN v_info->>'tipo' = 'cliente' THEN 'do cliente' ELSE 'da Bora' END
          || ' (' || COALESCE(v_info->>'nif', '?') || ') na caixa: ' || v_mot,
        'order', p_order_id,
        jsonb_build_object('nif', v_info->>'nif', 'tipo', v_info->>'tipo', 'motivo', v_mot),
        NULL);
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'notify_admin_event falhou: %', SQLERRM; END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'aplica', true, 'nif', v_info->>'nif', 'tipo', v_info->>'tipo', 'dado', p_dado);
END $$;
REVOKE ALL ON FUNCTION public.estafeta_confirmar_nif_caixa(text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_confirmar_nif_caixa(text, boolean, text) TO authenticated;

-- Painel: os pedidos que precisavam de NIF na caixa, com o NIF certo e se foi dado.
CREATE OR REPLACE FUNCTION public.admin_nif_caixa_listar(p_dias integer DEFAULT 30)
RETURNS TABLE (order_id text, criado_em timestamptz, loja text, cliente text, estado text,
               tipo text, nif text, dado boolean, motivo text, confirmado_em timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT o.id, o.created_at, COALESCE(o.vendor_name, CASE WHEN o.order_type = 'errand' THEN 'Favor' END),
         o.customer_name, o.status::text,
         CASE WHEN r.nif IS NOT NULL THEN 'cliente' ELSE 'bora' END,
         COALESCE(c.nif, r.nif, public.get_setting('nif_compras_nao_parceiro') #>> '{}'),
         c.dado, c.motivo, c.confirmado_em
    FROM public.orders o
    LEFT JOIN public.restaurants rs ON rs.id = o.restaurant_id
    LEFT JOIN public.order_invoice_requests r ON r.order_id = o.id
    LEFT JOIN public.order_nif_caixa c ON c.order_id = o.id
   WHERE o.created_at > now() - make_interval(days => GREATEST(1, LEAST(COALESCE(p_dias, 30), 366)))
     AND COALESCE(o.is_test_order, false) = false
     AND ((o.service_type IN ('restaurant', 'storeShopping') AND NOT COALESCE(rs.is_partner, o.is_partner_store, false))
          OR (o.order_type = 'errand' AND COALESCE(o.errand_has_purchase, false)))
   ORDER BY o.created_at DESC;
END $$;
REVOKE ALL ON FUNCTION public.admin_nif_caixa_listar(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_nif_caixa_listar(integer) TO authenticated;
