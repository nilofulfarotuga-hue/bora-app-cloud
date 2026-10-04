-- ============================================================================
-- APLICADA EM PRODUÇÃO a 04/10/2026 (versão 20261004205144).
-- Painel admin (não-dinheiro) — ronda de correção 04/10/2026, agente admin-geral.
--
-- 1. Acesso do admin às tabelas dos ecrãs novos (políticas "admin vê e gere"):
--    blocked_users (bloqueios que a Apple exige), product_option_groups/items
--    (opções/variantes), restaurant_tables (mesas). Antes o admin não via nada.
-- 2. admin_blocked_users_list — quem bloqueou quem, com nomes.
-- 3. admin_tvde_chats_list / admin_tvde_chat_mensagens — ler as conversas das
--    corridas TVDE por corrida (tabela tvde_messages; não havia ecrã).
-- 4. Auditoria das edições do admin a parceiros (comissão, markup, horários,
--    online, ativo, pedido mínimo/taxa) — gatilho novo trg_restaurants_auditoria_admin
--    que escreve em admin_audit_log quem mudou o quê (antes/depois). Só regista
--    quando quem mexe é admin; não muda nenhum valor.
-- 5. Clientes parados (como Uber/Glovo): UM push a quem não pede há N dias,
--    no máximo 1 a cada 30 dias por pessoa, pela infra existente
--    (Edge push-clientes-alvo). Interruptor reativacao_ligada nasce DESLIGADO.
--    Tabela reativacao_envios + cron diário + RPCs do painel.
-- 6. Contadores "de hoje" do painel cortados à hora de Lisboa (não UTC):
--    admin_dashboard_metrics.orders_today, admin_get_reservations_stats,
--    admin_list_waitlist_today. Só muda o corte do dia.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Políticas do admin
-- ---------------------------------------------------------------------------
DO $pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename = 'blocked_users' AND policyname = 'blocked_users_admin_tudo') THEN
    CREATE POLICY blocked_users_admin_tudo ON public.blocked_users
      FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename = 'product_option_groups' AND policyname = 'option_groups_admin_tudo') THEN
    CREATE POLICY option_groups_admin_tudo ON public.product_option_groups
      FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename = 'product_option_items' AND policyname = 'option_items_admin_tudo') THEN
    CREATE POLICY option_items_admin_tudo ON public.product_option_items
      FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                  AND tablename = 'restaurant_tables' AND policyname = 'tables_admin_tudo') THEN
    CREATE POLICY tables_admin_tudo ON public.restaurant_tables
      FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
  END IF;
END
$pol$;

