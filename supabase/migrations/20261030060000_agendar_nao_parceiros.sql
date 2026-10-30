-- Agendar pedido também nos mercados e lojas NÃO parceiras (adendo 11, ordem do Danilo de 30/10/2026 05:22).
--
-- Até aqui o agendar (C5) era só para restaurantes parceiros, e com a loja fechada o pedido nem nascia
-- (STORE_CLOSED no gatilho de criação). Agora:
--   1. _sched_windows_core deixa de exigir parceiro (mantém: online, aprovada, não "em breve", ativa, horário,
--      sem festas). client_set_order_schedule aceita restaurant e storeShopping, parceiro ou não.
--   2. client_create_order_agendado(p_input, p_scheduled_for): chama o create_order de sempre (SEM o alterar:
--      preços, taxas e cobrança ficam iguais) com a hora numa variável da transação; o gatilho
--      a0a_orders_agendado_na_criacao valida a janela e grava scheduled_for no próprio INSERT. No cartão pelo
--      rascunho (já pago), a hora vem do payload do rascunho (chave scheduled_for) e basta a loja estar aberta
--      nessa hora.
--   3. _store_closed_guard_orders: com hora marcada, a loja só tem de estar aberta NA HORA MARCADA.
--   4. Retenção: o gatilho a0b_orders_agendado_retem não deixa um pedido não-parceiro agendado passar a
--      callingDriver antes de scheduled_for - dispatch_antecedencia_agendado_minutos (fica em preparing, sem
--      chamar estafeta). Os parceiros seguem pelo partner_auto_dispatch_ready_orders, como antes.
--   5. agendados_nao_parceiros_despachar() (pg_cron de minuto a minuto) passa-os a callingDriver na hora;
--      falhas vão para order_lifecycle_errors.
--   6. O alerta de pedido órfão deixa de disparar para pedidos agendados que ainda não chegaram à hora.
-- Nada aqui mexe em preços, taxas, comissões, carteira ou tokens.

