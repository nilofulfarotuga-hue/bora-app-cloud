-- =============================================================================
-- MUDAR DESTINO — correções da revisão adversarial (30/09/2026)
-- Autorização do Danilo: "sim" (30/09/2026 12:51).
--   A) Km do SERVIDOR: a cotação e o pedido deixam de usar os km mandados pela
--      app. A Edge `tvde-dest-change` pede a rota ao Google (chave do servidor)
--      e grava-a em `tvde_dest_change_routes` (só service_role escreve); as RPCs
--      só aceitam uma rota com menos de 10 min para aquele destino. Os
--      parâmetros p_done_km/p_remaining_km ficam na assinatura mas são IGNORADOS.
--   B) Dinheiro nunca preso: colunas de reembolso + `tvde_dest_change_pendentes`
--      (lista para o varrimento da Edge) + `tvde_dest_change_mark_refunded`
--      + `tvde_dest_change_sweep_kick` (cron de 2 em 2 min, só chama a Edge
--      quando há pendentes).
--   C) Pacote ida-e-volta: guarda a distância combinada da ida ANTES da
--      primeira mudança (`dest_change_base_km`) — a volta só é grátis até aí
--      (a mudança da ida é paga à parte e não pode dar km grátis na volta).
-- =============================================================================

-- A) rotas calculadas pelo servidor --------------------------------------------
CREATE TABLE IF NOT EXISTS public.tvde_dest_change_routes (
  id           bigserial PRIMARY KEY,
  ride_id      uuid NOT NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  dest_lat     double precision NOT NULL,
  dest_lng     double precision NOT NULL,
  from_lat     double precision,
  from_lng     double precision,
  km_done      numeric NOT NULL DEFAULT 0,
  km_remaining numeric NOT NULL,
  fonte        text NOT NULL DEFAULT 'google_directions',
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tvde_dest_change_routes_ride_idx ON public.tvde_dest_change_routes (ride_id, created_at DESC);
ALTER TABLE public.tvde_dest_change_routes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tvde_dest_change_routes FROM anon, authenticated;

-- B) reembolso da mudança -------------------------------------------------------
ALTER TABLE public.tvde_destination_changes
  ADD COLUMN IF NOT EXISTS refunded_at   timestamptz,
  ADD COLUMN IF NOT EXISTS refund_cents  integer,
  ADD COLUMN IF NOT EXISTS refund_motivo text;

-- C) distância combinada antes da primeira mudança ----------------------------
ALTER TABLE public.tvde_rides ADD COLUMN IF NOT EXISTS dest_change_base_km numeric;
COMMENT ON COLUMN public.tvde_rides.dest_change_base_km IS
  'Mudar destino: distância combinada ANTES da primeira mudança. Na volta do pacote, só estes km da ida contam como grátis.';

