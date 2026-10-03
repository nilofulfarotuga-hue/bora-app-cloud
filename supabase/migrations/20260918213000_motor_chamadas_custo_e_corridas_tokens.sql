-- Telemetria dos agentes (2026-09-18, missão sistema-redondo-2026-09-18), aditiva.
--
-- 1. motor_chamadas.custo_eur — o Motor Bora passa a gravar o custo estimado
--    (tabela PRECO_POR_MILHAO, EUR por milhão de tokens) por chamada.
-- 2. preencher_custos_corridas() — cada linha de agentes_corridas nasce sem
--    tokens/custo_eur porque o `hermes -p` só devolve texto. As chamadas ao
--    modelo ficam em motor_chamadas (máquina vps). Esta função soma, para cada
--    corrida ainda a NULL, as chamadas do mesmo perfil dentro da janela
--    [quando − ms, quando] e escreve tokens e custo_eur. Corre de 10 em 10 min
--    pelo pg_cron. Sem isto ninguém sabe o que se gasta e os tectos por dia de
--    agentes_estado não têm com que se comparar.

ALTER TABLE public.motor_chamadas ADD COLUMN IF NOT EXISTS custo_eur numeric;

CREATE OR REPLACE FUNCTION public.preencher_custos_corridas(p_desde interval DEFAULT interval '2 days')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer := 0;
BEGIN
  WITH alvo AS (
    SELECT c.id, c.quando, c.ms, c.modelo
      FROM public.agentes_corridas c
     WHERE c.tokens IS NULL
       AND c.quando > now() - p_desde
       AND c.quando < now() - interval '90 seconds'   -- dá tempo ao sync do Motor (20 s)
  ), soma AS (
    SELECT a.id,
           SUM(m.tokens)::integer AS tokens,
           ROUND(SUM(COALESCE(m.custo_eur, 0))::numeric, 6) AS custo_eur
      FROM alvo a
      JOIN public.motor_chamadas m
        ON m.created_at BETWEEN a.quando - make_interval(secs => COALESCE(a.ms, 0) / 1000.0 + 5)
                            AND a.quando + interval '5 seconds'
       AND (a.modelo IS NULL OR a.modelo NOT LIKE 'perfil:%' OR m.perfil = substr(a.modelo, 8))
     GROUP BY a.id
  )
  UPDATE public.agentes_corridas c
     SET tokens = s.tokens, custo_eur = s.custo_eur
    FROM soma s
   WHERE c.id = s.id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  -- Corridas antigas sem nenhuma chamada registada ficam a 0, não a NULL:
  -- "não gastou" é uma resposta; NULL é "ninguém sabe".
  UPDATE public.agentes_corridas c
     SET tokens = 0, custo_eur = 0
   WHERE c.tokens IS NULL
     AND c.quando > now() - p_desde
     AND c.quando < now() - interval '30 minutes';
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION public.preencher_custos_corridas(interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.preencher_custos_corridas(interval) FROM anon;

SELECT cron.schedule('preencher-custos-corridas', '*/10 * * * *', $$SELECT public.preencher_custos_corridas();$$)
 WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'preencher-custos-corridas');
