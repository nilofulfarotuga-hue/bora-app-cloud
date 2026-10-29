-- ============================================================================
-- C5 · PROPOSTA 03 — ALERTA AO PARCEIRO 30 MIN ANTES DO PEDIDO AGENDADO (push + som)
-- Item 5 do adendo 5 do Danilo (29/10/2026). NÃO APLICADA.
--
-- O QUE FAZ: de 5 em 5 minutos (pg_cron), procura pedidos agendados a 30 minutos ou menos da hora marcada,
-- ainda por avisar, e manda UM aviso à loja pelo mesmo caminho dos outros avisos ao parceiro:
-- _notify_partner_status_change → Edge Function notify-partner (kind 'status_change').
--   • iPhone: alerta com o som bora_alert.wav, prioridade alta, "time-sensitive" (notify-partner v24).
--   • Android: o kind 'status_change' já está tratado na app (notification_service.dart) e mostra uma
--     notificação persistente. NÃO toca em ciclo como o "Novo pedido" — para isso seria preciso um kind
--     novo na Edge Function + na app (fora desta missão: supabase/functions/** não se toca).
--   • Com o ecrã "Pedidos agendados" aberto, a app toca o alerta uma vez por pedido (já feito no Dart).
-- Resolução: o aviso sai entre 25 e 30 min antes (o cron corre de 5 em 5 min).
--
-- Reutiliza o que já existe (não inventa canal): _notify_partner_status_change(restaurant_id, título, texto)
-- é a função de 20261007105848, que lê o endereço e a chave de serviço do cofre e chama notify-partner.
--
-- Atrás do interruptor: sem `scheduled_orders_enabled` = true devolve 0 e não faz nada.
-- Sem alterar a tabela orders (tabela quente, cheia de gatilhos): o "já avisei" fica numa tabela à parte.
--
-- COMO USAR: PARTE 3 (prova) sozinha primeiro; PARTES 1+2 depois do SIM do revisor; PARTE 4 reverte.
-- ============================================================================

-- ANTES: confirmar que o caminho de aviso existe e como está definido
--   select pg_get_functiondef('public._notify_partner_status_change(text,text,text)'::regprocedure);
--   select jobname, schedule from cron.job order by jobname;   -- o nome 'partner-scheduled-reminders' não pode existir

-- ============================================================================
-- PARTE 1 — Tabela do "já avisei" (uma linha por pedido avisado)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.scheduled_order_reminders (
  order_id  text PRIMARY KEY,
  sent_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.scheduled_order_reminders ENABLE ROW LEVEL SECURITY;   -- sem política: ninguém lê pela API
COMMENT ON TABLE public.scheduled_order_reminders IS
  'C5 29/10/2026: pedidos agendados cujo aviso de 30 min ao parceiro já saiu (dedupe do cron partner-scheduled-reminders).';

-- ============================================================================
-- PARTE 2 — A função do cron e o cron
-- ============================================================================
CREATE OR REPLACE FUNCTION public.partner_scheduled_reminders(p_simular boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_on    boolean;
  v_o     record;
  v_novo  integer;
  v_ids   jsonb := '[]'::jsonb;
  v_hora  text;
  v_cod   text;
BEGIN
  SELECT COALESCE((value #>> '{}')::boolean, false) INTO v_on
    FROM public.platform_settings WHERE key = 'scheduled_orders_enabled';
  IF NOT COALESCE(v_on, false) THEN
    RETURN jsonb_build_object('ativo', false, 'avisos', 0, 'ids', v_ids);
  END IF;

  FOR v_o IN
    SELECT o.id, o.restaurant_id, o.scheduled_for, o.status
      FROM public.orders o
     WHERE o.scheduled_for IS NOT NULL
       AND o.status IN ('created', 'preparing')
       AND o.scheduled_for <= now() + interval '30 minutes'
       AND o.scheduled_for >  now() - interval '30 minutes'
       AND NOT EXISTS (SELECT 1 FROM public.scheduled_order_reminders r WHERE r.order_id = o.id)
     ORDER BY o.scheduled_for
     LIMIT 100
  LOOP
    v_ids := v_ids || to_jsonb(v_o.id);
    CONTINUE WHEN p_simular;       -- simulação: lista o que SERIA avisado, sem gravar nem enviar

    -- Dedupe atómico: só avisa quem conseguir inserir a linha.
    INSERT INTO public.scheduled_order_reminders (order_id) VALUES (v_o.id) ON CONFLICT (order_id) DO NOTHING;
    GET DIAGNOSTICS v_novo = ROW_COUNT;
    CONTINUE WHEN v_novo = 0;

    BEGIN
      v_hora := to_char(v_o.scheduled_for AT TIME ZONE 'Europe/Lisbon', 'HH24:MI');
      v_cod  := upper(right(v_o.id, 4));
      PERFORM public._notify_partner_status_change(
        v_o.restaurant_id,
        'Pedido agendado para as ' || v_hora,
        CASE WHEN v_o.status = 'created'
             THEN 'O pedido #' || v_cod || ' é para as ' || v_hora || ' e ainda não foi aceite. Abra a app e aceite.'
             ELSE 'Comece a preparar: o pedido #' || v_cod || ' é para as ' || v_hora || '.'
        END);
    EXCEPTION WHEN OTHERS THEN
      -- Falhar o envio nunca pára o resto; fica registado e não se repete (já está na tabela).
      RAISE WARNING 'partner_scheduled_reminders: pedido % — %', v_o.id, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('ativo', true, 'simulado', p_simular,
                            'avisos', jsonb_array_length(v_ids), 'ids', v_ids);
END;
$function$;

REVOKE ALL ON FUNCTION public.partner_scheduled_reminders(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.partner_scheduled_reminders(boolean) TO service_role;

-- O cron (idempotente): de 5 em 5 minutos.
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'partner-scheduled-reminders';
SELECT cron.schedule('partner-scheduled-reminders', '*/5 * * * *',
  $$SELECT public.partner_scheduled_reminders();$$);

