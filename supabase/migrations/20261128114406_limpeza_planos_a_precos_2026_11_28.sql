-- Missão limpeza-planos-empresas-2026-11-28, Bloco A (preços dos planos e Bora Empresas).
-- Autorização do Danilo 28/11/2026 (09:25, 09:26, ~10:28 "Sim, aplica tu", 11:43 "eu tô autorizando e tem que fazer tudo").
-- Só cria coisas novas: não mexe em cleaning_quote*, create_cleaning_booking nem nas séries antigas.
-- JÁ APLICADA no servidor pela Claude.ai a 28/11/2026 11:44 (versão 20261128114406, e2e 17563).
-- Este ficheiro é a cópia fiel de supabase_migrations.schema_migrations, para o repo ficar igual ao servidor.
CREATE TABLE IF NOT EXISTS public.cleaning_plan_prices (
  segment text NOT NULL CHECK (segment IN ('casa','empresa')),
  frequency text NOT NULL,
  client_cents_per_hour integer NOT NULL CHECK (client_cents_per_hour > 0),
  pro_cents_per_hour integer NOT NULL CHECK (pro_cents_per_hour > 0),
  min_hours numeric(4,1) NOT NULL DEFAULT 2 CHECK (min_hours > 0),
  products_included boolean NOT NULL DEFAULT false,
  visits_per_week_default numeric(4,2) NOT NULL DEFAULT 1,
  sort integer NOT NULL DEFAULT 0,
  label_pt text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  PRIMARY KEY (segment, frequency),
  CONSTRAINT cleaning_plan_prices_pro_le_client CHECK (pro_cents_per_hour <= client_cents_per_hour),
  CONSTRAINT cleaning_plan_prices_freq_ok CHECK (
    (segment = 'casa' AND frequency IN ('once','biweekly','weekly','multi_weekly')) OR
    (segment = 'empresa' AND frequency IN ('once','weekly_1','weekly_2','weekly_3plus')))
);

COMMENT ON TABLE public.cleaning_plan_prices IS
'Preços por hora dos planos de limpeza (casas e Bora Empresas) e o que a profissional recebe por hora. Valores do Danilo 28/11/2026. Editar só por admin_set_cleaning_plan_price (auditado).';

INSERT INTO public.cleaning_plan_prices
  (segment, frequency, client_cents_per_hour, pro_cents_per_hour, min_hours, products_included, visits_per_week_default, sort, label_pt)
VALUES
  ('casa','once',         1200, 1020, 2, false, 0,    1, 'Uma vez'),
  ('casa','biweekly',     1100,  935, 2, false, 0.5,  2, 'De 15 em 15 dias'),
  ('casa','weekly',       1000,  918, 2, false, 1,    3, 'Semanal'),
  ('casa','multi_weekly',  980,  900, 2, false, 2,    4, 'Mais de uma vez por semana'),
  ('empresa','once',      1500, 1275, 1, true,  0,    1, 'Uma vez'),
  ('empresa','weekly_1',  1400, 1190, 1, true,  1,    2, '1 vez por semana'),
  ('empresa','weekly_2',  1300, 1105, 1, true,  2,    3, '2 vezes por semana'),
  ('empresa','weekly_3plus',1200,1020,1, true,  3,    4, '3 ou mais vezes por semana')
ON CONFLICT (segment, frequency) DO NOTHING;

ALTER TABLE public.cleaning_plan_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY cleaning_plan_prices_ler ON public.cleaning_plan_prices FOR SELECT TO anon, authenticated USING (true);

