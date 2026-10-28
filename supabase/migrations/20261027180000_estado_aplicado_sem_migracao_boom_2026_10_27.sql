-- 20261027180000_estado_aplicado_sem_migracao_boom_2026_10_27.sql
-- Missão boom-burger-2026-10-27, passo F0 (Claude Code, 27/10/2026).
--
-- Objetos aplicados hoje em produção por execute_sql (sem linha em schema_migrations); este ficheiro
-- guarda a definição viva tal como estava às 18:02 UTC de 27/10/2026 (lida entre 17:53 e 18:02 UTC,
-- md5 conferido de novo às 18:02), para o repo não ficar atrás da base.
--
-- Cada função é o texto exacto de pg_get_functiondef(...) seguido de ';'. Cada gatilho é o texto exacto
-- de pg_get_triggerdef(...) seguido de ';', precedido de drop trigger if exists.
-- Ficam de fora (já estão iguais em 20261027161559_business_hours_guarda_pausa_2026_10_27.sql):
--   public.fn_business_hours_guarda_pausa() e o gatilho trg_business_hours_guarda_pausa.
-- public.fn_conformidade_abrir_loja_parceira() e o gatilho trg_conformidade_abrir_loja_parceira repetem-se
-- aqui por pedido da missão; a função é byte a byte igual à de 20261027160958.
--
-- Modo demonstração da loja: a definição (loja, janela, contas demo) vive em public.platform_settings,
-- key 'modo_demo_loja' (is_secret=true). O valor tem ids de contas e NÃO vai para o repo.

-- ===================== FUNCOES (pg_get_functiondef) =====================

-- public._modo_demo_def()
CREATE OR REPLACE FUNCTION public._modo_demo_def()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select value from public.platform_settings where key = 'modo_demo_loja' $function$
;

-- public._modo_demo_loja(text, uuid)
CREATE OR REPLACE FUNCTION public._modo_demo_loja(p_rid text, p_uid uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (d->>'restaurant_id') = p_rid
                      and now() >= (d->>'inicio')::timestamptz and now() < (d->>'fim')::timestamptz
                      and (p_uid is null or (d->>'cliente_user_id')::uuid = p_uid)
                     from (select public._modo_demo_def() as d) s where s.d is not null), false) $function$
;

-- public._modo_demo_estafeta()
CREATE OR REPLACE FUNCTION public._modo_demo_estafeta()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select nullif(public._modo_demo_def()->>'estafeta_user_id', '')::uuid $function$
;

-- public._e_pedido_demo_loja(text)
CREATE OR REPLACE FUNCTION public._e_pedido_demo_loja(p_order_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.orders o, (select public._modo_demo_def() as d) s
                  where o.id = p_order_id and coalesce(o.is_test_order, false) and s.d is not null
                    and o.restaurant_id = s.d->>'restaurant_id' and o.user_id = (s.d->>'cliente_user_id')::uuid) $function$
;

-- public._pedido_demo_em_caixa_fechada()
CREATE OR REPLACE FUNCTION public._pedido_demo_em_caixa_fechada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_demo_estafeta constant text := 'dede0000-0000-4000-8000-000000000002';
  v_demo_estafeta_user constant uuid := 'dede0000-0000-4000-8000-000000000001';
begin
  if new.user_id is null then return new; end if;
  -- 27/10/2026 (boom-burger, modo demonstracao): o cliente demo da loja em demonstracao, dentro da janela,
  -- em dinheiro, faz um pedido de TESTE que segue o fluxo normal (parceiro aceita, despacho so ao estafeta
  -- demo). Nada e pre-atribuido aqui.
  if coalesce(new.payment_method, '') = 'cash' and public._modo_demo_loja(new.restaurant_id, new.user_id) then
    new.is_test_order := true;
    return new;
  end if;
  -- So contas demo. Qualquer outra passa intacta.
  if not exists (
    select 1 from auth.users u
     where u.id = new.user_id
       and u.email in ('demo@bora.app', 'demo.cliente@bora.app', 'demo.apagar@bora.app')
  ) then
    return new;
  end if;
  new.is_test_order := true;
  new.payment_method := 'cash';
  new.payment_status := 'pending';
  new.status := 'driverAccepted';
  new.assigned_driver_id := v_demo_estafeta;
  -- 2026-09-13: a guarda de integridade exige tambem driver_id.
  new.driver_id := v_demo_estafeta_user;
  return new;
