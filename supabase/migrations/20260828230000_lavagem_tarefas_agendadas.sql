-- ============================================================================
-- A LAVAGEM PASSA A TER TAREFAS AGENDADAS
--
-- O buraco, medido a 2026-08-28: existiam três funções de rotação prontas —
-- `_carwash_cron_offer_timeout`, `_carwash_cron_retry_unoffered` e
-- `_carwash_cron_stuck` — e **nenhuma tarefa agendada a chamá-las**. A limpeza
-- tinha oito; a lavagem tinha zero.
--
-- Consequência real: o pedido `a0f22229-58b7-4763-aa7a-628abf9aa100`, de vinte
-- euros, foi oferecido a um lavador às 06h24, a oferta expirou às 06h34, e
-- ficou parado seis horas porque não havia nada a olhar para ele. Uma função
-- que ninguém chama é código morto com aspecto de funcionalidade.
--
-- Também se tiram do código três números que lá estavam cravados. A regra da
-- casa é que tempos de espera vivem em `platform_settings`, para se afinarem
-- sem novo lançamento.
--
-- Nada aqui toca em preços, comissões ou pagamentos.
-- ============================================================================

-- ── 1. Os tempos saem do código e vão para as definições ───────────────────
INSERT INTO public.platform_settings (key, value)
VALUES
  -- Até quando vale a pena voltar a tentar um pedido que ninguém aceitou.
  ('carwash_retry_window_hours', '12'::jsonb),
  -- Só se insiste em pedidos cuja hora marcada está a chegar.
  ('carwash_retry_lead_hours',   '2'::jsonb),
  -- A partir de quantas horas um trabalho a decorrer é considerado preso.
  ('carwash_stuck_after_hours',  '4'::jsonb)
ON CONFLICT (key) DO NOTHING;


-- ── 2. As funções passam a ler as definições ───────────────────────────────
CREATE OR REPLACE FUNCTION public._carwash_cron_retry_unoffered()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_janela int;
  v_antecedencia int;
BEGIN
  SELECT COALESCE((value #>> '{}')::int, 12) INTO v_janela
    FROM platform_settings WHERE key = 'carwash_retry_window_hours';
  SELECT COALESCE((value #>> '{}')::int, 2) INTO v_antecedencia
    FROM platform_settings WHERE key = 'carwash_retry_lead_hours';
  v_janela := COALESCE(v_janela, 12);
  v_antecedencia := COALESCE(v_antecedencia, 2);

  FOR r IN SELECT id FROM carwash_bookings
           WHERE status = 'scheduled' AND offer_washer_id IS NULL
             AND created_at > now() - make_interval(hours => v_janela)
             AND scheduled_at < now() + make_interval(hours => v_antecedencia)
  LOOP
    -- Limpar quem já recusou dá a volta ao círculo outra vez: mais vale
    -- perguntar duas vezes do que deixar o cliente sem ninguém.
    UPDATE carwash_bookings SET offered_washer_ids = '{}'::uuid[] WHERE id = r.id;
    PERFORM public._carwash_next_offer(r.id);
  END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION public._carwash_cron_stuck()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_horas int;
BEGIN
  SELECT COALESCE((value #>> '{}')::int, 4) INTO v_horas
    FROM platform_settings WHERE key = 'carwash_stuck_after_hours';
  v_horas := COALESCE(v_horas, 4);

  FOR r IN SELECT id, plate, status FROM carwash_bookings
           WHERE status IN ('picked_up', 'in_progress', 'delivering')
             AND started_at < now() - make_interval(hours => v_horas)
             AND stuck_alerted_at IS NULL
  LOOP
    UPDATE carwash_bookings SET stuck_alerted_at = now() WHERE id = r.id;
    PERFORM public._carwash_notify_admin(
      'Lavagem parada ha muito tempo',
      'Pedido ' || r.id::text || ' (' || r.plate || ') esta em ' || r.status ||
      ' ha mais de ' || v_horas || ' horas.');
  END LOOP;
END $function$;


-- ── 3. Alguém tem de as chamar ─────────────────────────────────────────────
-- Cadência proporcional ao tempo de espera, tal como na limpeza: lá a oferta
-- dura 30 minutos e a tarefa corre de 5 em 5; aqui dura 10, logo corre de 2
-- em 2. O alerta de preso é de hora a hora, igual ao da limpeza.
SELECT cron.unschedule('carwash-offer-timeout')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carwash-offer-timeout');
SELECT cron.unschedule('carwash-retry-unoffered')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carwash-retry-unoffered');
SELECT cron.unschedule('carwash-stuck-alert')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carwash-stuck-alert');

SELECT cron.schedule('carwash-offer-timeout',   '*/2 * * * *',
                     'SELECT public._carwash_cron_offer_timeout();');
SELECT cron.schedule('carwash-retry-unoffered', '*/2 * * * *',
                     'SELECT public._carwash_cron_retry_unoffered();');
SELECT cron.schedule('carwash-stuck-alert',     '20 * * * *',
                     'SELECT public._carwash_cron_stuck();');
