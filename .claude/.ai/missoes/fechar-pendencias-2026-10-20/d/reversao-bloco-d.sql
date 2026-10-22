-- REVERSÃO do Bloco D (marcos do check-in), migrações 20261021045300 .. 20261021061215
-- (as 11 primeiras + as 2 da ronda 1 do revisor: 20261021061136 e 20261021061215).
-- NÃO correr sem ordem do Danilo. Desliga primeiro, depois desfaz (sem apagar dados de clientes:
-- os vales ficam guardados numa cópia antes de a tabela sair).
--
-- Passo 0 (basta para parar tudo, sem apagar nada): desligar.
--   select public.admin_update_setting('checkin_marco_ativo', 'false'::jsonb);
--   update public.support_skills set active = false where skill_name = 'CHECKIN_MARCOS_PREMIOS';
--
-- Passo 1 (desfazer de vez):
BEGIN;
SELECT cron.unschedule('checkin-premios-manutencao');

-- 1.º os lembretes das 11h/20h: repor JÁ a versão que estava no ar antes do Bloco D (a frase da manhã
-- "Ontem fizeste o dia %s do check-in…"), porque a de agora usa _checkin_estado_marcos e
-- _checkin_marcos_config, que saem mais abaixo. Atenção: essa versão NÃO é a da migração 20261018170119
-- ("Vais no dia %s seguido!…"); foi trocada fora das migrações antes do Bloco D.
-- md5(prosrc) depois de correr isto = 4b15f97f32371b65399ea1d691b463a7 (ronda 2, 21/10: provado numa
-- transação desfeita e confirmado pelo revisor; a ronda 1 tinha aqui um md5 errado, abfeca53…, e o guião
-- parava no passo seguinte).
CREATE OR REPLACE FUNCTION public.checkin_lembretes_processar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje      date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_hora      integer := extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon'))::integer;
  v_ligado    boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_enabled'), false)
                         AND to_regprocedure('public.client_daily_checkin()') IS NOT NULL;
  v_m_on      boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_push_morning_enabled'), true);
  v_m_h       integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'checkin_push_morning_hour'), 11);
  v_n_on      boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_push_evening_enabled'), true);
  v_n_h       integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'checkin_push_evening_hour'), 20);
  v_exige_tel boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_require_phone'), true);
  v_so_opt_in boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_push_so_opt_in'), false);
  v_premios   integer[] := public._checkin_premios();
  v_turno     text;
  v_url       text;
  v_key       text;
  v_titulo    text := 'Check-in diário';
  v_texto     text;
  v_req       bigint;
  v_pessoas   integer := 0;
  v_grupos    integer := 0;
  g           record;
