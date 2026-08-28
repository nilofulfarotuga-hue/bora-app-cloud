-- ============================================================================
-- O CLIENTE PASSA A SABER DE CADA PASSO
--
-- Pergunta do Danilo a 2026-08-29: de cada vez que o prestador muda o estado,
-- o que e que o cliente recebe?
--
-- ── A resposta, levantada estado a estado ─────────────────────────────────
-- LIMPEZA:  aceite -> avisava.  a caminho -> NADA.  comecou -> NADA.
--           concluida -> avisava.
-- LAVAGEM:  aceite -> avisava.  a caminho -> NADA.  carro recolhido -> NADA.
--           a lavar -> NADA.  a devolver -> NADA.  entregue/concluida -> avisava.
--
-- Ou seja: dois avisos no principio e no fim, e silencio no meio — justamente
-- enquanto o cliente esta sem o carro ou com uma pessoa em casa. Nas entregas
-- ele e avisado a cada passo; aqui nao era.
--
-- A causa e uma so, e por isso a correccao tambem: todos os passos do meio
-- passam por `_cleaning_transition` / `_carwash_transition`, e nenhuma delas
-- tinha uma linha sequer de aviso. Corrigir nas seis funcoes de accao seria
-- criar gemeos; corrige-se nas duas por onde tudo passa.
--
-- Nao mexe em dinheiro nem em quem e chamado.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._carwash_transition(
  p_booking_id uuid, p_from text, p_to text, p_ts_col text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me washers; v_b carwash_bookings;
  v_titulo text; v_corpo text;
BEGIN
  v_me := public._carwash_current_washer();
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.washer_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> p_from THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;
  EXECUTE format('UPDATE carwash_bookings SET status = $1, %I = now() WHERE id = $2', p_ts_col)
  USING p_to, p_booking_id;

  -- O CLIENTE SABE DE CADA PASSO. O texto e o que ele quer ouvir na rua, nao
  -- o nome do estado na base.
  SELECT t, c INTO v_titulo, v_corpo FROM (VALUES
    ('on_the_way',  'A caminho',            v_me.name || ' vai a caminho do teu carro.'),
    ('picked_up',   'Carro recolhido',      v_me.name || ' ja esta com o teu carro.'),
    ('in_progress', 'A lavar',              'A lavagem comecou.'),
    ('delivering',  'A caminho de volta',   v_me.name || ' vai a caminho com o teu carro lavado.'),
    ('delivered',   'Carro entregue',       'O teu carro foi entregue. Obrigado!')
  ) AS x(s, t, c) WHERE x.s = p_to;

  IF v_titulo IS NOT NULL THEN
    PERFORM public._carwash_notify_user(v_b.client_user_id, 'carwash_' || p_to,
      v_titulo, v_corpo, p_booking_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM carwash_bookings b WHERE b.id = p_booking_id);
END $function$;


CREATE OR REPLACE FUNCTION public._cleaning_transition(
  p_booking_id uuid, p_from text, p_to text, p_ts_col text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me cleaners; v_b cleaning_bookings;
  v_titulo text; v_corpo text;
BEGIN
  v_me := public._cleaning_current_cleaner();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.cleaner_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  IF v_b.status <> p_from THEN
    RAISE EXCEPTION 'invalid_transition_from_%', v_b.status;
  END IF;
  EXECUTE format(
    'UPDATE cleaning_bookings SET status = $1, %I = now() WHERE id = $2', p_ts_col)
  USING p_to, p_booking_id;

  SELECT t, c INTO v_titulo, v_corpo FROM (VALUES
    ('on_the_way',  'A caminho',   v_me.name || ' vai a caminho de tua casa.'),
    ('in_progress', 'A limpeza comecou', v_me.name || ' ja comecou a limpeza.'),
    ('done',        'Limpeza terminada', v_me.name || ' terminou. Confirma quando puderes.')
  ) AS x(s, t, c) WHERE x.s = p_to;

  IF v_titulo IS NOT NULL THEN
    PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_' || p_to,
      v_titulo, v_corpo, p_booking_id::text);
  END IF;

  RETURN (SELECT to_jsonb(b) FROM cleaning_bookings b WHERE b.id = p_booking_id);
END $function$;
