-- Bora Todo Dia, novidade n.º 1: CHECK-IN DIÁRIO com sequência (13/10/2026).
-- Regras fixadas pelo Danilo a 13/10: ciclo de 7 dias, prémios 5,5,10,10,15,15,40
-- tokens; falhou um dia de calendário (Europe/Lisbon) volta ao Dia 1; depois do Dia 7
-- começa um ciclo novo; 1 check-in por dia; só clientes com telemóvel; sem sorteios.
--
-- Esta migração é a parte SEM dinheiro: tabela, definições, estado, lembretes e as
-- leituras do painel. A função que credita os tokens (client_daily_checkin) vai numa
-- proposta à parte, à espera do "vai" do Danilo. Enquanto ela não existir, o check-in
-- fica desligado sozinho (ver _checkin_estado: 'ativo' exige a função criada).

-- ---------------------------------------------------------------------------
-- 1. Tabelas
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.daily_checkins (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkin_date   date NOT NULL,                 -- dia de calendário em Europe/Lisbon
  streak_day     smallint NOT NULL CHECK (streak_day BETWEEN 1 AND 7),
  tokens_awarded integer NOT NULL DEFAULT 0 CHECK (tokens_awarded >= 0),
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT daily_checkins_um_por_dia UNIQUE (user_id, checkin_date)
);
CREATE INDEX IF NOT EXISTS daily_checkins_data_idx ON public.daily_checkins (checkin_date);

ALTER TABLE public.daily_checkins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS daily_checkins_ler_os_meus ON public.daily_checkins;
CREATE POLICY daily_checkins_ler_os_meus ON public.daily_checkins
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS daily_checkins_admin_le ON public.daily_checkins;
CREATE POLICY daily_checkins_admin_le ON public.daily_checkins
  FOR SELECT TO authenticated USING (public.is_admin());
-- Escrita só pelas funções SECURITY DEFINER: nenhuma política de INSERT/UPDATE/DELETE.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.daily_checkins FROM anon, authenticated;

-- Um lembrete por pessoa, por dia, por turno ('manha' | 'noite') = no máximo 2 por dia.
CREATE TABLE IF NOT EXISTS public.checkin_lembretes_envios (
  id            bigserial PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dia           date NOT NULL,
  turno         text NOT NULL CHECK (turno IN ('manha', 'noite')),
  dia_sequencia smallint,
  tokens        integer,
  pedido_http   bigint,
  enviado_em    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT checkin_lembretes_um_por_turno UNIQUE (user_id, dia, turno)
);
ALTER TABLE public.checkin_lembretes_envios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS checkin_lembretes_admin_le ON public.checkin_lembretes_envios;
CREATE POLICY checkin_lembretes_admin_le ON public.checkin_lembretes_envios
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.checkin_lembretes_envios FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Definições (o painel admin muda-as; nada cravado na app)
-- Os VALORES em tokens (checkin_rewards e a validade) entram com a proposta do
-- crédito, à espera do "vai": a bora-tranca trata-os como definições de dinheiro.
-- Até lá _checkin_premios devolve os do Danilo (5,5,10,10,15,15,40).
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('checkin_enabled', 'true'::jsonb,
   'Check-in diário ligado. Só fica ativo de facto quando a função que dá os tokens existir.', 'marketing'),
  ('checkin_require_phone', 'true'::jsonb,
   'Só clientes com telemóvel confirmado ganham tokens no check-in diário.', 'marketing'),
  ('checkin_push_morning_enabled', 'true'::jsonb,
   'Lembrete da manhã do check-in diário ligado (a quem ainda não fez o de hoje).', 'marketing'),
  ('checkin_push_morning_hour', '11'::jsonb,
   'Hora de Lisboa (0-23) do lembrete da manhã do check-in diário.', 'marketing'),
  ('checkin_push_evening_enabled', 'true'::jsonb,
   'Lembrete da noite do check-in diário ligado (só a quem tem sequência a correr).', 'marketing'),
  ('checkin_push_evening_hour', '20'::jsonb,
   'Hora de Lisboa (0-23) do lembrete da noite do check-in diário.', 'marketing'),
  ('checkin_push_so_opt_in', 'true'::jsonb,
   'Lembretes do check-in só a quem aceitou promoções (users.marketing_opt_in) — regra RGPD de 23/09, igual à reativação. Desligar é decisão do Danilo.', 'marketing')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. Ajudantes
