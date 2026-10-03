-- ============================================================================
-- O TRABALHO EM CURSO — o servidor diz sempre onde a pessoa esta a meio
--
-- Teste ao vivo de 2026-08-29: o Danilo aceitou uma lavagem, saiu da app e
-- voltou. Caiu no ecra de motorista. **Julgou que tinha perdido a lavagem.**
--
-- A causa e simples: a app decidia o ecra so pelo papel guardado no telemovel,
-- e nunca perguntava ao servidor se havia trabalho a meio. Estado de trabalho
-- guardado so no telemovel morre quando o Android mata a app.
--
-- Esta funcao e a fonte unica: pergunta-se ao servidor, nao a memoria local.
-- So leitura, e so da propria pessoa.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.meu_trabalho_em_curso()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  r record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  -- LAVAGEM primeiro: e a que prende a pessoa por mais tempo (leva o carro).
  SELECT w.id INTO v_id FROM washers w WHERE w.user_id = v_uid;
  IF v_id IS NOT NULL THEN
    SELECT b.id, b.status, b.address_street, b.address_city, b.washer_earnings_cents
      INTO r
      FROM carwash_bookings b
     WHERE b.washer_id = v_id
       AND b.status IN ('accepted','on_the_way','picked_up','in_progress','delivering')
     ORDER BY b.scheduled_at
     LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok', true, 'tem', true, 'categoria', 'lavagem',
        'booking_id', r.id, 'estado', r.status,
        'morada', trim(both ', ' from COALESCE(r.address_street,'') || ', ' || COALESCE(r.address_city,'')),
        'ganho_cents', COALESCE(r.washer_earnings_cents, 0));
    END IF;
  END IF;

  SELECT c.id INTO v_id FROM cleaners c WHERE c.user_id = v_uid;
  IF v_id IS NOT NULL THEN
    SELECT b.id, b.status, b.address_street, b.address_city, b.cleaner_earnings_cents
      INTO r
      FROM cleaning_bookings b
     WHERE b.cleaner_id = v_id
       AND b.status IN ('accepted','on_the_way','in_progress')
     ORDER BY b.scheduled_at
     LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok', true, 'tem', true, 'categoria', 'limpeza',
        'booking_id', r.id, 'estado', r.status,
        'morada', trim(both ', ' from COALESCE(r.address_street,'') || ', ' || COALESCE(r.address_city,'')),
        'ganho_cents', COALESCE(r.cleaner_earnings_cents, 0));
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'tem', false);
END $function$;

REVOKE ALL ON FUNCTION public.meu_trabalho_em_curso() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.meu_trabalho_em_curso() TO authenticated;