end;
$function$
;

-- public._coming_soon_guard_orders()
CREATE OR REPLACE FUNCTION public._coming_soon_guard_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_coming_soon boolean;
BEGIN
  IF NEW.restaurant_id IS NULL THEN RETURN NEW; END IF;
  -- 27/10/2026 modo demonstracao: so o pedido de teste do cliente demo, na loja e janela definidas.
  IF COALESCE(NEW.is_test_order, false) AND public._modo_demo_loja(NEW.restaurant_id, NEW.user_id) THEN RETURN NEW; END IF;
  SELECT r.coming_soon INTO v_coming_soon FROM public.restaurants r WHERE r.id = NEW.restaurant_id;
  IF COALESCE(v_coming_soon, false) THEN
    RAISE EXCEPTION 'STORE_COMING_SOON: Esta loja ainda nao esta a aceitar pedidos.' USING ERRCODE = 'P0001', HINT = 'STORE_COMING_SOON';
  END IF;
  RETURN NEW;
END;
$function$
;

-- public._store_closed_guard_orders()
CREATE OR REPLACE FUNCTION public._store_closed_guard_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_estado JSONB; v_abre TEXT;
BEGIN
  IF NEW.restaurant_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.service_type NOT IN ('restaurant','storeShopping','takeaway') THEN RETURN NEW; END IF;
  IF COALESCE(current_setting('app.parceiro_chama_estafeta', true), '') = 'on' THEN RETURN NEW; END IF;
  -- 27/10/2026 modo demonstracao: so o pedido de teste do cliente demo, na loja e janela definidas.
  IF COALESCE(NEW.is_test_order, false) AND public._modo_demo_loja(NEW.restaurant_id, NEW.user_id) THEN RETURN NEW; END IF;
  v_estado := public.is_partner_open(NEW.restaurant_id);
  IF COALESCE((v_estado->>'is_open')::boolean, true) IS FALSE THEN
    v_abre := v_estado->>'opens_at';
    RAISE EXCEPTION 'STORE_CLOSED: A loja esta fechada neste momento.%',
      CASE WHEN v_abre IS NOT NULL THEN ' Abre as ' || v_abre || '.' ELSE '' END
      USING ERRCODE = 'P0001', HINT = 'STORE_CLOSED';
  END IF;
  RETURN NEW;
END;
$function$
;