-- ---------------------------------------------------------------------------
-- 2) Bloqueios entre utilizadores
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_blocked_users_list(p_limit integer DEFAULT 300)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb) INTO r
    FROM (
      SELECT b.id, b.blocker_id, b.blocked_ref, b.blocked_label, b.motivo, b.created_at,
             COALESCE(NULLIF(u.name, ''), au.email) AS bloqueador_nome,
             u.role AS bloqueador_papel,
             au.email AS bloqueador_email,
             COALESCE(NULLIF(u2.name, ''),
                      (SELECT d.name FROM public.drivers d WHERE d.user_id::text = b.blocked_ref LIMIT 1),
                      b.blocked_label) AS bloqueado_nome,
             COALESCE(u2.role,
                      CASE WHEN EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id::text = b.blocked_ref)
                           THEN 'driver' END) AS bloqueado_papel
        FROM public.blocked_users b
        LEFT JOIN public.users u   ON u.id = b.blocker_id
        LEFT JOIN auth.users au    ON au.id = b.blocker_id
        LEFT JOIN public.users u2  ON u2.id::text = b.blocked_ref
       ORDER BY b.created_at DESC
       LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 300), 1000))
    ) x;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_blocked_users_list(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_blocked_users_list(integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Conversas das corridas TVDE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_tvde_chats_list(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(x ORDER BY x.ultima_em DESC), '[]'::jsonb) INTO r
    FROM (
      SELECT m.tvde_ride_id AS ride_id, tr.status, tr.created_at AS corrida_em,
             m.n AS mensagens, m.ultima_em, m.ultima,
             COALESCE(NULLIF(cu.name, ''), cu.email) AS cliente,
             COALESCE(NULLIF(du.name, ''),
                      (SELECT d.name FROM public.drivers d WHERE d.user_id = tr.driver_id LIMIT 1),
                      du.email) AS motorista
        FROM (
          SELECT tm.tvde_ride_id, count(*) AS n, max(tm.created_at) AS ultima_em,
                 (array_agg(tm.message ORDER BY tm.created_at DESC))[1] AS ultima
            FROM public.tvde_messages tm
           GROUP BY tm.tvde_ride_id
        ) m
        JOIN public.tvde_rides tr ON tr.id = m.tvde_ride_id
        LEFT JOIN public.users cu ON cu.id = tr.client_id
        LEFT JOIN public.users du ON du.id = tr.driver_id
       ORDER BY m.ultima_em DESC
       LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
    ) x;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_tvde_chats_list(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_chats_list(integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_tvde_chat_mensagens(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', tm.id, 'sender_role', tm.sender_role, 'message', tm.message,
           'read', tm.read, 'created_at', tm.created_at) ORDER BY tm.created_at), '[]'::jsonb)
    INTO r
    FROM public.tvde_messages tm
   WHERE tm.tvde_ride_id = p_ride_id;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_tvde_chat_mensagens(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_chat_mensagens(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Auditoria das edições do admin a parceiros
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_restaurants_auditoria_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mud jsonb := '{}'::jsonb;
BEGIN
  -- Só edições feitas por um admin com sessão (crons/serviço/dono não contam).
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.partner_commission_billing IS DISTINCT FROM OLD.partner_commission_billing THEN
    v_mud := v_mud || jsonb_build_object('partner_commission_billing',
      jsonb_build_object('antes', OLD.partner_commission_billing, 'depois', NEW.partner_commission_billing));
  END IF;
  IF NEW.app_markup_pct IS DISTINCT FROM OLD.app_markup_pct THEN
    v_mud := v_mud || jsonb_build_object('app_markup_pct',
      jsonb_build_object('antes', OLD.app_markup_pct, 'depois', NEW.app_markup_pct));
  END IF;
  IF NEW.is_partner IS DISTINCT FROM OLD.is_partner THEN
    v_mud := v_mud || jsonb_build_object('is_partner',
      jsonb_build_object('antes', OLD.is_partner, 'depois', NEW.is_partner));
  END IF;
  IF NEW.business_hours IS DISTINCT FROM OLD.business_hours THEN
    v_mud := v_mud || jsonb_build_object('business_hours',
      jsonb_build_object('antes', OLD.business_hours, 'depois', NEW.business_hours));
  END IF;
  IF NEW.is_online IS DISTINCT FROM OLD.is_online THEN
    v_mud := v_mud || jsonb_build_object('is_online',
      jsonb_build_object('antes', OLD.is_online, 'depois', NEW.is_online));
  END IF;
  IF NEW.is_active_admin IS DISTINCT FROM OLD.is_active_admin THEN
    v_mud := v_mud || jsonb_build_object('is_active_admin',
      jsonb_build_object('antes', OLD.is_active_admin, 'depois', NEW.is_active_admin));
  END IF;
  IF NEW.min_order_cents_override IS DISTINCT FROM OLD.min_order_cents_override THEN
    v_mud := v_mud || jsonb_build_object('min_order_cents_override',
      jsonb_build_object('antes', OLD.min_order_cents_override, 'depois', NEW.min_order_cents_override));
  END IF;
  IF NEW.small_order_fee_cents_override IS DISTINCT FROM OLD.small_order_fee_cents_override THEN
    v_mud := v_mud || jsonb_build_object('small_order_fee_cents_override',
      jsonb_build_object('antes', OLD.small_order_fee_cents_override, 'depois', NEW.small_order_fee_cents_override));
  END IF;

  IF v_mud = '{}'::jsonb THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(),
          COALESCE(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email'),
          'parceiro_editado', 'restaurant', NEW.id::text,
          jsonb_build_object('restaurant_id', NEW.id, 'nome', NEW.name, 'mudancas', v_mud));
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- A auditoria nunca pode impedir a edição; deixa rasto no log do Postgres.
  RAISE WARNING '[auditoria parceiro] falhou para %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_restaurants_auditoria_admin() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER trg_restaurants_auditoria_admin
  AFTER UPDATE ON public.restaurants
  FOR EACH ROW EXECUTE FUNCTION public.fn_restaurants_auditoria_admin();

-- ---------------------------------------------------------------------------
-- 5) Clientes parados — reativação (como Uber/Glovo)
-- ---------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('reativacao_ligada', 'false'::jsonb, 'marketing',
   'Clientes parados: true = todos os dias manda UM push a quem não pede há reativacao_dias dias (máx. 1 a cada reativacao_intervalo_dias por pessoa).'),
  ('reativacao_dias', '14'::jsonb, 'marketing',
   'Clientes parados: dias sem pedir para receber o push de reativação.'),
  ('reativacao_intervalo_dias', '30'::jsonb, 'marketing',
   'Clientes parados: a mesma pessoa só recebe outro push de reativação passados estes dias.'),
  ('reativacao_titulo', to_jsonb('Há quanto tempo!'::text), 'marketing',
   'Clientes parados: título do push (PT-PT).'),
  ('reativacao_texto', to_jsonb('Já não pedes há uns dias. Vê o que há de novo na Bora — entregamos na Guarda.'::text), 'marketing',
   'Clientes parados: texto do push (PT-PT).'),
  ('reativacao_so_opt_in', 'true'::jsonb, 'marketing',
   'Clientes parados: true = só quem aceitou receber promoções (regra D3 de 23/09: comunicação comercial só com opt-in).')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.reativacao_envios (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL,
  enviado_em       timestamptz NOT NULL DEFAULT now(),
  dias_parado      integer,
  ultimo_pedido_em timestamptz,
  titulo           text,
  texto            text,
  pedido_http      bigint,
  voltou_em        timestamptz,
  voltou_order_id  text
);
CREATE INDEX IF NOT EXISTS reativacao_envios_user_idx ON public.reativacao_envios (user_id, enviado_em DESC);
ALTER TABLE public.reativacao_envios ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reativacao_envios FROM anon, authenticated;
COMMENT ON TABLE public.reativacao_envios IS
  'Push de reativação a clientes parados (1 linha por pessoa por envio). voltou_em = primeiro pedido depois do push (até 14 dias). Só o painel admin lê, por RPC.';

-- Quem está parado agora (lista de users.id), segundo as definições.
CREATE OR REPLACE FUNCTION public._reativacao_candidatos()
RETURNS TABLE(user_id uuid, ultimo_pedido_em timestamptz)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_dias int := COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'reativacao_dias'), 14);
  v_intervalo int := COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'reativacao_intervalo_dias'), 30);
  v_opt_in boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'reativacao_so_opt_in'), true);
