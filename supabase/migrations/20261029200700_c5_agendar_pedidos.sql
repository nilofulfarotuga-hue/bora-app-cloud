-- C5 · AGENDAR PEDIDOS COM A LOJA FECHADA (item 5 do adendo 5 do Danilo, 29/10/2026)
-- Missão: missao-geral-2026-10-28. NÃO APLICADA: quem aplica é o Claude Code principal, depois de
-- ler docs/propostas/missao-geral-2026-10-28/C5_agendar/ (4 propostas).
--
-- O que esta migração FAZ (tudo fechado a anon, tudo atrás do interruptor `scheduled_orders_enabled`,
-- que nasce DESLIGADO — desligado, nenhuma destas funções devolve ou grava nada):
--   1) platform_settings: scheduled_orders_enabled (false), scheduled_orders_max_days (7),
--      scheduled_orders_min_lead_minutes (60) e scheduled_orders_revisor_ok (false).
--      O painel NÃO consegue ligar o interruptor enquanto `scheduled_orders_revisor_ok` for false:
--      só passa a true depois de o revisor independente dizer SIM (UPDATE feito à mão, com o "vai").
--   2) scheduled_orders_config()                      -> o que a app do cliente/parceiro precisa de saber.
--   3) scheduled_windows_for_store(loja, dia)         -> janelas de 30 min dentro do horário da loja
--      (por baixo: _sched_windows_core, sem verificação de sessão, para o create_order da proposta 04
--      — que corre com a chave de serviço no caminho do cartão — poder validar a mesma regra).
--   4) client_set_order_schedule(pedido, instante)    -> o próprio cliente grava a hora no pedido que
--      acabou de criar (mesmo desenho de festas_set_schedule; NÃO toca create_order).
--   5) partner_scheduled_orders(loja)                 -> separador "Agendados" do parceiro.
--   6) admin_scheduled_orders() + admin_scheduled_orders_config() + admin_scheduled_orders_definir().
--
-- O que NÃO faz (propostas separadas, mexem em dinheiro/despacho/Edge Functions):
--   01_dispatch_proposta.sql            -> hora de chamar o estafeta a contar da hora agendada.
--   02_cancelamento_sem_taxa_proposta.md-> cancelar até 1 h antes sem taxa.
--   03_alerta_parceiro_proposta.sql     -> aviso (push + som) 30 min antes ao parceiro.
--   04_create_order_loja_fechada_proposta.md -> sem isto a loja FECHADA recusa o pedido (STORE_CLOSED).
--
-- Reversível: tudo CREATE OR REPLACE / ON CONFLICT DO NOTHING; para desfazer basta DROP FUNCTION das
-- 10 funções abaixo e DELETE das 4 chaves de platform_settings. Não mexe em nenhuma função existente.

-- ============================================================================
-- 1) Definições
-- ============================================================================
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('scheduled_orders_enabled', 'false'::jsonb,
   'Pedidos agendados: o cliente escolhe dia e janela de 30 min (mesmo com a loja fechada). Nasce DESLIGADO; só liga depois do revisor dizer SIM.',
   'scheduling'),
  ('scheduled_orders_max_days', '7'::jsonb,
   'Pedidos agendados: máximo de dias à frente em que o cliente pode agendar.',
   'scheduling'),
  ('scheduled_orders_min_lead_minutes', '60'::jsonb,
   'Pedidos agendados: antecedência mínima, em minutos, entre o pedido e o início da janela escolhida.',
   'scheduling'),
  ('scheduled_orders_revisor_ok', 'false'::jsonb,
   'Pedidos agendados: o revisor independente já disse SIM? Enquanto false o painel não deixa ligar o interruptor. Só se muda à mão.',
   'scheduling')
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- 2) Funções internas (fechadas a toda a gente)
-- ============================================================================
CREATE OR REPLACE FUNCTION public._sched_cfg()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_en   boolean;
  v_days integer;
  v_lead integer;
  v_ok   boolean;