-- Rota do servidor mais recente para aquele destino (10 min).
CREATE OR REPLACE FUNCTION public._tvde_dest_change_route(p_ride uuid, p_lat double precision, p_lng double precision)
RETURNS public.tvde_dest_change_routes LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.tvde_dest_change_routes
   WHERE ride_id = p_ride
     AND abs(dest_lat - p_lat) < 0.00001 AND abs(dest_lng - p_lng) < 0.00001
     AND created_at > now() - interval '10 minutes'
   ORDER BY created_at DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.tvde_dest_change_quote(
  p_ride_id uuid, p_dest_lat double precision, p_dest_lng double precision,
  p_dest_label text DEFAULT NULL, p_done_km numeric DEFAULT 0, p_remaining_km numeric DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ride public.tvde_rides; v_calc jsonb; v_rt public.tvde_dest_change_routes;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  PERFORM public._tvde_dest_change_check(v_ride);
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  -- 30/09 correção A: os km vêm da rota calculada pelo servidor, nunca da app.
  v_rt := public._tvde_dest_change_route(p_ride_id, p_dest_lat, p_dest_lng);
  IF v_rt.id IS NULL THEN RAISE EXCEPTION 'route_not_computed'; END IF;
  v_calc := public._tvde_dest_change_calc(v_ride, p_dest_lat, p_dest_lng, v_rt.km_done, v_rt.km_remaining);
  IF (v_calc->>'km_new_total')::numeric > 300 THEN RAISE EXCEPTION 'dest_too_far'; END IF;
  RETURN v_calc || jsonb_build_object('ride_id', v_ride.id, 'dest_label', p_dest_label,
    'payment_method', COALESCE(v_ride.payment_method, 'cash'), 'route_id', v_rt.id,
    'needs_payment', (v_calc->>'client_diff_cents')::int > 0 AND COALESCE(v_ride.payment_method,'cash') <> 'cash');
END $$;

CREATE OR REPLACE FUNCTION public.tvde_dest_change_request(
  p_ride_id uuid, p_dest_lat double precision, p_dest_lng double precision,
  p_dest_label text DEFAULT NULL, p_done_km numeric DEFAULT 0, p_remaining_km numeric DEFAULT 0,
  p_expected_client_diff_cents integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ride public.tvde_rides; v_calc jsonb; v_ch public.tvde_destination_changes;
  v_method text; v_diff int; v_res jsonb; v_rt public.tvde_dest_change_routes;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  PERFORM public._tvde_dest_change_check(v_ride);
  IF p_dest_lat IS NULL OR p_dest_lng IS NULL THEN RAISE EXCEPTION 'invalid_dest'; END IF;
  v_rt := public._tvde_dest_change_route(p_ride_id, p_dest_lat, p_dest_lng);
  IF v_rt.id IS NULL THEN RAISE EXCEPTION 'route_not_computed'; END IF;
  v_calc := public._tvde_dest_change_calc(v_ride, p_dest_lat, p_dest_lng, v_rt.km_done, v_rt.km_remaining);
  IF (v_calc->>'km_new_total')::numeric > 300 THEN RAISE EXCEPTION 'dest_too_far'; END IF;
  v_diff := (v_calc->>'client_diff_cents')::int;
  IF p_expected_client_diff_cents IS NOT NULL AND p_expected_client_diff_cents <> v_diff THEN
    RAISE EXCEPTION 'dest_change_price_changed: %', v_diff; END IF;

  UPDATE public.tvde_destination_changes SET estado = 'recusada', motivo = 'substituida', updated_at = now()
   WHERE ride_id = v_ride.id AND estado = 'proposta';

  v_method := CASE WHEN v_diff = 0 THEN 'nenhum' ELSE COALESCE(v_ride.payment_method, 'cash') END;
  INSERT INTO public.tvde_destination_changes (ride_id, client_id, driver_id, ride_status,
    old_dest_lat, old_dest_lng, old_dest_label, new_dest_lat, new_dest_lng, new_dest_label,
    km_done, km_remaining, km_new_total, km_before, price_before_cents, price_new_cents, table_diff_cents,
    client_diff_cents, driver_before_cents, driver_new_cents, driver_table_diff_cents, driver_diff_cents,
    min_applied, driver_min_applied, method, estado, created_by, created_by_role)
  VALUES (v_ride.id, v_ride.client_id, v_ride.driver_id, v_ride.status,
    v_ride.dest_lat, v_ride.dest_lng, v_ride.dest_label, p_dest_lat, p_dest_lng, p_dest_label,
    (v_calc->>'km_done')::numeric, (v_calc->>'km_remaining')::numeric, (v_calc->>'km_new_total')::numeric,
    (v_calc->>'km_before')::numeric, (v_calc->>'price_before_cents')::int, (v_calc->>'price_new_cents')::int,
    (v_calc->>'table_diff_cents')::int, v_diff, (v_calc->>'driver_before_cents')::int,
    (v_calc->>'driver_new_cents')::int, (v_calc->>'driver_table_diff_cents')::int,
    (v_calc->>'driver_diff_cents')::int, (v_calc->>'min_applied')::boolean,
    (v_calc->>'driver_min_applied')::boolean, v_method, 'proposta', auth.uid(), 'cliente')
  RETURNING * INTO v_ch;

  IF v_method IN ('card','mbway') THEN
    RETURN v_calc || jsonb_build_object('change_id', v_ch.id, 'estado', 'proposta',
      'needs_payment', true, 'method', v_method);
  END IF;
  v_res := public._tvde_dest_change_apply(v_ch.id);
  RETURN v_calc || v_res || jsonb_build_object('needs_payment', false, 'method', v_method);
END $$;

-- C) guardar a distância combinada antes da 1.ª mudança (patch por âncora à _apply)
DO $$
DECLARE d text; n text; a text := '    dest_change_count = dest_change_count + 1,
    dest_change_fee_cents = dest_change_fee_cents + v_ch.client_diff_cents,';
BEGIN
  d := pg_get_functiondef('public._tvde_dest_change_apply(uuid)'::regprocedure);
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'ancora _apply'; END IF;
  n := replace(d, a, '    dest_change_base_km = COALESCE(dest_change_base_km, v_ch.km_before),
' || a);
  EXECUTE n;
END $$;

-- B) varrimento: o que precisa de ser reconciliado com a Stripe --------------------
CREATE OR REPLACE FUNCTION public.tvde_dest_change_pendentes()
RETURNS TABLE (change_id uuid, ride_id uuid, estado text, payment_intent_id text,
               client_diff_cents integer, ride_status text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT c.id, c.ride_id, c.estado, c.payment_intent_id, c.client_diff_cents, r.status, c.created_at
    FROM public.tvde_destination_changes c
    JOIN public.tvde_rides r ON r.id = c.ride_id
   WHERE c.payment_intent_id IS NOT NULL
     AND c.refunded_at IS NULL
     AND c.created_at > now() - interval '3 days'
     AND (
       -- pago tarde / confirmação perdida: ainda proposta ao fim de 2 min
       (c.estado = 'proposta' AND c.created_at < now() - interval '2 minutes')
       -- recusada/falhada mas o dinheiro pode ter entrado
       OR c.estado IN ('recusada','falhada','paga')
       -- aplicada e a corrida foi cancelada: a diferença volta ao cliente
       OR (c.estado = 'aplicada' AND r.status IN ('cancelada_cliente','cancelada_motorista','no_show','sem_motorista'))
     )
   ORDER BY c.created_at
   LIMIT 50;
$$;

CREATE OR REPLACE FUNCTION public.tvde_dest_change_mark_refunded(p_change_id uuid, p_cents integer, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ch public.tvde_destination_changes;
BEGIN
  UPDATE public.tvde_destination_changes
     SET refunded_at = now(), refund_cents = p_cents, refund_motivo = left(p_motivo, 200), updated_at = now(),
         estado = CASE WHEN estado IN ('proposta','paga') THEN 'falhada' ELSE estado END
   WHERE id = p_change_id AND refunded_at IS NULL
  RETURNING * INTO v_ch;
  IF v_ch.id IS NOT NULL THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      SELECT v_ch.ride_id, r.status, 'system', jsonb_build_object('event', 'dest_change_refunded',
        'change_id', v_ch.id, 'refund_cents', p_cents, 'motivo', p_motivo, 'payment_intent_id', v_ch.payment_intent_id)
        FROM public.tvde_rides r WHERE r.id = v_ch.ride_id;
  END IF;
END $$;

-- Chama a Edge só quando há alguma coisa a reconciliar (poupa invocações).
CREATE OR REPLACE FUNCTION public.tvde_dest_change_sweep_kick()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net', 'extensions', 'vault' AS $$
DECLARE v_n int; v_key text; v_url text;
BEGIN
  SELECT count(*) INTO v_n FROM public.tvde_dest_change_pendentes();
  IF v_n = 0 THEN RETURN 0; END IF;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  v_url := COALESCE(v_url, 'https://ojykpzwqrtusfeakzrna.supabase.co');
  PERFORM net.http_post(
    url := v_url || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action', 'sweep_dest_changes'));
  RETURN v_n;
END $$;

REVOKE ALL ON FUNCTION public._tvde_dest_change_route(uuid, double precision, double precision) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_dest_change_pendentes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_dest_change_mark_refunded(uuid, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tvde_dest_change_sweep_kick() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_pendentes() TO service_role;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_mark_refunded(uuid, integer, text) TO service_role;
REVOKE ALL ON FUNCTION public.tvde_dest_change_quote(uuid, double precision, double precision, text, numeric, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.tvde_dest_change_request(uuid, double precision, double precision, text, numeric, numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_quote(uuid, double precision, double precision, text, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_dest_change_request(uuid, double precision, double precision, text, numeric, numeric, integer) TO authenticated;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'tvde-dest-change-sweep';
SELECT cron.schedule('tvde-dest-change-sweep', '*/2 * * * *', $c$SELECT public.tvde_dest_change_sweep_kick();$c$);
