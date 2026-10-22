DO $rev$
DECLARE
  r jsonb := '{}'::jsonb;
  d jsonb := '{}'::jsonb;
  est jsonb := '{}'::jsonb;
  v_cw uuid := gen_random_uuid();
BEGIN
  -- REVISOR N3b (contexto limpo). Tudo desfeito no fim por RAISE EXCEPTION.
  -- Ajudante: UMA escrita como a API (authenticated / anon / service_role), desfeita logo (subtransação).
  CREATE FUNCTION pg_temp.rv_tenta(p_uid uuid, p_role text, p_sql text) RETURNS text
  LANGUAGE plpgsql AS $f$
  DECLARE n bigint; v text;
  BEGIN
    IF p_role = 'authenticated' THEN
      PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated')::text, true);
    ELSE
      PERFORM set_config('request.jwt.claim.sub', '', true);
      PERFORM set_config('request.jwt.claims', json_build_object('role',p_role)::text, true);
    END IF;
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I', p_role);
      IF p_sql ~* '(\yreturning\y|^\s*select\y)' THEN
        EXECUTE p_sql INTO v;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__PASSOU__ ' || coalesce(v, '(sem linha)');
      ELSE
        EXECUTE p_sql;
        GET DIAGNOSTICS n = ROW_COUNT;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__PASSOU__ (' || n || ')';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE '__PASSOU__%' THEN RETURN 'PASSOU' || substr(SQLERRM, 11); END IF;
      RETURN SQLSTATE || ' ' || left(SQLERRM, 120);
    END;
  END $f$;

  -- ===== Preparação (como servidor, para a auditoria de estafeta não ler "SQL direto") =====
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role','service_role')::text, true);
  UPDATE public.orders SET status = 'created', assigned_driver_id = NULL, driver_id = NULL, current_driver_offer_id = NULL,
         preassigned_driver_id = NULL, helper_driver_id = NULL, tried_driver_ids = '{}'
   WHERE id IN ('4a3bb2ca-4fad-40c6-897c-a8827c6c8754', 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03');
  UPDATE public.orders SET status = 'driverAccepted', assigned_driver_id = 'dede0000-0000-4000-8000-000000000002',
         driver_id = 'dede0000-0000-4000-8000-000000000001'
   WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49';
  INSERT INTO public.carwash_bookings
    SELECT (jsonb_populate_record(NULL::public.carwash_bookings, to_jsonb(b) || jsonb_build_object(
      'id', v_cw, 'client_user_id', '183a32cd-d570-447a-a86d-a86c2a6845d6', 'is_test_order', true,
      'status', 'scheduled', 'washer_id', '231e1c82-8f49-4d6c-bb30-349e91b6cc26', 'payment_status', 'cash_pending',
      'cancelled_at', NULL, 'cancelled_by', NULL, 'cancel_reason', NULL))).*
      FROM public.carwash_bookings b WHERE b.id = '03e96507-408f-471f-bc03-44eb193a08d0';

  -- ===== Migrações N3b (texto igual aos ficheiros) =====
-- N3b · P4 · lavagens: por escrita direta (API), o cliente e o lavador só mudam o que a app escreve.
-- Preparado na missão fechar-pendencias-2026-10-20 (d/pronto/P4_aplicar.sql, 21/10) e aplicado por
-- ordem do Danilo no prompt de 22/10 04:33, passo 3b ("fechar ... as colunas de dinheiro das lavagens
-- a quem não é admin ... aplicar"). Não muda preços, valores, políticas nem dados: só quem pode escrever.
--
-- Hoje a política carwash_bookings_update_own deixa o cliente e o lavador mudar QUALQUER coluna da sua
-- lavagem: estado, pagamento, ganho do lavador, total. A app só escreve uma coisa por escrita direta:
-- o cliente anexa a foto (carwash_store.dart:372, photos_client). Tudo o resto vai pelas funções do
-- servidor (create_carwash_booking, cancel_carwash_booking, carwash_confirm_completion, as do lavador e
-- as do admin) e pela Edge carwash-checkout (chave de serviço), que não passam por aqui.
-- Um gatilho que, numa escrita direta de quem não é admin, só deixa mudar photos_client (e updated_at).
--
-- A LEITURA das colunas de dinheiro (total, ganho do lavador, taxa Bora) continua aberta ao cliente e ao
-- lavador da própria lavagem: a app lê a linha inteira (carwash_store.dart:178/231, washer_store.dart:
-- 139/159, select()), por isso tirar a leitura de colunas parte as duas apps. Fica para uma ronda com
-- mudança na app (relatório da noite 21/10, PARA O DANILO).
CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_novo  jsonb;
  v_velho jsonb;
  v_quais text;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  v_novo  := to_jsonb(NEW) - 'photos_client' - 'updated_at';
  v_velho := to_jsonb(OLD) - 'photos_client' - 'updated_at';
  IF v_novo IS DISTINCT FROM v_velho THEN
    SELECT string_agg(n.key, ', ' ORDER BY n.key) INTO v_quais
      FROM jsonb_each(v_novo) n WHERE n.value IS DISTINCT FROM (v_velho -> n.key);
    RAISE EXCEPTION 'lavagem_so_pelo_servidor (%)', v_quais USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._lavagem_escrita_direta_guarda() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER a00_lavagem_escrita_direta_guarda
  BEFORE UPDATE ON public.carwash_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public._lavagem_escrita_direta_guarda();

-- N3b · o cliente não escreve a loja nem o estafeta do seu próprio pedido (22/10/2026).
-- Ordem do Danilo (prompt de 22/10 04:33, passo 3b): "impedir que o cliente escreva a loja ou o
-- estafeta no próprio pedido" — segurança, não mexe em preços nem em valores.
--
-- O buraco (RELATORIO-D.md, ronda 2, ponto 17): a política orders_update_client deixa o dono do
-- pedido mudar QUALQUER coluna pela API. O R2 (a00_pedido_cliente_guarda) já fechou estado,
-- pagamento e valor a cobrar; ficaram abertas as colunas que dizem de que loja é o pedido e que
-- estafeta o leva. Com elas, um cliente pode pôr no seu pedido um estafeta à escolha (ou uma
-- oferta para ele), tirar o pedido a uma loja, ou marcar um restaurante parceiro como não parceiro.
--
-- O que a app do cliente escreve em orders (lido no código a 22/10): nenhuma destas colunas.
--   * criar o pedido vai pela função create_order (corre como o dono dela, não passa aqui);
--   * as escritas diretas do cliente são fotos/recolha à porta (order_store.dart:1071), itens e
--     sacos (2961), estado (2995, já guardado pelo R2) e substituições (1967);
--   * assigned_driver_id/current_driver_offer_id/tried_driver_ids só os escreve o ESTAFETA ao
--     desistir (order_store.dart:1510) — não é o dono; se for o dono e o estafeta que aceitou
--     (histórico order_status_events, que o cliente não escreve), passa como no R2;
--   * a localização do estafeta (driver_lat/lng) é o estafeta (driver_store.dart:638): fica de fora.
-- Funções e Edges do servidor correm como o dono delas ou como service_role: não passam aqui.
-- Admin: passa. Não muda políticas, colunas nem dados.
--
-- No INSERT direto pela API (política orders_insert_client), o cliente também não pode nascer o
-- pedido já com estafeta. O nome a00_ corre antes de a_trg_pedido_demo_caixa_fechada, que põe o
-- estafeta demo nos pedidos das contas demo — esse continua a funcionar.

-- NULL = deixa; senão, a coluna que se recusa.
CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_recusa(o public.orders, n public.orders)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR o.user_id IS DISTINCT FROM v_uid THEN RETURN NULL; END IF;
  IF public.is_admin() THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.order_status_events e
              WHERE e.order_id = o.id AND e.to_status = 'driverAccepted' AND e.actor_uid = v_uid) THEN
    RETURN NULL;
  END IF;
  -- a loja
  IF n.restaurant_id      IS DISTINCT FROM o.restaurant_id      THEN RETURN 'restaurant_id'; END IF;
  IF n.is_partner_store   IS DISTINCT FROM o.is_partner_store   THEN RETURN 'is_partner_store'; END IF;
  IF n.vendor_name        IS DISTINCT FROM o.vendor_name        THEN RETURN 'vendor_name'; END IF;
  -- o estafeta e a escolha do estafeta
  IF n.assigned_driver_id      IS DISTINCT FROM o.assigned_driver_id      THEN RETURN 'assigned_driver_id'; END IF;
  IF n.driver_id               IS DISTINCT FROM o.driver_id               THEN RETURN 'driver_id'; END IF;
  IF n.current_driver_offer_id IS DISTINCT FROM o.current_driver_offer_id THEN RETURN 'current_driver_offer_id'; END IF;
  IF n.preassigned_driver_id   IS DISTINCT FROM o.preassigned_driver_id   THEN RETURN 'preassigned_driver_id'; END IF;
  IF n.helper_driver_id        IS DISTINCT FROM o.helper_driver_id        THEN RETURN 'helper_driver_id'; END IF;
  IF n.tried_driver_ids        IS DISTINCT FROM o.tried_driver_ids        THEN RETURN 'tried_driver_ids'; END IF;
  IF n.driver_offer_expires_at IS DISTINCT FROM o.driver_offer_expires_at THEN RETURN 'driver_offer_expires_at'; END IF;
  IF n.driver_offer_history    IS DISTINCT FROM o.driver_offer_history    THEN RETURN 'driver_offer_history'; END IF;
  RETURN NULL;
END;
$function$;

-- SECURITY INVOKER de propósito: current_user diz se a escrita veio direta da API.
CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_guarda()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_motivo text;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF public.is_admin() THEN RETURN NEW; END IF;
    v_motivo := CASE
      WHEN NEW.assigned_driver_id      IS NOT NULL THEN 'assigned_driver_id'
      WHEN NEW.driver_id               IS NOT NULL THEN 'driver_id'
      WHEN NEW.current_driver_offer_id IS NOT NULL THEN 'current_driver_offer_id'
      WHEN NEW.preassigned_driver_id   IS NOT NULL THEN 'preassigned_driver_id'
      WHEN NEW.helper_driver_id        IS NOT NULL THEN 'helper_driver_id'
    END;
  ELSE
    v_motivo := public._pedido_cliente_loja_estafeta_recusa(OLD, NEW);
  END IF;
  IF v_motivo IS NOT NULL THEN
    RAISE EXCEPTION 'pedido_loja_estafeta_so_pelo_servidor (%)', v_motivo USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._pedido_cliente_loja_estafeta_guarda() FROM PUBLIC, anon, authenticated;
-- o gatilho corre como quem escreve: o cliente com sessão tem de poder chamar a função de decisão
GRANT EXECUTE ON FUNCTION public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders) TO authenticated;