BEGIN
  IF NOT v_ligado THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'desligado');
  END IF;

  IF v_m_on AND v_hora = v_m_h THEN
    v_turno := 'manha';
  ELSIF v_n_on AND v_hora = v_n_h THEN
    v_turno := 'noite';
  ELSE
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'fora_de_hora', 'hora_lisboa', v_hora);
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'segredos_em_falta', 'turno', v_turno);
  END IF;

  FOR g IN
    WITH base AS (
      SELECT u.id AS user_id, l.checkin_date AS ult_data, l.streak_day::integer AS ult_dia
        FROM public.users u
        LEFT JOIN LATERAL (
          SELECT d.checkin_date, d.streak_day
            FROM public.daily_checkins d
           WHERE d.user_id = u.id
           ORDER BY d.checkin_date DESC
           LIMIT 1
        ) l ON true
       WHERE public._checkin_e_cliente(u.id)
         AND (NOT v_exige_tel OR public._checkin_telemovel_confirmado(u.id))
         -- quem desligou as notificações não tem aparelho ativo
         AND EXISTS (SELECT 1 FROM public.client_push_tokens t WHERE t.user_id = u.id AND t.active)
         -- opt-in de promoções: desligado a 18/10/2026 por decisão do Danilo (fica a chave para voltar a ligar)
         AND (NOT v_so_opt_in OR COALESCE(u.marketing_opt_in, false))
         AND NOT EXISTS (SELECT 1 FROM public.checkin_lembretes_envios e
                          WHERE e.user_id = u.id AND e.dia = v_hoje AND e.turno = v_turno)
    ), alvo AS (
      SELECT b.user_id, b.ult_dia, public._checkin_dia_de_hoje(b.ult_data, b.ult_dia, v_hoje) AS dia
        FROM base b
       -- manhã e noite: só quem fez ONTEM e ainda não fez hoje (sequência a correr).
       -- Quem nunca fez ou falhou um dia não recebe, até voltar a fazer sozinho (Danilo, 18/10/2026).
       WHERE b.ult_data = v_hoje - 1
         AND b.ult_dia >= 1
    )
    , lotes AS (
      SELECT a.*, (row_number() OVER (PARTITION BY a.dia, a.ult_dia ORDER BY a.user_id) - 1) / 150 AS lote
        FROM alvo a
    )
    SELECT l.dia, l.ult_dia AS seq, array_agg(l.user_id) AS ids
      FROM lotes l
     GROUP BY 1, 2, l.lote
  LOOP
    IF v_turno = 'manha' THEN
      v_texto := format('Ontem fizeste o dia %s do check-in. O de hoje vale %s tokens!',
                        g.seq, v_premios[g.dia]);
    ELSE
      v_texto := format('Não percas a tua sequência de %s %s! Faz o check-in de hoje e ganha %s tokens.',
                        g.seq, CASE WHEN g.seq = 1 THEN 'dia' ELSE 'dias' END, v_premios[g.dia]);
    END IF;

    -- regista primeiro: se o envio falhar, ninguém recebe o mesmo lembrete duas vezes
    INSERT INTO public.checkin_lembretes_envios (user_id, dia, turno, dia_sequencia, tokens)
    SELECT x, v_hoje, v_turno, g.dia, v_premios[g.dia] FROM unnest(g.ids) AS x
    ON CONFLICT ON CONSTRAINT checkin_lembretes_um_por_turno DO NOTHING;

    SELECT net.http_post(
      url := v_url || '/functions/v1/push-clientes-alvo',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('user_ids', to_jsonb(g.ids), 'title', v_titulo, 'body', v_texto,
                                 'type', 'checkin_diario'),
      timeout_milliseconds := 60000
    ) INTO v_req;

    UPDATE public.checkin_lembretes_envios
       SET pedido_http = v_req
     WHERE dia = v_hoje AND turno = v_turno AND user_id = ANY (g.ids);

    v_pessoas := v_pessoas + array_length(g.ids, 1);
    v_grupos  := v_grupos + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'turno', v_turno, 'dia', v_hoje,
                            'pessoas', v_pessoas, 'pedidos_http', v_grupos);
END;
$function$;
DO $confere$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.checkin_lembretes_processar()'::regprocedure)
     IS DISTINCT FROM '4b15f97f32371b65399ea1d691b463a7' THEN
    RAISE EXCEPTION 'reversao: os lembretes nao ficaram iguais aos de antes do Bloco D; nada foi desfeito';
  END IF;
END $confere$;

DROP TRIGGER IF EXISTS trg_checkin_premio_limpeza_cancelada ON public.cleaning_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_lavagem_cancelada ON public.carwash_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_no_pedido ON public.orders;
DROP TRIGGER IF EXISTS trg_checkin_premio_pedido_cancelado ON public.orders;
DROP TRIGGER IF EXISTS trg_checkin_premio_items_guarda ON public.orders;
DROP TRIGGER IF EXISTS trg_checkin_premio_guarda_pagamento ON public.cleaning_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_guarda_pagamento_upd ON public.cleaning_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_guarda_pagamento ON public.carwash_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_guarda_pagamento_upd ON public.carwash_bookings;
DROP TRIGGER IF EXISTS trg_checkin_marcos_apos_checkin ON public.daily_checkins;

