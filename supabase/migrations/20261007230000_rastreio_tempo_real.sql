-- ============================================================================
-- Rastreio em tempo real (07/10/2026) — "o cliente vê o condutor exacto, o
-- condutor vê o cliente a chegar"
--
-- 1) platform_settings: cadência do GPS da corrida/entrega para o servidor,
--    interruptor e cadência do pontinho azul do cliente.
-- 2) driver_locations: o CLIENTE da corrida TVDE / do pedido em curso pode
--    ler a linha do SEU condutor (só posição: lat/lng/heading/velocidade),
--    e a tabela entra no Realtime. É a mesma linha que a RPC
--    tvde_ride_driver_card já devolvia e que o matching lê — uma verdade só.
-- 3) client_live_locations: a posição do cliente para o condutor, opt-in,
--    com RLS (cliente escreve a sua; condutor lê a dele), RPCs que validam a
--    corrida/pedido e descobrem o driver_user_id, e limpeza automática quando
--    a corrida/pedido termina (gatilhos que SÓ apagam nesta tabela; não
--    escrevem em orders nem em tvde_rides).
--
-- NÃO toca em: dispatch, pricing, ganhos, RLS de orders/wallets/ledger, Stripe.
-- Idempotente: pode correr duas vezes.
-- ============================================================================

BEGIN;

-- ── 1. Definições ──────────────────────────────────────────────────────────
INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('tvde_ride_gps_interval_seconds', '5'::jsonb, 'tvde',
   'Corrida TVDE e entrega: de quantos em quantos segundos a posicao do motorista/estafeta vai para o servidor enquanto a corrida/entrega decorre (e o que o cliente ve a mexer no mapa). O GPS local da navegacao continua a ~1 por segundo. Nao e dinheiro.'),
  ('client_live_location_enabled', 'true'::jsonb, 'tvde',
   'Pontinho azul: deixa o cliente partilhar a sua localizacao com o motorista/estafeta enquanto ele vem a caminho (TVDE e entregas). E sempre opt-in no telemovel do cliente; false esconde o cartao.'),
  ('client_live_location_interval_seconds', '4'::jsonb, 'tvde',
   'Pontinho azul: de quantos em quantos segundos o telemovel do cliente manda a posicao ao motorista/estafeta (2 a 60).')
ON CONFLICT (key) DO NOTHING;

-- ── 2. driver_locations: leitura pelo cliente da corrida/pedido + Realtime ─
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'driver_locations'
       AND policyname = 'driver_locations_select_cliente_atribuido'
  ) THEN
    CREATE POLICY driver_locations_select_cliente_atribuido
      ON public.driver_locations FOR SELECT TO authenticated
      USING (
        -- corrida TVDE em curso deste cliente com este motorista
        EXISTS (
          SELECT 1 FROM public.tvde_rides r
           WHERE r.client_id = auth.uid()
             AND r.status IN ('motorista_atribuido', 'motorista_a_caminho',
                              'motorista_chegou', 'em_andamento')
             AND (r.driver_id = driver_locations.driver_id
                  OR r.driver_id IN (SELECT d.id FROM public.drivers d
                                      WHERE d.user_id = driver_locations.driver_id))
        )
        OR
        -- pedido (restaurante, mercado, favor) em curso deste cliente com este estafeta
        EXISTS (
          SELECT 1 FROM public.orders o
           WHERE o.user_id = auth.uid()
             AND o.status IN ('driverAccepted', 'pickedUp', 'onTheWay')
             AND o.assigned_driver_id = driver_locations.driver_id::text
        )
      );
  END IF;
END $$;

COMMENT ON POLICY driver_locations_select_cliente_atribuido ON public.driver_locations IS
  'Rastreio em tempo real (07/10/2026): o cliente da corrida TVDE / do pedido em curso le a posicao do SEU condutor. So esta tabela (posicao); drivers continua fechada.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND tablename = 'driver_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_locations;
  END IF;
END $$;