-- ---------------------------------------------------------------------------
-- Dia do ciclo que cabe a HOJE, dado o último check-in. Pura (provada no PGlite).
CREATE OR REPLACE FUNCTION public._checkin_dia_de_hoje(p_ultima_data date, p_ultimo_dia integer, p_hoje date)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_ultima_data IS NOT NULL
     AND p_ultima_data = p_hoje - 1
     AND COALESCE(p_ultimo_dia, 0) BETWEEN 1 AND 6 THEN p_ultimo_dia + 1
    ELSE 1
  END
$function$;

-- Os 7 prémios. Valor inválido no painel → os do Danilo (13/10).
CREATE OR REPLACE FUNCTION public._checkin_premios()
RETURNS integer[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
  r integer[] := ARRAY[]::integer[];
  i integer;
BEGIN
  SELECT value INTO v FROM public.platform_settings WHERE key = 'checkin_rewards';
  IF v IS NULL OR jsonb_typeof(v) <> 'array' OR jsonb_array_length(v) <> 7 THEN
    RETURN ARRAY[5,5,10,10,15,15,40];
  END IF;
  FOR i IN 0..6 LOOP
    IF jsonb_typeof(v -> i) <> 'number' THEN
      RETURN ARRAY[5,5,10,10,15,15,40];
    END IF;
    r := r || GREATEST(0, LEAST(1000, floor((v ->> i)::numeric)::integer));
  END LOOP;
  RETURN r;
END;
$function$;

-- Telemóvel confirmado. Fonte única: se a confirmação mudar de sítio, muda só aqui.
-- A 13/10 a app NÃO tem confirmação por SMS (0 contas com phone_confirmed_at); o que
-- existe é o ecrã "Completar perfil", que grava em users.phone um telemóvel português
-- válido. É o mesmo teste do normalizarTelemovelPt (lib/utils/contact_validators.dart):
-- tira espaços/hífenes/parênteses/pontos, o '+', o 00351 ou o 351, e exige 9 dígitos
-- a começar por 9.
CREATE OR REPLACE FUNCTION public._checkin_telemovel_confirmado(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE((
    SELECT CASE
             WHEN s LIKE '00351%' THEN substr(s, 6)
             WHEN length(s) > 9 AND s LIKE '351%' THEN substr(s, 4)
             ELSE s
           END ~ '^9[0-9]{8}$'
      FROM (SELECT regexp_replace(regexp_replace(COALESCE(u.phone, ''), '[[:space:]().-]', '', 'g'), '^\+', '') AS s
              FROM public.users u
             WHERE u.id = p_uid) x
  ), false)
$function$;

-- É cliente? A verdade dos papéis vive em user_roles; users.role cobre os clientes
-- antigos que nunca ganharam a linha (149 em users.role, 29 em user_roles a 13/10).
CREATE OR REPLACE FUNCTION public._checkin_e_cliente(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_uid AND r.role = 'client')
      OR EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_uid AND u.role = 'client')
$function$;

-- Estado completo de uma pessoa (usado pela app, pelo crédito e pelos lembretes).
CREATE OR REPLACE FUNCTION public._checkin_estado(p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje      date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_ligado    boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_enabled'), false);
  v_pronto    boolean := to_regprocedure('public.client_daily_checkin()') IS NOT NULL;
  v_exige_tel boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_require_phone'), true);
  v_premios   integer[] := public._checkin_premios();
  v_ult_data  date;
  v_ult_dia   integer;
  v_ult_tok   integer;
  v_feito     boolean := false;
  v_dia       integer;
  v_prox      integer;
  v_motivo    text := NULL;
BEGIN
  IF p_uid IS NULL THEN
    v_motivo := 'sem_sessao';
  ELSIF NOT (v_ligado AND v_pronto) THEN
    v_motivo := 'desligado';
  ELSIF NOT public._checkin_e_cliente(p_uid) THEN
    v_motivo := 'nao_cliente';
  ELSIF v_exige_tel AND NOT public._checkin_telemovel_confirmado(p_uid) THEN
    v_motivo := 'sem_telemovel';
  END IF;

  IF p_uid IS NOT NULL THEN
    SELECT d.checkin_date, d.streak_day, d.tokens_awarded
      INTO v_ult_data, v_ult_dia, v_ult_tok
      FROM public.daily_checkins d
     WHERE d.user_id = p_uid
     ORDER BY d.checkin_date DESC
     LIMIT 1;
  END IF;

  IF v_ult_data = v_hoje THEN
    v_feito := true;
    v_dia   := v_ult_dia;
    v_prox  := CASE WHEN v_ult_dia >= 7 THEN 1 ELSE v_ult_dia + 1 END;
  ELSE
    v_dia  := public._checkin_dia_de_hoje(v_ult_data, v_ult_dia, v_hoje);
    v_prox := v_dia;
  END IF;

  RETURN jsonb_build_object(
    'enabled',        v_ligado AND v_pronto,
    'eligible',       v_motivo IS NULL,
    'reason',         v_motivo,
    'today',          v_hoje,
    'already_done',   v_feito,
    'streak_day',     v_dia,
    'tokens_today',   CASE WHEN v_feito THEN COALESCE(v_ult_tok, 0) ELSE v_premios[v_dia] END,
    'next_day',       v_prox,
    'next_reward',    v_premios[v_prox],
    'rewards',        to_jsonb(v_premios),
    'streak_running', v_ult_data IS NOT NULL AND v_ult_data >= v_hoje - 1,
    'require_phone',  v_exige_tel
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. RPC só de leitura para a app do cliente
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.client_checkin_status()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public._checkin_estado(auth.uid())
$function$;

-- ---------------------------------------------------------------------------
-- 5. Lembretes (pg_cron de hora a hora; a hora certa vem das definições, em Lisboa)
-- ---------------------------------------------------------------------------
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
  v_so_opt_in boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'checkin_push_so_opt_in'), true);
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
         -- quem não aceitou promoções no perfil não recebe (RGPD, 23/09)
         AND (NOT v_so_opt_in OR COALESCE(u.marketing_opt_in, false))
         AND NOT EXISTS (SELECT 1 FROM public.checkin_lembretes_envios e
                          WHERE e.user_id = u.id AND e.dia = v_hoje AND e.turno = v_turno)
    ), alvo AS (
      SELECT b.user_id, b.ult_dia, public._checkin_dia_de_hoje(b.ult_data, b.ult_dia, v_hoje) AS dia
        FROM base b
       WHERE b.ult_data IS DISTINCT FROM v_hoje                                 -- ainda não fez hoje
         AND (v_turno = 'manha' OR (b.ult_data = v_hoje - 1 AND b.ult_dia >= 1)) -- noite: sequência a correr
    )
    , lotes AS (
      -- lotes de 150: o push-clientes-alvo lê os aparelhos por GET com a lista no endereço
      SELECT a.*, (row_number() OVER (PARTITION BY a.dia, a.ult_dia ORDER BY a.user_id) - 1) / 150 AS lote
        FROM alvo a
    )
    SELECT l.dia, CASE WHEN v_turno = 'noite' THEN l.ult_dia END AS seq, array_agg(l.user_id) AS ids
      FROM lotes l
     GROUP BY 1, 2, l.lote
  LOOP
    IF v_turno = 'manha' THEN
      v_texto := format('O teu check-in de hoje vale %s tokens.', v_premios[g.dia]);
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

