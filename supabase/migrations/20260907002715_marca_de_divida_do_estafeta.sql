-- BLOCO 4.3 — 2026-09-07
-- Como a Uber e a Glovo: acima de um tecto de divida acumulada, o estafeta
-- deixa de receber trabalho ate acertar.
--
-- AQUI FICA SO A MARCA. O motor de despacho e zona protegida e NAO se toca
-- nesta missao: a coluna e a funcao ficam prontas e a decisao de as ligar ao
-- despacho e um passo a parte, com ordem propria. Enquanto o tecto for 0
-- (por defeito) isto nao marca ninguem.

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS blocked_for_debt boolean NOT NULL DEFAULT false;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS debt_cents int NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.drivers.blocked_for_debt IS
  'Divida acumulada acima do tecto (platform_settings.driver_cash_debt_block_cents). '
  'Marca informativa: o motor de despacho ainda NAO a le (2026-09-07).';

-- Recalcula a divida de cada estafeta e marca quem passou o tecto.
CREATE OR REPLACE FUNCTION public._refresh_driver_debt_marks()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tecto int := COALESCE((public.get_setting('driver_cash_debt_block_cents') #>> '{}')::int, 0);
  v_marcados int := 0;
BEGIN
  WITH divida AS (
    SELECT d.subject_id, sum(d.cents)::int AS total
      FROM public.settlement_debtors() d
     WHERE d.subject_type = 'driver'
     GROUP BY d.subject_id
  )
  UPDATE public.drivers dr
     SET debt_cents = COALESCE(v.total, 0),
         blocked_for_debt = (v_tecto > 0 AND COALESCE(v.total, 0) > v_tecto)
    FROM (SELECT dr2.id, dv.total
            FROM public.drivers dr2
            LEFT JOIN divida dv
              ON dv.subject_id = dr2.id::text OR dv.subject_id = dr2.user_id::text) v
   WHERE dr.id = v.id
     AND (dr.debt_cents IS DISTINCT FROM COALESCE(v.total, 0)
       OR dr.blocked_for_debt IS DISTINCT FROM (v_tecto > 0 AND COALESCE(v.total, 0) > v_tecto));

  SELECT count(*)::int INTO v_marcados FROM public.drivers WHERE blocked_for_debt;
  RETURN jsonb_build_object('ok', true, 'tecto_cents', v_tecto, 'marcados', v_marcados);
END $function$;

REVOKE ALL ON FUNCTION public._refresh_driver_debt_marks() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._refresh_driver_debt_marks() TO service_role;;