-- ── 3. client_live_locations ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.client_live_locations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id        uuid NULL REFERENCES public.tvde_rides(id) ON DELETE CASCADE,
  order_id       text NULL,  -- orders.id e TEXT em producao (legado); sem FK
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_user_id uuid NOT NULL,
  lat            double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng            double precision NOT NULL CHECK (lng BETWEEN -180 AND 180),
  heading        double precision NULL,
  accuracy_m     double precision NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  expires_at     timestamptz NOT NULL DEFAULT now() + interval '2 minutes',
  CONSTRAINT client_live_locations_alvo CHECK (ride_id IS NOT NULL OR order_id IS NOT NULL)
);

COMMENT ON TABLE public.client_live_locations IS
  'Pontinho azul (07/10/2026): posicao do CLIENTE partilhada, por opcao dele, com o condutor enquanto ele chega. Uma linha por corrida/pedido; apagada ao parar, ao expirar e quando a corrida/pedido termina.';

CREATE UNIQUE INDEX IF NOT EXISTS client_live_locations_ride_uq
  ON public.client_live_locations (ride_id) WHERE ride_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS client_live_locations_order_uq
  ON public.client_live_locations (order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS client_live_locations_driver_idx
  ON public.client_live_locations (driver_user_id);

ALTER TABLE public.client_live_locations ENABLE ROW LEVEL SECURITY;
-- O DELETE no Realtime so chega com o filtro driver_user_id se a linha velha
-- vier inteira.
ALTER TABLE public.client_live_locations REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                  AND tablename='client_live_locations' AND policyname='client_live_locations_insert_own') THEN
    CREATE POLICY client_live_locations_insert_own ON public.client_live_locations
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                  AND tablename='client_live_locations' AND policyname='client_live_locations_update_own') THEN
    CREATE POLICY client_live_locations_update_own ON public.client_live_locations
      FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                  AND tablename='client_live_locations' AND policyname='client_live_locations_delete_own') THEN
    CREATE POLICY client_live_locations_delete_own ON public.client_live_locations
      FOR DELETE TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                  AND tablename='client_live_locations' AND policyname='client_live_locations_select_driver') THEN
    CREATE POLICY client_live_locations_select_driver ON public.client_live_locations
      FOR SELECT TO authenticated USING (driver_user_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND tablename = 'client_live_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.client_live_locations;
  END IF;
END $$;

-- ── 3a. RPC: o cliente manda a posicao ─────────────────────────────────────
-- Valida que a corrida/pedido e do cliente e tem condutor atribuido, descobre
-- o driver_user_id (TVDE: tvde_rides.driver_id -> drivers.user_id; entregas:
-- orders.assigned_driver_id, que e o user_id) e faz upsert. Devolve
-- {ok, motivo} — ok=false NAO e erro: o telemovel para de enviar.
CREATE OR REPLACE FUNCTION public.client_live_location_upsert(
  p_ride_id  uuid,
  p_order_id text,
  p_lat      double precision,
  p_lng      double precision,
  p_heading  double precision DEFAULT NULL,
  p_accuracy double precision DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_driver_raw uuid;
  v_driver     uuid;
  v_txt        text;
  v_ligado     jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sem sessao';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'posicao invalida';
  END IF;

  SELECT value INTO v_ligado FROM public.platform_settings
   WHERE key = 'client_live_location_enabled';
  IF v_ligado IS NOT NULL AND v_ligado::text = 'false' THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'desligado');
  END IF;

  IF p_ride_id IS NOT NULL THEN
    SELECT r.driver_id INTO v_driver_raw
      FROM public.tvde_rides r
     WHERE r.id = p_ride_id
       AND r.client_id = v_uid
       AND r.status IN ('motorista_atribuido', 'motorista_a_caminho', 'motorista_chegou');
    IF v_driver_raw IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'corrida sem motorista a caminho');
    END IF;
    -- identidade do estafeta: o user_id manda (Valdemir 16/08, Ney 16/09)
    SELECT d.user_id INTO v_driver
      FROM public.drivers d
     WHERE d.user_id = v_driver_raw OR d.id = v_driver_raw
     LIMIT 1;
    v_driver := COALESCE(v_driver, v_driver_raw);

    INSERT INTO public.client_live_locations
      (ride_id, order_id, user_id, driver_user_id, lat, lng, heading, accuracy_m, updated_at, expires_at)
    VALUES
      (p_ride_id, NULL, v_uid, v_driver, p_lat, p_lng, p_heading, p_accuracy, now(), now() + interval '2 minutes')
    ON CONFLICT (ride_id) WHERE ride_id IS NOT NULL DO UPDATE SET
      driver_user_id = EXCLUDED.driver_user_id,
      lat = EXCLUDED.lat, lng = EXCLUDED.lng,
      heading = EXCLUDED.heading, accuracy_m = EXCLUDED.accuracy_m,
      updated_at = now(), expires_at = now() + interval '2 minutes';
    RETURN jsonb_build_object('ok', true, 'driver_user_id', v_driver);
  END IF;

  IF p_order_id IS NOT NULL THEN
    SELECT o.assigned_driver_id INTO v_txt
      FROM public.orders o
     WHERE o.id::text = p_order_id
       AND o.user_id = v_uid
       AND o.status IN ('driverAccepted', 'pickedUp', 'onTheWay');
    IF v_txt IS NULL OR v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'pedido sem estafeta a caminho');
    END IF;
    v_driver := v_txt::uuid;

    INSERT INTO public.client_live_locations
      (ride_id, order_id, user_id, driver_user_id, lat, lng, heading, accuracy_m, updated_at, expires_at)
    VALUES
      (NULL, p_order_id, v_uid, v_driver, p_lat, p_lng, p_heading, p_accuracy, now(), now() + interval '2 minutes')
    ON CONFLICT (order_id) WHERE order_id IS NOT NULL DO UPDATE SET
      driver_user_id = EXCLUDED.driver_user_id,
      lat = EXCLUDED.lat, lng = EXCLUDED.lng,
      heading = EXCLUDED.heading, accuracy_m = EXCLUDED.accuracy_m,
      updated_at = now(), expires_at = now() + interval '2 minutes';
    RETURN jsonb_build_object('ok', true, 'driver_user_id', v_driver);
  END IF;

  RAISE EXCEPTION 'indica a corrida ou o pedido';