-- ============================================================================
-- PARTE 3 — PROVA numa transação que se desfaz sozinha (DO + RAISE)
--   Correr o bloco abaixo SOZINHO (tirar o /* e o */). Termina SEMPRE com um erro "PROVA ...": é o rollback
--   propositado e o texto é o resultado. NÃO envia nenhum aviso (usa o modo simulado) e NÃO toca em pedidos.
--   Prova: (a) o dedupe — a mesma chave inserida duas vezes só entra uma; (b) com o interruptor desligado a
--   função devolve ativo=false; (c) lista os pedidos reais que SERIAM avisados agora (normalmente 0).
-- ============================================================================
/*
BEGIN;

-- (a) dedupe, com uma chave de prova (a tabela não tem FK para orders)
INSERT INTO public.scheduled_order_reminders (order_id) VALUES ('PROVA-C5-1') ON CONFLICT (order_id) DO NOTHING;
DO $prova$
DECLARE
  n1 int; n2 int; ligado boolean; r_off jsonb; r_on jsonb; txt text := '';
BEGIN
  INSERT INTO public.scheduled_order_reminders (order_id) VALUES ('PROVA-C5-1') ON CONFLICT (order_id) DO NOTHING;
  GET DIAGNOSTICS n2 = ROW_COUNT;                       -- tem de ser 0: já estava
  txt := txt || 'dedupe: segunda inserção da mesma chave → ' || n2 || ' linhas (esperado 0)' || E'\n';

  -- (b)/(c) interruptor: guardar, forçar desligado, chamar em simulação, forçar ligado, chamar em simulação
  SELECT COALESCE((value #>> '{}')::boolean, false) INTO ligado
    FROM public.platform_settings WHERE key = 'scheduled_orders_enabled';
  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'scheduled_orders_enabled';
  r_off := public.partner_scheduled_reminders(true);
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'scheduled_orders_enabled';
  r_on := public.partner_scheduled_reminders(true);
  txt := txt || 'interruptor desligado → ' || r_off::text || E'\n'
             || 'interruptor ligado (simulado) → ' || r_on::text || E'\n'
             || 'valor do interruptor antes da prova: ' || ligado || ' (volta sozinho com o rollback)' || E'\n';

  IF n2 = 0 AND (r_off->>'ativo')::boolean IS FALSE AND (r_off->>'avisos')::int = 0 THEN
    RAISE EXCEPTION 'PROVA OK (rollback propositado)%', E'\n' || txt;
  ELSE
    RAISE EXCEPTION 'PROVA FALHOU (rollback propositado)%', E'\n' || txt;
  END IF;
END
$prova$;
ROLLBACK;
*/

-- ============================================================================
-- PARTE 4 — REVERSÃO
-- ============================================================================
/*
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'partner-scheduled-reminders';
DROP FUNCTION IF EXISTS public.partner_scheduled_reminders(boolean);
-- A tabela scheduled_order_reminders pode ficar (é só um registo).
*/

-- ============================================================================
-- NOTAS PARA O REVISOR
--   1. A prova mexe no interruptor DENTRO da transação que se desfaz: confirmar depois do erro que
--      `select value from platform_settings where key='scheduled_orders_enabled'` continua false.
--   2. O pedido que entra no sistema já a menos de 30 min da hora marcada (não deve acontecer: a antecedência
--      mínima é 60 min) recebe o aviso no ciclo seguinte; o filtro `> now() − 30 min` evita avisar pedidos velhos.
--   3. Limite de 100 por ciclo; sobrando, o ciclo seguinte apanha.
--   4. Quem recebe: restaurants.fcm_token da loja (o mesmo dos avisos de "loja aberta/fechada"). Loja sem token →
--      _notify_partner_status_change sai calada (já fica na tabela, não repete).
-- ============================================================================
