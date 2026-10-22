-- Reversão do R1: repõe create_order exatamente como estava antes (cópia em bkp_fn_create_order_20261021,
-- md5 8688fcf8b22429246079ec873d076fd8). Não apaga a cópia.
DO $r1rev$
DECLARE
  v_def text;
BEGIN
  SELECT def INTO v_def FROM public.bkp_fn_create_order_20261021
   WHERE md5 = '8688fcf8b22429246079ec873d076fd8' ORDER BY guardado_em LIMIT 1;
  IF v_def IS NULL THEN RAISE EXCEPTION 'R1 reversao: nao ha copia com o md5 de antes'; END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.create_order(jsonb)'::regprocedure)) <> '8688fcf8b22429246079ec873d076fd8' THEN
    RAISE EXCEPTION 'R1 reversao: a funcao nao ficou igual a de antes';
  END IF;
END $r1rev$;
