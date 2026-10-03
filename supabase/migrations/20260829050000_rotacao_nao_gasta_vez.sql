-- ============================================================================
-- A ROTACAO DEIXA DE OFERECER A QUEM NAO PODE SER AVISADO
--
-- ⚠️ Nao mexe em preco, comissao nem em quem ganha o que. Mexe em QUEM e
-- chamado e por QUANTO TEMPO se espera por ele.
--
-- ── O que se viu, duas vezes, no teste ao vivo de 2026-08-29 ───────────────
-- A oferta foi para prestadores **sem um unico aparelho registado**. Ninguem
-- podia sequer saber que tinha trabalho. A rotacao esperou a janela inteira —
-- dez minutos na lavagem, trinta na limpeza — e so depois passou adiante. O
-- trabalho ficou parado a toa, e o cliente a espera.
--
-- ── A regra ────────────────────────────────────────────────────────────────
-- Quem nao tem aparelho **nao gasta a vez inteira**. Continua a receber a
-- oferta (pode ter a app aberta e ver a lista), mas com uma janela curta, para
-- a rotacao passar depressa a quem pode mesmo ser chamado. Nao o saltamos de
-- todo: saltar seria decidir por ele que nunca vai olhar, e ha quem trabalhe
-- com a app aberta.
--
-- ── E fica registado ───────────────────────────────────────────────────────
-- Uma linha por oferta, com o motivo do fim. Sem isto nao ha como ver onde o
-- trabalho emperra — foi preciso ir a mao as tabelas para descobrir isto.
-- ============================================================================

-- ── 1. Esta pessoa tem aparelho onde receber? ──────────────────────────────
CREATE OR REPLACE FUNCTION public.tem_aparelho(p_user_id uuid, p_papel text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.provider_push_tokens t
     WHERE t.user_id = p_user_id AND t.role = p_papel AND t.active
  ) OR EXISTS (
    -- A coluna antiga de um aparelho unico. Ainda e a que serve os estafetas.
    SELECT 1 FROM public.users u
     WHERE u.id = p_user_id AND COALESCE(u.fcm_token, '') <> ''
  );
$function$;

REVOKE ALL ON FUNCTION public.tem_aparelho(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tem_aparelho(uuid, text) TO authenticated, service_role;


-- ── 2. Quanto tempo se espera por quem nao pode ser avisado ────────────────
INSERT INTO public.platform_settings (key, value)
VALUES ('oferta_sem_aparelho_min', '1'::jsonb)
ON CONFLICT (key) DO NOTHING;


-- ── 3. O registo das ofertas ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ofertas_prestador_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  categoria     text NOT NULL CHECK (categoria IN ('limpeza', 'lavagem')),
  booking_id    uuid NOT NULL,
  prestador_id  uuid NOT NULL,
  user_id       uuid,
  nome          text,
  tem_aparelho  boolean NOT NULL,
  janela_min    int NOT NULL,
  oferecida_em  timestamptz NOT NULL DEFAULT now(),
  desfecho      text,          -- 'aceite' | 'recusada' | 'expirou' | NULL (a decorrer)
  fechada_em    timestamptz
);

CREATE INDEX IF NOT EXISTS idx_ofertas_log_booking
  ON public.ofertas_prestador_log (booking_id, oferecida_em DESC);
CREATE INDEX IF NOT EXISTS idx_ofertas_log_data
  ON public.ofertas_prestador_log (oferecida_em DESC);

ALTER TABLE public.ofertas_prestador_log ENABLE ROW LEVEL SECURITY;
-- Sem policy de leitura: so o admin la chega, e chega pela RPC abaixo, que e
-- SECURITY DEFINER e verifica `is_admin()`.

