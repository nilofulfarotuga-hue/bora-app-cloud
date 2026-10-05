-- PROPOSTA (NAO APLICADA) — ronda 04/10, Bloco B, item 8 (tokens com semana de Lisboa).
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
--
-- driver_convert_tokens (conversao de tokens do estafeta em dinheiro) e funcao protegida
-- pela Trava; o agente nao a pode reescrever. Hoje o tecto semanal
-- (token_withdrawal_max_pct_weekly) conta a semana a partir de segunda 00:00 UTC
-- (date_trunc('week', now())). Em Portugal isso e segunda 01:00 no verao: uma conversao
-- feita domingo a noite/segunda de madrugada conta na semana errada.
--
-- Mudanca unica (remendo por ancora sobre a versao no ar; aborta se a ancora nao aparecer
-- exactamente 1 vez):
DO $patch$
DECLARE d text; a text := 'v_week_start := date_trunc(''week'', now());'; n int;
BEGIN
  d := pg_get_functiondef('public.driver_convert_tokens'::regproc);
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'ancora encontrada % vezes', n; END IF;
  d := replace(d, a,
    'v_week_start := date_trunc(''week'', now() AT TIME ZONE ''Europe/Lisbon'') AT TIME ZONE ''Europe/Lisbon'';');
  EXECUTE d;
END $patch$;
