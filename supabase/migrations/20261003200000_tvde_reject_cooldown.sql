-- 2026-10-03 — TVDE: quem recusou uma corrida não a volta a receber.
-- Corrida de referência 540b738a: recusa às 13:26:05 e a MESMA corrida voltou ao
-- MESMO motorista às 13:26:48. Causa: tvde_dispatch_sweep, ao fim de
-- tvde_reoffer_pause_seconds sem ninguém, faz tried_driver_ids = '{}' e a recusa
-- perdia-se. Correção: tvde_offer_to_next exclui quem recusou (evento
-- tvde_ride_events.meta.rejected_by) nos últimos tvde_reject_cooldown_seconds,
-- seja qual for o estado de tried_driver_ids. Quem só deixou expirar continua
-- como antes. Padrão Uber.
-- Remendo por âncora: a linha "AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))"
-- aparece 2x (livres e ocupados) e recebe a condição nova a seguir. Backup antes.

CREATE TABLE IF NOT EXISTS public.bkp_fn_tvde_despacho_20261003 (
  proname text, definicao text, guardado_em timestamptz DEFAULT now());
ALTER TABLE public.bkp_fn_tvde_despacho_20261003 ENABLE ROW LEVEL SECURITY;
INSERT INTO public.bkp_fn_tvde_despacho_20261003(proname, definicao)
SELECT 'tvde_offer_to_next', pg_get_functiondef('public.tvde_offer_to_next(uuid)'::regprocedure)
WHERE NOT EXISTS (SELECT 1 FROM public.bkp_fn_tvde_despacho_20261003 WHERE proname = 'tvde_offer_to_next');

INSERT INTO public.platform_settings(key, value, category, description)
VALUES ('tvde_reject_cooldown_seconds', '600'::jsonb, 'dispatch',
        'Segundos durante os quais um motorista que RECUSOU uma corrida não a volta a receber (padrão Uber). 0 = desliga.')
ON CONFLICT (key) DO NOTHING;

DO $do$
DECLARE
  d text;
  ancora text := '      AND NOT (d.user_id = ANY(v_ride.tried_driver_ids))' || chr(10);
  extra text :=
    '      -- 2026-10-03: quem recusou esta corrida não a volta a receber (cooldown).' || chr(10) ||
    '      AND NOT EXISTS (' || chr(10) ||
    '        SELECT 1 FROM public.tvde_ride_events e' || chr(10) ||
    '        WHERE e.ride_id = p_ride_id' || chr(10) ||
    '          AND e.actor = ''driver''' || chr(10) ||
    '          AND e.meta->>''rejected_by'' = d.user_id::text' || chr(10) ||
    '          AND e.at > now() - make_interval(secs => COALESCE((public.get_setting(''tvde_reject_cooldown_seconds'') #>> ''{}'')::int, 600)))' || chr(10);
  n int;
BEGIN
  d := pg_get_functiondef('public.tvde_offer_to_next(uuid)'::regprocedure);
  IF position('tvde_reject_cooldown_seconds' in d) > 0 THEN
    RAISE NOTICE 'tvde_offer_to_next já tem o cooldown — nada a fazer';
    RETURN;
  END IF;
  n := (length(d) - length(replace(d, ancora, ''))) / length(ancora);
  IF n <> 2 THEN
    RAISE EXCEPTION 'âncora encontrada % vezes (esperado 2) — remendo abortado', n;
  END IF;
  EXECUTE replace(d, ancora, ancora || extra);
END
$do$;