BEGIN
  RETURN QUERY
  WITH ult AS (
    SELECT o.user_id AS uid, max(o.created_at) AS u
      FROM public.orders o
     WHERE o.user_id IS NOT NULL
       AND COALESCE(o.is_test_order, false) = false
       AND o.status NOT IN ('cancelled', 'rejected')
     GROUP BY o.user_id
  )
  SELECT ult.uid, ult.u
    FROM ult
    JOIN public.users us ON us.id = ult.uid AND us.role = 'client'
   WHERE ult.u < now() - make_interval(days => v_dias)
     AND (NOT v_opt_in OR us.marketing_opt_in)
     AND EXISTS (SELECT 1 FROM public.client_push_tokens t WHERE t.user_id = ult.uid AND t.active)
     AND NOT EXISTS (SELECT 1 FROM public.reativacao_envios e
                      WHERE e.user_id = ult.uid
                        AND e.enviado_em > now() - make_interval(days => v_intervalo))
     -- não incomodar quem tem um pedido a decorrer
     AND NOT EXISTS (SELECT 1 FROM public.orders o2
                      WHERE o2.user_id = ult.uid
                        AND o2.status NOT IN ('delivered', 'cancelled', 'rejected'));
END;
$function$;

REVOKE ALL ON FUNCTION public._reativacao_candidatos() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._reativacao_candidatos() TO service_role;

