-- =============================================================================
-- 20261010073000 · Limpeza: a rotação dá N voltas pela lista antes de desistir
-- Missão "a chamada grita sempre" (10/10/2026), Bloco B (limpeza).
--
-- Hoje _cleaning_next_offer faz UMA volta: quando todas as profissionais da
-- lista já receberam a oferta, avisa o admin e pára — a reserva fica à espera
-- até ser cancelada 15 min depois da hora marcada. Regra do Danilo: se ninguém
-- aceitar, volta a chamar (como as entregas). Agora, esgotada a lista, limpa a
-- lista de quem já recebeu e começa outra volta, até cleaning_voltas_ofertas
-- voltas (2 por defeito). Só depois avisa o admin "sem profissional".
-- Nota: na limpeza as ofertas já vão a quem está desligado (não há "online"),
-- por isso não há fase de reforço — basta repetir a volta.
-- Tudo o resto da função fica igual (ordem, aparelho, janela curta sem
-- aparelho, registo da oferta, aviso à profissional).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.bkp_fn_limpeza_20261010 (
  nome        text PRIMARY KEY,
  definicao   text NOT NULL,
  guardado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.bkp_fn_limpeza_20261010 ENABLE ROW LEVEL SECURITY;
INSERT INTO public.bkp_fn_limpeza_20261010 (nome, definicao)
SELECT p.proname, pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = '_cleaning_next_offer'
ON CONFLICT (nome) DO NOTHING;

INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('cleaning_voltas_ofertas', '2', 'cleaning',
   'Limpeza: quantas voltas pela lista de profissionais antes de avisar que não há ninguém.')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS offer_rounds integer NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION public._cleaning_next_offer(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b cleaning_bookings;
  v_next uuid;
  v_next_user uuid;
  v_next_nome text;
  v_tem boolean;
  v_timeout int := public._cleaning_setting_int('cleaning_offer_timeout_min', 30);
  v_curto int;
  v_voltas int := GREATEST(public._cleaning_setting_int('cleaning_voltas_ofertas', 2), 1);
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;

  FOR i IN 1..2 LOOP
    SELECT c.id, c.user_id, c.name INTO v_next, v_next_user, v_next_nome
    FROM cleaners c
    WHERE c.approval_status = 'approved' AND c.is_active
      AND c.user_id <> v_b.client_user_id
      AND NOT (c.id = ANY (v_b.offered_cleaner_ids))
      AND (c.base_lat IS NULL OR v_b.lat IS NULL
           OR public._cleaning_distance_km(c.base_lat, c.base_lng, v_b.lat, v_b.lng) <= c.service_radius_km)
      AND public._cleaning_is_available(c.id, v_b.scheduled_at, v_b.duration_min)
    ORDER BY (c.id = v_b.requested_cleaner_id) DESC,
             public.tem_aparelho(c.user_id, 'cleaner') DESC,
             c.rating_avg DESC, c.cleanings_done DESC
    LIMIT 1;

    EXIT WHEN v_next IS NOT NULL;

    -- Lista esgotada: se ainda há voltas, começa outra (só se alguém já tinha
    -- recebido nesta volta — lista vazia de raiz não dá voltas em vão).
    EXIT WHEN COALESCE(v_b.offer_rounds, 1) >= v_voltas
           OR COALESCE(cardinality(v_b.offered_cleaner_ids), 0) = 0;
    UPDATE cleaning_bookings
       SET offered_cleaner_ids = '{}'::uuid[],
           offer_rounds = COALESCE(offer_rounds, 1) + 1
     WHERE id = p_booking_id;
    SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  END LOOP;

  IF v_next IS NULL THEN
    UPDATE cleaning_bookings
    SET offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._cleaning_notify_admin(
      'Limpeza sem profissional',
      'Reserva ' || p_booking_id::text || ' para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' sem profissional disponível (' || COALESCE(v_b.offer_rounds, 1) || ' volta(s) pela lista).');
    RETURN;
  END IF;

  v_tem := public.tem_aparelho(v_next_user, 'cleaner');
  SELECT COALESCE((value #>> '{}')::int, 1) INTO v_curto
    FROM platform_settings WHERE key = 'oferta_sem_aparelho_min';
  IF NOT v_tem THEN v_timeout := LEAST(v_timeout, COALESCE(v_curto, 1)); END IF;

  UPDATE cleaning_bookings
  SET offer_cleaner_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_cleaner_ids = offered_cleaner_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public.registar_oferta('limpeza', p_booking_id, v_next, v_next_user,
                                 v_next_nome, v_tem, v_timeout);

  PERFORM public._cleaning_notify_user(
    v_next_user,
    'cleaning_offer', 'Nova limpeza disponível',
    'Limpeza a ' || to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
    ' — ' || (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $function$;
