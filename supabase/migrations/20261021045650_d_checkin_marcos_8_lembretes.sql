-- Bloco D · fechar-pendencias-2026-10-20 — lembretes das 11h e das 20h dizem quantos dias
-- faltam para o proximo marco (premio) quando faltam ate checkin_marco_lembrete_dias (3).
-- Igual a versao de 18/10 (so quem fez ontem e ainda nao fez hoje; max 2 por dia; quem
-- desligou as notificacoes nao recebe) com uma frase a mais no fim do texto.
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
  v_marcos_on boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_marco_ativo'), false);
  v_lim_dias  integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'checkin_marco_lembrete_dias'), 3);
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
      SELECT b.user_id, b.ult_dia, public._checkin_dia_de_hoje(b.ult_data, b.ult_dia, v_hoje) AS dia,
             CASE WHEN v_marcos_on THEN public._checkin_estado_marcos(b.user_id) -> 'proximo' END AS prox
        FROM base b
       -- manhã e noite: só quem fez ONTEM e ainda não fez hoje (sequência a correr).
       -- Quem nunca fez ou falhou um dia não recebe, até voltar a fazer sozinho (Danilo, 18/10/2026).
       WHERE b.ult_data = v_hoje - 1
         AND b.ult_dia >= 1
    ), com_marco AS (
      SELECT a.user_id, a.ult_dia, a.dia,
             CASE
               WHEN a.prox IS NULL THEN ''
               WHEN COALESCE((a.prox ->> 'faltam')::int, 99) < 1 THEN ''
               WHEN (SELECT x ->> 'tipo' FROM jsonb_array_elements(public._checkin_marcos_config()) x
                      WHERE x ->> 'chave' = a.prox ->> 'chave' LIMIT 1) NOT IN ('produto','servico') THEN ''
               WHEN (a.prox ->> 'faltam')::int = 1 THEN
                 ' Faz o check-in de hoje e ganhas ' || (a.prox ->> 'titulo') || '!'
               WHEN (a.prox ->> 'faltam')::int <= v_lim_dias THEN
                 ' Faltam ' || (a.prox ->> 'faltam') || ' dias para ganhares ' || (a.prox ->> 'titulo') || '.'
               ELSE ''
             END AS sufixo
        FROM alvo a
    ), lotes AS (
      SELECT c.*, (row_number() OVER (PARTITION BY c.dia, c.ult_dia, c.sufixo ORDER BY c.user_id) - 1) / 150 AS lote
        FROM com_marco c
    )
    SELECT l.dia, l.ult_dia AS seq, l.sufixo, array_agg(l.user_id) AS ids
      FROM lotes l
     GROUP BY 1, 2, 3, l.lote
  LOOP
    IF v_turno = 'manha' THEN
      v_texto := format('Ontem fizeste o dia %s do check-in. O de hoje vale %s tokens!',
                        g.seq, v_premios[g.dia]);
    ELSE
      v_texto := format('Não percas a tua sequência de %s %s! Faz o check-in de hoje e ganha %s tokens.',
                        g.seq, CASE WHEN g.seq = 1 THEN 'dia' ELSE 'dias' END, v_premios[g.dia]);
    END IF;
    v_texto := v_texto || COALESCE(g.sufixo, '');

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
