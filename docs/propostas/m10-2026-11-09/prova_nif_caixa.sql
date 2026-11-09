-- ============================================================================
-- PROVA EM ROLLBACK — supabase/migrations/20261109010000_m10_nif_na_caixa.sql
-- M10 b2-nif (09/11/2026). Corre a migração INTEIRA e as provas dentro de UM só bloco DO; o
-- RAISE EXCEPTION 'PROVA_OK ...' do fim desfaz tudo (funções, tabela, setting, respostas, avisos,
-- auditoria) e a mensagem do erro é a prova. Nada fica escrito na base.
-- Os pedidos escolhem-se por SELECT (o mais recente de cada tipo); nenhum dado pessoal aqui:
-- a saída mostra só os 8 primeiros caracteres de cada pedido e nunca o NIF de um cliente.
-- Correr pelo MCP execute_sql (projeto ojykpzwqrtusfeakzrna). Gerado a partir da migração:
-- se a migração mudar, gerar outra vez (corpo da migração entre os marcadores).
-- ============================================================================
DO $prova$
DECLARE
  t_out jsonb := '{}'::jsonb;
  t_r   jsonb;
  t_n   bigint; t_n2 bigint; t_n3 bigint; t_n4 bigint;
  t_np  text; t_np_drv  text;
  t_npf text; t_npf_drv text;
  t_par text; t_par_drv text;
  t_fav text; t_fav_drv text;
  t_fsc text; t_fsc_drv text;
  t_adm uuid;
