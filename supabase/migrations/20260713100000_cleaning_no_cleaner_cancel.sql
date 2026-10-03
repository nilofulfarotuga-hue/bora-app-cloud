-- ============================================================================
-- LIMPEZA — cancelamento por FALTA DE PROFISSIONAL + aviso ao CLIENTE
-- ----------------------------------------------------------------------------
-- Antes: quando a rotation esgotava sem ninguém aceitar, `_cleaning_next_offer`
-- avisava só o ADMIN e a reserva ficava `scheduled` para sempre — o cliente
-- nunca era informado. Agora, se a hora marcada passa sem profissional aceite,
-- a reserva passa a um estado próprio `cancelled_no_cleaner` e o CLIENTE recebe
-- notificação (in-app + push).
--
-- ⚠️ NÃO mexe em reembolso/valores (Lista Vermelha). Reservas pagas ficam com o
--    `payment_status` intacto — o estorno é tratado numa proposta separada.
-- ============================================================================

-- 1) Novo valor no CHECK de status --------------------------------------------
ALTER TABLE public.cleaning_bookings
  DROP CONSTRAINT IF EXISTS cleaning_bookings_status_check;
ALTER TABLE public.cleaning_bookings
  ADD CONSTRAINT cleaning_bookings_status_check
  CHECK (status IN ('scheduled','accepted','on_the_way','in_progress',
                    'done','completed','cancelled_client','cancelled_cleaner',
                    'cancelled_no_cleaner'));

-- 2) Cron: reservas cuja hora passou sem profissional aceite ------------------
-- "sem profissional aceite" = cleaner_id IS NULL (a atribuição só acontece no
-- accept). Damos uma folga de segurança (grace) depois da hora marcada antes de
-- cancelar, para não apanhar uma aceitação a decorrer.
CREATE OR REPLACE FUNCTION public._cleaning_cron_expire_no_cleaner()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_grace int := public._cleaning_setting_int('cleaning_no_cleaner_grace_min', 15);
  v_count int := 0;
  v_rec record;
BEGIN
  FOR v_rec IN
    SELECT id, client_user_id, scheduled_at
    FROM cleaning_bookings
    WHERE status = 'scheduled'
      AND cleaner_id IS NULL
      AND scheduled_at < now() - make_interval(mins => v_grace)
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE cleaning_bookings
    SET status = 'cancelled_no_cleaner',
        cancelled_at = now(),
        cancel_reason = 'no_cleaner_found',
        offer_cleaner_id = NULL,
        offer_expires_at = NULL
    WHERE id = v_rec.id;

    PERFORM public._cleaning_notify_user(
      v_rec.client_user_id,
      'cleaning_no_cleaner',
      'Limpeza cancelada',
      'Não conseguimos encontrar uma profissional para a limpeza de ' ||
      to_char(v_rec.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
      '. O pedido foi cancelado. Pedimos desculpa pelo incómodo.',
      v_rec.id::text);

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;
REVOKE ALL ON FUNCTION public._cleaning_cron_expire_no_cleaner() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_cron_expire_no_cleaner() TO service_role;

-- 3) ADMIN (read-only): ver a disponibilidade semanal de uma profissional ----
-- A RLS fecha cleaner_availability à leitura de terceiros; o admin lê via RPC
-- guardada. Devolve array [{weekday,start_time,end_time}] ordenado.
CREATE OR REPLACE FUNCTION public.admin_cleaner_availability(p_cleaner_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'weekday', weekday,
             'start_time', start_time,
             'end_time', end_time)
           ORDER BY weekday, start_time)
    FROM cleaner_availability
    WHERE cleaner_id = p_cleaner_id
  ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_cleaner_availability(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cleaner_availability(uuid) TO authenticated;

-- 4) Agenda o cron — de 5 em 5 min (idempotente) -----------------------------
SELECT cron.unschedule(jobid) FROM cron.job
WHERE jobname = 'cleaning-expire-no-cleaner';

SELECT cron.schedule('cleaning-expire-no-cleaner', '*/5 * * * *',
  $$SELECT public._cleaning_cron_expire_no_cleaner();$$);
