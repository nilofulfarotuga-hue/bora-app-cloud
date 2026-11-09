-- ============================================================================
-- M10 b2-nif (09/11/2026) — NIF na caixa, uma regra só.
-- Missão m10-noite-toda-sem-travas-2026-11-08, item 2.1. Junta as duas propostas:
--   * M1 08/11 (NO AR, versão 20261108234508): driver_order_invoice_nif(p_order_id) — a função
--     que a app chama (lib/widgets/driver_invoice_nif_card.dart). Tinha o NIF da Bora escrito no
--     código e não cobria o Favor com compra nem o ajudante (helper_driver_id).
--   * cd3adda6 de 04/11 (NUNCA aplicada): setting nif_compras_nao_parceiro, tabela
--     order_nif_caixa, estafeta_confirmar_nif_caixa, admin_nif_caixa_listar.
-- Regra (análise fiscal 03/11 + Danilo 04/11 e 08/11): em compra de loja NÃO-parceira e em Favor
-- com compra, o estafeta dá SEMPRE um NIF na caixa — o do cliente se pediu fatura, senão o da
-- Bora (setting). Nunca "consumidor final". Loja parceira: quem fatura é a loja.
-- A regra vive num sítio só: public._nif_caixa_regra(p_order_id). Todas as outras leem-na.
-- NÃO mexe em dinheiro, preços, pedidos nem no fecho do talão: só mostra o NIF e regista se o
-- estafeta o deu. Idempotente (pode correr duas vezes).
-- ============================================================================

-- 1) O NIF da Bora (editável no painel: "NIF nas compras") -----------------------------------
INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('nif_compras_nao_parceiro', to_jsonb('519686233'::text),
        'NIF que o estafeta dá na caixa nas compras de lojas não-parceiras e Favores com compra quando o cliente NÃO pediu fatura com NIF (NIPC da Bora). Nunca "consumidor final". Muda-se no painel, ecrã "NIF nas compras".',
        'fiscal')
ON CONFLICT (key) DO NOTHING;

