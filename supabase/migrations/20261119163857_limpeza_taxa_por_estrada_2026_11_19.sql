-- APLICADA EM PRODUÇÃO pela Claude.ai via MCP a 19/11/2026 (versão 20261119163857). Cópia fiel para o repo.
-- 19/11/2026 16:35 correção do Danilo: "não tem que ser em linha reta, tem que somar em estrada mesmo".
-- A distância da taxa de deslocação passa a ser de CARRO desde o centro da Guarda, lida da grelha
-- cleaning_road_grid (Google Distance Matrix, 811 pontos de 1,5 km). Pela estrada o centro de Celorico
-- dá 28,6 km, por isso o máximo passa a 32 km para Celorico e arredores caberem.

INSERT INTO public.platform_settings(key, value, description, category) VALUES
 ('cleaning_travel_distance_mode', to_jsonb('estrada'::text), 'Limpeza: como se mede a distância da taxa de deslocação (estrada = km de carro desde o centro da Guarda)', 'cleaning'),
 ('cleaning_road_fallback_factor', to_jsonb(1.63), 'Limpeza: fator linha reta → estrada usado só fora da grelha de estradas', 'cleaning')
ON CONFLICT (key) DO NOTHING;

UPDATE public.platform_settings SET value = to_jsonb(32), updated_at = now(),
       description = 'Limpeza: distância máxima PELA ESTRADA ao centro da Guarda (acima disto não se aceita a limpeza)'
 WHERE key = 'cleaning_max_distance_km';
UPDATE public.platform_settings SET description = 'Limpeza: até estes km de ESTRADA do centro da Guarda não há taxa de deslocação', updated_at = now()
 WHERE key = 'cleaning_travel_free_km';
UPDATE public.platform_settings SET description = 'Limpeza: até estes km de ESTRADA cobra a taxa fixa do 1.º escalão', updated_at = now()
 WHERE key = 'cleaning_travel_tier1_max_km';

-- km de estrada desde o centro da Guarda até (lat,lng)
CREATE OR REPLACE FUNCTION public.cleaning_road_km(p_lat double precision, p_lng double precision)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clat double precision := COALESCE((SELECT (value #>> '{}')::double precision FROM platform_settings WHERE key='cleaning_travel_center_lat'), 40.5373);
  v_clng double precision := COALESCE((SELECT (value #>> '{}')::double precision FROM platform_settings WHERE key='cleaning_travel_center_lng'), -7.2676);
  v_fator numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_road_fallback_factor'), 1.63);
  v_reta numeric;
  v_ponto record;
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN RETURN NULL; END IF;
  v_reta := public._cleaning_distance_km(v_clat, v_clng, p_lat, p_lng)::numeric;
  -- muito perto do centro: a estrada é praticamente a mesma coisa
  IF v_reta < 0.5 THEN RETURN round(v_reta, 1); END IF;

  SELECT g.road_km, public._cleaning_distance_km(g.lat, g.lng, p_lat, p_lng)::numeric AS d
    INTO v_ponto
    FROM cleaning_road_grid g
   WHERE g.status = 'OK' AND g.road_km IS NOT NULL
     AND g.lat BETWEEN p_lat - 0.03 AND p_lat + 0.03
     AND g.lng BETWEEN p_lng - 0.04 AND p_lng + 0.04
   ORDER BY public._cleaning_distance_km(g.lat, g.lng, p_lat, p_lng)
   LIMIT 1;

  IF v_ponto.road_km IS NOT NULL AND v_ponto.d <= 2.0 THEN
    -- km de estrada até ao ponto da grelha + o bocadinho até à porta (com curvas)
    RETURN round(v_ponto.road_km + v_ponto.d * 1.3, 1);
  END IF;
  -- fora da grelha (mais de ~24 km em linha reta): estimativa
  RETURN round(v_reta * v_fator, 1);
END $function$;

GRANT EXECUTE ON FUNCTION public.cleaning_road_km(double precision, double precision) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.cleaning_travel_fee(p_lat double precision, p_lng double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_free numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_travel_free_km'), 10);
  v_t1_km numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_travel_tier1_max_km'), 15);
  v_t1_cents int := COALESCE((SELECT (value #>> '{}')::int FROM platform_settings WHERE key='cleaning_travel_tier1_cents'), 800);
  v_t2_base int := COALESCE((SELECT (value #>> '{}')::int FROM platform_settings WHERE key='cleaning_travel_tier2_base_cents'), 1500);
  v_per_km int := COALESCE((SELECT (value #>> '{}')::int FROM platform_settings WHERE key='cleaning_travel_per_km_cents'), 100);
  v_max numeric := COALESCE((SELECT (value #>> '{}')::numeric FROM platform_settings WHERE key='cleaning_max_distance_km'), 32);
  v_d numeric;
  v_fee int := 0;
BEGIN
  -- Sem coordenadas não se trava a limpeza (regra "a localização nunca trava"): taxa 0.
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object('distance_km', NULL, 'travel_fee_cents', 0,
                              'out_of_area', false, 'max_distance_km', v_max, 'distance_mode', 'estrada');
  END IF;
  v_d := public.cleaning_road_km(p_lat, p_lng);   -- km de ESTRADA (19/11/2026)
  IF v_d > v_max THEN
    RETURN jsonb_build_object('distance_km', v_d, 'travel_fee_cents', 0,
                              'out_of_area', true, 'max_distance_km', v_max, 'distance_mode', 'estrada');
  END IF;
  IF v_d <= v_free THEN
    v_fee := 0;
  ELSIF v_d <= v_t1_km THEN
    v_fee := v_t1_cents;
  ELSE
    v_fee := v_t2_base + (round(v_d - v_t1_km) * v_per_km)::int;
  END IF;
  RETURN jsonb_build_object('distance_km', v_d, 'travel_fee_cents', v_fee,
                            'out_of_area', false, 'max_distance_km', v_max, 'distance_mode', 'estrada');
END $function$;