END;
$$;

REVOKE ALL ON FUNCTION public.client_live_location_upsert(uuid, text, double precision, double precision, double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_live_location_upsert(uuid, text, double precision, double precision, double precision, double precision) TO authenticated;

-- ── 3b. RPC: o cliente para de partilhar ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_live_location_stop(
  p_ride_id  uuid,
  p_order_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sem sessao';
  END IF;
  DELETE FROM public.client_live_locations
   WHERE user_id = v_uid
     AND ((p_ride_id IS NOT NULL AND ride_id = p_ride_id)
          OR (p_order_id IS NOT NULL AND order_id = p_order_id));
END;
$$;

REVOKE ALL ON FUNCTION public.client_live_location_stop(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_live_location_stop(uuid, text) TO authenticated;

-- ── 3c. Limpeza automatica quando a corrida/pedido termina ─────────────────
-- Gatilhos AFTER UPDATE que SO fazem DELETE em client_live_locations.
-- SECURITY DEFINER porque quem muda o estado e o condutor/servidor, e a RLS
-- desta tabela so deixa o CLIENTE apagar.
CREATE OR REPLACE FUNCTION public.client_live_location_limpar_tvde()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('finalizada', 'cancelada_cliente', 'cancelada_motorista',
                        'no_show', 'sem_motorista') THEN
    DELETE FROM public.client_live_locations WHERE ride_id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_client_live_location_limpar_tvde
  AFTER UPDATE OF status ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public.client_live_location_limpar_tvde();

CREATE OR REPLACE FUNCTION public.client_live_location_limpar_pedido()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('delivered', 'cancelled', 'rejected') THEN
    DELETE FROM public.client_live_locations WHERE order_id = NEW.id::text;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_client_live_location_limpar_pedido
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.client_live_location_limpar_pedido();

COMMIT;