-- ---------------------------------------------------------------------------
-- 6. Leituras do painel admin (PT-BR)
-- ---------------------------------------------------------------------------
-- Totais por dia / semana / mês. O custo em euros calcula-o o ecrã com o valor do token
-- que já lê das definições (a mesma fonte da app; nada cravado).
CREATE OR REPLACE FUNCTION public.admin_checkin_resumo(p_dias integer DEFAULT 60)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje  date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_dias  integer := LEAST(GREATEST(COALESCE(p_dias, 60), 7), 400);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'hoje', v_hoje,
    'estado', public._checkin_estado(NULL) - 'reason' - 'eligible' - 'already_done' - 'streak_day'
              - 'tokens_today' - 'next_day' - 'next_reward' - 'streak_running',
    'funcao_de_credito_existe', to_regprocedure('public.client_daily_checkin()') IS NOT NULL,
    'por_dia', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('dia', d, 'checkins', n, 'tokens', t) ORDER BY d DESC)
        FROM (SELECT checkin_date AS d, count(*) AS n, COALESCE(sum(tokens_awarded), 0) AS t
                FROM public.daily_checkins
               WHERE checkin_date > v_hoje - v_dias
               GROUP BY 1) s), '[]'::jsonb),
    'por_semana', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('semana', w, 'checkins', n, 'tokens', t) ORDER BY w DESC)
        FROM (SELECT date_trunc('week', checkin_date)::date AS w, count(*) AS n, COALESCE(sum(tokens_awarded), 0) AS t
                FROM public.daily_checkins
               WHERE checkin_date > v_hoje - 7 * 13
               GROUP BY 1) s), '[]'::jsonb),
    'por_mes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('mes', m, 'checkins', n, 'tokens', t) ORDER BY m DESC)
        FROM (SELECT date_trunc('month', checkin_date)::date AS m, count(*) AS n, COALESCE(sum(tokens_awarded), 0) AS t
                FROM public.daily_checkins
               WHERE checkin_date > v_hoje - 400
               GROUP BY 1) s), '[]'::jsonb),
    'pessoas_por_dia_da_sequencia', COALESCE((
      SELECT jsonb_object_agg(dia::text, n)
        FROM (SELECT l.streak_day AS dia, count(*) AS n
                FROM (SELECT DISTINCT ON (user_id) user_id, checkin_date, streak_day
                        FROM public.daily_checkins
                       ORDER BY user_id, checkin_date DESC) l
               WHERE l.checkin_date >= v_hoje - 1
               GROUP BY 1) s), '{}'::jsonb),
    'lembretes_hoje', COALESCE((
      SELECT jsonb_object_agg(turno, n)
        FROM (SELECT turno, count(*) AS n FROM public.checkin_lembretes_envios WHERE dia = v_hoje GROUP BY 1) s), '{}'::jsonb),
    -- com checkin_push_so_opt_in ligado, só estes podem receber lembretes
    'clientes_com_promocoes_aceites', (
      SELECT count(*) FROM public.users u
       WHERE COALESCE(u.marketing_opt_in, false) AND public._checkin_e_cliente(u.id))
  );