-- O NIF da Bora a usar: o do setting se for um NIF português válido; senão o NIPC da empresa
-- (Danilo Fulfaro da Silva - Unipessoal Lda), para nunca ficar sem NIF na caixa.
CREATE OR REPLACE FUNCTION public._nif_bora()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT COALESCE(
    (SELECT d FROM (
       SELECT regexp_replace(COALESCE(s.value #>> '{}', ''), '\D', '', 'g') AS d
         FROM public.platform_settings s WHERE s.key = 'nif_compras_nao_parceiro') x
      WHERE public.nif_pt_valido(x.d)),
    '519686233');
$fn$;
REVOKE ALL ON FUNCTION public._nif_bora() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._nif_bora() TO service_role;

-- 2) A regra (sem verificação de quem pergunta — só para outras funções e o ocr-receipt) ------
-- Devolve {existe, aplica, ...}. Com aplica=true: {tipo 'cliente'|'bora', nif, nome, favor}.
CREATE OR REPLACE FUNCTION public._nif_caixa_regra(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  o       record;
  v_favor boolean;
  v_parc  boolean;
  v_pediu boolean := false;
  v_nif   text;
  v_nome  text;
BEGIN
  SELECT oo.id, oo.user_id, oo.service_type, oo.order_type, oo.is_partner_store,
         oo.errand_has_purchase, r.is_partner AS loja_e_parceira
    INTO o
    FROM public.orders oo
    LEFT JOIN public.restaurants r ON r.id = oo.restaurant_id
   WHERE oo.id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('existe', false, 'aplica', false);
  END IF;

  v_favor := COALESCE(o.service_type, '') = 'errand' OR COALESCE(o.order_type, '') = 'errand';
  -- A fotografia do pedido manda (is_partner_store); a loja só serve de recurso.
  v_parc := NOT v_favor AND COALESCE(o.is_partner_store, o.loja_e_parceira, false);

  IF v_parc THEN
    RETURN jsonb_build_object('existe', true, 'aplica', false, 'loja_parceira', true);
  END IF;
  IF v_favor AND NOT COALESCE(o.errand_has_purchase, false) THEN
    RETURN jsonb_build_object('existe', true, 'aplica', false, 'motivo', 'favor_sem_compra');
  END IF;
  IF NOT v_favor AND COALESCE(o.service_type, '') NOT IN ('restaurant', 'storeShopping') THEN
    RETURN jsonb_build_object('existe', true, 'aplica', false, 'motivo', 'sem_compra_na_loja');
  END IF;

  -- Cliente pediu fatura: o NIF do pedido; se o pedido veio sem NIF, o do perfil de faturação.
  SELECT true, NULLIF(btrim(COALESCE(i.nif, '')), ''), NULLIF(btrim(COALESCE(i.nome, '')), '')
    INTO v_pediu, v_nif, v_nome
    FROM public.order_invoice_requests i WHERE i.order_id = o.id;
  IF COALESCE(v_pediu, false) AND v_nif IS NULL THEN
    SELECT NULLIF(btrim(COALESCE(b.nif, '')), '') INTO v_nif
      FROM public.client_billing_profile b WHERE b.user_id = o.user_id;
  END IF;

  IF v_nif IS NOT NULL THEN
    RETURN jsonb_build_object('existe', true, 'aplica', true, 'favor', v_favor,
                              'tipo', 'cliente', 'nif', v_nif, 'nome', v_nome);
  END IF;
  RETURN jsonb_build_object('existe', true, 'aplica', true, 'favor', v_favor,
                            'tipo', 'bora', 'nif', public._nif_bora(), 'nome', NULL);
END $fn$;
REVOKE ALL ON FUNCTION public._nif_caixa_regra(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._nif_caixa_regra(text) TO service_role;

-- 3) O que o estafeta respondeu na caixa (só o admin lê) --------------------------------------
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
COMMENT ON TABLE public.order_nif_caixa IS
  'M10 09/11/2026: o NIF que o estafeta tinha de dar na caixa (loja não-parceira / Favor com compra) e se o deu. Escreve só estafeta_confirmar_nif_caixa; lê só o admin.';
ALTER TABLE public.order_nif_caixa ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_nif_caixa_admin_select ON public.order_nif_caixa;
CREATE POLICY order_nif_caixa_admin_select ON public.order_nif_caixa
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE ALL ON public.order_nif_caixa FROM anon;
REVOKE ALL ON public.order_nif_caixa FROM authenticated;  -- revisão M10: inclui MAINTAIN (Postgres 17)
GRANT SELECT ON public.order_nif_caixa TO authenticated;

-- 4) A função que a app chama (mesmo contrato da M1: ok, mostrar, pediu_fatura, nif, nome,
--    texto, loja_parceira) + tipo e confirmado. Agora com Favor com compra e o ajudante.
CREATE OR REPLACE FUNCTION public.driver_order_invoice_nif(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_uid  uuid := auth.uid();
  o      record;
  g      jsonb;
  c      record;
  v_conf jsonb;
  v_nif  text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  SELECT id, assigned_driver_id, current_driver_offer_id, helper_driver_id
    INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF NOT COALESCE((public.is_admin()
          OR o.assigned_driver_id = v_uid::text
          OR o.current_driver_offer_id = v_uid::text
          OR o.helper_driver_id = v_uid
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid)), false) THEN  -- NULL nunca deixa passar
    RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido');
  END IF;

  g := public._nif_caixa_regra(p_order_id);
  IF NOT COALESCE((g->>'aplica')::boolean, false) THEN
    RETURN jsonb_build_object('ok', true, 'mostrar', false,
                              'loja_parceira', COALESCE((g->>'loja_parceira')::boolean, false),
                              'motivo', g->>'motivo');
  END IF;

  SELECT nc.dado, nc.motivo, nc.confirmado_em INTO c
    FROM public.order_nif_caixa nc WHERE nc.order_id = p_order_id;
  v_conf := CASE WHEN c.confirmado_em IS NULL THEN NULL
                 ELSE jsonb_build_object('dado', c.dado, 'motivo', c.motivo, 'em', c.confirmado_em) END;
  v_nif := g->>'nif';

  IF g->>'tipo' = 'cliente' THEN
    RETURN jsonb_build_object('ok', true, 'mostrar', true, 'pediu_fatura', true, 'tipo', 'cliente',
      'nif', v_nif, 'nome', g->>'nome', 'favor', (g->>'favor')::boolean, 'confirmado', v_conf,
      'texto', 'Cliente pediu fatura com NIF ' || v_nif || ': pede ao balcão com este NIF');
  END IF;
  RETURN jsonb_build_object('ok', true, 'mostrar', true, 'pediu_fatura', false, 'tipo', 'bora',
    'nif', v_nif, 'favor', (g->>'favor')::boolean, 'confirmado', v_conf,
    'texto', 'Sem NIF do cliente → talão com o NIF da Bora ' || v_nif);
END $fn$;
REVOKE ALL ON FUNCTION public.driver_order_invoice_nif(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_order_invoice_nif(text) TO authenticated, service_role;

-- 5) O estafeta diz se deu o NIF na caixa. "Não consegui" exige motivo e avisa o admin.
--    A app chama-a em segundo plano (3 tentativas) e NUNCA trava o talão nem a entrega.
CREATE OR REPLACE FUNCTION public.estafeta_confirmar_nif_caixa(p_order_id text, p_dado boolean, p_motivo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_info  jsonb;
  v_mot   text := left(NULLIF(btrim(COALESCE(p_motivo, '')), ''), 300);
  v_antes record;
BEGIN
  -- Revisão M10: ver o cartão pode quem tem a oferta; RESPONDER à caixa só quem leva o pedido.
  IF NOT EXISTS (SELECT 1 FROM public.orders o
                  WHERE o.id = p_order_id
                    AND (public.is_admin()
                         OR o.assigned_driver_id = auth.uid()::text
                         OR o.helper_driver_id = auth.uid()
                         OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d
                                                      WHERE d.user_id = auth.uid()))) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido');
  END IF;
  v_info := public.driver_order_invoice_nif(p_order_id);
  IF NOT COALESCE((v_info->>'ok')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', v_info->>'error');
  END IF;
  IF NOT COALESCE((v_info->>'mostrar')::boolean, false) THEN
    RETURN jsonb_build_object('ok', true, 'aplica', false);
  END IF;
  IF p_dado IS NULL THEN RAISE EXCEPTION 'DADO_EM_FALTA' USING ERRCODE = '22023'; END IF;
  IF NOT p_dado AND v_mot IS NULL THEN RAISE EXCEPTION 'MOTIVO_EM_FALTA' USING ERRCODE = '22023'; END IF;

  SELECT nc.dado, nc.motivo INTO v_antes FROM public.order_nif_caixa nc WHERE nc.order_id = p_order_id;

  INSERT INTO public.order_nif_caixa (order_id, nif, tipo, dado, motivo, confirmado_por, confirmado_em)
  VALUES (p_order_id, v_info->>'nif', v_info->>'tipo', p_dado,
          CASE WHEN p_dado THEN NULL ELSE v_mot END, auth.uid(), now())
  ON CONFLICT (order_id) DO UPDATE
     SET nif = EXCLUDED.nif, tipo = EXCLUDED.tipo, dado = EXCLUDED.dado, motivo = EXCLUDED.motivo,
         confirmado_por = EXCLUDED.confirmado_por, confirmado_em = now();

  -- Avisa o admin uma vez (a 2.ª tentativa da app com a mesma resposta não repete o aviso).
  IF NOT p_dado AND (v_antes.dado IS DISTINCT FROM false OR v_antes.motivo IS DISTINCT FROM v_mot) THEN
    BEGIN
      PERFORM public.notify_admin_event(
        'nif_nao_dado_na_caixa', 'medium',
        'Estafeta não deu o NIF ' || CASE WHEN v_info->>'tipo' = 'cliente' THEN 'do cliente' ELSE 'da Bora' END
          || ' (' || COALESCE(v_info->>'nif', '?') || ') na caixa: ' || v_mot,
        'order', p_order_id,
        jsonb_build_object('nif', v_info->>'nif', 'tipo', v_info->>'tipo', 'motivo', v_mot),
        NULL);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notify_admin_event falhou: %', SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'aplica', true, 'nif', v_info->>'nif',
                            'tipo', v_info->>'tipo', 'dado', p_dado);
END $fn$;
REVOKE ALL ON FUNCTION public.estafeta_confirmar_nif_caixa(text, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_confirmar_nif_caixa(text, boolean, text) TO authenticated, service_role;

-- 6) Painel (ecrã "NIF nas compras"): os pedidos que precisavam de NIF na caixa ----------------
CREATE OR REPLACE FUNCTION public.admin_nif_caixa_listar(p_dias integer DEFAULT 30)
RETURNS TABLE (order_id text, criado_em timestamptz, loja text, cliente text, estado text,
               tipo text, nif text, dado boolean, motivo text, confirmado_em timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
#variable_conflict use_column
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT o.id, o.created_at,
         COALESCE(o.vendor_name, CASE WHEN (x.g->>'favor')::boolean THEN 'Favor' END),
         o.customer_name, o.status::text,
         COALESCE(c.tipo, x.g->>'tipo'),
         COALESCE(c.nif, x.g->>'nif'),
         c.dado, c.motivo, c.confirmado_em
    FROM public.orders o
    CROSS JOIN LATERAL (SELECT public._nif_caixa_regra(o.id) AS g) x
    LEFT JOIN public.order_nif_caixa c ON c.order_id = o.id
   WHERE o.created_at > now() - make_interval(days => GREATEST(1, LEAST(COALESCE(p_dias, 30), 366)))
     AND NOT COALESCE(o.is_test_order, false)
     AND (o.service_type IN ('restaurant', 'storeShopping', 'errand') OR o.order_type = 'errand')
     AND COALESCE((x.g->>'aplica')::boolean, false)
   ORDER BY o.created_at DESC;
END $fn$;
REVOKE ALL ON FUNCTION public.admin_nif_caixa_listar(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_nif_caixa_listar(integer) TO authenticated;

-- 7) Painel: mudar o NIF da Bora (valida o dígito de controlo e fica no log de auditoria) -----
CREATE OR REPLACE FUNCTION public.admin_nif_bora_definir(p_nif text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_nif   text := regexp_replace(COALESCE(p_nif, ''), '\D', '', 'g');
  v_antes jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  IF NOT public.nif_pt_valido(v_nif) THEN RAISE EXCEPTION 'NIF_INVALIDO' USING ERRCODE = '22023'; END IF;
  SELECT s.value INTO v_antes FROM public.platform_settings s WHERE s.key = 'nif_compras_nao_parceiro';
  INSERT INTO public.platform_settings (key, value, description, category, updated_at, updated_by)
  VALUES ('nif_compras_nao_parceiro', to_jsonb(v_nif),
          'NIF que o estafeta dá na caixa nas compras de lojas não-parceiras e Favores com compra quando o cliente NÃO pediu fatura com NIF (NIPC da Bora).',
          'fiscal', now(), auth.uid())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = auth.uid();
  PERFORM public.log_admin_action('nif_bora_compras_alterado'::text, 'platform_setting'::text,
    'nif_compras_nao_parceiro'::text, jsonb_build_object('antes', v_antes, 'depois', v_nif));
  RETURN jsonb_build_object('ok', true, 'nif', v_nif);
END $fn$;
REVOKE ALL ON FUNCTION public.admin_nif_bora_definir(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_nif_bora_definir(text) TO authenticated;

-- 8) Talões guardados (M1 07, no ar): o "NIF usado" passa a ler o mesmo NIF da Bora. Mesmo
--    corpo e mesma resposta; só sai o número escrito no código.
CREATE OR REPLACE FUNCTION public._talao_nif_usado(p_order_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT CASE
    WHEN COALESCE(o.is_partner_store, false) THEN jsonb_build_object('nif', NULL, 'origem', 'loja_parceira')
    WHEN i.order_id IS NOT NULL AND COALESCE(NULLIF(btrim(i.nif), ''), NULLIF(btrim(b.nif), '')) IS NOT NULL
      THEN jsonb_build_object('nif', COALESCE(NULLIF(btrim(i.nif), ''), NULLIF(btrim(b.nif), '')), 'origem', 'cliente')
    ELSE jsonb_build_object('nif', public._nif_bora(), 'origem', 'bora')
  END
  FROM public.orders o
  LEFT JOIN public.order_invoice_requests i ON i.order_id = o.id
  LEFT JOIN public.client_billing_profile b ON b.user_id = o.user_id
  WHERE o.id = p_order_id
$fn$;
REVOKE ALL ON FUNCTION public._talao_nif_usado(text) FROM PUBLIC, anon, authenticated;