CREATE OR REPLACE FUNCTION public.admin_set_cleaning_plan_price(
  p_segment text, p_frequency text, p_client_cents_per_hour integer,
  p_pro_cents_per_hour integer, p_min_hours numeric DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE g record; v_old record; v_new record;
BEGIN
  SELECT * INTO g FROM public._admin_op_guard();
  SELECT * INTO v_old FROM cleaning_plan_prices WHERE segment = p_segment AND frequency = p_frequency;
  IF NOT FOUND THEN RAISE EXCEPTION 'plano_inexistente: % %', p_segment, p_frequency; END IF;
  IF p_client_cents_per_hour IS NULL OR p_client_cents_per_hour <= 0
     OR p_pro_cents_per_hour IS NULL OR p_pro_cents_per_hour <= 0
     OR p_pro_cents_per_hour > p_client_cents_per_hour THEN
    RAISE EXCEPTION 'valores_invalidos: a profissional nao pode receber mais do que o cliente paga';
  END IF;
  UPDATE cleaning_plan_prices
     SET client_cents_per_hour = p_client_cents_per_hour,
         pro_cents_per_hour = p_pro_cents_per_hour,
         min_hours = COALESCE(p_min_hours, min_hours),
         updated_at = now(), updated_by = g.admin_id
   WHERE segment = p_segment AND frequency = p_frequency
   RETURNING * INTO v_new;
  INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (g.admin_id, g.admin_email, 'cleaning_plan_price_set', 'cleaning_plan_prices',
          p_segment || ':' || p_frequency,
          jsonb_build_object('antes', to_jsonb(v_old), 'depois', to_jsonb(v_new)));
  RETURN to_jsonb(v_new);
END $$;

CREATE OR REPLACE FUNCTION public.cleaning_plan_quote(
  p_segment text, p_frequency text, p_hours numeric,
  p_days_per_week integer DEFAULT NULL, p_team_size integer DEFAULT 1,
  p_products_by text DEFAULT 'client', p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  pr record; v_team int; v_max_team int; v_travel jsonb; v_travel_cents int := 0;
  v_labor int; v_products int := 0; v_pro_hour_cents int; v_bora int; v_total int;
  v_visits_week numeric; v_visits_month numeric; v_shares jsonb := '[]'::jsonb; i int;
  v_ladder jsonb;
BEGIN
  SELECT * INTO pr FROM cleaning_plan_prices WHERE segment = p_segment AND frequency = p_frequency;
  IF NOT FOUND THEN RAISE EXCEPTION 'plano_inexistente: % %', p_segment, p_frequency; END IF;
  IF p_hours IS NULL OR p_hours < pr.min_hours THEN
    RAISE EXCEPTION 'horas_minimas: % h', pr.min_hours;
  END IF;
  IF p_hours > 10 THEN RAISE EXCEPTION 'horas_maximas: 10 h'; END IF;
  IF (p_hours * 2) <> floor(p_hours * 2) THEN RAISE EXCEPTION 'horas_em_meias_horas'; END IF;

  v_max_team := COALESCE(_cleaning_setting_int('cleaning_max_professionals', 3), 3);
  v_team := GREATEST(1, LEAST(COALESCE(p_team_size, 1), v_max_team));

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_travel := cleaning_travel_fee(p_lat, p_lng);
    IF COALESCE((v_travel->>'out_of_area')::boolean, false) THEN
      RAISE EXCEPTION 'fora_da_area: % km', v_travel->>'distance_km';
    END IF;
    v_travel_cents := COALESCE((v_travel->>'travel_fee_cents')::int, 0);
  END IF;

  IF NOT pr.products_included AND p_products_by = 'cleaner' THEN
    v_products := COALESCE(_cleaning_setting_int('cleaning_products_fee_cents', 300), 300);
  END IF;

  v_labor := round(pr.client_cents_per_hour * p_hours)::int * v_team;
  v_pro_hour_cents := round(pr.pro_cents_per_hour * p_hours)::int;
  v_bora := v_labor - v_pro_hour_cents * v_team;
  v_total := v_labor + v_products + v_travel_cents * v_team;

  FOR i IN 1..v_team LOOP
    v_shares := v_shares || jsonb_build_object(
      'slot', i,
      'pro_cents', v_pro_hour_cents + v_travel_cents + CASE WHEN i = 1 THEN v_products ELSE 0 END,
      'client_cents', round(pr.client_cents_per_hour * p_hours)::int + v_travel_cents + CASE WHEN i = 1 THEN v_products ELSE 0 END);
  END LOOP;

  v_visits_week := CASE
    WHEN p_frequency = 'once' THEN 0
    WHEN p_frequency = 'biweekly' THEN 0.5
    WHEN p_frequency IN ('weekly','weekly_1') THEN 1
    WHEN p_frequency = 'weekly_2' THEN 2
    WHEN p_frequency = 'multi_weekly' THEN GREATEST(2, LEAST(COALESCE(p_days_per_week, 2), 7))
    WHEN p_frequency = 'weekly_3plus' THEN GREATEST(3, LEAST(COALESCE(p_days_per_week, 3), 7))
    ELSE pr.visits_per_week_default END;
  v_visits_month := CASE WHEN p_frequency = 'once' THEN 1 ELSE round(v_visits_week * 52.0 / 12.0, 2) END;

  SELECT jsonb_agg(jsonb_build_object('frequency', frequency, 'label', label_pt,
           'client_cents_per_hour', client_cents_per_hour) ORDER BY sort)
    INTO v_ladder FROM cleaning_plan_prices WHERE segment = p_segment;

  RETURN jsonb_build_object(
    'segment', p_segment, 'frequency', p_frequency, 'label', pr.label_pt,
    'hours', p_hours, 'team_size', v_team,
    'client_cents_per_hour', pr.client_cents_per_hour,
    'pro_cents_per_hour', pr.pro_cents_per_hour,
    'labor_cents', v_labor, 'products_cents', v_products, 'products_included', pr.products_included,
    'travel_fee_cents_per_pro', v_travel_cents, 'travel_fee_cents', v_travel_cents * v_team,
    'travel', v_travel,
    'total_per_visit_cents', v_total,
    'pro_earnings_cents', v_pro_hour_cents * v_team + v_travel_cents * v_team + v_products,
    'bora_fee_cents', v_bora,
    'shares', v_shares,
    'visits_per_week', v_visits_week, 'visits_per_month', v_visits_month,
    'approx_month_cents', CASE WHEN p_frequency = 'once' THEN v_total ELSE round(v_total * v_visits_month)::int END,
    'min_hours', pr.min_hours, 'ladder', v_ladder,
    'card_only', p_frequency <> 'once');
END $$;

GRANT SELECT ON public.cleaning_plan_prices TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleaning_plan_quote(text,text,numeric,integer,integer,text,double precision,double precision) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_cleaning_plan_price(text,text,integer,integer,numeric) TO authenticated;