-- public.notify_admin_event(text, text, text, text, text, jsonb, text)
CREATE OR REPLACE FUNCTION public.notify_admin_event(p_event_type text, p_severity text, p_summary text, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_deep_link text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
  v_sev text;
BEGIN

  -- 27/10/2026 modo demonstracao: o pedido de teste da loja em demonstracao nao alerta ninguem.
  IF p_entity_type = 'order' AND public._e_pedido_demo_loja(p_entity_id) THEN RETURN NULL; END IF;
  v_sev := CASE lower(coalesce(p_severity, ''))
             WHEN 'warning' THEN 'medium'
             WHEN 'warn'    THEN 'medium'
             WHEN 'info'    THEN 'low'
             WHEN 'error'   THEN 'high'
             ELSE p_severity
           END;
  INSERT INTO public.admin_notifications (
    event_type, severity, summary,
    entity_type, entity_id, payload, deep_link
  ) VALUES (
    p_event_type, v_sev, p_summary,
    p_entity_type, p_entity_id, COALESCE(p_payload, '{}'::jsonb), p_deep_link
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$
;

-- public.notify_admin_urgent_push(text, text, text, text, jsonb, text)
CREATE OR REPLACE FUNCTION public.notify_admin_urgent_push(p_event_type text, p_summary text, p_entity_type text, p_entity_id text, p_payload jsonb, p_deep_link text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id    uuid;
  v_url   text;
  v_key   text;
  v_title text := '🔴 Ação pendente — Bora Admin';
  v_body  text := p_summary;
  v_nl    int;
begin

  -- 27/10/2026 modo demonstracao: o pedido de teste da loja em demonstracao nao alerta ninguem.
  IF p_entity_type = 'order' AND public._e_pedido_demo_loja(p_entity_id) THEN RETURN NULL; END IF;
  -- 1) Persiste a linha (badge + inbox dependem disto), severidade HIGH.
  v_id := public.notify_admin_event(
    p_event_type, 'high', p_summary,
    p_entity_type, p_entity_id, coalesce(p_payload, '{}'::jsonb), p_deep_link
  );

  -- 2) Push persistente + Telegram, best-effort (nunca quebra a transação de origem).
  begin
    -- 2026-09-16: a 1.ª linha é o que aparece na pré-visualização do Telegram/push:
    -- quem é e o quê. Antes todas as mensagens começavam por "Ação pendente — Bora Admin".
    v_nl := position(E'\n' in coalesce(p_summary, ''));
    if v_nl > 1 then
      v_title := btrim(left(p_summary, v_nl - 1));
      v_body  := btrim(substr(p_summary, v_nl + 1), E' \n');
      if coalesce(v_title, '') = '' or coalesce(v_body, '') = '' then
        v_title := '🔴 Ação pendente — Bora Admin';
        v_body  := p_summary;
      end if;
    end if;

    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
    if v_url is not null and v_key is not null then
      perform net.http_post(
        url     := v_url || '/functions/v1/notify-admin-urgent',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type', 'application/json'),
        body    := jsonb_build_object(
          'kind',  'generic',
          'title', v_title,
          'body',  v_body,
          'route', coalesce(p_deep_link, '/admin'),
          'ref',   p_event_type)
      );
    end if;
  exception when others then
    raise notice 'notify_admin_urgent_push push error: %', sqlerrm;
  end;

  return v_id;
end
$function$
;

-- public.notify_new_order_admin()
CREATE OR REPLACE FUNCTION public.notify_new_order_admin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_resumo text; v_total numeric;
begin
  -- 27/10/2026 modo demonstracao: o pedido de teste da loja em demonstracao nao alerta o admin nem o Telegram.
  if coalesce(new.is_test_order, false) and public._e_pedido_demo_loja(new.id) then return new; end if;
  v_total := coalesce(new.final_total, new.price, 0);
  -- 2026-09-16: 1.ª linha = PEDIDO NOVO + NOME + TELEFONE (vira o título no Telegram/push).
  begin v_resumo := public._alerta_txt_pedido(new); exception when others then v_resumo := null; end;
  v_resumo := coalesce(v_resumo, '🛎️ PEDIDO NOVO · #' || left(new.id, 8));
  begin
    perform public.notify_admin_urgent_push('new_order', v_resumo, 'order', new.id,
      jsonb_build_object('order_id', new.id, 'restaurant_id', new.restaurant_id, 'total', v_total,
        'payment_method', new.payment_method, 'scheduled_for', new.scheduled_for, 'service_type', new.service_type,
        'order_type', new.order_type, 'client_name', new.customer_name, 'client_phone', new.client_phone), '/admin/orders');
  exception when others then raise notice 'notify_new_order_admin erro: %', sqlerrm; end;
  return new;
end
$function$
;

-- public.dispatch_candidatos_entrega(text)
CREATE OR REPLACE FUNCTION public.dispatch_candidatos_entrega(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision, vehicle_type text, dist_km double precision, mesma_loja boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o          record;
  v_fresh    int     := COALESCE((public.get_setting('dispatch_gps_fresh_seconds_entregas') #>> '{}')::int, 900);
  v_raio     numeric := COALESCE((public.get_setting('dispatch_raio_max_oferta_km') #>> '{}')::numeric, 20);
  v_req_car  boolean;
  v_favor    boolean;
  -- 27/10/2026 modo demonstracao (boom-burger): pedido demo -> so o estafeta demo; pedido normal -> nunca ele
  v_demo     boolean;
  v_demo_uid uuid;
BEGIN
  SELECT x.id, x.service_type, x.requires_car, x.pickup_lat, x.pickup_lng, x.restaurant_id
    INTO o FROM public.orders x WHERE x.id = p_order_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_req_car := COALESCE(o.requires_car, false) OR o.service_type = 'carryGroceries';
  v_favor   := o.service_type = 'errand';
  v_demo     := public._e_pedido_demo_loja(o.id);
  v_demo_uid := public._modo_demo_estafeta();

  RETURN QUERY
  WITH base AS (
    SELECT d.id AS d_id, d.user_id AS d_uid, d.lat AS d_lat, d.lng AS d_lng, d.vehicle_type AS d_veh,
           ARRAY[d.id::text, COALESCE(d.user_id, d.id)::text] AS chaves
      FROM public.drivers d
     WHERE d.is_online
       AND d.approval_status = 'approved'
       AND (COALESCE(d.is_banned, false) = false
            OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
       AND d.deleted_at IS NULL
       AND (CASE WHEN v_demo THEN d.user_id IS NOT DISTINCT FROM v_demo_uid AND v_demo_uid IS NOT NULL
                 ELSE (v_demo_uid IS NULL OR d.user_id IS DISTINCT FROM v_demo_uid) END)
       AND (d.work_mode IS NULL OR d.work_mode <> 'rides_only')
       AND d.last_heartbeat_at > now() - make_interval(secs => v_fresh)
       AND public.driver_gps_last_at(d.user_id, d.id) > now() - make_interval(secs => v_fresh)
       AND (NOT v_req_car OR d.vehicle_type IN ('car', 'carro_passageiros'))
       AND public.aceita_papel(COALESCE(d.user_id, d.id), 'delivery')
       AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r
                        WHERE r.driver_id = d.user_id
                          AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
  ), carga AS (
    SELECT b.*,
           (SELECT count(*) FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')) AS ativos,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND a.service_type = 'errand') AS tem_favor,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND o.restaurant_id IS NOT NULL AND a.restaurant_id = o.restaurant_id) AS leva_mesma_loja,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.id <> o.id
               AND a.status = 'callingDriver'
               AND a.current_driver_offer_id = ANY(b.chaves)
               AND a.driver_offer_expires_at > now()
               AND (v_favor OR a.service_type = 'errand'
                    OR o.restaurant_id IS NULL OR a.restaurant_id IS DISTINCT FROM o.restaurant_id)) AS oferta_ocupada
      FROM base b
  ), dist AS (
    SELECT c.*,
           CASE WHEN o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR c.d_lat IS NULL OR c.d_lng IS NULL THEN NULL
                ELSE 6371 * 2 * asin(sqrt(
                       power(sin(radians(o.pickup_lat::double precision - c.d_lat) / 2), 2)
                     + cos(radians(c.d_lat)) * cos(radians(o.pickup_lat::double precision))
                       * power(sin(radians(o.pickup_lng::double precision - c.d_lng) / 2), 2)))
           END AS km
      FROM carga c
  )
  SELECT x.d_id, x.d_uid, x.d_lat, x.d_lng, x.d_veh, x.km, x.leva_mesma_loja
    FROM dist x
   WHERE NOT x.oferta_ocupada
     AND x.ativos < 3
     AND NOT x.tem_favor
     AND (NOT v_favor OR x.ativos = 0)
     AND (o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR (x.km IS NOT NULL AND x.km <= v_raio))
   ORDER BY x.leva_mesma_loja DESC, x.km ASC NULLS LAST;
END;
$function$
;

-- public._demo_loja_sem_entrega()
CREATE OR REPLACE FUNCTION public._demo_loja_sem_entrega()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- 27/10/2026 modo demonstracao: "Entregue" correria os gatilhos de dinheiro (ganhos, tokens, livro, acerto
  -- semanal real da loja). O pedido demo da loja em demonstracao fecha antes, sem custo.
  if new.status = 'delivered' and old.status is distinct from 'delivered' and public._e_pedido_demo_loja(new.id) then
    new.status := 'cancelled';
    new.cancelled_at := now();
    new.cancel_reason := 'Demonstracao concluida: entrega simulada, sem custo';
    new.cancel_fee := 0;
  end if;
  return new;
end;
$function$
;

-- public.demo_boom_criar_pedido(jsonb, text)
CREATE OR REPLACE FUNCTION public.demo_boom_criar_pedido(p_itens jsonb, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- 27/10/2026 (boom-burger, modo demonstracao): o "telemovel 1" da demonstracao. So o cliente demo da
-- definicao modo_demo_loja, so dentro da janela, so produtos disponiveis da loja, so dinheiro. Chama o
-- create_order normal (que recalcula tudo no servidor); o gatilho da caixa fechada marca-o is_test_order.
declare
  v_def jsonb := public._modo_demo_def(); v_uid uuid := auth.uid(); v_rid text; v_r record; v_p record;
  v_it jsonb; v_q int; v_lines jsonb := '[]'::jsonb; v_items jsonb := '[]'::jsonb; v_sub numeric := 0;
begin
  if v_uid is null or v_def is null or v_uid is distinct from (v_def->>'cliente_user_id')::uuid then
    raise exception 'so_cliente_demo: esta funcao so serve a conta de demonstracao' using errcode = '42501';
  end if;
  v_rid := v_def->>'restaurant_id';
  if not public._modo_demo_loja(v_rid, v_uid) then
    raise exception 'fora_da_janela: a demonstracao so funciona entre % e % (UTC)', v_def->>'inicio', v_def->>'fim';
  end if;
  select id, name, lat, lng, address into v_r from public.restaurants where id = v_rid;
  for v_it in select * from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) loop
    v_q := greatest(1, least(10, coalesce((v_it->>'quantidade')::int, 1)));
    select id, name, price into v_p from public.products
     where id = v_it->>'product_id' and restaurant_id = v_rid and coalesce(is_available, true);
    if not found then raise exception 'produto_invalido: %', v_it->>'product_id'; end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('product_id', v_p.id, 'quantity', v_q, 'unit_price', v_p.price, 'name', v_p.name));
    v_items := v_items || jsonb_build_array(jsonb_build_object('name', v_p.name, 'price', v_p.price, 'quantity', v_q, 'basePrice', v_p.price,
                 'productId', v_p.id, 'purchaseStatus', 'pending', 'selected_options', '[]'::jsonb));
    v_sub := v_sub + v_p.price * v_q;
  end loop;
  if jsonb_array_length(v_lines) = 0 then raise exception 'sem_itens'; end if;
  return public.create_order(jsonb_build_object(
    'service_type', 'restaurant', 'vendor_name', v_r.name, 'is_partner_store', true, 'distance_km', 0.8,
    'payment_method', 'cash', 'subtotal', v_sub, 'apartment_delivery', false, 'order_type', 'partnerRestaurant',
    'bag_count', 1, 'requires_car', false, 'wallet_applied_cents', 0,
    'pickup_lat', v_r.lat, 'pickup_lng', v_r.lng, 'pickup_address', v_r.address,
    'dropoff_lat', 40.5373, 'dropoff_lng', -7.2676, 'dropoff_address', 'Praça Luís de Camões, Guarda (demonstração)',
    'dropoff_street', 'Praça Luís de Camões', 'dropoff_city', 'Guarda',
    'customer_name', 'Cliente Demonstração',
    'customer_notes', coalesce(nullif(p_notas, ''), 'Pedido de DEMONSTRAÇÃO'),
    'items', v_items, 'product_lines', v_lines));
end $function$
;

-- public._notify_on_order_cancel()
CREATE OR REPLACE FUNCTION public._notify_on_order_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- modo_demo_loja (27/10): o fim de uma demonstracao ("Demonstracao concluida/terminada", sem custo)
  -- nao e um cancelamento para o cliente de demonstracao; nao se manda o aviso "Pedido cancelado".
  IF COALESCE(NEW.is_test_order, false) AND COALESCE(NEW.cancel_reason, '') LIKE 'Demonstracao%' THEN
    RETURN NEW;
  END IF;
  IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' AND NEW.user_id IS NOT NULL THEN
    PERFORM _push_in_app_notification(
      NEW.user_id, 'cancellation',
      'Pedido cancelado',
      'O teu pedido ' || LEFT(NEW.id, 8) || ' foi cancelado. Reembolso em curso se aplicável.',
      NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$
;

-- public.fn_conformidade_abrir_loja_parceira()
CREATE OR REPLACE FUNCTION public.fn_conformidade_abrir_loja_parceira()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_falta text[];
  v_obrig boolean := COALESCE((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);
  v_abre  boolean;
BEGIN
  IF NOT COALESCE(NEW.is_partner, false)
     OR NEW.approval_status IS DISTINCT FROM 'approved'
     OR COALESCE(NEW.coming_soon, false) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    v_abre := true;
  ELSE
    v_abre := COALESCE(OLD.coming_soon, false) AND NOT COALESCE(NEW.coming_soon, false);
  END IF;
  IF NOT v_abre THEN
    RETURN NEW;
  END IF;
  v_falta := public._conformidade_em_falta(to_jsonb(NEW));
  IF array_length(v_falta, 1) > 0 THEN
    IF v_obrig AND COALESCE(current_setting('bora.forcar_ativacao', true), '') <> '1' THEN
      RAISE EXCEPTION 'conformidade_incompleta: faltam %', array_to_string(v_falta, ', ')
        USING HINT = 'Antes de abrir a loja parceira ao público: nome legal, NIF, morada, IBAN, data de nascimento (só pessoa singular) e autocertificação (DAC7, Lei 36/2023).';
    ELSE
      RAISE NOTICE 'conformidade_incompleta (nao bloqueante): restaurants % faltam %', NEW.id, array_to_string(v_falta, ', ');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;

-- ===================== GATILHOS (pg_get_triggerdef) =====================
-- trg_business_hours_guarda_pausa (restaurants) fica de fora: ja esta em 20261027161559.

drop trigger if exists a0_trg_demo_loja_sem_entrega on public.orders;
CREATE TRIGGER a0_trg_demo_loja_sem_entrega BEFORE UPDATE OF status ON public.orders FOR EACH ROW WHEN (((new.status = 'delivered'::text) AND (old.status IS DISTINCT FROM new.status))) EXECUTE FUNCTION _demo_loja_sem_entrega();

drop trigger if exists a_trg_pedido_demo_caixa_fechada on public.orders;
CREATE TRIGGER a_trg_pedido_demo_caixa_fechada BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION _pedido_demo_em_caixa_fechada();

drop trigger if exists trg_coming_soon_guard_orders on public.orders;
CREATE TRIGGER trg_coming_soon_guard_orders BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION _coming_soon_guard_orders();

drop trigger if exists trg_store_closed_guard_orders on public.orders;
CREATE TRIGGER trg_store_closed_guard_orders BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION _store_closed_guard_orders();

drop trigger if exists trg_notify_new_order_admin on public.orders;
CREATE TRIGGER trg_notify_new_order_admin AFTER INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION notify_new_order_admin();

drop trigger if exists trg_notify_on_order_cancel on public.orders;
CREATE TRIGGER trg_notify_on_order_cancel AFTER UPDATE OF status ON public.orders FOR EACH ROW WHEN (((new.status = 'cancelled'::text) AND (old.status IS DISTINCT FROM 'cancelled'::text))) EXECUTE FUNCTION _notify_on_order_cancel();

drop trigger if exists trg_conformidade_abrir_loja_parceira on public.restaurants;
CREATE TRIGGER trg_conformidade_abrir_loja_parceira BEFORE INSERT OR UPDATE OF coming_soon ON public.restaurants FOR EACH ROW EXECUTE FUNCTION fn_conformidade_abrir_loja_parceira();

-- ===================== PERMISSÕES =====================
-- Ajudantes do modo demonstração: só postgres e service_role os executam
-- (ACL lida às 18:01 UTC: {postgres=X/postgres,service_role=X/postgres}).
revoke all on function public._modo_demo_def(), public._modo_demo_loja(text, uuid), public._modo_demo_estafeta(), public._e_pedido_demo_loja(text) from public, anon, authenticated;

-- demo_boom_criar_pedido: só authenticated (a própria função recusa quem não for o cliente demo).
-- ACL lida às 18:01 UTC: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
revoke all on function public.demo_boom_criar_pedido(jsonb, text) from public, anon;
grant execute on function public.demo_boom_criar_pedido(jsonb, text) to authenticated;