DROP FUNCTION IF EXISTS public.client_checkin_premio_marcar_limpeza(uuid, timestamptz, text, text, text, double precision, double precision, text);
DROP FUNCTION IF EXISTS public.client_checkin_premio_marcar_lavagem(uuid, text, text, text, timestamptz, text, text, text, double precision, double precision, text, text, text);
DROP FUNCTION IF EXISTS public._checkin_premio_marcacao_cancelada();
DROP FUNCTION IF EXISTS public._checkin_premio_no_pedido();
DROP FUNCTION IF EXISTS public._checkin_premio_pedido_cancelado();
DROP FUNCTION IF EXISTS public._checkin_premio_guarda_pagamento();
DROP FUNCTION IF EXISTS public._checkin_premio_items_guarda();
DROP FUNCTION IF EXISTS public._checkin_premio_items_acrescenta(jsonb, jsonb);
DROP FUNCTION IF EXISTS public._checkin_premio_pode_voltar(text, text);
DROP FUNCTION IF EXISTS public._checkin_premio_consumir(uuid, text, text, jsonb);
DROP FUNCTION IF EXISTS public._checkin_premio_qtd_item(jsonb);
DROP FUNCTION IF EXISTS public._checkin_premio_ids_no_item(jsonb);
DROP FUNCTION IF EXISTS public.admin_checkin_premios_pagar_loja(uuid[], text);
DROP FUNCTION IF EXISTS public.admin_checkin_premio_marcar_usado(uuid, text);
DROP FUNCTION IF EXISTS public.admin_checkin_premio_dar(uuid, text, text);
DROP FUNCTION IF EXISTS public.admin_checkin_premio_anular(uuid, text);
DROP FUNCTION IF EXISTS public.admin_checkin_premios_resumo();
DROP FUNCTION IF EXISTS public.admin_checkin_premios_lista(text, text, integer);
DROP FUNCTION IF EXISTS public.checkin_premios_manutencao();
DROP FUNCTION IF EXISTS public.client_checkin_premio_escolher(uuid, text);
DROP FUNCTION IF EXISTS public.client_checkin_premio_libertar(uuid);
DROP FUNCTION IF EXISTS public.client_checkin_premio_reservar(uuid);
DROP FUNCTION IF EXISTS public.client_checkin_premio_visto(uuid[]);
DROP FUNCTION IF EXISTS public.client_checkin_premios();
DROP FUNCTION IF EXISTS public._checkin_vale_json(public.checkin_premios_vales);
DROP FUNCTION IF EXISTS public._checkin_marcos_apos_checkin();
DROP FUNCTION IF EXISTS public._checkin_vale_emitir(uuid, jsonb, date, text, uuid, text);
DROP FUNCTION IF EXISTS public._checkin_vale_ativar(uuid, boolean);
DROP FUNCTION IF EXISTS public._checkin_vale_avisar(uuid, text);
DROP FUNCTION IF EXISTS public._checkin_teve_pedido_pago(uuid, integer);
-- _checkin_estado_marcos e _checkin_marcos_config eram usadas pelos lembretes: já foram repostos lá em cima.
DROP FUNCTION IF EXISTS public._checkin_estado_marcos(uuid);
DROP FUNCTION IF EXISTS public._checkin_sequencia(uuid, date);
DROP FUNCTION IF EXISTS public._checkin_marcos_config();
DROP FUNCTION IF EXISTS public._checkin_marco_cfg(text, jsonb);

-- forma de pagamento 'premio': só se volta à lista antiga se não houver marcações 'premio'
-- (se houver, primeiro decidir o que fazer com elas).
-- ALTER TABLE public.cleaning_bookings DROP CONSTRAINT cleaning_bookings_payment_method_check;
-- ALTER TABLE public.cleaning_bookings ADD CONSTRAINT cleaning_bookings_payment_method_check
--   CHECK (payment_method = ANY (ARRAY['card','mbway','cash']));
-- (o mesmo para carwash_bookings)

DROP POLICY IF EXISTS products_premio_checkin_oculto_anon ON public.products;
DROP POLICY IF EXISTS products_premio_checkin_oculto ON public.products;
-- os 2 artigos-prémio a 0 EUR: tirar do catálogo SEM apagar (ficam escondidos)
UPDATE public.products SET is_available = false, removal_reason = 'bloco D revertido'
 WHERE id IN ('premio-checkin-salgados', 'premio-checkin-acai');

UPDATE public.support_skills SET active = false WHERE skill_name = 'CHECKIN_MARCOS_PREMIOS';

-- cópia dos vales antes de a tabela sair (regra: nunca apagar dados de produção sem backup)
CREATE TABLE IF NOT EXISTS public.bkp_checkin_premios_vales_20261021 AS TABLE public.checkin_premios_vales;
ALTER TABLE public.bkp_checkin_premios_vales_20261021 ENABLE ROW LEVEL SECURITY;
DROP TABLE IF EXISTS public.checkin_premios_vales;

DELETE FROM public.platform_settings WHERE key LIKE 'checkin\_marco\_%';
COMMIT;