-- 0. Cópias das funções que mudam.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['_sched_windows_core(text,date,integer)', 'client_set_order_schedule(text,timestamp with time zone)',
                           '_store_closed_guard_orders()', '_cron_check_orphan_orders()'] LOOP
    EXECUTE format('CREATE TABLE IF NOT EXISTS public.%I AS SELECT now() AS guardado_em, pg_get_functiondef(%L::regprocedure) AS def',
                   'bkp_fn_' || ltrim(split_part(f, '(', 1), '_') || '_20261030', 'public.' || f);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', 'bkp_fn_' || ltrim(split_part(f, '(', 1), '_') || '_20261030');
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', 'bkp_fn_' || ltrim(split_part(f, '(', 1), '_') || '_20261030');
  END LOOP;
END $$;

-- 1. Janelas: também para lojas não parceiras.
CREATE OR REPLACE FUNCTION public._sched_windows_core(p_restaurant_id text, p_day date, p_folga_min integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cfg     jsonb;
  v_hoje    date;
  v_r       record;
  v_hours   jsonb;
  v_dh      jsonb;
  v_key     text;
  v_o       integer;
  v_c       integer;
  v_bs      integer;
  v_be      integer;
  v_c_eff   integer;
  v_seg     integer;
  v_seg_ini integer;
  v_seg_fim integer;
  v_slot    integer;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_min_ts  timestamptz;
  v_max_ts  timestamptz;
  v_out     jsonb := '[]'::jsonb;
BEGIN
  IF p_restaurant_id IS NULL OR p_day IS NULL THEN RETURN '[]'::jsonb; END IF;

  v_cfg := public._sched_cfg();
  IF NOT (v_cfg->>'enabled')::boolean THEN RETURN '[]'::jsonb; END IF;

  v_hoje := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  IF p_day < v_hoje OR p_day > v_hoje + (v_cfg->>'max_days')::integer THEN RETURN '[]'::jsonb; END IF;
  v_min_ts := now() + make_interval(mins => GREATEST((v_cfg->>'min_lead_minutes')::integer - GREATEST(COALESCE(p_folga_min, 0), 0), 0));
  v_max_ts := now() + make_interval(days => (v_cfg->>'max_days')::integer);

  SELECT category, business_hours, pausa_ate,
         COALESCE(is_online, true)        AS online,
         COALESCE(coming_soon, false)     AS em_breve,
         COALESCE(is_active_admin, true)  AS ativo_admin,
         approval_status
    INTO v_r
    FROM public.restaurants WHERE id = p_restaurant_id;
  -- 30/10/2026: parceiros e não parceiros (mercados e restantes lojas), como na Glovo/Uber Eats.
  IF NOT FOUND
     OR v_r.category = 'festas'
     OR NOT v_r.online OR v_r.em_breve OR NOT v_r.ativo_admin
     OR (v_r.approval_status IS NOT NULL AND v_r.approval_status <> 'approved')
  THEN
    RETURN '[]'::jsonb;
  END IF;

  v_hours := v_r.business_hours;
  IF v_hours IS NULL OR jsonb_typeof(v_hours) <> 'object' THEN RETURN '[]'::jsonb; END IF;

  v_dh := NULL;
  IF v_hours ? 'special_dates' AND jsonb_typeof(v_hours->'special_dates') = 'array' THEN
    SELECT elem INTO v_dh
      FROM jsonb_array_elements(v_hours->'special_dates') elem
     WHERE elem->>'date' = to_char(p_day, 'YYYY-MM-DD')
     LIMIT 1;
  END IF;
  IF v_dh IS NULL THEN
    v_key := CASE EXTRACT(DOW FROM p_day)::integer
               WHEN 0 THEN 'sun' WHEN 1 THEN 'mon' WHEN 2 THEN 'tue' WHEN 3 THEN 'wed'
               WHEN 4 THEN 'thu' WHEN 5 THEN 'fri' ELSE 'sat' END;
    v_dh := v_hours->v_key;
  END IF;
  IF v_dh IS NULL OR jsonb_typeof(v_dh) <> 'object' OR (v_dh->>'closed')::boolean IS TRUE THEN
    RETURN '[]'::jsonb;
  END IF;

  v_o := public._parse_hhmm_to_minutes(v_dh->>'open');
  v_c := public._parse_hhmm_to_minutes(v_dh->>'close');
  IF v_o IS NULL OR v_c IS NULL THEN RETURN '[]'::jsonb; END IF;
  v_c_eff := CASE WHEN v_c <= v_o THEN 1440 ELSE v_c END;

  v_bs := public._parse_hhmm_to_minutes(v_dh->>'break_start');
  v_be := public._parse_hhmm_to_minutes(v_dh->>'break_end');

  FOR v_seg IN 1..2 LOOP
    IF v_bs IS NOT NULL AND v_be IS NOT NULL AND v_bs < v_be AND v_bs > v_o AND v_be < v_c_eff THEN
      IF v_seg = 1 THEN v_seg_ini := v_o;  v_seg_fim := v_bs;
      ELSE              v_seg_ini := v_be; v_seg_fim := v_c_eff;
      END IF;
    ELSE
      EXIT WHEN v_seg = 2;
      v_seg_ini := v_o; v_seg_fim := v_c_eff;
    END IF;

    v_slot := ((v_seg_ini + 29) / 30) * 30;
    WHILE v_slot + 30 <= v_seg_fim LOOP
      v_ini := (p_day::timestamp + make_interval(mins => v_slot)) AT TIME ZONE 'Europe/Lisbon';
      v_fim := v_ini + interval '30 minutes';
      IF v_ini >= v_min_ts
         AND v_ini <= v_max_ts
         AND (v_r.pausa_ate IS NULL OR v_ini >= v_r.pausa_ate)
         AND COALESCE((public.is_partner_open(p_restaurant_id, v_ini)->>'is_open')::boolean, false)
         AND COALESCE((public.is_partner_open(p_restaurant_id, v_fim - interval '1 minute')->>'is_open')::boolean, false)
      THEN
        v_out := v_out || jsonb_build_array(jsonb_build_object(
          'inicio',      v_ini,
          'fim',         v_fim,
          'hora_inicio', public._sched_hhmm(v_slot),
          'hora_fim',    public._sched_hhmm(v_slot + 30)
        ));
      END IF;
      v_slot := v_slot + 30;
    END LOOP;
  END LOOP;

  RETURN v_out;
END;
$function$;

-- 2. Marcar a hora depois de criar (loja aberta agora): também restaurant/storeShopping não parceiros.
CREATE OR REPLACE FUNCTION public.client_set_order_schedule(p_order_id text, p_scheduled_for timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_cfg   jsonb;
  v_o     record;
  v_valid boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  IF p_order_id IS NULL OR p_scheduled_for IS NULL THEN RAISE EXCEPTION 'schedule_required'; END IF;
  v_cfg := public._sched_cfg();
  IF NOT (v_cfg->>'enabled')::boolean THEN RAISE EXCEPTION 'scheduled_orders_disabled'; END IF;

  SELECT id, user_id, status, restaurant_id, service_type, is_partner_store, scheduled_for
    INTO v_o FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
  IF v_o.user_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'not_your_order' USING ERRCODE = '42501'; END IF;
  -- Não parceiros: o cliente pode já ter passado a preparing (a app avança sozinha); ainda sem estafeta.
  IF NOT (v_o.status = 'created'
          OR (v_o.status = 'preparing'
              AND NOT (v_o.service_type = 'restaurant' AND COALESCE(v_o.is_partner_store, false))))
  THEN
    RAISE EXCEPTION 'order_already_processed: %', v_o.status;
  END IF;
  IF v_o.service_type NOT IN ('restaurant', 'storeShopping') THEN
    RAISE EXCEPTION 'schedule_not_supported';
  END IF;
  IF v_o.scheduled_for IS NOT NULL THEN
    IF v_o.scheduled_for = p_scheduled_for THEN
      RETURN jsonb_build_object('ok', true, 'order_id', p_order_id, 'scheduled_for', p_scheduled_for, 'ja_estava', true);
    END IF;
    RAISE EXCEPTION 'schedule_already_set';
  END IF;

  SELECT EXISTS (
    SELECT 1
      FROM jsonb_array_elements(
             public._sched_windows_core(
               v_o.restaurant_id,
               (p_scheduled_for AT TIME ZONE 'Europe/Lisbon')::date,
               10)) w
     WHERE (w->>'inicio')::timestamptz = p_scheduled_for
  ) INTO v_valid;
  IF NOT v_valid THEN RAISE EXCEPTION 'schedule_window_invalid'; END IF;

  UPDATE public.orders SET scheduled_for = p_scheduled_for WHERE id = p_order_id;

  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id, 'scheduled_for', p_scheduled_for);
END;
$function$;

-- 3. Criar já agendado (a loja pode estar fechada agora). O create_order não muda.
CREATE OR REPLACE FUNCTION public.client_create_order_agendado(p_input jsonb, p_scheduled_for timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_res jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  IF p_scheduled_for IS NULL THEN RAISE EXCEPTION 'schedule_required'; END IF;
  IF NOT (public._sched_cfg()->>'enabled')::boolean THEN RAISE EXCEPTION 'scheduled_orders_disabled'; END IF;
  PERFORM set_config('app.agendar_para', p_scheduled_for::text, true);
  v_res := public.create_order(p_input);
  PERFORM set_config('app.agendar_para', '', true);
  RETURN COALESCE(v_res, '{}'::jsonb) || jsonb_build_object('scheduled_for', p_scheduled_for);
END;
$function$;

-- Gatilho BEFORE INSERT: grava a hora marcada no próprio pedido (antes da guarda de loja fechada).
CREATE OR REPLACE FUNCTION public._orders_agendado_na_criacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sched  timestamptz;
  v_rasc   boolean := false;
  v_cfg    jsonb;
  v_valid  boolean;
BEGIN
  IF NEW.scheduled_for IS NOT NULL THEN RETURN NEW; END IF;
  v_sched := NULLIF(current_setting('app.agendar_para', true), '')::timestamptz;
  IF v_sched IS NULL AND NEW.payment_intent_id IS NOT NULL THEN
    SELECT NULLIF(d.payload->>'scheduled_for', '')::timestamptz INTO v_sched
      FROM public.payment_drafts d
     WHERE d.payment_intent_id = NEW.payment_intent_id
     ORDER BY d.created_at DESC
     LIMIT 1;
    v_rasc := v_sched IS NOT NULL;
  END IF;
  IF v_sched IS NULL THEN RETURN NEW; END IF;

  v_cfg := public._sched_cfg();
  IF NOT v_rasc THEN
    -- Pela RPC (ainda nada pago): a hora tem de ser uma janela válida desta loja, senão não há pedido.
    IF NOT (v_cfg->>'enabled')::boolean THEN RAISE EXCEPTION 'scheduled_orders_disabled'; END IF;
    IF NEW.restaurant_id IS NULL OR NEW.service_type NOT IN ('restaurant', 'storeShopping') THEN
      RAISE EXCEPTION 'schedule_not_supported';
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM jsonb_array_elements(
               public._sched_windows_core(NEW.restaurant_id, (v_sched AT TIME ZONE 'Europe/Lisbon')::date, 10)) w
       WHERE (w->>'inicio')::timestamptz = v_sched) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'schedule_window_invalid'; END IF;
    NEW.scheduled_for := v_sched;
  ELSE
    -- Cartão pelo rascunho (o cliente já pagou): basta a loja abrir nessa hora; se não, segue sem hora
    -- (e a guarda de loja fechada decide como sempre).
    IF NEW.restaurant_id IS NOT NULL
       AND NEW.service_type IN ('restaurant', 'storeShopping')
       AND (v_cfg->>'enabled')::boolean
       AND v_sched > now()
       AND v_sched <= now() + make_interval(days => (v_cfg->>'max_days')::integer + 1)
       AND COALESCE((public.is_partner_open(NEW.restaurant_id, v_sched)->>'is_open')::boolean, false)
    THEN
      NEW.scheduled_for := v_sched;
    ELSE
      RAISE WARNING '_orders_agendado_na_criacao: hora do rascunho % recusada (loja %)', v_sched, NEW.restaurant_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS a0a_orders_agendado_na_criacao ON public.orders;
CREATE TRIGGER a0a_orders_agendado_na_criacao
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_agendado_na_criacao();

-- 4. Loja fechada: com hora marcada, conta a hora marcada.
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
  -- 30/10/2026: pedido agendado (a hora ja foi validada no a0a_orders_agendado_na_criacao): a loja so tem de
  -- estar aberta na hora marcada.
  IF NEW.scheduled_for IS NOT NULL AND NEW.scheduled_for > now() THEN
    v_estado := public.is_partner_open(NEW.restaurant_id, NEW.scheduled_for);
  ELSE
    v_estado := public.is_partner_open(NEW.restaurant_id);
  END IF;
  IF COALESCE((v_estado->>'is_open')::boolean, true) IS FALSE THEN
    v_abre := v_estado->>'opens_at';
    RAISE EXCEPTION 'STORE_CLOSED: A loja esta fechada neste momento.%',
      CASE WHEN v_abre IS NOT NULL THEN ' Abre as ' || v_abre || '.' ELSE '' END
      USING ERRCODE = 'P0001', HINT = 'STORE_CLOSED';
  END IF;
  RETURN NEW;
END;
$function$;

-- 5. Retenção: um não-parceiro agendado não chama estafeta antes da hora (fica em preparing).
CREATE OR REPLACE FUNCTION public._orders_agendado_retem()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ant integer;
BEGIN
  IF NEW.status = 'callingDriver'
     AND OLD.status IN ('created', 'preparing')
     AND NEW.scheduled_for IS NOT NULL
     AND NOT (COALESCE(NEW.service_type, '') = 'restaurant' AND COALESCE(NEW.is_partner_store, false))
  THEN
    SELECT (value #>> '{}')::integer INTO v_ant
      FROM public.platform_settings WHERE key = 'dispatch_antecedencia_agendado_minutos';
    v_ant := GREATEST(COALESCE(v_ant, 30), 0);
    IF now() < NEW.scheduled_for - make_interval(mins => v_ant) THEN
      NEW.status := 'preparing';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS a0b_orders_agendado_retem ON public.orders;
CREATE TRIGGER a0b_orders_agendado_retem
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_agendado_retem();

-- 6. Na hora: passa os não-parceiros agendados a callingDriver (o gatilho de sempre chama o despacho).
CREATE OR REPLACE FUNCTION public.agendados_nao_parceiros_despachar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ant   integer;
  v_o     record;
  v_n     integer := 0;
BEGIN
  SELECT (value #>> '{}')::integer INTO v_ant
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_agendado_minutos';
  v_ant := GREATEST(COALESCE(v_ant, 30), 0);

  FOR v_o IN
    SELECT id, status
      FROM public.orders
     WHERE status IN ('created', 'preparing')
       AND scheduled_for IS NOT NULL
       AND service_type IN ('restaurant', 'storeShopping')
       AND NOT (service_type = 'restaurant' AND COALESCE(is_partner_store, false))
       AND assigned_driver_id IS NULL
       AND driver_id IS NULL
       AND (COALESCE(payment_method, 'cash') = 'cash' OR payment_status = 'paid')
       AND now() >= scheduled_for - make_interval(mins => v_ant)
     ORDER BY scheduled_for
     LIMIT 50
     FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      PERFORM set_config('app.order_transition_source', 'agendados_nao_parceiros_despachar', true);
      IF v_o.status = 'created' THEN
        UPDATE public.orders SET status = 'preparing' WHERE id = v_o.id AND status = 'created';
      END IF;
      UPDATE public.orders SET status = 'callingDriver' WHERE id = v_o.id AND status = 'preparing';
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_lifecycle_errors(order_id, component, error_message)
      VALUES (v_o.id, 'agendados_nao_parceiros_despachar', SQLERRM);
    END;
  END LOOP;
  RETURN v_n;
END;
$function$;

-- 7. O alerta de órfão ignora agendados que ainda não chegaram à hora.
CREATE OR REPLACE FUNCTION public._cron_check_orphan_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT o.id, o.created_at, o.status, o.price
    FROM public.orders o
    WHERE o.status IN ('callingDriver', 'created', 'preparing')
      AND o.driver_id IS NULL
      AND o.created_at < now() - interval '10 minutes'
      AND o.created_at > now() - interval '2 hours'  -- evita re-alertar pedidos antigos
      AND (o.scheduled_for IS NULL OR o.scheduled_for <= now() + interval '30 minutes')  -- 30/10: agendados so na hora
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_notifications n
        WHERE n.event_type = 'order_orphan'
          AND n.entity_id = o.id::text
          AND n.created_at > now() - interval '1 hour'  -- dedup 1h
      )
  LOOP
    PERFORM public.notify_admin_event(
      'order_orphan',
      'high',
      format('Pedido órfão há %s min: #%s (status=%s)',
        EXTRACT(EPOCH FROM (now() - r.created_at))::int / 60,
        substring(r.id::text, 1, 8),
        r.status),
      'order',
      r.id::text,
      jsonb_build_object('status', r.status, 'price', r.price, 'age_minutes',
        EXTRACT(EPOCH FROM (now() - r.created_at))::int / 60),
      '/admin/orders/' || r.id::text
    );
  END LOOP;
END;
$function$;

-- 8. Permissões e o relógio.
REVOKE ALL ON FUNCTION public.client_create_order_agendado(jsonb, timestamp with time zone) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_create_order_agendado(jsonb, timestamp with time zone) TO authenticated;
REVOKE ALL ON FUNCTION public.agendados_nao_parceiros_despachar() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._orders_agendado_na_criacao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._orders_agendado_retem() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'agendados-nao-parceiros') THEN
    PERFORM cron.unschedule('agendados-nao-parceiros');
  END IF;
  PERFORM cron.schedule('agendados-nao-parceiros', '* * * * *', 'SELECT public.agendados_nao_parceiros_despachar();');
END $$;
