-- [09/10/2026 · Mayra] Toque persistente da oferta de limpeza: repete o push
-- urgente a cada minuto enquanto a oferta estiver à espera dela (padrão estafeta/TVDE).
-- Para sozinho quando ela aceita/recusa (offer_cleaner_id volta a NULL) ou a oferta expira.
-- Só chama a Edge `notify-cleaner` (não duplica avisos na caixa da app).
--
-- Aplicada em produção pela Claude.ai a 09/10/2026 (versão 20261009122152 na lista de
-- migrações do servidor). Guardada no repo a 09/10/2026 (missão fecho-total-2026-10-09)
-- com a definição lida do AR por pg_get_functiondef — md5 bec6c23bd150df30a573224b31264f0c.
-- Interruptor: _cleaning_setting_bool('cleaning_offer_reping_enabled', true).
CREATE OR REPLACE FUNCTION public._cleaning_cron_offer_reping()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url text; v_key text; r record;
BEGIN
  IF NOT COALESCE(public._cleaning_setting_bool('cleaning_offer_reping_enabled', true), true) THEN
    RETURN;
  END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN RETURN; END IF;

  FOR r IN
    SELECT b.id, b.scheduled_at, b.total_cents, b.offer_expires_at, c.user_id
    FROM cleaning_bookings b
    JOIN cleaners c ON c.id = b.offer_cleaner_id
    WHERE b.status = 'scheduled'
      AND b.cleaner_id IS NULL
      AND b.offer_cleaner_id IS NOT NULL
      AND b.offer_expires_at > now()
      AND NOT COALESCE(b.is_test_order, false)
  LOOP
    PERFORM net.http_post(
      url := v_url || '/functions/v1/notify-cleaner',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
      body := jsonb_build_object(
        'cleanerUserId', r.user_id::text,
        'bookingId', r.id::text,
        'title', 'Nova limpeza à tua espera',
        'body', 'Limpeza a ' || to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
                ' — ' || (r.total_cents / 100.0)::numeric(10,2) || ' EUR. Aceita ou recusa (faltam ' ||
                GREATEST(1, ceil(extract(epoch FROM (r.offer_expires_at - now())) / 60))::int || ' min).',
        'kind', 'cleaning_offer_reping', 'type', 'cleaning_offer')
    );
  END LOOP;
END $function$
;

REVOKE ALL ON FUNCTION public._cleaning_cron_offer_reping() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('cleaning-offer-reping') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='cleaning-offer-reping');
SELECT cron.schedule('cleaning-offer-reping', '* * * * *', 'SELECT public._cleaning_cron_offer_reping();');