CREATE OR REPLACE FUNCTION public.registar_oferta(
  p_categoria text, p_booking_id uuid, p_prestador_id uuid,
  p_user_id uuid, p_nome text, p_tem_aparelho boolean, p_janela_min int
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO public.ofertas_prestador_log
    (categoria, booking_id, prestador_id, user_id, nome, tem_aparelho, janela_min)
  VALUES (p_categoria, p_booking_id, p_prestador_id, p_user_id, p_nome,
          p_tem_aparelho, p_janela_min);
$function$;

REVOKE ALL ON FUNCTION public.registar_oferta(text, uuid, uuid, uuid, text, boolean, int)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fechar_oferta(
  p_booking_id uuid, p_prestador_id uuid, p_desfecho text
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  UPDATE public.ofertas_prestador_log
     SET desfecho = p_desfecho, fechada_em = now()
   WHERE id = (SELECT id FROM public.ofertas_prestador_log
                WHERE booking_id = p_booking_id
                  AND prestador_id = p_prestador_id
                  AND desfecho IS NULL
                ORDER BY oferecida_em DESC LIMIT 1);
$function$;

REVOKE ALL ON FUNCTION public.fechar_oferta(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;


-- ── 4. A rotacao da LAVAGEM ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._carwash_next_offer(p_booking_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_b carwash_bookings;
  v_next uuid;
  v_next_user uuid;
  v_next_nome text;
  v_tem boolean;
  v_timeout int := public._carwash_setting_int('carwash_offer_timeout_min', 10);
  v_curto int;
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;

  IF v_b.payment_method IN ('card','mbway') AND v_b.payment_status = 'unpaid' THEN
    RETURN;
  END IF;

  SELECT w.id, w.user_id, w.name INTO v_next, v_next_user, v_next_nome
  FROM washers w
  WHERE w.approval_status = 'approved' AND w.is_active AND NOT w.is_banned
    AND w.user_id <> v_b.client_user_id
    AND NOT (w.id = ANY (v_b.offered_washer_ids))
    AND (w.base_lat IS NULL OR v_b.lat IS NULL
         OR public._carwash_distance_km(w.base_lat, w.base_lng, v_b.lat, v_b.lng) <= w.service_radius_km)
    AND public._carwash_is_available(w.id, v_b.scheduled_at, v_b.duration_min)
  -- QUEM PODE SER AVISADO VAI A FRENTE. E o unico criterio novo, e vem antes
  -- da nota e da experiencia: de nada serve o melhor lavador da lista se ele
  -- nao tem como saber que tem trabalho.
  ORDER BY (w.id = v_b.requested_washer_id) DESC,
           public.tem_aparelho(w.user_id, 'washer') DESC,
           w.rating_avg DESC, w.washes_done DESC
  LIMIT 1;

  IF v_next IS NULL THEN
    UPDATE carwash_bookings SET offer_washer_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._carwash_notify_admin(
      'Lavagem sem lavador',
      'Pedido ' || p_booking_id::text || ' (' || v_b.plate || ') para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' sem lavador disponivel.');
    RETURN;
  END IF;

  -- Sem aparelho, janela curta: nao se para o trabalho dez minutos a espera de
  -- alguem que nao foi avisado.
  v_tem := public.tem_aparelho(v_next_user, 'washer');
  SELECT COALESCE((value #>> '{}')::int, 1) INTO v_curto
    FROM platform_settings WHERE key = 'oferta_sem_aparelho_min';
  IF NOT v_tem THEN v_timeout := LEAST(v_timeout, COALESCE(v_curto, 1)); END IF;

  UPDATE carwash_bookings
  SET offer_washer_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_washer_ids = offered_washer_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public.registar_oferta('lavagem', p_booking_id, v_next, v_next_user,
                                 v_next_nome, v_tem, v_timeout);

  PERFORM public._carwash_notify_user(
    v_next_user, 'carwash_offer', 'Nova lavagem disponivel',
    'Lavagem ' || CASE v_b.service_type WHEN 'exterior' THEN 'exterior'
                                        WHEN 'full' THEN 'completa'
                                        ELSE 'so interior' END ||
    ' - ' || (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $function$;


-- ── 5. A rotacao da LIMPEZA ────────────────────────────────────────────────
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
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;

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

  IF v_next IS NULL THEN
    UPDATE cleaning_bookings
    SET offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._cleaning_notify_admin(
      'Limpeza sem profissional',
      'Reserva ' || p_booking_id::text || ' para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' sem profissional disponível.');
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


-- ── 6. O painel do admin ve onde o trabalho emperra ────────────────────────
CREATE OR REPLACE FUNCTION public.admin_ofertas_log(
  p_categoria text DEFAULT NULL,
  p_dias integer DEFAULT 7,
  p_limite integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out jsonb; v_resumo jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', o.id, 'categoria', o.categoria, 'booking_id', o.booking_id,
           'nome', COALESCE(o.nome, '(sem nome)'),
           'tem_aparelho', o.tem_aparelho, 'janela_min', o.janela_min,
           'oferecida_em', o.oferecida_em,
           'desfecho', COALESCE(o.desfecho, 'a decorrer'),
           'fechada_em', o.fechada_em) ORDER BY o.oferecida_em DESC), '[]'::jsonb)
    INTO v_out
    FROM (SELECT * FROM public.ofertas_prestador_log
           WHERE oferecida_em > now() - make_interval(days => GREATEST(COALESCE(p_dias,7),1))
             AND (p_categoria IS NULL OR categoria = p_categoria)
           ORDER BY oferecida_em DESC
           LIMIT GREATEST(COALESCE(p_limite,200),1)) o;

  SELECT jsonb_build_object(
      'total', count(*),
      'sem_aparelho', count(*) FILTER (WHERE NOT tem_aparelho),
      'expiraram', count(*) FILTER (WHERE desfecho = 'expirou'),
      'aceites', count(*) FILTER (WHERE desfecho = 'aceite'))
    INTO v_resumo
    FROM public.ofertas_prestador_log
   WHERE oferecida_em > now() - make_interval(days => GREATEST(COALESCE(p_dias,7),1))
     AND (p_categoria IS NULL OR categoria = p_categoria);

  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'itens', v_out);
END $function$;

REVOKE ALL ON FUNCTION public.admin_ofertas_log(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ofertas_log(text, integer, integer) TO authenticated;
