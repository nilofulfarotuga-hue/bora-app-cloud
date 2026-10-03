-- 2026-09-14 (missao painel-admin-limpo) — o digest semanal nunca escreve
-- para enderecos de demonstracao, e quem fica de fora aparece no aviso ao
-- Danilo com o motivo.
--   1. Trigger BEFORE INSERT em weekly_digest_log: sujeito demo nao entra.
--   2. Limpa linhas demo por enviar que ja la estivessem.
--   3. weekly_closeout_excluidos(semana): lista quem teve actividade demo na
--      semana e ficou de fora, para a Edge weekly-closeout-digest (v8) mostrar.
--
-- Prova (14/09 01:17 Lisboa): weekly_closeout_excluidos('2026-09-06') devolve
-- [{"name":"Estafeta Demo","type":"driver","n":1,"amount_cents":569,
--   "motivo":"conta de demonstração — 1 entrega(s) de teste fora do fecho"}].
-- O digest das 01:20 saiu com 4 recibos reais e zero demo.

CREATE OR REPLACE FUNCTION public._digest_ignora_demo()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.is_demo_subject(NEW.subject_type, NEW.subject_id)
     OR public.is_demo_email(NEW.subject_email) THEN
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('digest_demo_ignorado', 'weekly_digest_log', NEW.subject_id,
            jsonb_build_object('tipo', NEW.subject_type, 'week_start_at', NEW.week_start_at, 'email', NEW.subject_email));
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_digest_ignora_demo
  BEFORE INSERT ON public.weekly_digest_log
  FOR EACH ROW EXECUTE FUNCTION public._digest_ignora_demo();

DELETE FROM public.weekly_digest_log
 WHERE (public.is_demo_subject(subject_type, subject_id) OR public.is_demo_email(subject_email))
   AND COALESCE(email_status, 'pending') <> 'sent';

CREATE OR REPLACE FUNCTION public.weekly_closeout_excluidos(p_week_start date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ws date;
  v_from timestamptz; v_to timestamptz;
  v_out jsonb;
BEGIN
  v_ws := COALESCE(p_week_start, (
    SELECT max(w) FROM (
      SELECT week_start_at::date w FROM public.driver_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM public.partner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM public.appointment_payouts
      UNION ALL SELECT week_start_at::date FROM public.cleaner_weekly_settlements
      UNION ALL SELECT week_start_at::date FROM public.washer_weekly_settlements
    ) x WHERE w < (date_trunc('week', now() AT TIME ZONE 'Europe/Lisbon'))::date));
  IF v_ws IS NULL THEN RETURN '[]'::jsonb; END IF;
  -- Semana de Lisboa a partir da data guardada (que e' a data UTC do inicio).
  SELECT b.week_start, b.week_end INTO v_from, v_to
    FROM public.driver_settlement_week_bounds((v_ws + 1)::timestamptz) b;

  WITH demo_drivers AS (
    SELECT o.assigned_driver_id AS sid, count(*) AS n, COALESCE(sum(o.driver_earnings), 0) AS eur
    FROM public.orders o
    WHERE o.status = 'delivered' AND o.delivered_at >= v_from AND o.delivered_at <= v_to
      AND public.is_demo_driver(o.assigned_driver_id)
    GROUP BY o.assigned_driver_id
  ), demo_partners AS (
    SELECT o.restaurant_id AS sid, count(*) AS n, COALESCE(sum(o.subtotal), 0) AS eur
    FROM public.orders o
    WHERE o.status = 'delivered' AND o.delivered_at >= v_from AND o.delivered_at <= v_to
      AND public.is_demo_restaurant(o.restaurant_id)
    GROUP BY o.restaurant_id
  ), demo_orders_real_people AS (
    SELECT o.assigned_driver_id AS sid, count(*) AS n, COALESCE(sum(o.driver_earnings), 0) AS eur
    FROM public.orders o
    WHERE o.status = 'delivered' AND o.delivered_at >= v_from AND o.delivered_at <= v_to
      AND public.is_demo_order(o) AND NOT public.is_demo_driver(o.assigned_driver_id)
      AND o.assigned_driver_id IS NOT NULL
    GROUP BY o.assigned_driver_id
  ), demo_appts AS (
    SELECT a.provider_id AS sid, count(*) AS n, COALESCE(sum(a.deposit_cents), 0) / 100.0 AS eur
    FROM public.appointments a
    WHERE a.scheduled_at >= v_from AND a.scheduled_at <= v_to
      AND a.status IN ('completed', 'no_show')
      AND (public.is_demo_user(a.client_user_id) OR public.is_demo_provider(a.provider_id))
    GROUP BY a.provider_id
  ), linhas AS (
    SELECT 'driver' AS type, COALESCE(d.name, 'Estafeta demo') AS name, dd.n, dd.eur,
           'conta de demonstração — ' || dd.n || ' entrega(s) de teste fora do fecho' AS motivo
    FROM demo_drivers dd LEFT JOIN public.drivers d ON d.id::text = dd.sid OR d.user_id::text = dd.sid
    UNION ALL
    SELECT 'partner', COALESCE(r.name, 'Loja demo'), dp.n, dp.eur,
           'loja de demonstração — ' || dp.n || ' pedido(s) de teste fora do fecho'
    FROM demo_partners dp LEFT JOIN public.restaurants r ON r.id = dp.sid
    UNION ALL
    SELECT 'driver', COALESCE(d.name, 'Estafeta'), dr.n, dr.eur,
           'pessoa REAL com ' || dr.n || ' pedido(s) de demonstração — esses pedidos ficam fora do acerto'
    FROM demo_orders_real_people dr LEFT JOIN public.drivers d ON d.id::text = dr.sid OR d.user_id::text = dr.sid
    UNION ALL
    SELECT 'provider', COALESCE(sp.name, 'Parceiro'), da.n, da.eur,
           da.n || ' marcação(ões) de cliente de demonstração fora do fecho'
    FROM demo_appts da LEFT JOIN public.service_providers sp ON sp.id = da.sid
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'name', name, 'type', type, 'motivo', motivo,
      'amount_cents', ROUND(eur * 100)::int, 'n', n)), '[]'::jsonb)
  INTO v_out FROM linhas;
  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public.weekly_closeout_excluidos(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.weekly_closeout_excluidos(date) TO authenticated, service_role;
