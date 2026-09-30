-- =============================================================================
-- tvde_finish_ride — VOLTA DO PACOTE com mudança de destino na IDA (30/09/2026)
-- Achado da revisão adversarial: a volta era grátis até aos km REAIS da ida;
-- se a ida mudou de destino (5 km -> 9 km, paga à parte), a volta de 9 km
-- saía toda grátis e a Bora perdia (motoristas €12,30 vs recebido €11,00).
-- Agora a volta é grátis só até à distância COMBINADA da ida antes da
-- primeira mudança (`dest_change_base_km`). Sem mudança na ida essa coluna é
-- NULL e o comportamento é exatamente o de antes.
-- Patch por âncora: backup em fn_definition_backups + prova de igualdade.
-- =============================================================================
DO $$
DECLARE d text; n text; back text;
  a text := '      SELECT r2.final_distance_km INTO v_outbound_km';
  b text := '      SELECT CASE WHEN r2.dest_change_base_km IS NOT NULL THEN LEAST(r2.final_distance_km, r2.dest_change_base_km) ELSE r2.final_distance_km END INTO v_outbound_km';
BEGIN
  d := pg_get_functiondef('public.tvde_finish_ride(uuid,numeric,text,integer)'::regprocedure);
  IF md5(d) <> '448c830d086d81a82895b6cc1be8cd88' THEN
    RAISE EXCEPTION 'tvde_finish_ride no ar nao e a esperada (md5 %) — nada aplicado', md5(d);
  END IF;
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'ancora nao unica'; END IF;
  INSERT INTO public.fn_definition_backups(fn, definition, reason)
    VALUES ('tvde_finish_ride', d, 'antes da volta do pacote com base_km 2026-09-30');
  n := replace(d, a, b);
  back := replace(n, b, a);
  IF back <> d THEN RAISE EXCEPTION 'prova de igualdade falhou — nada aplicado'; END IF;
  EXECUTE n;
END $$;
