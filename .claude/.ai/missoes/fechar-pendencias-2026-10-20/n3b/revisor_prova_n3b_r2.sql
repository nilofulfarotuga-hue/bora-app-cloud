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
-- Um gatilho que, numa escrita direta de quem não é admin, só deixa mudar photos_client (e updated_at),
-- e photos_client só pelo próprio cliente da lavagem (revisor N3b, achado 3: o lavador não troca as
-- fotos que o cliente tirou ao carro, que são a prova numa queixa).
--
-- A LEITURA das colunas de dinheiro (total, ganho do lavador, taxa Bora) continua aberta ao cliente e ao
-- lavador da própria lavagem: a app lê a linha inteira (carwash_store.dart:178/231, washer_store.dart:
-- 139/159, select()), por isso tirar a leitura de colunas parte as duas apps. Para a fechar é preciso
-- primeiro mudar a app (ler só as colunas de que cada um precisa), publicar nas 3 plataformas, e só
-- depois tirar a leitura na base. Escrito para o Danilo em
-- .claude/.ai/missoes/fechar-pendencias-2026-10-20/RELATORIO-N3b.md (secção PARA O DANILO).
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
  IF NEW.photos_client IS DISTINCT FROM OLD.photos_client
     AND auth.uid() IS DISTINCT FROM OLD.client_user_id THEN
    RAISE EXCEPTION 'lavagem_fotos_so_do_cliente' USING ERRCODE = '42501';
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
-- No INSERT direto pela API (política orders_insert_client, que nenhuma app usa), o cliente também
-- não pode nascer o pedido já com estafeta, oferta, estafetas excluídos (tried_driver_ids) ou
-- histórico de ofertas (revisor N3b, achado 1: driver_offer_history nasce '[]' por defeito).
-- O nome a00_ corre antes de a_trg_pedido_demo_caixa_fechada, que põe o estafeta demo nos pedidos
-- das contas demo — esse continua a funcionar.

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
      WHEN COALESCE(cardinality(NEW.tried_driver_ids), 0) > 0 THEN 'tried_driver_ids'
      WHEN NEW.driver_offer_expires_at IS NOT NULL THEN 'driver_offer_expires_at'
      WHEN COALESCE(NEW.driver_offer_history, '[]'::jsonb) <> '[]'::jsonb THEN 'driver_offer_history'
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
        OR NEW.helper_driver_id IS NOT NULL
        OR COALESCE(cardinality(NEW.tried_driver_ids), 0) > 0
        OR NEW.driver_offer_expires_at IS NOT NULL
        OR COALESCE(NEW.driver_offer_history, '[]'::jsonb) <> '[]'::jsonb)
  EXECUTE FUNCTION public._pedido_cliente_loja_estafeta_guarda();

  -- ===== Estrutura depois de aplicar (ronda 2) =====
  est := jsonb_build_object(
    'md5_prosrc', (SELECT jsonb_object_agg(proname, md5(prosrc)) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
                     AND proname IN ('_lavagem_escrita_direta_guarda','_pedido_cliente_loja_estafeta_recusa','_pedido_cliente_loja_estafeta_guarda')),
    'exec_recusa_auth', has_function_privilege('authenticated', 'public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders)', 'EXECUTE'),
    'exec_recusa_anon', has_function_privilege('anon', 'public._pedido_cliente_loja_estafeta_recusa(public.orders, public.orders)', 'EXECUTE'),
    'when_ins', (SELECT pg_get_triggerdef(oid) ~ 'cardinality' FROM pg_trigger WHERE tgname = 'a00_pedido_loja_estafeta_guarda_ins'));

  -- ===== Ataques da ronda 1 que passavam (têm de dar 42501) =====
  r := r || jsonb_build_object('t09b_T_cria_com_tried_driver_ids_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}')
      RETURNING status || ' tried=' || tried_driver_ids::text$$));
  r := r || jsonb_build_object('t13_T_cria_com_oferta_expira_e_historico_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, driver_offer_expires_at, driver_offer_history)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, now() + interval '1 hour', '[{"x":1}]'::jsonb)
      RETURNING status$$));
  r := r || jsonb_build_object('n2_T_cria_com_historico_json_null', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, driver_offer_history)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, 'null'::jsonb)
      RETURNING status$$));
  r := r || jsonb_build_object('n2b_T_cria_so_com_historico', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, driver_offer_history)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '[{"driver":"dede0000-0000-4000-8000-000000000002"}]'::jsonb)
      RETURNING status$$));
  r := r || jsonb_build_object('c03_lavador_troca_foto_do_cliente', pg_temp.rv_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('c03b_lavador_apaga_fotos_do_cliente', pg_temp.rv_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = NULL WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('t03_dono_transicao_permitida_mais_estafeta', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET status = 'preparing', assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  r := r || jsonb_build_object('c01_cliente_escolhe_lavador_da_oferta', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$UPDATE public.carwash_bookings SET offer_washer_id = '231e1c82-8f49-4d6c-bb30-349e91b6cc26' WHERE id = %L$$, v_cw)));

  -- ===== Legítimos (têm de passar) =====
  r := r || jsonb_build_object('L1_cliente_anexa_foto_como_a_app', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = '[{"angle":"","url":"prova-r2.jpg"}]'::jsonb WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('L2_lavador_escrita_sem_mudar_foto', pg_temp.rv_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'authenticated',
    format($$UPDATE public.carwash_bookings SET updated_at = now() WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('L3_admin_troca_foto', pg_temp.rv_tenta('c9fccf85-03ee-4efc-83bf-613f211a78ff', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = '[]'::jsonb WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('L4_servidor_troca_foto', pg_temp.rv_tenta(NULL, 'service_role',
    format($$UPDATE public.carwash_bookings SET photos_client = '[]'::jsonb WHERE id = %L$$, v_cw)));
  r := r || jsonb_build_object('L5_T_cria_sem_estafeta_pacote', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true)
      RETURNING status || ' tried=' || coalesce(tried_driver_ids::text, '-') || ' hist=' || coalesce(driver_offer_history::text, '-')$$));
  r := r || jsonb_build_object('L6_T_cria_com_lista_vazia', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids, driver_offer_history)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{}', '[]'::jsonb)
      RETURNING status$$));
  r := r || jsonb_build_object('L7_demo_cria_sem_estafeta_pacote', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
      VALUES ('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'created', 'sendPackage', 10, 'cash', true)
      RETURNING status || ' drv=' || coalesce(assigned_driver_id, '-') || '/' || coalesce(driver_id::text, '-')$$));
  r := r || jsonb_build_object('L8_servidor_cria_com_estafeta_e_lista', pg_temp.rv_tenta(NULL, 'service_role',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids, driver_offer_history)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}', '[{"x":1}]'::jsonb)
      RETURNING status$$));
  r := r || jsonb_build_object('L9_dono_muda_notas', pg_temp.rv_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'authenticated',
    $$UPDATE public.orders SET customer_notes = 'nota revisor r2' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));

  -- ===== Defeitos plantados do revisor (ronda 2) =====
  CREATE OR REPLACE TRIGGER a00_pedido_loja_estafeta_guarda_ins
    BEFORE INSERT ON public.orders FOR EACH ROW
    WHEN (NEW.assigned_driver_id IS NOT NULL OR NEW.driver_id IS NOT NULL
          OR NEW.current_driver_offer_id IS NOT NULL OR NEW.preassigned_driver_id IS NOT NULL
          OR NEW.helper_driver_id IS NOT NULL)
    EXECUTE FUNCTION public._pedido_cliente_loja_estafeta_guarda();
  d := d || jsonb_build_object('dC_WHEN_da_ronda1_t09b', pg_temp.rv_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'authenticated',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}')
      RETURNING status$$));
  CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $dd$
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN RETURN NEW; END IF;
    -- DEFEITO: sem a regra das fotos do cliente
    IF (to_jsonb(NEW) - 'photos_client' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'photos_client' - 'updated_at') THEN
      RAISE EXCEPTION 'lavagem_so_pelo_servidor' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $dd$;
  d := d || jsonb_build_object('dD_fotos_livres_c03', pg_temp.rv_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'authenticated',
    format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, v_cw)));

  RAISE EXCEPTION 'RESULT %', jsonb_build_object('estrutura', est, 'testes', r, 'defeitos_revisor', d)::text;
END
$rev$;