BEGIN
  SELECT COALESCE((value #>> '{}')::boolean, false) INTO v_en
    FROM public.platform_settings WHERE key = 'scheduled_orders_enabled';
  SELECT COALESCE((value #>> '{}')::integer, 7) INTO v_days
    FROM public.platform_settings WHERE key = 'scheduled_orders_max_days';
  SELECT COALESCE((value #>> '{}')::integer, 60) INTO v_lead
    FROM public.platform_settings WHERE key = 'scheduled_orders_min_lead_minutes';
  SELECT COALESCE((value #>> '{}')::boolean, false) INTO v_ok
    FROM public.platform_settings WHERE key = 'scheduled_orders_revisor_ok';
  RETURN jsonb_build_object(
    'enabled',           COALESCE(v_en, false),
    'max_days',          LEAST(GREATEST(COALESCE(v_days, 7), 1), 14),
    'min_lead_minutes',  LEAST(GREATEST(COALESCE(v_lead, 60), 30), 720),
    'revisor_ok',        COALESCE(v_ok, false)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._sched_hhmm(p_min integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT lpad((p_min / 60)::text, 2, '0') || ':' || lpad((p_min % 60)::text, 2, '0')
$function$;

-- ============================================================================
-- 3) scheduled_orders_config() — lido pela app (cliente e parceiro)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.scheduled_orders_config()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cfg jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  v_cfg := public._sched_cfg();
  RETURN jsonb_build_object(
    'enabled',          (v_cfg->>'enabled')::boolean,
    'max_days',         (v_cfg->>'max_days')::integer,
    'min_lead_minutes', (v_cfg->>'min_lead_minutes')::integer
  );
END;
$function$;

-- ============================================================================
-- 4) scheduled_windows_for_store(loja, dia) — janelas de 30 min dentro do horário
--    Lê restaurants.business_hours: {mon:{open,close,closed,break_start,break_end},...,
--    special_dates:[{date,open,close,closed,break_start,break_end}]}, na hora de Lisboa.
--    As janelas alinham-se às :00 e :30 e cabem INTEIRAS dentro de cada período aberto
--    (antes e depois da pausa). Cada janela passa ainda por is_partner_open() ao início e ao fim
--    (assim respeita o "forçar fechado" do admin e a pausa temporária).
--    Devolve [] com o interruptor desligado, dia fora de [hoje, hoje + max_days], loja que não é
--    parceira de restaurante, "em breve", desligada, ou de festas (essas têm o fluxo próprio).
-- ============================================================================
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
  -- p_folga_min: a validação ao gravar o pedido dá alguns minutos de folga (o cartão demora a pagar).
  v_min_ts := now() + make_interval(mins => GREATEST((v_cfg->>'min_lead_minutes')::integer - GREATEST(COALESCE(p_folga_min, 0), 0), 0));
  v_max_ts := now() + make_interval(days => (v_cfg->>'max_days')::integer);

  SELECT category, business_hours, pausa_ate,
         COALESCE(is_online, true)        AS online,
         COALESCE(coming_soon, false)     AS em_breve,
         COALESCE(is_partner, false)      AS parceiro,
         COALESCE(is_active_admin, true)  AS ativo_admin,
         approval_status
    INTO v_r
    FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND
     OR v_r.category = 'festas'
     OR NOT v_r.online OR v_r.em_breve OR NOT v_r.parceiro OR NOT v_r.ativo_admin
     OR (v_r.approval_status IS NOT NULL AND v_r.approval_status <> 'approved')
  THEN
    RETURN '[]'::jsonb;
  END IF;

  v_hours := v_r.business_hours;
  IF v_hours IS NULL OR jsonb_typeof(v_hours) <> 'object' THEN RETURN '[]'::jsonb; END IF;

  -- Horário desse dia: dia especial da data, senão o dia da semana.
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
  -- Horário que passa a meia-noite (ex.: 20:00-02:00): só se agenda até à meia-noite desse dia.
  v_c_eff := CASE WHEN v_c <= v_o THEN 1440 ELSE v_c END;

  v_bs := public._parse_hhmm_to_minutes(v_dh->>'break_start');
  v_be := public._parse_hhmm_to_minutes(v_dh->>'break_end');

  FOR v_seg IN 1..2 LOOP
    IF v_bs IS NOT NULL AND v_be IS NOT NULL AND v_bs < v_be AND v_bs > v_o AND v_be < v_c_eff THEN
      IF v_seg = 1 THEN v_seg_ini := v_o;  v_seg_fim := v_bs;
      ELSE              v_seg_ini := v_be; v_seg_fim := v_c_eff;
      END IF;
    ELSE
      EXIT WHEN v_seg = 2;            -- sem pausa válida: um só período
      v_seg_ini := v_o; v_seg_fim := v_c_eff;
    END IF;

    v_slot := ((v_seg_ini + 29) / 30) * 30;          -- primeira marca :00 ou :30 dentro do período
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

CREATE OR REPLACE FUNCTION public.scheduled_windows_for_store(p_restaurant_id text, p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  RETURN public._sched_windows_core(p_restaurant_id, p_day, 0);
END;
$function$;

-- ============================================================================
-- 5) client_set_order_schedule(pedido, instante) — o cliente grava a hora no SEU pedido
--    Mesmo desenho de festas_set_schedule (que também nasceu para não tocar create_order):
--    só o dono, só enquanto 'created', só restaurante parceiro com entrega, só uma vez
--    (repetir o mesmo instante é aceite), e o instante tem de ser o início de uma janela
--    devolvida por scheduled_windows_for_store (horário, antecedência, 7 dias, pausa, override).
--    Com o interruptor desligado recusa.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.client_set_order_schedule(p_order_id text, p_scheduled_for timestamptz)
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
  IF v_o.status <> 'created' THEN RAISE EXCEPTION 'order_already_processed: %', v_o.status; END IF;
  IF v_o.service_type <> 'restaurant' OR NOT COALESCE(v_o.is_partner_store, false) THEN
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

-- ============================================================================
-- 6) partner_scheduled_orders(loja) — separador "Agendados" do parceiro (dono ou admin)
--    Pedidos com hora marcada que ainda não acabaram, do mais próximo para o mais distante.
--    Mostra também os que passaram há menos de 2 h e ainda estão por entregar.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.partner_scheduled_orders(p_restaurant_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required' USING ERRCODE = '42501'; END IF;
  IF NOT (public._sched_cfg()->>'enabled')::boolean THEN RETURN '[]'::jsonb; END IF;
  IF NOT (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.restaurants r
                WHERE r.id = p_restaurant_id AND (r.user_ = v_uid OR r.user_id = v_uid))
  ) THEN
    RAISE EXCEPTION 'not_your_restaurant' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.scheduled_for, x.id)
      FROM (
        SELECT o.id, o.status, o.scheduled_for,
               o.scheduled_for + interval '30 minutes' AS scheduled_until,
               o.price, o.customer_name, o.customer_notes,
               o.payment_method, o.payment_status,
               o.prep_time_minutes, o.accepted_at, o.items, o.created_at
          FROM public.orders o
         WHERE o.restaurant_id = p_restaurant_id
           AND o.scheduled_for IS NOT NULL
           AND o.scheduled_for > now() - interval '2 hours'
           AND o.status NOT IN ('delivered', 'cancelled', 'rejected')
         ORDER BY o.scheduled_for, o.id
         LIMIT 200
      ) x
  ), '[]'::jsonb);
END;
$function$;

-- ============================================================================
-- 7) Painel admin (PT-BR no ecrã): lista, estado e interruptores
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_scheduled_orders()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.scheduled_for, x.id)
      FROM (
        SELECT o.id, o.status, o.scheduled_for, o.restaurant_id,
               r.name AS restaurant_name, r.category AS restaurant_category,
               o.price, o.customer_name, o.payment_method, o.payment_status,
               o.prep_time_minutes, o.created_at
          FROM public.orders o
          LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
         WHERE o.scheduled_for IS NOT NULL
           AND o.scheduled_for > now() - interval '1 day'
           AND o.status NOT IN ('delivered', 'cancelled', 'rejected')
         ORDER BY o.scheduled_for, o.id
         LIMIT 300
      ) x
  ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_scheduled_orders_config()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cfg jsonb; v_total integer; v_24h integer;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  v_cfg := public._sched_cfg();
  SELECT count(*) INTO v_total
    FROM public.orders o
   WHERE o.scheduled_for IS NOT NULL AND o.scheduled_for > now()
     AND o.status NOT IN ('delivered', 'cancelled', 'rejected');
  SELECT count(*) INTO v_24h
    FROM public.orders o
   WHERE o.scheduled_for IS NOT NULL
     AND o.scheduled_for > now() AND o.scheduled_for <= now() + interval '24 hours'
     AND o.status NOT IN ('delivered', 'cancelled', 'rejected');
  RETURN v_cfg || jsonb_build_object('total_agendados', v_total, 'proximas_24h', v_24h);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_scheduled_orders_definir(p_chave text, p_valor jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_num numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF p_valor IS NULL THEN RAISE EXCEPTION 'valor_invalido'; END IF;

  IF p_chave = 'scheduled_orders_enabled' THEN
    IF jsonb_typeof(p_valor) <> 'boolean' THEN RAISE EXCEPTION 'valor_invalido'; END IF;
    -- Ligar exige o SIM do revisor independente (despacho em jogo). Desligar é sempre possível.
    IF p_valor = 'true'::jsonb AND NOT (public._sched_cfg()->>'revisor_ok')::boolean THEN
      RAISE EXCEPTION 'revisor_em_falta';
    END IF;
  ELSIF p_chave = 'scheduled_orders_max_days' THEN
    IF jsonb_typeof(p_valor) <> 'number' THEN RAISE EXCEPTION 'valor_invalido'; END IF;
    v_num := (p_valor #>> '{}')::numeric;
    IF v_num < 1 OR v_num > 14 OR v_num <> trunc(v_num) THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  ELSIF p_chave = 'scheduled_orders_min_lead_minutes' THEN
    IF jsonb_typeof(p_valor) <> 'number' THEN RAISE EXCEPTION 'valor_invalido'; END IF;
    v_num := (p_valor #>> '{}')::numeric;
    IF v_num < 30 OR v_num > 720 OR v_num <> trunc(v_num) THEN RAISE EXCEPTION 'valor_invalido'; END IF;
  ELSE
    -- scheduled_orders_revisor_ok NÃO se muda por aqui, de propósito.
    RAISE EXCEPTION 'chave_invalida';
  END IF;

  UPDATE public.platform_settings
     SET value = p_valor, updated_at = now(), updated_by = auth.uid()
   WHERE key = p_chave;

  PERFORM public.log_admin_action('scheduled_orders_definir'::text, 'platform_settings'::text, p_chave::text,
    jsonb_build_object('valor', p_valor));

  RETURN public.admin_scheduled_orders_config();
END;
$function$;

-- ============================================================================
-- 8) Permissões: fechado a anon e a PUBLIC; as internas só para o dono da função.
--    Cada função confirma quem chama (cliente com sessão, dono da loja ou admin).
-- ============================================================================
REVOKE ALL ON FUNCTION public._sched_cfg() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._sched_hhmm(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._sched_windows_core(text, date, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.scheduled_orders_config() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.scheduled_windows_for_store(text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_set_order_schedule(text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.partner_scheduled_orders(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_scheduled_orders() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_scheduled_orders_config() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_scheduled_orders_definir(text, jsonb) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.scheduled_orders_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.scheduled_windows_for_store(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_set_order_schedule(text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_scheduled_orders(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_scheduled_orders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_scheduled_orders_config() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_scheduled_orders_definir(text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.scheduled_windows_for_store(text, date) IS
  'C5 29/10/2026: janelas de 30 min (:00/:30) dentro do business_hours da loja, com pausa, dias especiais, antecedência e máximo de dias. [] com o interruptor desligado.';
COMMENT ON FUNCTION public.client_set_order_schedule(text, timestamptz) IS
  'C5 29/10/2026: o cliente grava orders.scheduled_for no pedido que acabou de criar (sem tocar create_order). Atrás do interruptor scheduled_orders_enabled.';