CREATE OR REPLACE TRIGGER a00_pedido_loja_estafeta_guarda_upd
  BEFORE UPDATE OF restaurant_id, is_partner_store, vendor_name,
                   assigned_driver_id, driver_id, current_driver_offer_id, preassigned_driver_id,
                   helper_driver_id, tried_driver_ids, driver_offer_expires_at, driver_offer_history
  ON public.orders
  FOR EACH ROW
  WHEN (NEW.restaurant_id IS DISTINCT FROM OLD.restaurant_id
        OR NEW.is_partner_store IS DISTINCT FROM OLD.is_partner_store
        OR NEW.vendor_name IS DISTINCT FROM OLD.vendor_name
        OR NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id
        OR NEW.driver_id IS DISTINCT FROM OLD.driver_id
        OR NEW.current_driver_offer_id IS DISTINCT FROM OLD.current_driver_offer_id
        OR NEW.preassigned_driver_id IS DISTINCT FROM OLD.preassigned_driver_id
        OR NEW.helper_driver_id IS DISTINCT FROM OLD.helper_driver_id
        OR NEW.tried_driver_ids IS DISTINCT FROM OLD.tried_driver_ids
        OR NEW.driver_offer_expires_at IS DISTINCT FROM OLD.driver_offer_expires_at
        OR NEW.driver_offer_history IS DISTINCT FROM OLD.driver_offer_history)
  EXECUTE FUNCTION public._pedido_cliente_loja_estafeta_guarda();