-- O trabalho do dia: marca quem voltou, e (se ligado) manda o push.
CREATE OR REPLACE FUNCTION public.reativacao_processar()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ligada boolean := COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'reativacao_ligada'), false);
  v_dias int := COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'reativacao_dias'), 14);
  v_titulo text := COALESCE((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'reativacao_titulo'), 'Há quanto tempo!');
  v_texto text := COALESCE((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'reativacao_texto'), 'Vê o que há de novo na Bora.');
  v_ids uuid[];
  v_req bigint;
  v_voltaram int := 0;
BEGIN
  -- 1) Quem voltou a pedir até 14 dias depois do push.
  UPDATE public.reativacao_envios e
     SET voltou_em = p.created_at, voltou_order_id = p.order_id
    FROM (
      SELECT DISTINCT ON (e2.id) e2.id AS envio_id, o.id AS order_id, o.created_at
        FROM public.reativacao_envios e2
        JOIN public.orders o
          ON o.user_id = e2.user_id
         AND o.created_at > e2.enviado_em
         AND o.created_at <= e2.enviado_em + interval '14 days'
         AND COALESCE(o.is_test_order, false) = false
         AND o.status NOT IN ('cancelled', 'rejected')
       WHERE e2.voltou_em IS NULL
         AND e2.enviado_em > now() - interval '30 days'
       ORDER BY e2.id, o.created_at
    ) p
   WHERE e.id = p.envio_id;
  GET DIAGNOSTICS v_voltaram = ROW_COUNT;

  IF NOT v_ligada THEN
    RETURN jsonb_build_object('ligada', false, 'voltaram_marcados', v_voltaram);
  END IF;

  -- 2) Candidatos (máx. 500 por dia).
  SELECT array_agg(c.user_id) INTO v_ids
    FROM (SELECT * FROM public._reativacao_candidatos() LIMIT 500) c;

  IF v_ids IS NULL OR array_length(v_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('ligada', true, 'enviados', 0, 'voltaram_marcados', v_voltaram);
  END IF;

  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
           || '/functions/v1/push-clientes-alvo',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := jsonb_build_object('user_ids', to_jsonb(v_ids), 'title', v_titulo, 'body', v_texto,
                               'type', 'reativacao'),
    timeout_milliseconds := 60000
  ) INTO v_req;

  INSERT INTO public.reativacao_envios (user_id, dias_parado, ultimo_pedido_em, titulo, texto, pedido_http)
  SELECT c.user_id, (now()::date - c.ultimo_pedido_em::date), c.ultimo_pedido_em, v_titulo, v_texto, v_req
    FROM public._reativacao_candidatos() c
   WHERE c.user_id = ANY(v_ids);

  -- sininho (a mensagem fica também na caixa da app)
  INSERT INTO public.in_app_notifications (user_id, kind, title, body)
  SELECT u, 'promo', v_titulo, v_texto FROM unnest(v_ids) AS u;

  RETURN jsonb_build_object('ligada', true, 'enviados', array_length(v_ids, 1),
                            'dias', v_dias, 'pedido_http', v_req, 'voltaram_marcados', v_voltaram);