END;
$function$;

-- Quem está em que dia. Sem pesquisa: quem já fez check-in. Com pesquisa: qualquer cliente
-- (nome, email ou telemóvel), para o admin poder dar ou tirar tokens.
CREATE OR REPLACE FUNCTION public.admin_checkin_clientes(p_busca text DEFAULT NULL, p_limite integer DEFAULT 500)
RETURNS TABLE (
  user_id uuid, nome text, email text, telefone text, telemovel_confirmado boolean,
  ultimo_checkin date, dia_sequencia integer, em_sequencia boolean, fez_hoje boolean,
  total_checkins integer, total_tokens_checkin integer, saldo_tokens integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje  date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_busca text := NULLIF(trim(COALESCE(p_busca, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH agg AS (
    SELECT d.user_id AS uid, count(*)::integer AS n, COALESCE(sum(d.tokens_awarded), 0)::integer AS t,
           max(d.checkin_date) AS ult
      FROM public.daily_checkins d
     GROUP BY d.user_id
  ), quem AS (
    SELECT u.id AS uid FROM public.users u
     WHERE v_busca IS NOT NULL
       AND public._checkin_e_cliente(u.id)
       AND (u.name ILIKE '%' || v_busca || '%' OR u.email ILIKE '%' || v_busca || '%'
            OR COALESCE(u.phone, '') ILIKE '%' || v_busca || '%')
    UNION
    SELECT agg.uid FROM agg WHERE v_busca IS NULL
  )
  SELECT q.uid, u.name, u.email, u.phone,
         public._checkin_telemovel_confirmado(q.uid),
         a.ult,
         (SELECT d.streak_day::integer FROM public.daily_checkins d
           WHERE d.user_id = q.uid AND d.checkin_date = a.ult),
         COALESCE(a.ult >= v_hoje - 1, false),
         COALESCE(a.ult = v_hoje, false),
         COALESCE(a.n, 0), COALESCE(a.t, 0),
         public.get_user_tokens(q.uid)
    FROM quem q
    JOIN public.users u ON u.id = q.uid
    LEFT JOIN agg a ON a.uid = q.uid
   ORDER BY a.ult DESC NULLS LAST, u.name
   LIMIT LEAST(GREATEST(COALESCE(p_limite, 500), 1), 2000);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Permissões (funções novas nascem fechadas a anon desde 05/10)
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public._checkin_dia_de_hoje(date, integer, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._checkin_premios() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_telemovel_confirmado(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_e_cliente(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_estado(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.checkin_lembretes_processar() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_checkin_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_resumo(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_checkin_clientes(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_checkin_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_resumo(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_checkin_clientes(text, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. Tarefa agendada: de hora a hora, ao minuto 2; a função decide se é a hora certa.
-- ---------------------------------------------------------------------------
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'checkin-lembretes';
SELECT cron.schedule('checkin-lembretes', '2 * * * *', 'SELECT public.checkin_lembretes_processar();');