CREATE OR REPLACE TRIGGER a00_pedido_loja_estafeta_guarda_ins
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  WHEN (NEW.assigned_driver_id IS NOT NULL OR NEW.driver_id IS NOT NULL
        OR NEW.current_driver_offer_id IS NOT NULL OR NEW.preassigned_driver_id IS NOT NULL
        OR NEW.helper_driver_id IS NOT NULL)
  EXECUTE FUNCTION public._pedido_cliente_loja_estafeta_guarda();

  -- ===== Estrutura depois de aplicar =====
  est := jsonb_build_object(
    'md5_prosrc', (SELECT jsonb_object_agg(proname, md5(prosrc)) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('_lavagem_escrita_direta_guarda','_pedido_cliente_loja_estafeta_recusa','_pedido_cliente_loja_estafeta_guarda')),
    'secdef', (SELECT jsonb_object_agg(proname, prosecdef) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('_lavagem_escrita_direta_guarda','_pedido_cliente_loja_estafeta_recusa','_pedido_cliente_loja_estafeta_guarda')),
    'exec_recusa_auth', has_function_privilege('authenticated', 'public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders)', 'EXECUTE'),
    'exec_recusa_anon', has_function_privilege('anon', 'public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders)', 'EXECUTE'),
    'exec_isadmin_auth', has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE'),
    'orders_before_insert_ordem', (SELECT jsonb_agg(tgname ORDER BY tgname COLLATE "C") FROM (SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.orders'::regclass
        AND NOT tgisinternal AND (tgtype & 2) = 2 AND (tgtype & 4) = 4 ORDER BY tgname COLLATE "C" LIMIT 4) x),
    'orders_before_update_ordem', (SELECT jsonb_agg(tgname ORDER BY tgname COLLATE "C") FROM (SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.orders'::regclass
        AND NOT tgisinternal AND (tgtype & 2) = 2 AND (tgtype & 16) = 16 ORDER BY tgname COLLATE "C" LIMIT 3) x),
    'cw_before_update_ordem', (SELECT jsonb_agg(tgname ORDER BY tgname COLLATE "C") FROM pg_trigger WHERE tgrelid = 'public.carwash_bookings'::regclass
        AND NOT tgisinternal AND (tgtype & 2) = 2 AND (tgtype & 16) = 16));

  -- ===== Pedidos: o dono (A = demo@bora.app) no 4a3bb2ca (created, mercado não parceiro) =====
  r := r || jsonb_build_object('t01_dono_muda_coordenadas_da_recolha', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET pickup_lat = 38.7, pickup_lng = -9.1 WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  r := r || jsonb_build_object('t02_dono_muda_telefone_do_estafeta', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET driver_phone = '910000000' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  r := r || jsonb_build_object('t03_dono_transicao_permitida_mais_estafeta', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET status = 'preparing', assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  r := r || jsonb_build_object('t04_dono_mexe_historico_de_ofertas', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET driver_offer_history = '[{"x":1}]'::jsonb WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  r := r || jsonb_build_object('t06_anon_poe_estafeta', pg_temp.rv_tenta(NULL, 'anon',
    $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  -- quem NÃO é o dono (fora do âmbito da ordem, para registo)
  r := r || jsonb_build_object('t07_estafeta_nao_dono_muda_loja_f18', pg_temp.rv_tenta('dede0000-0000-4000-8000-000000000001', 'authenticated',
    $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'$$));
  r := r || jsonb_build_object('t08_parceiro_nao_dono_poe_estafeta_ec05', pg_temp.rv_tenta('033e0fef-1a93-4c1b-b738-18572a936285', 'authenticated',
    $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'$$));

  -- ===== Pedidos: INSERT direto pela API (política orders_insert_client) =====
  r := r || jsonb_build_object('t09a_T_cria_com_tried_driver_ids_mercado', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, restaurant_id, vendor_name, is_partner_store, price, payment_method, is_test_order, tried_driver_ids)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'storeShopping', 'continente-guarda', 'Continente', false, 500, 'cash', true, '{dede0000-0000-4000-8000-000000000002}')$$));
  r := r || jsonb_build_object('t09b_T_cria_com_tried_driver_ids_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}')
      RETURNING status || ' tried=' || tried_driver_ids::text$$));
  r := r || jsonb_build_object('t10a_demo_cria_sem_estafeta_mercado', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, restaurant_id, vendor_name, is_partner_store, price, payment_method, is_test_order)
      VALUES ('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'created', 'storeShopping', 'continente-guarda', 'Continente', false, 500, 'cash', true)$$));
  r := r || jsonb_build_object('t10b_demo_cria_sem_estafeta_pacote', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
      VALUES ('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'created', 'sendPackage', 10, 'cash', true)
      RETURNING status || ' drv=' || coalesce(assigned_driver_id, '-') || '/' || coalesce(driver_id::text, '-')$$));
  r := r || jsonb_build_object('t11_T_cria_com_estafeta_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, assigned_driver_id)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002')
      RETURNING status$$));
  r := r || jsonb_build_object('t12_T_cria_sem_estafeta_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true)
      RETURNING status$$));
  r := r || jsonb_build_object('t13_T_cria_com_oferta_expira_e_historico_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, driver_offer_expires_at, driver_offer_history)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, now() + interval '1 hour', '[{"x":1}]'::jsonb)
      RETURNING status || ' exp=' || driver_offer_expires_at::text$$));

  -- ===== Lavagens (lavagem de prova: cliente T, lavador W) =====
  r := r || jsonb_build_object('c01_cliente_escolhe_lavador_da_oferta', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$UPDATE public.carwash_bookings SET offer_washer_id = '231e1c82-8f49-4d6c-bb30-349e91b6cc26' WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('c02_cliente_foto_mais_nota', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = '[]'::jsonb, rating = 5 WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('c03_lavador_troca_foto_do_cliente', pg_temp.rv_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('c04_cliente_so_updated_at', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$UPDATE public.carwash_bookings SET updated_at = now() WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('c05_cliente_LE_ganho_e_taxa', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$SELECT 'total=' || total_cents || ' ganho_lavador=' || washer_earnings_cents || ' taxa_bora=' || bora_fee_cents FROM public.carwash_bookings WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('c06_lavador_LE_taxa_bora', pg_temp.rv_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'authenticated',
    format($$SELECT 'total=' || total_cents || ' taxa_bora=' || bora_fee_cents FROM public.carwash_bookings WHERE id = %L$$, v_cw)));

  -- ===== Defeitos plantados do revisor (o teste tem de mudar de resultado) =====
  DROP TRIGGER a00_pedido_loja_estafeta_guarda_upd ON public.orders;
  d := d || jsonb_build_object('dA_sem_gatilho_upd_t03', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET status = 'preparing', assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda() RETURNS trigger LANGUAGE plpgsql AS $d$ BEGIN RETURN NEW; END $d$;
  d := d || jsonb_build_object('dB_guarda_lavagem_vazia_c01', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$UPDATE public.carwash_bookings SET offer_washer_id = '231e1c82-8f49-4d6c-bb30-349e91b6cc26' WHERE id = %L$$, v_cw)));

  RAISE EXCEPTION 'RESULT %', jsonb_build_object('estrutura', est, 'testes', r, 'defeitos_revisor', d)::text;
END
$rev$;