END;
$function$;

REVOKE ALL ON FUNCTION public.reativacao_processar() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reativacao_processar() TO service_role;

-- Painel: estado + números.
CREATE OR REPLACE FUNCTION public.admin_reativacao_resumo()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT jsonb_build_object(
    'ligada', COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'reativacao_ligada'), false),
    'dias', COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'reativacao_dias'), 14),
    'intervalo_dias', COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings WHERE key = 'reativacao_intervalo_dias'), 30),
    'so_opt_in', COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'reativacao_so_opt_in'), true),
    'titulo', (SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'reativacao_titulo'),
    'texto', (SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'reativacao_texto'),
    'candidatos_agora', (SELECT count(*) FROM public._reativacao_candidatos()),
    'enviados_total', (SELECT count(*) FROM public.reativacao_envios),
    'enviados_30d', (SELECT count(*) FROM public.reativacao_envios WHERE enviado_em > now() - interval '30 days'),
    'voltaram_total', (SELECT count(*) FROM public.reativacao_envios WHERE voltou_em IS NOT NULL),
    'voltaram_30d', (SELECT count(*) FROM public.reativacao_envios
                      WHERE voltou_em IS NOT NULL AND enviado_em > now() - interval '30 days'),
    'ultimos', COALESCE((
      SELECT jsonb_agg(x ORDER BY x.enviado_em DESC) FROM (
        SELECT e.enviado_em, e.dias_parado, e.voltou_em, e.voltou_order_id,
               COALESCE(NULLIF(u.name, ''), u.email) AS cliente
          FROM public.reativacao_envios e
          LEFT JOIN public.users u ON u.id = e.user_id
         ORDER BY e.enviado_em DESC LIMIT 100) x), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_reativacao_resumo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reativacao_resumo() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_reativacao_configurar(
  p_ligada boolean, p_dias integer, p_titulo text, p_texto text, p_so_opt_in boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_antes jsonb;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_dias IS NULL OR p_dias < 3 OR p_dias > 365 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Dias tem de estar entre 3 e 365.');
  END IF;
  IF length(trim(COALESCE(p_titulo, ''))) < 2 OR length(p_titulo) > 100 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Título entre 2 e 100 letras.');
  END IF;
  IF length(trim(COALESCE(p_texto, ''))) < 5 OR length(p_texto) > 300 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Texto entre 5 e 300 letras.');
  END IF;

  SELECT jsonb_object_agg(key, value) INTO v_antes
    FROM public.platform_settings WHERE key LIKE 'reativacao_%';

  UPDATE public.platform_settings SET value = to_jsonb(COALESCE(p_ligada, false)), updated_at = now(), updated_by = v_admin.admin_id
   WHERE key = 'reativacao_ligada';
  UPDATE public.platform_settings SET value = to_jsonb(p_dias), updated_at = now(), updated_by = v_admin.admin_id
   WHERE key = 'reativacao_dias';
  UPDATE public.platform_settings SET value = to_jsonb(trim(p_titulo)), updated_at = now(), updated_by = v_admin.admin_id
   WHERE key = 'reativacao_titulo';
  UPDATE public.platform_settings SET value = to_jsonb(trim(p_texto)), updated_at = now(), updated_by = v_admin.admin_id
   WHERE key = 'reativacao_texto';
  IF p_so_opt_in IS NOT NULL THEN
    UPDATE public.platform_settings SET value = to_jsonb(p_so_opt_in), updated_at = now(), updated_by = v_admin.admin_id
     WHERE key = 'reativacao_so_opt_in';
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'reativacao_configurar', 'platform_settings', 'reativacao',
          jsonb_build_object('antes', v_antes,
                             'depois', jsonb_build_object('ligada', p_ligada, 'dias', p_dias, 'titulo', p_titulo,
                                                          'texto', p_texto, 'so_opt_in', p_so_opt_in)));
  RETURN jsonb_build_object('ok', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_reativacao_configurar(boolean, integer, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reativacao_configurar(boolean, integer, text, text, boolean) TO authenticated, service_role;

-- Cron diário 17:07 UTC (18:07 em Lisboa no verão, 17:07 no inverno) — antes do jantar.
DO $cron$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'reativacao-clientes-parados') THEN
    PERFORM cron.schedule('reativacao-clientes-parados', '7 17 * * *',
                          'SELECT public.reativacao_processar();');
  END IF;
END
$cron$;

-- ---------------------------------------------------------------------------
-- 6) Contadores "de hoje" à hora de Lisboa
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_dashboard_metrics()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_result JSON;
  v_ws timestamptz;
  v_we timestamptz;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT b.week_start, b.week_end INTO v_ws, v_we
    FROM public.driver_settlement_week_bounds(now()) b;

  SELECT json_build_object(
    'platform_revenue', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries WHERE user_type = 'platform'
    ),
    'platform_revenue_week', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries
      WHERE user_type = 'platform'
        AND created_at >= v_ws AND created_at <= v_we
    ),
    -- 04/10: "hoje" começa à meia-noite de Lisboa (antes: meia-noite UTC).
    'orders_today', (
      SELECT COUNT(*) FROM public.orders
      WHERE created_at >= (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon')
    ),
    'drivers_payable', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries WHERE user_type = 'driver'
    ),
    'restaurants_payable', (
      SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
      FROM public.ledger_entries WHERE user_type = 'restaurant'
    ),
    'week_start', v_ws,
    'week_end', v_we,
    'generated_at', now()
  ) INTO v_result;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_reservations_stats(p_restaurant_id text DEFAULT NULL::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- 04/10: dias de Lisboa (antes: dia do servidor, em UTC).
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_start date := COALESCE(p_start_date, v_hoje - 30);
  v_end date := COALESCE(p_end_date, v_hoje);
  v_result jsonb;
BEGIN
  PERFORM _reservas_pro_assert_admin();

  WITH stats AS (
    SELECT
      count(*) FILTER (WHERE status='pending') as pending,
      count(*) FILTER (WHERE status='approved') as approved,
      count(*) FILTER (WHERE status IN ('cancelled_refunded','cancelled_no_refund','rejected_refunded','cancelled')) as cancelled,
      count(*) FILTER (WHERE status='no_show') as no_show,
      count(*) FILTER (WHERE seated_at IS NOT NULL) as seated,
      count(*) FILTER (WHERE finished_at IS NOT NULL) as finished,
      count(*) FILTER (WHERE is_walk_in=true) as walk_ins,
      coalesce(sum(people), 0) as total_covers,
      coalesce(avg(people), 0) as avg_party_size,
      count(*) as total
    FROM reservations
    WHERE (p_restaurant_id IS NULL OR restaurant_id = p_restaurant_id)
      AND (reserved_for AT TIME ZONE 'Europe/Lisbon')::date BETWEEN v_start AND v_end
  )
  SELECT to_jsonb(stats.*) INTO v_result FROM stats;

  RETURN jsonb_build_object(
    'success', true,
    'period', jsonb_build_object('start', v_start, 'end', v_end),
    'restaurant_id', p_restaurant_id,
    'stats', v_result
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_list_waitlist_today()
 RETURNS TABLE(restaurant_id text, restaurant_name text, em_espera bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT w.restaurant_id, r.name, count(*)
  FROM reservation_waitlist w
  JOIN restaurants r ON r.id = w.restaurant_id
  WHERE is_admin()
    AND w.status = 'active'
    AND w.target_date = (now() AT TIME ZONE 'Europe/Lisbon')::date
  GROUP BY w.restaurant_id, r.name
  ORDER BY count(*) DESC;
$function$;
