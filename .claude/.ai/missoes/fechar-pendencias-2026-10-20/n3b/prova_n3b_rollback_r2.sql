DO $prova$
DECLARE
  v_antes  jsonb;
  v_depois jsonb;
  v_defeito jsonb := '{}'::jsonb;
  v_out    jsonb := '{}'::jsonb;
  v_cw     uuid := gen_random_uuid();
BEGIN
  -- ===== Ajudante: corre UMA escrita como a API (cliente, admin ou servidor) e desfaz logo =====
  CREATE FUNCTION pg_temp.n3b_tenta(p_uid uuid, p_tipo text, p_sql text) RETURNS text
  LANGUAGE plpgsql AS $f$
  DECLARE n bigint; v_ret text;
  BEGIN
    IF p_tipo = 'servidor' THEN
      PERFORM set_config('request.jwt.claim.sub', '', true);
      PERFORM set_config('request.jwt.claims', json_build_object('role','service_role')::text, true);
    ELSIF p_tipo = 'admin' THEN
      PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated','email','nilofulfarotuga@gmail.com','app_metadata',json_build_object('role','admin'))::text, true);
    ELSE
      PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
      PERFORM set_config('request.jwt.claims', json_build_object('sub',p_uid,'role','authenticated')::text, true);
    END IF;
    BEGIN
      IF p_tipo = 'servidor' THEN SET LOCAL ROLE service_role; ELSE SET LOCAL ROLE authenticated; END IF;
      IF p_sql ILIKE '%RETURNING%' THEN EXECUTE p_sql INTO v_ret; ELSE EXECUTE p_sql; END IF;
      GET DIAGNOSTICS n = ROW_COUNT;
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__PASSOU__' || n || COALESCE(') ' || v_ret, ')');
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE '__PASSOU__%' THEN RETURN 'PASSOU (' || substr(SQLERRM, 11); END IF;
      RETURN SQLSTATE || ' ' || left(SQLERRM, 110);
    END;
  END $f$;

  -- ===== A bateria: ataques (devem passar ANTES e dar 42501 DEPOIS) e caminhos legítimos (iguais antes e depois) =====
  -- A = demo@bora.app d5b0c0a1 (dono de ORD 4a3bb2ca, mercado não parceiro), V = e3c166d2 (dono de ORDP ec0506ef,
  -- restaurante parceiro), T = 183a32cd (cliente de teste, dono da lavagem de prova), estafeta demo dede…0001/…0002,
  -- lavador W = 4f61dd31 (lavador "Danilo" 231e1c82, não é admin), admin = c9fccf85.
  CREATE FUNCTION pg_temp.n3b_bateria(p_cw uuid) RETURNS jsonb
  LANGUAGE plpgsql AS $b$
  DECLARE
    A uuid := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
    V uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
    T uuid := '183a32cd-d570-447a-a86d-a86c2a6845d6';
    D uuid := 'dede0000-0000-4000-8000-000000000001';
    W uuid := '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7';
    ADM uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
    r jsonb := '{}'::jsonb;
    cw text := p_cw::text;
  BEGIN
    -- pedidos: ataques do dono
    r := r || jsonb_build_object('o1_ataque_dono_muda_loja', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o2_ataque_dono_tira_parceiro', pg_temp.n3b_tenta(V, 'cliente',
      $$UPDATE public.orders SET is_partner_store = false WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'$$));
    r := r || jsonb_build_object('o3_ataque_dono_muda_nome_loja', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET vendor_name = 'Loja falsa' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o4_ataque_dono_poe_estafeta', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o5_ataque_dono_poe_oferta', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET current_driver_offer_id = 'dede0000-0000-4000-8000-000000000001', driver_offer_expires_at = now() + interval '1 minute' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o6_ataque_dono_pre_atribui', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET preassigned_driver_id = 'dede0000-0000-4000-8000-000000000002' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o7_ataque_dono_exclui_estafetas', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET tried_driver_ids = '{dede0000-0000-4000-8000-000000000002}' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o8_ataque_dono_poe_ajudante', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET helper_driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('o9_ataque_cliente_cria_ja_com_estafeta', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, restaurant_id, vendor_name, is_partner_store, price, payment_method, is_test_order, assigned_driver_id, driver_id)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'storeShopping', 'continente-guarda', 'Continente', false, 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002', 'dede0000-0000-4000-8000-000000000001')$$));
    r := r || jsonb_build_object('o9b_ataque_cliente_cria_com_estafetas_excluidos', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}') RETURNING status$$));
    r := r || jsonb_build_object('o9c_ataque_cliente_cria_com_oferta_e_historico', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, driver_offer_expires_at, driver_offer_history)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, now() + interval '1 hour', '[{"x":1}]'::jsonb) RETURNING status$$));
    r := r || jsonb_build_object('o9d_ataque_cliente_cria_pacote_com_estafeta', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, assigned_driver_id)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002') RETURNING status$$));
    r := r || jsonb_build_object('l10_cliente_cria_pacote_sem_estafeta_chega_ao_fim', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true) RETURNING status || ' tried=' || coalesce(tried_driver_ids::text,'-') || ' hist=' || coalesce(driver_offer_history::text,'-')$$));
    r := r || jsonb_build_object('l11_demo_cria_pacote_fica_com_estafeta_demo', pg_temp.n3b_tenta(A, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order)
        VALUES ('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'created', 'sendPackage', 10, 'cash', true) RETURNING status || ' drv=' || coalesce(assigned_driver_id, '-') || '/' || coalesce(driver_id::text, '-')$$));
    -- pedidos: caminhos legítimos
    r := r || jsonb_build_object('l1_dono_muda_notas', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET customer_notes = 'nota de prova N3b' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('l2_dono_created_para_preparing', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET status = 'preparing' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('v3_vazio_cliente_cria_com_loja_fechada_as_5h', pg_temp.n3b_tenta(T, 'cliente',
      $$INSERT INTO public.orders (user_id, status, service_type, restaurant_id, vendor_name, is_partner_store, price, payment_method, is_test_order)
        VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'storeShopping', 'continente-guarda', 'Continente', false, 10, 'cash', true)$$));
    r := r || jsonb_build_object('l4_servidor_muda_loja', pg_temp.n3b_tenta(NULL, 'servidor',
      $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('v5_vazio_admin_sem_politica_update_em_orders', pg_temp.n3b_tenta(ADM, 'admin',
      $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    r := r || jsonb_build_object('v6_vazio_cancelDelivery_codigo_morto_ja_RLS', pg_temp.n3b_tenta(D, 'cliente',
      $$UPDATE public.orders SET assigned_driver_id = NULL, current_driver_offer_id = NULL, driver_offer_expires_at = NULL, status = 'callingDriver', tried_driver_ids = '{dede0000-0000-4000-8000-000000000002}' WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'$$));
    r := r || jsonb_build_object('l7_estafeta_manda_localizacao', pg_temp.n3b_tenta(D, 'cliente',
      $$UPDATE public.orders SET driver_lat = 40.5373, driver_lng = -7.2676 WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'$$));
    r := r || jsonb_build_object('l8_dono_V_muda_notas_no_pedido_parceiro', pg_temp.n3b_tenta(V, 'cliente',
      $$UPDATE public.orders SET customer_notes = 'nota V' WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'$$));
    -- o dono que é o estafeta que aceitou (histórico que o cliente não escreve) continua livre, como no R2
    INSERT INTO public.order_status_events (order_id, from_status, to_status, actor_uid, source)
      VALUES ('4a3bb2ca-4fad-40c6-897c-a8827c6c8754', 'callingDriver', 'driverAccepted', A, 'prova_n3b');
    r := r || jsonb_build_object('l9_dono_que_aceitou_como_estafeta', pg_temp.n3b_tenta(A, 'cliente',
      $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
    DELETE FROM public.order_status_events WHERE order_id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754' AND source = 'prova_n3b';

    -- lavagens (T é o cliente da lavagem de prova; W é o lavador)
    r := r || jsonb_build_object('c1_cliente_anexa_foto', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET photos_client = '["prova-n3b.jpg"]'::jsonb WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c2_ataque_cliente_muda_total', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET total_cents = 1 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c3_ataque_cliente_marca_concluida', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET status = 'completed' WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c4_ataque_cliente_muda_ganho_lavador', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c5_ataque_cliente_marca_pago', pg_temp.n3b_tenta(T, 'cliente',
      format($$UPDATE public.carwash_bookings SET payment_status = 'paid' WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c6_ataque_lavador_muda_ganho', pg_temp.n3b_tenta(W, 'cliente',
      format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c9_ataque_lavador_troca_foto_do_cliente', pg_temp.n3b_tenta(W, 'cliente',
      format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c7_admin_muda_total', pg_temp.n3b_tenta(ADM, 'admin',
      format($$UPDATE public.carwash_bookings SET total_cents = 2100 WHERE id = %L$$, cw)));
    r := r || jsonb_build_object('c8_servidor_marca_concluida', pg_temp.n3b_tenta(NULL, 'servidor',
      format($$UPDATE public.carwash_bookings SET status = 'completed' WHERE id = %L$$, cw)));
    RETURN r;
  END $b$;

  -- ===== Preparação (como o servidor, para a auditoria de estafeta não ler "SQL direto") =====
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role','service_role')::text, true);
  UPDATE public.orders SET status = 'created', assigned_driver_id = NULL, driver_id = NULL, current_driver_offer_id = NULL,
         preassigned_driver_id = NULL, helper_driver_id = NULL
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
  v_out := v_out || jsonb_build_object('preparacao', jsonb_build_object(
    'ord', (SELECT status || '/' || coalesce(assigned_driver_id,'-') FROM public.orders WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'),
    'ordp', (SELECT status || '/parceiro=' || is_partner_store FROM public.orders WHERE id = 'ec0506ef-0b46-4cad-a5cb-47c8a520ab03'),
    'ordd', (SELECT status || '/' || assigned_driver_id FROM public.orders WHERE id = 'f18c21cf-8e72-429e-aec7-d1a04c25ee49'),
    'lavagem', (SELECT status || '/' || total_cents FROM public.carwash_bookings WHERE id = v_cw)));

  -- ===== ANTES (como está no ar) =====
  v_antes := pg_temp.n3b_bateria(v_cw);

  -- ===== Aplicar as duas migrações (texto igual aos ficheiros, colado pelo gerador) =====
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

  -- ===== DEPOIS =====
  v_depois := pg_temp.n3b_bateria(v_cw);

  -- ===== DEFEITO PLANTADO 1: a guarda dos pedidos "esquece" o estafeta → o ataque o4 tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_recusa(o public.orders, n public.orders)
  RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $d1$
  DECLARE v_uid uuid := auth.uid();
  BEGIN
    IF v_uid IS NULL OR o.user_id IS DISTINCT FROM v_uid THEN RETURN NULL; END IF;
    IF public.is_admin() THEN RETURN NULL; END IF;
    IF n.restaurant_id IS DISTINCT FROM o.restaurant_id THEN RETURN 'restaurant_id'; END IF;
    RETURN NULL;  -- DEFEITO: sem as colunas do estafeta
  END $d1$;
  v_defeito := v_defeito || jsonb_build_object('d1_sem_estafeta_o4', pg_temp.n3b_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'cliente',
    $$UPDATE public.orders SET assigned_driver_id = 'dede0000-0000-4000-8000-000000000002', driver_id = 'dede0000-0000-4000-8000-000000000001' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));
  v_defeito := v_defeito || jsonb_build_object('d1_loja_continua_o1', pg_temp.n3b_tenta('d5b0c0a1-f49e-4593-a919-147edfc069c2', 'cliente',
    $$UPDATE public.orders SET restaurant_id = 'auchan-guarda' WHERE id = '4a3bb2ca-4fad-40c6-897c-a8827c6c8754'$$));

  -- ===== DEFEITO PLANTADO 2: a guarda das lavagens deixa passar o total → o ataque c2 tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $d2$
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN RETURN NEW; END IF;
    IF NEW.photos_client IS DISTINCT FROM OLD.photos_client AND auth.uid() IS DISTINCT FROM OLD.client_user_id THEN
      RAISE EXCEPTION 'lavagem_fotos_so_do_cliente' USING ERRCODE = '42501';
    END IF;
    IF (to_jsonb(NEW) - 'photos_client' - 'updated_at' - 'total_cents') IS DISTINCT FROM
       (to_jsonb(OLD) - 'photos_client' - 'updated_at' - 'total_cents') THEN  -- DEFEITO: total_cents fora
      RAISE EXCEPTION 'lavagem_so_pelo_servidor' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $d2$;
  v_defeito := v_defeito || jsonb_build_object('d2_total_fora_c2', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    format($$UPDATE public.carwash_bookings SET total_cents = 1 WHERE id = %L$$, v_cw::text)));
  v_defeito := v_defeito || jsonb_build_object('d2_ganho_continua_c4', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, v_cw::text)));

  -- ===== DEFEITO PLANTADO 3: a guarda das lavagens deixa qualquer um mexer nas fotos → o ataque c9 tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._lavagem_escrita_direta_guarda()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $d3$
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN RETURN NEW; END IF;
    -- DEFEITO: sem a regra "fotos só do cliente"
    IF (to_jsonb(NEW) - 'photos_client' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'photos_client' - 'updated_at') THEN
      RAISE EXCEPTION 'lavagem_so_pelo_servidor' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $d3$;
  v_defeito := v_defeito || jsonb_build_object('d3_fotos_livres_c9', pg_temp.n3b_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'cliente',
    format($$UPDATE public.carwash_bookings SET photos_client = '["do-lavador.jpg"]'::jsonb WHERE id = %L$$, v_cw::text)));
  v_defeito := v_defeito || jsonb_build_object('d3_ganho_continua_c6', pg_temp.n3b_tenta('4f61dd31-5e9e-4a7c-a557-7d53d2ceded7', 'cliente',
    format($$UPDATE public.carwash_bookings SET washer_earnings_cents = 99999 WHERE id = %L$$, v_cw::text)));

  -- ===== DEFEITO PLANTADO 4: a guarda do INSERT "esquece" os estafetas excluídos → o ataque o9b tem de voltar a passar =====
  CREATE OR REPLACE FUNCTION public._pedido_cliente_loja_estafeta_guarda()
  RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $d4$
  DECLARE v_motivo text;
  BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' THEN
      IF public.is_admin() THEN RETURN NEW; END IF;
      v_motivo := CASE WHEN NEW.assigned_driver_id IS NOT NULL THEN 'assigned_driver_id' END;  -- DEFEITO: só o estafeta
    ELSE
      v_motivo := public._pedido_cliente_loja_estafeta_recusa(OLD, NEW);
    END IF;
    IF v_motivo IS NOT NULL THEN
      RAISE EXCEPTION 'pedido_loja_estafeta_so_pelo_servidor (%)', v_motivo USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END $d4$;
  v_defeito := v_defeito || jsonb_build_object('d4_insert_sem_excluidos_o9b', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, tried_driver_ids)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, '{dede0000-0000-4000-8000-000000000002}') RETURNING status$$));
  v_defeito := v_defeito || jsonb_build_object('d4_estafeta_continua_o9d', pg_temp.n3b_tenta('183a32cd-d570-447a-a86d-a86c2a6845d6', 'cliente',
    $$INSERT INTO public.orders (user_id, status, service_type, price, payment_method, is_test_order, assigned_driver_id)
      VALUES ('183a32cd-d570-447a-a86d-a86c2a6845d6', 'created', 'sendPackage', 10, 'cash', true, 'dede0000-0000-4000-8000-000000000002') RETURNING status$$));

  -- ===== Veredicto mecânico =====
  -- ataques: chaves o<n>[letra]_ataque / c<n>_ataque · legítimos: l<n>_ e c1/c7/c8 · vazios (não provam nada, só se
  -- mostra que ficaram iguais): v<n>_
  v_out := v_out || jsonb_build_object(
    'antes', v_antes,
    'depois', v_depois,
    'defeito', v_defeito,
    'ataques_passavam_antes', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v LIKE 'PASSOU (1)%'),
    'ataques_ja_travados_antes_por_outra_regra', (SELECT jsonb_agg(k || '=' || v ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v NOT LIKE 'PASSOU (1)%'),
    'ataques_recusados_depois', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_depois) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v LIKE '42501 %'),
    'ataques_NAO_recusados_depois', (SELECT jsonb_agg(k || '=' || v ORDER BY k) FROM jsonb_each_text(v_depois) e(k, v) WHERE k ~ '^[oc][0-9]+[a-z]?_ataque' AND v NOT LIKE '42501 %'),
    'legitimos_que_passam_e_iguais', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v)
                          WHERE (k ~ '^l[0-9]+_' OR k ~ '^c[178]_') AND v LIKE 'PASSOU (1)%' AND v = v_depois ->> k),
    'legitimos_MUDARAM_ou_nao_passam', (SELECT jsonb_agg(k || ': ' || v || ' -> ' || (v_depois ->> k) ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v)
                          WHERE (k ~ '^l[0-9]+_' OR k ~ '^c[178]_') AND (v NOT LIKE 'PASSOU (1)%' OR v IS DISTINCT FROM v_depois ->> k)),
    'vazios_iguais', (SELECT jsonb_agg(k || ': ' || v ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^v[0-9]+_' AND v = v_depois ->> k),
    'vazios_MUDARAM', (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_each_text(v_antes) e(k, v) WHERE k ~ '^v[0-9]+_' AND v IS DISTINCT FROM v_depois ->> k),
    'defeito_apanhado',
         (v_defeito ->> 'd1_sem_estafeta_o4') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd1_loja_continua_o1') LIKE '42501 %'
     AND (v_defeito ->> 'd2_total_fora_c2') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd2_ganho_continua_c4') LIKE '42501 %'
     AND (v_defeito ->> 'd3_fotos_livres_c9') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd3_ganho_continua_c6') LIKE '42501 %'
     AND (v_defeito ->> 'd4_insert_sem_excluidos_o9b') LIKE 'PASSOU (1)%' AND (v_defeito ->> 'd4_estafeta_continua_o9d') LIKE '42501 %');
  RAISE EXCEPTION 'RESULT %', v_out::text;
END
$prova$;