BEGIN
  -- >>> MIGRAÇÃO (cópia literal de 20261109010000_m10_nif_na_caixa.sql) >>>
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
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.order_nif_caixa FROM authenticated;
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
  -- <<< FIM DA MIGRAÇÃO <<<

  -- ==========================================================================
  -- PROVAS (tudo dentro deste bloco; o RAISE do fim desfaz a migração e as provas)
  -- ==========================================================================
  -- Pedidos reais escolhidos por SELECT (nada de dados pessoais neste ficheiro).
  SELECT o.id, o.assigned_driver_id INTO t_np, t_np_drv FROM public.orders o
   WHERE o.status = 'delivered' AND o.order_type = 'nonPartnerPurchase'
     AND NOT COALESCE(o.is_test_order, false)
     AND NOT EXISTS (SELECT 1 FROM public.order_invoice_requests i WHERE i.order_id = o.id)
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id::text = o.assigned_driver_id)
   ORDER BY o.created_at DESC LIMIT 1;
  SELECT o.id, o.assigned_driver_id INTO t_npf, t_npf_drv FROM public.orders o
   WHERE o.status = 'delivered' AND o.order_type = 'nonPartnerPurchase'
     AND EXISTS (SELECT 1 FROM public.order_invoice_requests i WHERE i.order_id = o.id AND btrim(COALESCE(i.nif, '')) <> '')
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id::text = o.assigned_driver_id)
   ORDER BY o.created_at DESC LIMIT 1;
  SELECT o.id, o.assigned_driver_id INTO t_par, t_par_drv FROM public.orders o
   WHERE o.status = 'delivered' AND o.order_type = 'partnerRestaurant'
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id::text = o.assigned_driver_id)
   ORDER BY o.created_at DESC LIMIT 1;
  SELECT o.id, o.assigned_driver_id INTO t_fav, t_fav_drv FROM public.orders o
   WHERE o.status = 'delivered' AND o.service_type = 'errand' AND o.errand_has_purchase
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id::text = o.assigned_driver_id)
   ORDER BY o.created_at DESC LIMIT 1;
  SELECT o.id, o.assigned_driver_id INTO t_fsc, t_fsc_drv FROM public.orders o
   WHERE o.status = 'delivered' AND o.service_type = 'errand' AND NOT COALESCE(o.errand_has_purchase, false)
     AND EXISTS (SELECT 1 FROM auth.users u WHERE u.id::text = o.assigned_driver_id)
   ORDER BY o.created_at DESC LIMIT 1;
  SELECT u.id INTO t_adm FROM auth.users u
   WHERE COALESCE(u.raw_app_meta_data->>'role', '') = 'admin' ORDER BY u.created_at LIMIT 1;

  t_out := t_out || jsonb_build_object('pedidos', jsonb_build_object(
    'nao_parceiro_sem_fatura', left(t_np, 8), 'nao_parceiro_com_fatura', left(t_npf, 8),
    'parceiro', left(t_par, 8), 'favor_com_compra', left(t_fav, 8), 'favor_sem_compra', left(t_fsc, 8),
    'admin_encontrado', t_adm IS NOT NULL));

  -- Fechadas a anon; as internas fechadas também a authenticated.
  t_out := t_out || jsonb_build_object('grants', jsonb_build_object(
    'anon_driver_order_invoice_nif', has_function_privilege('anon', 'public.driver_order_invoice_nif(text)', 'execute'),
    'anon_estafeta_confirmar', has_function_privilege('anon', 'public.estafeta_confirmar_nif_caixa(text,boolean,text)', 'execute'),
    'anon_admin_listar', has_function_privilege('anon', 'public.admin_nif_caixa_listar(integer)', 'execute'),
    'anon_admin_nif_bora', has_function_privilege('anon', 'public.admin_nif_bora_definir(text)', 'execute'),
    'auth_regra_interna', has_function_privilege('authenticated', 'public._nif_caixa_regra(text)', 'execute'),
    'auth_nif_bora_interna', has_function_privilege('authenticated', 'public._nif_bora()', 'execute'),
    'auth_driver_order_invoice_nif', has_function_privilege('authenticated', 'public.driver_order_invoice_nif(text)', 'execute'),
    'auth_estafeta_confirmar', has_function_privilege('authenticated', 'public.estafeta_confirmar_nif_caixa(text,boolean,text)', 'execute'),
    'anon_tabela_select', has_table_privilege('anon', 'public.order_nif_caixa', 'select'),
    'auth_tabela_insert', has_table_privilege('authenticated', 'public.order_nif_caixa', 'insert'),
    'rls_ligada', (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.order_nif_caixa'::regclass),
    'setting', (SELECT value FROM public.platform_settings WHERE key = 'nif_compras_nao_parceiro'),
    'nif_bora_lido', public._nif_bora()));

  -- A partir daqui como a app: papel authenticated + JWT do estafeta do pedido.
  SET LOCAL ROLE authenticated;

  -- 1) não-parceiro sem fatura → NIF da Bora (do setting)
  PERFORM set_config('request.jwt.claim.sub', t_np_drv, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t_np_drv, 'role', 'authenticated')::text, true);
  t_r := public.driver_order_invoice_nif(t_np);
  t_out := t_out || jsonb_build_object('1_nao_parceiro_bora', jsonb_build_object(
    'ok', t_r->'ok', 'mostrar', t_r->'mostrar', 'tipo', t_r->'tipo', 'pediu_fatura', t_r->'pediu_fatura',
    'nif', t_r->'nif', 'confirmado', t_r->'confirmado'));

  -- 2) confirmar "Não consegui" sem motivo → MOTIVO_EM_FALTA
  BEGIN
    t_r := public.estafeta_confirmar_nif_caixa(t_np, false, '  ');
    t_out := t_out || jsonb_build_object('2_sem_motivo', t_r);
  EXCEPTION WHEN OTHERS THEN
    t_out := t_out || jsonb_build_object('2_sem_motivo', SQLERRM);
  END;

  -- 3) "Dei este NIF" → gravado; a função da app devolve confirmado.dado=true
  t_r := public.estafeta_confirmar_nif_caixa(t_np, true, NULL);
  t_out := t_out || jsonb_build_object('3_dei', t_r,
    '3_reler', public.driver_order_invoice_nif(t_np)->'confirmado'->'dado');

  -- 4) o estafeta não lê a tabela (RLS: só admin)
  SELECT count(*) INTO t_n FROM public.order_nif_caixa;
  t_out := t_out || jsonb_build_object('4_estafeta_le_tabela_linhas', t_n);

  -- 5) "Não consegui: Esqueci-me" → aviso ao admin uma vez (a 2.ª tentativa igual não repete)
  t_r := public.estafeta_confirmar_nif_caixa(t_np, false, 'Esqueci-me');
  t_r := public.estafeta_confirmar_nif_caixa(t_np, false, 'Esqueci-me');
  t_out := t_out || jsonb_build_object('5_nao_consegui', t_r);

  -- 6) não-parceiro com fatura → NIF do cliente (não se mostra o número, só que é válido)
  PERFORM set_config('request.jwt.claim.sub', t_npf_drv, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t_npf_drv, 'role', 'authenticated')::text, true);
  t_r := public.driver_order_invoice_nif(t_npf);
  t_out := t_out || jsonb_build_object('6_nao_parceiro_cliente', jsonb_build_object(
    'mostrar', t_r->'mostrar', 'tipo', t_r->'tipo', 'pediu_fatura', t_r->'pediu_fatura',
    'nif_valido', public.nif_pt_valido(t_r->>'nif'), 'nif_e_o_da_bora', (t_r->>'nif') = '519686233'));

  -- 7) loja parceira → não se mostra
  PERFORM set_config('request.jwt.claim.sub', t_par_drv, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t_par_drv, 'role', 'authenticated')::text, true);
  t_out := t_out || jsonb_build_object('7_parceiro', public.driver_order_invoice_nif(t_par));

  -- 8) Favor com compra → mostra; Favor sem compra → não
  PERFORM set_config('request.jwt.claim.sub', t_fav_drv, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t_fav_drv, 'role', 'authenticated')::text, true);
  t_r := public.driver_order_invoice_nif(t_fav);
  t_out := t_out || jsonb_build_object('8_favor_com_compra', jsonb_build_object(
    'mostrar', t_r->'mostrar', 'favor', t_r->'favor', 'tipo', t_r->'tipo'));
  PERFORM set_config('request.jwt.claim.sub', t_fsc_drv, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t_fsc_drv, 'role', 'authenticated')::text, true);
  t_out := t_out || jsonb_build_object('8_favor_sem_compra', public.driver_order_invoice_nif(t_fsc));

  -- 9) outra pessoa qualquer → não é o teu pedido (nem confirma)
  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated')::text, true);
  t_out := t_out || jsonb_build_object('9_outro_ve', public.driver_order_invoice_nif(t_np),
    '9_outro_confirma', public.estafeta_confirmar_nif_caixa(t_np, true, NULL));

  -- 10) quem não é admin não lista
  BEGIN
    SELECT count(*) INTO t_n FROM public.admin_nif_caixa_listar(30);
    t_out := t_out || jsonb_build_object('10_nao_admin_lista', t_n);
  EXCEPTION WHEN OTHERS THEN
    t_out := t_out || jsonb_build_object('10_nao_admin_lista', SQLERRM);
  END;

  -- 11) admin: lista, vê a resposta do estafeta, muda o NIF da Bora (inválido recusa)
  PERFORM set_config('request.jwt.claim.sub', t_adm::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', t_adm, 'role', 'authenticated')::text, true);
  SELECT count(*), count(*) FILTER (WHERE l.tipo = 'cliente'), count(*) FILTER (WHERE l.tipo = 'bora'),
         count(*) FILTER (WHERE l.dado IS NULL)
    INTO t_n, t_n2, t_n3, t_n4 FROM public.admin_nif_caixa_listar(366) l;
  t_out := t_out || jsonb_build_object('11_admin_lista_366d', jsonb_build_object(
    'linhas', t_n, 'do_cliente', t_n2, 'da_bora', t_n3, 'sem_resposta', t_n4,
    'pedido_1', (SELECT jsonb_build_object('dado', l.dado, 'motivo', l.motivo, 'tipo', l.tipo, 'nif', l.nif)
                   FROM public.admin_nif_caixa_listar(366) l WHERE l.order_id = t_np)));
  SELECT count(*) INTO t_n FROM public.order_nif_caixa;
  t_out := t_out || jsonb_build_object('11_admin_le_tabela_linhas', t_n);
  BEGIN
    t_r := public.admin_nif_bora_definir('123456788');
    t_out := t_out || jsonb_build_object('11_nif_invalido', t_r);
  EXCEPTION WHEN OTHERS THEN
    t_out := t_out || jsonb_build_object('11_nif_invalido', SQLERRM);
  END;
  -- (duas instruções: uma função STABLE vê a base como estava no início da instrução)
  t_out := t_out || jsonb_build_object('11_nif_novo', public.admin_nif_bora_definir('123 456 789'));
  t_out := t_out || jsonb_build_object('11_app_le_nif_novo', public.driver_order_invoice_nif(t_np)->'nif');

  RESET ROLE;
  t_out := t_out || jsonb_build_object(
    '12_talao_nif_usado', public._talao_nif_usado(t_np),
    '12_avisos_ao_admin', (SELECT count(*) FROM public.admin_notifications n
                            WHERE n.event_type = 'nif_nao_dado_na_caixa' AND n.entity_id = t_np),
    '12_auditoria', (SELECT count(*) FROM public.admin_audit_log a
                      WHERE a.action = 'nif_bora_compras_alterado' AND a.created_at > now() - interval '1 minute'));

  RAISE EXCEPTION 'PROVA_OK %', t_out::text;
END $prova$;

-- ============================================================================
-- SAÍDA LITERAL (09/11/2026, MCP execute_sql, projeto ojykpzwqrtusfeakzrna):
-- ERROR:  P0001: PROVA_OK {"3_dei": {"ok": true, "nif": "519686233", "dado": true, "tipo": "bora", "aplica": true}, "grants": {"setting": "519686233", "rls_ligada": true, "nif_bora_lido": "519686233", "anon_admin_listar": false, "anon_tabela_select": false, "auth_regra_interna": false, "auth_tabela_insert": false, "anon_admin_nif_bora": false, "auth_nif_bora_interna": false, "anon_estafeta_confirmar": false, "auth_estafeta_confirmar": true, "anon_driver_order_invoice_nif": false, "auth_driver_order_invoice_nif": true}, "3_reler": true, "pedidos": {"parceiro": "078698ae", "admin_encontrado": true, "favor_com_compra": "eb617ebf", "favor_sem_compra": "c5eba567", "nao_parceiro_com_fatura": "c1e9495f", "nao_parceiro_sem_fatura": "7abb748d"}, "7_parceiro": {"ok": true, "motivo": null, "mostrar": false, "loja_parceira": true}, "9_outro_ve": {"ok": false, "error": "nao_e_o_teu_pedido"}, "11_nif_novo": {"ok": true, "nif": "123456789"}, "12_auditoria": 1, "2_sem_motivo": "MOTIVO_EM_FALTA", "5_nao_consegui": {"ok": true, "nif": "519686233", "dado": false, "tipo": "bora", "aplica": true}, "11_nif_invalido": "NIF_INVALIDO", "9_outro_confirma": {"ok": false, "error": "nao_e_o_teu_pedido"}, "10_nao_admin_lista": "SO_ADMIN", "11_app_le_nif_novo": "123456789", "12_avisos_ao_admin": 1, "12_talao_nif_usado": {"nif": "123456789", "origem": "bora"}, "8_favor_com_compra": {"tipo": "cliente", "favor": true, "mostrar": true}, "8_favor_sem_compra": {"ok": true, "motivo": "favor_sem_compra", "mostrar": false, "loja_parceira": false}, "11_admin_lista_366d": {"linhas": 66, "da_bora": 58, "pedido_1": {"nif": "519686233", "dado": false, "tipo": "bora", "motivo": "Esqueci-me"}, "do_cliente": 8, "sem_resposta": 65}, "1_nao_parceiro_bora": {"ok": true, "nif": "519686233", "tipo": "bora", "mostrar": true, "confirmado": null, "pediu_fatura": false}, "6_nao_parceiro_cliente": {"tipo": "cliente", "mostrar": true, "nif_valido": true, "pediu_fatura": true, "nif_e_o_da_bora": false}, "11_admin_le_tabela_linhas": 1, "4_estafeta_le_tabela_linhas": 0}
-- CONTEXT:  PL/pgSQL function inline_code_block line 389 at RAISE
-- Depois, a conferir que nada ficou (SELECT): tabela=null, funcoes_novas=0, setting=0,
-- driver_order_invoice_nif igual ao ar (c_bora constant)=true, _talao_nif_usado igual ao ar=true,
-- avisos nif_nao_dado_na_caixa=0, auditoria nif_bora_compras_alterado=0.
-- ============================================================================
