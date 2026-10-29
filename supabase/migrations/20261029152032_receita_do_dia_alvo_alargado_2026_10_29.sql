-- Receita do Dia — aviso diário também para quem tem sequência de check-in ou aceitou
-- promoções (missão final-app-2026-10-29, bloco 7 C2, 29/10/2026).
--
-- A Receita do Dia já existia desde 15/10 (receitas_do_dia, receita_avisos,
-- receita_avisos_envios, cron receita-do-dia-avisos, 14 receitas). O aviso só chegava a quem
-- ligasse o interruptor no ecrã da receita: em 14 dias, 0 pessoas ligaram. Esta migração
-- NÃO cria tabelas: alarga a quem o aviso chega, mantendo uma só definição ("quem quer o
-- aviso") para o envio, para o interruptor da app e para o painel.
--
--  * pediu (receita_avisos.ligado = true)                     -> recebe sempre;
--  * desligou (receita_avisos.ligado = false)                 -> nunca recebe;
--  * nunca mexeu + interruptor alargado ligado + (sequência de check-in ativa
--    [último check-in ontem ou hoje, dia >= 1] OU users.marketing_opt_in) -> recebe.
-- Só clientes, com aparelho ativo, nunca contas demo/teste (is_demo_user), um aviso por dia
-- (receita_avisos_envios, regista-se antes de enviar). A hora continua a ser a do painel
-- (receita_do_dia_push_hour, hora de Lisboa, por isso respeita o verão/inverno); o texto
-- vive só aqui (_receita_aviso_corpo) e o painel mostra-o tal e qual.

INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('receita_do_dia_push_alargado', 'true'::jsonb,
   'Receita do Dia: o aviso diário chega também a quem tem sequência de check-in ativa ou aceitou promoções (quem o desligou no ecrã da receita nunca recebe). Desligado = só quem pediu.',
   'marketing')
ON CONFLICT (key) DO NOTHING;

-- Texto do aviso (uma só fonte: o envio e a pré-visualização do painel).
CREATE OR REPLACE FUNCTION public._receita_aviso_corpo(p_titulo text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT 'Hoje: ' || p_titulo || '. Os ingredientes vão para o carrinho num toque.'
$$;

-- Esta pessoa quer o aviso de hoje? (a escolha explícita manda sempre)
CREATE OR REPLACE FUNCTION public._receita_aviso_quer(p_uid uuid, p_dia date)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_largo  boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings
                                 WHERE key = 'receita_do_dia_push_alargado'), false);
  v_pedido boolean;
BEGIN
  SELECT a.ligado INTO v_pedido FROM public.receita_avisos a WHERE a.user_id = p_uid;
  IF FOUND THEN RETURN v_pedido; END IF;
  IF NOT v_largo THEN RETURN false; END IF;
  RETURN COALESCE((SELECT u.marketing_opt_in FROM public.users u WHERE u.id = p_uid), false)
      OR EXISTS (SELECT 1
                   FROM (SELECT d.checkin_date, d.streak_day
                           FROM public.daily_checkins d
                          WHERE d.user_id = p_uid
                          ORDER BY d.checkin_date DESC LIMIT 1) l
                  WHERE l.checkin_date >= p_dia - 1 AND l.streak_day >= 1);
END;
$$;

-- Quem recebe o aviso do dia p_dia (p_so_por_enviar = false conta também quem já recebeu hoje).
CREATE OR REPLACE FUNCTION public._receita_aviso_alvo(p_dia date, p_so_por_enviar boolean DEFAULT true)
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id
    FROM public.users u
   WHERE public._checkin_e_cliente(u.id)
     AND NOT public.is_demo_user(u.id)
     AND EXISTS (SELECT 1 FROM public.client_push_tokens t WHERE t.user_id = u.id AND t.active)
     AND public._receita_aviso_quer(u.id, p_dia)
     AND (NOT p_so_por_enviar
          OR NOT EXISTS (SELECT 1 FROM public.receita_avisos_envios e
                          WHERE e.user_id = u.id AND e.dia = p_dia))
$$;

