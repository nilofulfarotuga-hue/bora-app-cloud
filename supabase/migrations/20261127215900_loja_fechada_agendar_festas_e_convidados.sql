-- Espelho da migração aplicada em produção por MCP a 27/11/2026 (~22:05, Claude.ai):
-- versão 20261127215900, nome loja_fechada_agendar_festas_e_convidados_2026_11_27.
-- NÃO voltar a correr: já está em supabase_migrations.schema_migrations.

-- 27/11/2026 (caso Karen Sabrina, Sabores do Brasil às 21:38).
-- Regra do Danilo: com a loja fechada o cliente enche o carrinho e pode
-- marcar para amanhã (da abertura ao fecho) ou outro dia. Aqui fica a parte
-- do servidor:
--  1) a loja de festas passa a ter janelas de agendamento como as outras
--     (itens "Na hora" marcam-se para quando a loja abrir);
--  2) a encomenda de festa (item da prateleira 'Para festa (encomenda)') não é
--     travada pela loja fechada: a data marca-se logo a seguir com
--     festas_set_schedule (mínimo dia seguinte);
--  3) quem ainda não entrou na conta (convidado) também lê a configuração e as
--     janelas, para poder encher o carrinho e ver a que horas a loja abre.

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
  -- 27/11/2026: festas também (itens "Na hora" marcam-se para quando a loja abrir).
  IF NOT FOUND
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
  -- 27/11/2026: encomenda de festa (loja 'festas' com item da prateleira 'Para festa (encomenda)').
  -- A data marca-se logo a seguir a criar (festas_set_schedule, minimo dia seguinte), por isso a loja
  -- fechada AGORA nao trava. Itens "Na hora" sozinhos continuam a precisar da loja aberta ou de hora marcada.
  IF NEW.scheduled_for IS NULL
     AND EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id = NEW.restaurant_id AND r.category = 'festas')
     AND EXISTS (
       SELECT 1
         FROM jsonb_array_elements(CASE WHEN jsonb_typeof(NEW.items) = 'array' THEN NEW.items ELSE '[]'::jsonb END) it
         JOIN public.products p ON p.id = it->>'productId' AND p.restaurant_id = NEW.restaurant_id
        WHERE p.category = 'Para festa (encomenda)')
  THEN
    RETURN NEW;
  END IF;
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

-- 3) Convidados: a configuração e as janelas são informação pública (horário da loja).
CREATE OR REPLACE FUNCTION public.scheduled_orders_config()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cfg jsonb;
BEGIN
  -- 27/11/2026: sem exigir conta (o convidado tambem enche o carrinho e ve quando a loja abre).
  v_cfg := public._sched_cfg();
  RETURN jsonb_build_object(
    'enabled',          (v_cfg->>'enabled')::boolean,
    'max_days',         (v_cfg->>'max_days')::integer,
    'min_lead_minutes', (v_cfg->>'min_lead_minutes')::integer
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.scheduled_windows_for_store(p_restaurant_id text, p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 27/11/2026: sem exigir conta (so devolve as janelas de 30 min do horario publico da loja).
  RETURN public._sched_windows_core(p_restaurant_id, p_day, 0);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.scheduled_orders_config() TO anon;
GRANT EXECUTE ON FUNCTION public.scheduled_windows_for_store(text, date) TO anon;
