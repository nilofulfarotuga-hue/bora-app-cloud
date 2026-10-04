-- Agente parceiro (ronda 04/10/2026)
-- A5 pausar a loja · produto esgotado com volta automática · dias fechados (feriados)
-- A5 tempo de preparação ao aceitar · A2/ALTO 3 "Chamar estafeta" calculado no servidor
-- #5 avaliações das marcações (barbearias) → service_providers.avg_rating/ratings_count

-- ── Pausa da loja ──────────────────────────────────────────────────────────
ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS pausa_ate timestamptz;
COMMENT ON COLUMN public.restaurants.pausa_ate IS
  'Loja em pausa até esta hora (null = sem pausa). create_order/quote recusam STORE_PAUSED; a app do cliente mostra "Fechada temporariamente — volta às HH:MM".';

CREATE OR REPLACE FUNCTION public._parceiro_pode_loja(p_restaurant_id text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT auth.uid() IS NOT NULL AND (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.restaurants r
                WHERE r.id = p_restaurant_id
                  AND (r.user_id = auth.uid() OR r.user_ = auth.uid())));
$fn$;
REVOKE ALL ON FUNCTION public._parceiro_pode_loja(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._parceiro_pode_loja(text) TO authenticated, service_role;

-- p_minutos: 0 = retomar já; -1 = até à hora de fecho de hoje; 1..480 = minutos.
CREATE OR REPLACE FUNCTION public.partner_pausar_loja(p_restaurant_id text, p_minutos integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ate timestamptz;
  v_estado jsonb;
BEGIN
  IF NOT public._parceiro_pode_loja(p_restaurant_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF p_minutos IS NULL OR p_minutos < -1 OR p_minutos > 480 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'minutos_invalidos');
  END IF;

  IF p_minutos = 0 THEN
    v_ate := NULL;
  ELSIF p_minutos = -1 THEN
    v_estado := public.is_partner_open(p_restaurant_id, now());
    IF COALESCE((v_estado->>'is_open')::boolean, false)
       AND (v_estado->>'closes_in_minutes') IS NOT NULL THEN
      v_ate := now() + make_interval(mins => (v_estado->>'closes_in_minutes')::int);
    ELSE
      -- Sem hora de fecho conhecida: até ao fim do dia (Lisboa).
      v_ate := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') + interval '1 day')
               AT TIME ZONE 'Europe/Lisbon';
    END IF;
  ELSE
    v_ate := now() + make_interval(mins => p_minutos);
  END IF;

  UPDATE public.restaurants SET pausa_ate = v_ate WHERE id = p_restaurant_id;

  RETURN jsonb_build_object(
    'ok', true,
    'pausa_ate', v_ate,
    'volta_as', CASE WHEN v_ate IS NULL THEN NULL
                     ELSE to_char(v_ate AT TIME ZONE 'Europe/Lisbon', 'HH24:MI') END);
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_pausar_loja(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_pausar_loja(text, integer) TO authenticated, service_role;

-- ── Produto esgotado com volta automática ─────────────────────────────────
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS esgotado_ate timestamptz;
COMMENT ON COLUMN public.products.esgotado_ate IS
  'Esgotado até esta hora: o cron produtos-esgotados-voltam põe is_available=true e limpa a coluna.';

-- p_modo: 'ate_amanha' (volta à meia-noite de Lisboa), 'sem_data' (fica esgotado),
--         'disponivel' (volta já).
CREATE OR REPLACE FUNCTION public.partner_produto_esgotado(p_product_id text, p_modo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_rest text;
  v_ate timestamptz;
BEGIN
  SELECT restaurant_id INTO v_rest FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'produto_nao_encontrado');
  END IF;
  IF NOT public._parceiro_pode_loja(v_rest) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  IF p_modo = 'disponivel' THEN
    UPDATE public.products SET is_available = true, esgotado_ate = NULL WHERE id = p_product_id;
  ELSIF p_modo = 'sem_data' THEN
    UPDATE public.products SET is_available = false, esgotado_ate = NULL WHERE id = p_product_id;
  ELSIF p_modo = 'ate_amanha' THEN
    v_ate := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') + interval '1 day')
             AT TIME ZONE 'Europe/Lisbon';
    UPDATE public.products SET is_available = false, esgotado_ate = v_ate WHERE id = p_product_id;
  ELSE
    RETURN jsonb_build_object('ok', false, 'error', 'modo_invalido');
  END IF;

  RETURN jsonb_build_object('ok', true, 'modo', p_modo, 'esgotado_ate', v_ate);
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_produto_esgotado(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_produto_esgotado(text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.produtos_esgotados_voltam()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_n integer;
BEGIN
  UPDATE public.products
     SET is_available = true, esgotado_ate = NULL
   WHERE esgotado_ate IS NOT NULL AND esgotado_ate <= now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$fn$;
REVOKE ALL ON FUNCTION public.produtos_esgotados_voltam() FROM PUBLIC, anon, authenticated;

DO $cron$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'produtos-esgotados-voltam') THEN
    PERFORM cron.schedule('produtos-esgotados-voltam', '*/10 * * * *',
                          'select public.produtos_esgotados_voltam()');
  END IF;
END $cron$;

-- ── Horário e dias fechados (feriados) ─────────────────────────────────────
-- Guardar o horário semanal SEM perder os dias especiais (antes a app do
-- parceiro escrevia business_hours inteiro e apagava os special_dates do admin).
CREATE OR REPLACE FUNCTION public.partner_guardar_horario(p_restaurant_id text, p_hours jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_atual jsonb;
  v_novo jsonb;
BEGIN
  IF NOT public._parceiro_pode_loja(p_restaurant_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF p_hours IS NULL OR jsonb_typeof(p_hours) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'horario_invalido');
  END IF;
  SELECT COALESCE(business_hours, '{}'::jsonb) INTO v_atual FROM public.restaurants WHERE id = p_restaurant_id;
  v_novo := p_hours - 'special_dates';
  IF v_atual ? 'special_dates' THEN
    v_novo := v_novo || jsonb_build_object('special_dates', v_atual->'special_dates');
  END IF;
  UPDATE public.restaurants SET business_hours = v_novo WHERE id = p_restaurant_id;
  RETURN jsonb_build_object('ok', true, 'business_hours', v_novo);
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_guardar_horario(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_guardar_horario(text, jsonb) TO authenticated, service_role;

-- Define a lista de dias em que a loja está FECHADA o dia todo (feriados,
-- férias). Substitui os dias fechados anteriores; os dias com horário
-- especial postos pelo admin (com open/close) ficam intactos. Datas passadas
-- são ignoradas.
CREATE OR REPLACE FUNCTION public.partner_dias_fechados(p_restaurant_id text, p_datas date[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_hours jsonb;
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_mantidos jsonb;
  v_fechados jsonb;
BEGIN
  IF NOT public._parceiro_pode_loja(p_restaurant_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF COALESCE(cardinality(p_datas), 0) > 60 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'demasiadas_datas');
  END IF;
  SELECT COALESCE(business_hours, '{}'::jsonb) INTO v_hours FROM public.restaurants WHERE id = p_restaurant_id;

  SELECT COALESCE(jsonb_agg(e), '[]'::jsonb) INTO v_mantidos
    FROM jsonb_array_elements(COALESCE(v_hours->'special_dates', '[]'::jsonb)) e
   WHERE NOT (COALESCE((e->>'closed')::boolean, false) AND (e->>'open') IS NULL)
     AND NOT ((e->>'date')::date = ANY (COALESCE(p_datas, '{}'::date[])));

  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d::text, 'closed', true) ORDER BY d), '[]'::jsonb)
    INTO v_fechados
    FROM (SELECT DISTINCT unnest(COALESCE(p_datas, '{}'::date[])) AS d) x
   WHERE d >= v_hoje;

  v_hours := v_hours || jsonb_build_object('special_dates', v_mantidos || v_fechados);
  UPDATE public.restaurants SET business_hours = v_hours WHERE id = p_restaurant_id;
  RETURN jsonb_build_object('ok', true, 'dias_fechados', v_fechados);
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_dias_fechados(text, date[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_dias_fechados(text, date[]) TO authenticated, service_role;

-- ── Aceitar com tempo de preparação ────────────────────────────────────────
-- O despacho chama o estafeta em accepted_at + prep - 8 min (cron 72,
-- partner_auto_dispatch_ready_orders, agente despacho).
CREATE OR REPLACE FUNCTION public.partner_aceitar_pedido(p_order_id text, p_prep_minutes integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_res jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_prep_minutes IS NOT NULL AND (p_prep_minutes < 5 OR p_prep_minutes > 120) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_prep_minutes');
  END IF;
  v_res := public.partner_accept_order(p_order_id);
  IF COALESCE((v_res->>'ok')::boolean, false) AND p_prep_minutes IS NOT NULL THEN
    UPDATE public.orders SET prep_time_minutes = p_prep_minutes
     WHERE id = p_order_id AND status = 'preparing';
    v_res := v_res || jsonb_build_object('prep_time_minutes', p_prep_minutes);
  END IF;
  RETURN v_res;
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_aceitar_pedido(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_aceitar_pedido(text, integer) TO authenticated, service_role;

-- ── "Chamar estafeta" (cliente que pediu ao balcão/telefone) — §2.4.1 ──────
-- Nenhum valor de dinheiro vem do telemóvel: o servidor lê o PREÇO DE BALCÃO
-- de cada produto (partner_shelf_price; sem ele, a parte da loja do preço da
-- app) e calcula: comissão 10 % (visível), taxa de serviço 5 %, entrega pela
-- tabela; sem markup oculto e sem saco. O cliente paga tudo em dinheiro.
-- Ganho do estafeta = o de um pedido de parceiro normal.

-- A guarda de horário não trava um pedido criado pelo próprio parceiro.
CREATE OR REPLACE FUNCTION public._store_closed_guard_orders()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_estado JSONB;
  v_abre   TEXT;
BEGIN
  IF NEW.restaurant_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.service_type NOT IN ('restaurant','storeShopping','takeaway') THEN
    RETURN NEW;
  END IF;

  -- 04/10/2026: "Chamar estafeta" do parceiro (partner_chamar_estafeta).
  IF COALESCE(current_setting('app.parceiro_chama_estafeta', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  v_estado := public.is_partner_open(NEW.restaurant_id);

  IF COALESCE((v_estado->>'is_open')::boolean, true) IS FALSE THEN
    v_abre := v_estado->>'opens_at';
    RAISE EXCEPTION 'STORE_CLOSED: A loja esta fechada neste momento.%',
      CASE WHEN v_abre IS NOT NULL THEN ' Abre as ' || v_abre || '.' ELSE '' END
      USING ERRCODE = 'P0001', HINT = 'STORE_CLOSED';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.partner_chamar_estafeta(
  p_restaurant_id text,
  p_itens jsonb,
  p_nome_cliente text,
  p_telefone_cliente text,
  p_morada text,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_notas text DEFAULT NULL,
  p_distancia_km numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  r public.restaurants%ROWTYPE;
  v_item jsonb;
  v_prod record;
  v_qtd integer;
  v_unit numeric;
  v_itens jsonb := '[]'::jsonb;
  v_sub numeric := 0;
  v_hav numeric;
  v_dist numeric;
  v_estimada boolean := true;
  v_pc record;
  v_comm_pct numeric;
  v_svc_pct numeric;
  v_comm numeric;
  v_svc numeric;
  v_total numeric;
  v_id text := gen_random_uuid()::text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO r FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND OR NOT (r.user_id = auth.uid() OR r.user_ = auth.uid() OR public.is_admin()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT COALESCE(r.is_partner, false) OR r.approval_status <> 'approved'
     OR NOT COALESCE(r.is_active_admin, true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'loja_nao_parceira');
  END IF;
  IF NULLIF(trim(COALESCE(p_morada, '')), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'morada_em_falta');
  END IF;
  IF p_itens IS NULL OR jsonb_typeof(p_itens) <> 'array' OR jsonb_array_length(p_itens) = 0
     OR jsonb_array_length(p_itens) > 50 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'itens_invalidos');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_itens) LOOP
    v_qtd := COALESCE((v_item->>'quantity')::integer, 0);
    IF v_qtd < 1 OR v_qtd > 50 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'quantidade_invalida');
    END IF;
    SELECT p.id, p.name, p.price, p.partner_shelf_price INTO v_prod
      FROM public.products p
     WHERE p.id = v_item->>'product_id' AND p.restaurant_id = p_restaurant_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'produto_nao_encontrado',
                                'product_id', v_item->>'product_id');
    END IF;
    v_unit := COALESCE(v_prod.partner_shelf_price,
                       public.partner_store_share(COALESCE(v_prod.price, 0), p_restaurant_id));
    v_unit := ROUND(v_unit, 2);
    IF v_unit <= 0 THEN
      RETURN jsonb_build_object('ok', false, 'error', 'produto_sem_preco', 'product_id', v_prod.id);
    END IF;
    v_sub := v_sub + v_unit * v_qtd;
    v_itens := v_itens || jsonb_build_array(jsonb_build_object(
      'productId', v_prod.id, 'name', v_prod.name, 'price', v_unit, 'basePrice', v_unit,
      'quantity', v_qtd, 'purchaseStatus', 'pending'));
  END LOOP;
  v_sub := ROUND(v_sub, 2);

  -- Distância: a do mapa da app, mas presa entre a linha reta e 2,5× a linha reta.
  IF r.lat IS NOT NULL AND r.lng IS NOT NULL AND p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_hav := public._haversine_km(r.lat, r.lng, p_lat, p_lng)::numeric;
    IF p_distancia_km IS NOT NULL AND p_distancia_km > 0 THEN
      v_dist := LEAST(GREATEST(p_distancia_km, v_hav), v_hav * 2.5);
      v_estimada := false;
    ELSE
      v_dist := v_hav * 1.3;
    END IF;
  ELSE
    v_dist := 1;
  END IF;
  v_dist := ROUND(GREATEST(v_dist, 0), 2);

  SELECT * INTO v_pc FROM public.pricing_calculate('restaurant', v_sub, v_dist, true, false, false, 0);
  SELECT COALESCE((SELECT (value::text)::numeric FROM public.platform_settings WHERE key = 'partner_visible_commission_pct'), 0.10)
    INTO v_comm_pct;
  SELECT COALESCE((SELECT (value::text)::numeric FROM public.platform_settings WHERE key = 'client_service_fee_pct'), 0.05)
    INTO v_svc_pct;
  v_comm  := ROUND(v_sub * v_comm_pct, 2);
  v_svc   := ROUND(v_sub * v_svc_pct, 2);
  v_total := ROUND(v_sub + v_comm + v_svc + v_pc.delivery_fee, 2);

  PERFORM set_config('app.parceiro_chama_estafeta', 'on', true);

  INSERT INTO public.orders (
    id, user_id, service_type, order_type, status, is_partner_store, restaurant_id,
    vendor_name, pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    customer_name, client_phone, customer_notes, items,
    subtotal, delivery_fee, service_fee, bag_fee, bag_count,
    platform_commission, partner_commission_visible, partner_service_fee_client,
    partner_markup_hidden, driver_earnings, distance_km, is_distance_estimated,
    price, final_total, payment_buffer_total,
    payment_method, payment_status, apartment_delivery
  ) VALUES (
    v_id, NULL, 'restaurant', 'partnerRestaurant', 'callingDriver', true, r.id,
    r.name, r.address, r.lat, r.lng,
    trim(p_morada), p_lat, p_lng,
    NULLIF(trim(COALESCE(p_nome_cliente, '')), ''), NULLIF(trim(COALESCE(p_telefone_cliente, '')), ''),
    NULLIF(trim(COALESCE(p_notas, '')), ''), v_itens,
    v_sub, v_pc.delivery_fee, v_svc, 0, 0,
    v_comm + v_svc, v_comm, v_svc,
    NULL, v_pc.driver_earnings, v_dist, v_estimada,
    v_total, v_total, v_total,
    'cash', 'pending', false
  );

  PERFORM set_config('app.parceiro_chama_estafeta', '', true);

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', v_id,
    'subtotal', v_sub,
    'comissao', v_comm,
    'taxa_servico', v_svc,
    'entrega', v_pc.delivery_fee,
    'total', v_total,
    'ganho_estafeta', v_pc.driver_earnings,
    'distancia_km', v_dist);
END;
$fn$;
REVOKE ALL ON FUNCTION public.partner_chamar_estafeta(text, jsonb, text, text, text, double precision, double precision, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.partner_chamar_estafeta(text, jsonb, text, text, text, double precision, double precision, text, numeric) TO authenticated, service_role;

-- ── #5 Avaliações das marcações (barbearias/salões) ───────────────────────
CREATE TABLE IF NOT EXISTS public.appointment_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id uuid NOT NULL UNIQUE REFERENCES public.appointments(id),
  provider_id text NOT NULL,
  client_user_id uuid NOT NULL,
  stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment text,
  response_text text,
  response_at timestamptz,
  flagged_inappropriate boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS appointment_ratings_provider_idx ON public.appointment_ratings (provider_id, created_at DESC);
ALTER TABLE public.appointment_ratings ENABLE ROW LEVEL SECURITY;

DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'appointment_ratings' AND policyname = 'appointment_ratings_public_read') THEN
    CREATE POLICY appointment_ratings_public_read ON public.appointment_ratings
      FOR SELECT USING (flagged_inappropriate IS NOT TRUE OR client_user_id = auth.uid() OR public.is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'appointment_ratings' AND policyname = 'appointment_ratings_admin_all') THEN
    CREATE POLICY appointment_ratings_admin_all ON public.appointment_ratings
      FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  END IF;
END $pol$;

CREATE OR REPLACE FUNCTION public.avaliar_marcacao(p_appointment_id uuid, p_stars smallint, p_comment text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  a record;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_stars IS NULL OR p_stars < 1 OR p_stars > 5 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estrelas_invalidas');
  END IF;
  SELECT id, provider_id, client_user_id, status INTO a FROM public.appointments WHERE id = p_appointment_id;
  IF NOT FOUND OR a.client_user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'marcacao_nao_encontrada');
  END IF;
  IF a.status <> 'completed' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'marcacao_nao_concluida');
  END IF;
  INSERT INTO public.appointment_ratings (appointment_id, provider_id, client_user_id, stars, comment)
  VALUES (a.id, a.provider_id, a.client_user_id, p_stars, NULLIF(trim(COALESCE(p_comment, '')), ''))
  ON CONFLICT (appointment_id) DO UPDATE
    SET stars = EXCLUDED.stars, comment = EXCLUDED.comment, updated_at = now()
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'rating_id', v_id);
END;
$fn$;
REVOKE ALL ON FUNCTION public.avaliar_marcacao(uuid, smallint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.avaliar_marcacao(uuid, smallint, text) TO authenticated, service_role;

-- O dono do prestador responde à avaliação.
CREATE OR REPLACE FUNCTION public.prestador_responder_avaliacao(p_rating_id uuid, p_resposta text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_prov text;
BEGIN
  SELECT provider_id INTO v_prov FROM public.appointment_ratings WHERE id = p_rating_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'nao_encontrada'); END IF;
  IF NOT (public.is_admin() OR EXISTS (SELECT 1 FROM public.service_providers sp
                                        WHERE sp.id = v_prov AND sp.user_id = auth.uid())) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  UPDATE public.appointment_ratings
     SET response_text = NULLIF(trim(COALESCE(p_resposta, '')), ''),
         response_at = CASE WHEN NULLIF(trim(COALESCE(p_resposta, '')), '') IS NULL THEN NULL ELSE now() END,
         updated_at = now()
   WHERE id = p_rating_id;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;
REVOKE ALL ON FUNCTION public.prestador_responder_avaliacao(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prestador_responder_avaliacao(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._update_provider_avg_rating()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_prov text := NEW.provider_id;
BEGIN
  UPDATE public.service_providers sp
     SET avg_rating = x.media, ratings_count = x.n
    FROM (SELECT ROUND(AVG(stars)::numeric, 2) AS media, COUNT(*)::int AS n
            FROM public.appointment_ratings
           WHERE provider_id = v_prov AND flagged_inappropriate IS NOT TRUE) x
   WHERE sp.id = v_prov;
  IF TG_OP = 'UPDATE' AND OLD.provider_id IS DISTINCT FROM NEW.provider_id THEN
    UPDATE public.service_providers sp
       SET avg_rating = x.media, ratings_count = x.n
      FROM (SELECT ROUND(AVG(stars)::numeric, 2) AS media, COUNT(*)::int AS n
              FROM public.appointment_ratings
             WHERE provider_id = OLD.provider_id AND flagged_inappropriate IS NOT TRUE) x
     WHERE sp.id = OLD.provider_id;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE OR REPLACE TRIGGER trg_appointment_ratings_provider_avg
  AFTER INSERT OR UPDATE ON public.appointment_ratings
  FOR EACH ROW EXECUTE FUNCTION public._update_provider_avg_rating();
