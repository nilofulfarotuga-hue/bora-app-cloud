-- APLICADA EM PRODUÇÃO pela Claude.ai via MCP a 19/11/2026 (versão 20261119161344).
-- Cópia fiel para o repo (regra de ouro 5). Superada em parte por 20261119163857 (km de estrada, máx. 32).
--
-- 19/11/2026 (regra do Danilo, "eu autorizo"): a limpeza passa a ir até 28 km do centro da Guarda
-- com taxa de deslocação. Distância em linha reta ao centro da Guarda.
--   até 10 km: sem taxa | 10 a 15 km: 8 € | acima de 15 km: 15 € + 1 €/km acima dos 15 | acima de 28 km: não faz.
-- A taxa vai INTEIRA para a limpadora (é ela que conduz). A Bora fica com os 15% só da limpeza.
-- O desconto da série semanal não toca na taxa; cobra-se em cada visita.
-- cleaning_quote (6 args) fica igual; a versão com morada é cleaning_quote_at (usada no servidor e, depois, no app).

ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS travel_fee_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS travel_distance_km numeric(6,1);

INSERT INTO public.platform_settings(key, value, description, category) VALUES
 ('cleaning_travel_center_lat', to_jsonb(40.5373), 'Limpeza: latitude do centro da Guarda (de onde se mede a distância da taxa de deslocação)', 'cleaning'),
 ('cleaning_travel_center_lng', to_jsonb(-7.2676), 'Limpeza: longitude do centro da Guarda', 'cleaning'),
 ('cleaning_travel_free_km', to_jsonb(10), 'Limpeza: até estes km do centro da Guarda não há taxa de deslocação', 'cleaning'),
 ('cleaning_travel_tier1_max_km', to_jsonb(15), 'Limpeza: até estes km cobra a taxa fixa do 1.º escalão', 'cleaning'),
 ('cleaning_travel_tier1_cents', to_jsonb(800), 'Limpeza: taxa de deslocação do 1.º escalão (cêntimos)', 'cleaning'),
 ('cleaning_travel_tier2_base_cents', to_jsonb(1500), 'Limpeza: taxa de deslocação acima do 1.º escalão (cêntimos), mais o valor por km', 'cleaning'),
 ('cleaning_travel_per_km_cents', to_jsonb(100), 'Limpeza: cêntimos por cada km acima do 1.º escalão', 'cleaning'),
 ('cleaning_max_distance_km', to_jsonb(28), 'Limpeza: distância máxima ao centro da Guarda (acima disto não se aceita a limpeza)', 'cleaning')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.cleaning_travel_fee(p_lat double precision, p_lng double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clat double precision := COALESCE((SELECT (value #>> '{}')::double precision FROM platform_settings WHERE key='cleaning_travel_center_lat'), 40.5373);
  v_clng double precision := COALESCE((SELECT (value #>> '{}')::double precision FROM platform_settings WHERE key='cleaning_travel_center_lng'), -7.2676);
  v_free numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_travel_free_km'), 10);
  v_t1_km numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_travel_tier1_max_km'), 15);
  v_t1_cents int := COALESCE((SELECT (value #>> '{}')::int FROM platform_settings WHERE key='cleaning_travel_tier1_cents'), 800);
  v_t2_base int := COALESCE((SELECT (value #>> '{}')::int FROM platform_settings WHERE key='cleaning_travel_tier2_base_cents'), 1500);
  v_per_km int := COALESCE((SELECT (value #>> '{}')::int FROM platform_settings WHERE key='cleaning_travel_per_km_cents'), 100);
  v_max numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_max_distance_km'), 28);
  v_d numeric;
  v_fee int := 0;
BEGIN
  -- Sem coordenadas não se trava a limpeza (regra "a localização nunca trava"): taxa 0.
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object('distance_km', NULL, 'travel_fee_cents', 0,
                              'out_of_area', false, 'max_distance_km', v_max);
  END IF;
  v_d := round(public._cleaning_distance_km(v_clat, v_clng, p_lat, p_lng)::numeric, 1);
  IF v_d > v_max THEN
    RETURN jsonb_build_object('distance_km', v_d, 'travel_fee_cents', 0,
                              'out_of_area', true, 'max_distance_km', v_max);
  END IF;
  IF v_d <= v_free THEN
    v_fee := 0;
  ELSIF v_d <= v_t1_km THEN
    v_fee := v_t1_cents;
  ELSE
    v_fee := v_t2_base + (round(v_d - v_t1_km) * v_per_km)::int;
  END IF;
  RETURN jsonb_build_object('distance_km', v_d, 'travel_fee_cents', v_fee,
                            'out_of_area', false, 'max_distance_km', v_max);
END $function$;

GRANT EXECUTE ON FUNCTION public.cleaning_travel_fee(double precision, double precision) TO authenticated, service_role;

-- Preço com a morada: o mesmo cálculo de cleaning_quote + taxa de deslocação.
CREATE OR REPLACE FUNCTION public.cleaning_quote_at(p_cleaning_type text, p_pricing_mode text, p_home_size text, p_hours integer, p_recurrence text, p_products_by text, p_lat double precision, p_lng double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_q jsonb; v_travel jsonb; v_travel_cents int := 0; v_out boolean;
  v_total int; v_products int; v_bora int; v_bora_pct int;
BEGIN
  v_q := public.cleaning_quote(p_cleaning_type, p_pricing_mode, p_home_size, p_hours,
                               COALESCE(p_recurrence, 'single'), COALESCE(p_products_by, 'client'));
  v_travel := public.cleaning_travel_fee(p_lat, p_lng);
  v_out := COALESCE((v_travel ->> 'out_of_area')::boolean, false);
  IF NOT v_out THEN
    v_travel_cents := COALESCE((v_travel ->> 'travel_fee_cents')::int, 0);
  END IF;
  v_products := (v_q ->> 'products_fee_cents')::int;
  v_total    := (v_q ->> 'total_cents')::int + v_travel_cents;
  v_bora_pct := public._cleaning_setting_int('cleaning_bora_pct', 15);
  -- a Bora só leva % da limpeza (sem produtos e sem deslocação)
  v_bora     := round((v_total - v_products - v_travel_cents) * v_bora_pct / 100.0)::int;
  RETURN v_q || jsonb_build_object(
    'travel_fee_cents', v_travel_cents,
    'travel_distance_km', v_travel -> 'distance_km',
    'out_of_area', v_out,
    'max_distance_km', v_travel -> 'max_distance_km',
    'total_cents', v_total,
    'bora_fee_cents', v_bora,
    'cleaner_earnings_cents', v_total - v_bora);
END $function$;

GRANT EXECUTE ON FUNCTION public.cleaning_quote_at(text, text, text, integer, text, text, double precision, double precision) TO authenticated, service_role;

-- create_cleaning_booking e generate_recurring_bookings: só se trocam os pedaços necessários
-- (o resto do corpo fica exatamente igual).
DO $mig$
DECLARE
  v_def text; v_new text;
BEGIN
  -- 1) create_cleaning_booking
  v_def := pg_get_functiondef('public.create_cleaning_booking(text,text,text,integer,timestamptz,text,text,text,text,text,text,double precision,double precision,text,uuid,text)'::regprocedure);
  v_new := replace(v_def,
    'v_quote := public.cleaning_quote(p_cleaning_type',
    'v_quote := public.cleaning_quote_at(p_cleaning_type');
  IF v_new = v_def THEN RAISE EXCEPTION 'create_cleaning_booking: troca 0 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    'p_hours, p_recurrence, p_products_by);',
    E'p_hours, p_recurrence, p_products_by, p_lat, p_lng);\n'
    || E'  -- 19/11/2026: limpeza só até cleaning_max_distance_km do centro da Guarda\n'
    || E'  IF COALESCE((v_quote ->> ''out_of_area'')::boolean, false) THEN\n'
    || E'    RAISE EXCEPTION ''fora_da_area_limpeza: ainda não fazemos limpezas a mais de % km da Guarda'', v_quote ->> ''max_distance_km'';\n'
    || E'  END IF;');
  IF v_new = v_def THEN RAISE EXCEPTION 'create_cleaning_booking: troca 1 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    E'bora_fee_cents,\n    idempotency_key',
    E'bora_fee_cents,\n    travel_fee_cents, travel_distance_km,\n    idempotency_key');
  IF v_new = v_def THEN RAISE EXCEPTION 'create_cleaning_booking: troca 2 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    E'(v_quote ->> ''bora_fee_cents'')::int,\n    v_key',
    E'(v_quote ->> ''bora_fee_cents'')::int,\n    COALESCE((v_quote ->> ''travel_fee_cents'')::int, 0), NULLIF(v_quote ->> ''travel_distance_km'', '''')::numeric,\n    v_key');
  IF v_new = v_def THEN RAISE EXCEPTION 'create_cleaning_booking: troca 3 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    E'  PERFORM public._cleaning_next_offer(v_id);\n',
    E'  PERFORM public._cleaning_next_offer(v_id);\n\n'
    || E'  -- 19/11/2026: avisa o cliente da taxa de deslocação (morada longe do centro da Guarda)\n'
    || E'  IF COALESCE((v_quote ->> ''travel_fee_cents'')::int, 0) > 0 THEN\n'
    || E'    BEGIN\n'
    || E'      PERFORM public._cleaning_notify_user(v_uid, ''cleaning_travel_fee'', ''Taxa de deslocação'',\n'
    || E'        ''A tua morada fica a '' || replace((v_quote ->> ''travel_distance_km''), ''.'', '','') || '' km do centro da Guarda: a limpeza inclui ''\n'
    || E'        || to_char(((v_quote ->> ''travel_fee_cents'')::int) / 100.0, ''FM990D00'') || '' € de deslocação. Total: ''\n'
    || E'        || to_char(((v_quote ->> ''total_cents'')::int) / 100.0, ''FM990D00'') || '' €.'',\n'
    || E'        v_id::text);\n'
    || E'    EXCEPTION WHEN OTHERS THEN\n'
    || E'      RAISE NOTICE ''create_cleaning_booking: aviso da taxa falhou (%)'', sqlerrm;\n'
    || E'    END;\n'
    || E'  END IF;\n');
  IF v_new = v_def THEN RAISE EXCEPTION 'create_cleaning_booking: troca 4 falhou'; END IF;
  EXECUTE v_new;

  -- 2) generate_recurring_bookings (série semanal/quinzenal leva a taxa em cada visita)
  v_def := pg_get_functiondef('public.generate_recurring_bookings()'::regprocedure);
  v_new := replace(v_def,
    'v_quote := public.cleaning_quote(v_last.cleaning_type',
    'v_quote := public.cleaning_quote_at(v_last.cleaning_type');
  IF v_new = v_def THEN RAISE EXCEPTION 'generate_recurring_bookings: troca 0 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    'v_last.recurrence, v_last.products_by);',
    E'v_last.recurrence, v_last.products_by,\n                                     v_last.lat, v_last.lng);');
  IF v_new = v_def THEN RAISE EXCEPTION 'generate_recurring_bookings: troca 1 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    E'cleaner_earnings_cents, bora_fee_cents\n    ) VALUES',
    E'cleaner_earnings_cents, bora_fee_cents,\n      travel_fee_cents, travel_distance_km\n    ) VALUES');
  IF v_new = v_def THEN RAISE EXCEPTION 'generate_recurring_bookings: troca 2 falhou'; END IF;
  v_def := v_new;
  v_new := replace(v_def,
    E'(v_quote ->> ''bora_fee_cents'')::int\n    ) RETURNING',
    E'(v_quote ->> ''bora_fee_cents'')::int,\n      COALESCE((v_quote ->> ''travel_fee_cents'')::int, 0), NULLIF(v_quote ->> ''travel_distance_km'', '''')::numeric\n    ) RETURNING');
  IF v_new = v_def THEN RAISE EXCEPTION 'generate_recurring_bookings: troca 3 falhou'; END IF;
  EXECUTE v_new;
END $mig$;

NOTIFY pgrst, 'reload schema';