-- Funções internas: fechadas a anon e authenticated (só o servidor e as funções acima).
REVOKE ALL ON FUNCTION public._receita_aviso_corpo(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._receita_aviso_quer(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._receita_aviso_alvo(date, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._receita_aviso_corpo(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._receita_aviso_quer(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public._receita_aviso_alvo(date, boolean) TO service_role;

-- O envio diário: igual ao de 15/10 (lotes de 150, regista antes de enviar, mesmo push),
-- só muda quem entra (_receita_aviso_alvo) e o texto vem de _receita_aviso_corpo.
CREATE OR REPLACE FUNCTION public.receita_avisos_processar()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hoje    date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_hora    integer := extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon'))::integer;
  v_on      boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_enabled'), false);
  v_push    boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_push_enabled'), false);
  v_h       integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'receita_do_dia_push_hour'), 10);
  r         public.receitas_do_dia;
  v_url     text;
  v_key     text;
  v_req     bigint;
  v_pessoas integer := 0;
  v_lotes   integer := 0;
  g         record;
BEGIN
  IF NOT (v_on AND v_push) THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'desligado');
  END IF;
  IF v_hora <> v_h THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'fora_de_hora', 'hora_lisboa', v_hora);
  END IF;
  r := public._receita_de_hoje(v_hoje);
  IF r.id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'sem_receita');
  END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'segredos_em_falta');
  END IF;

  FOR g IN
    WITH alvo AS (
      SELECT x AS user_id FROM public._receita_aviso_alvo(v_hoje, true) AS x
    ), lotes AS (
      -- lotes de 150: o push-clientes-alvo lê os aparelhos com a lista no endereço
      SELECT user_id, (row_number() OVER (ORDER BY user_id) - 1) / 150 AS lote FROM alvo
    )
    SELECT array_agg(user_id) AS ids FROM lotes GROUP BY lote
  LOOP
    -- regista primeiro: se o envio falhar, ninguém recebe o mesmo aviso duas vezes
    INSERT INTO public.receita_avisos_envios (user_id, dia, receita_id)
    SELECT x, v_hoje, r.id FROM unnest(g.ids) AS x
    ON CONFLICT ON CONSTRAINT receita_avisos_um_por_dia DO NOTHING;

    SELECT net.http_post(
      url := v_url || '/functions/v1/push-clientes-alvo',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('user_ids', to_jsonb(g.ids), 'title', 'Receita do dia',
                                 'body', public._receita_aviso_corpo(r.titulo),
                                 'type', 'receita_do_dia'),
      timeout_milliseconds := 60000
    ) INTO v_req;

    UPDATE public.receita_avisos_envios SET pedido_http = v_req
     WHERE dia = v_hoje AND user_id = ANY (g.ids);

    v_pessoas := v_pessoas + array_length(g.ids, 1);
    v_lotes := v_lotes + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'dia', v_hoje, 'receita', r.titulo,
                            'pessoas', v_pessoas, 'pedidos_http', v_lotes);
END;
$$;

-- O ecrã da receita mostra o interruptor como ele realmente está para esta pessoa
-- (quem tem sequência e nunca mexeu aparece ligado; ao desligar, deixa de receber).
CREATE OR REPLACE FUNCTION public.client_receita_de_hoje()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_hoje   date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_on     boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_enabled'), false);
  v_push   boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_push_enabled'), false);
  v_hora   integer := COALESCE((SELECT (value #>> '{}')::integer FROM public.platform_settings WHERE key = 'receita_do_dia_push_hour'), 10);
  r        public.receitas_do_dia;
BEGIN
  IF v_uid IS NULL OR NOT v_on THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;
  r := public._receita_de_hoje(v_hoje);
  IF r.id IS NULL THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;
  RETURN jsonb_build_object(
    'enabled', true,
    'dia', v_hoje,
    'aviso_disponivel', v_push,
    'aviso_hora', v_hora,
    'aviso_ligado', public._receita_aviso_quer(v_uid, v_hoje),
    'receita', jsonb_build_object(
      'id', r.id, 'titulo', r.titulo, 'resumo', r.resumo,
      'ingredientes', r.ingredientes, 'passos', r.passos,
      'tempo_min', r.tempo_min, 'doses', r.doses, 'foto_url', r.foto_url));
END;
$$;

-- O painel: quantas pessoas o aviso de hoje alcança e o texto exato que vai sair.
CREATE OR REPLACE FUNCTION public.admin_receita_resumo()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  r      public.receitas_do_dia;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  r := public._receita_de_hoje(v_hoje);
  RETURN jsonb_build_object(
    'hoje', v_hoje,
    'receita_hoje', r.titulo,
    'receita_hoje_id', r.id,
    'avisos_ligados', (SELECT count(*) FROM public.receita_avisos WHERE ligado),
    'enviados_hoje', (SELECT count(*) FROM public.receita_avisos_envios WHERE dia = v_hoje),
    'enviados_7_dias', (SELECT count(*) FROM public.receita_avisos_envios WHERE dia > v_hoje - 7),
    'receitas_ativas', (SELECT count(*) FROM public.receitas_do_dia WHERE ativa),
    'alargado', COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'receita_do_dia_push_alargado'), false),
    'destinatarios_hoje', (SELECT count(*) FROM public._receita_aviso_alvo(v_hoje, false)),
    'aviso_titulo', 'Receita do dia',
    'aviso_corpo', CASE WHEN r.id IS NULL THEN NULL ELSE public._receita_aviso_corpo(r.titulo) END);
END;
$$;
