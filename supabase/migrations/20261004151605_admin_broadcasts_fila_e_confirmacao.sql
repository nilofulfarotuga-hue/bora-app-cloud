-- ============================================================================
-- Notificações em massa do painel (push_broadcasts) — a fila volta a andar.
-- Missão 04/10/2026 (agente admin-geral), achado 06-admin §3.1 / resumo 4.
-- APLICADA EM PRODUÇÃO a 04/10/2026 (versão 20261004151605) — cópia fiel.
--
-- O que estava partido (provado em produção a 04/10):
--   1. Não havia tarefa agendada a chamar a Edge Function `execute-broadcast`
--      (o cron "execute-broadcast-queue" morreu no incidente de junho e nunca
--      foi reposto) — as notificações agendadas e o push do modo "Imediato"
--      ficavam em `pending` para sempre (o sininho recebia, o telemóvel não).
--   2. A Edge Function (v7) gravava o estado 'completed', que o CHECK da tabela
--      não aceita (só pending/sending/sent/failed) — por isso as 3 linhas de
--      21/05 ficaram presas em 'sending' com 0 enviados.
--   3. O segmento "Drivers online" usava drivers.id em vez de drivers.user_id
--      (regra da identidade do estafeta) e o "Clientes activos (30d)" mandava o
--      push a TODOS os clientes (só o sininho respeitava o segmento).
--   4. O registo no histórico usava a sobrecarga de log_admin_action que
--      escreve numa tabela que não existe (admin_logs) e engole o erro.
--
-- O que esta migration faz (a Edge Function v8 vai em
-- supabase/functions/execute-broadcast/index.ts):
--   · colunas novas: status_note, target_user_ids, kind, claimed_at;
--   · as 3 linhas presas desde 21/05 passam a 'failed' com nota (cópia antes em
--     bkp_push_broadcasts_20261004 e linha no admin_audit_log);
--   · _admin_broadcast_alvos: UMA definição de quem recebe cada segmento;
--   · admin_broadcast_preview: quantas pessoas/aparelhos vão receber;
--   · admin_broadcast_notification: usa a lista certa e audita de verdade;
--   · admin_cancel_broadcast e admin_list_broadcasts_v2 (histórico com nota);
--   · broadcasts_processar_fila + cron a cada 2 min (minutos ímpares).
-- ============================================================================

ALTER TABLE public.push_broadcasts
  ADD COLUMN IF NOT EXISTS status_note text,
  ADD COLUMN IF NOT EXISTS target_user_ids uuid[],
  ADD COLUMN IF NOT EXISTS kind text,
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

COMMENT ON COLUMN public.push_broadcasts.status_note IS
  'Explicação em PT-BR do estado (porquê falhou, foi cancelado, ou quantos aparelhos). Escrita pela fila/Edge Function/admin.';
COMMENT ON COLUMN public.push_broadcasts.target_user_ids IS
  'Lista fechada de pessoas (users.id) do segmento escolhido no painel. NULL = segmento inteiro (agendados antigos).';

-- 1) As 3 linhas presas em 'sending' desde 21/05 → 'failed' com nota.
CREATE TABLE IF NOT EXISTS public.bkp_push_broadcasts_20261004 AS
  SELECT * FROM public.push_broadcasts
   WHERE status = 'sending' AND created_at < timestamptz '2026-06-01 00:00:00+00';
ALTER TABLE public.bkp_push_broadcasts_20261004 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_push_broadcasts_20261004 FROM anon, authenticated;

WITH presas AS (
  UPDATE public.push_broadcasts
     SET status = 'failed',
         completed_at = COALESCE(completed_at, now()),
         status_note = 'Ficou presa em "a enviar" desde 21/05/2026: a função antiga gravava um estado que a tabela não aceita. '
                    || 'Não se sabe se chegou aos telemóveis (0 contados). Marcada como falhada a 04/10/2026 pela missão de correção.'
   WHERE status = 'sending' AND created_at < timestamptz '2026-06-01 00:00:00+00'
  RETURNING id, segment, title
)
INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
SELECT NULL, 'agente admin-geral (missão 04/10, VAI do Danilo)', 'broadcast_marcado_falhado', 'push_broadcast', p.id,
       jsonb_build_object('segment', p.segment, 'title', p.title, 'estado_antes', 'sending',
                          'estado_depois', 'failed', 'copia', 'bkp_push_broadcasts_20261004')
  FROM presas p;

-- 2) Quem recebe cada segmento — UMA definição. Devolve users.id.
CREATE OR REPLACE FUNCTION public._admin_broadcast_alvos(p_segment text, p_kind text DEFAULT 'admin')
RETURNS uuid[]
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ids uuid[];
  v_marketing boolean := COALESCE(p_kind, 'admin') IN ('promo', 'cashback', 'referral');
BEGIN
  CASE p_segment
    WHEN 'all_clients' THEN
      SELECT array_agg(u.id) INTO v_ids FROM public.users u WHERE u.role = 'client';
    WHEN 'recent_clients_30d' THEN
      SELECT array_agg(DISTINCT o.user_id) INTO v_ids
        FROM public.orders o
       WHERE o.created_at > now() - interval '30 days' AND o.user_id IS NOT NULL;
    WHEN 'drivers_online' THEN
      -- user_id manda em tudo o que a app vê (regra da identidade do estafeta).
      SELECT array_agg(DISTINCT d.user_id) INTO v_ids
        FROM public.drivers d
       WHERE COALESCE(d.is_online, false) AND d.user_id IS NOT NULL;
    WHEN 'partners' THEN
      SELECT array_agg(u.id) INTO v_ids FROM public.users u WHERE u.role = 'partner';
    WHEN 'all_users' THEN
      SELECT array_agg(u.id) INTO v_ids FROM public.users u WHERE u.role IN ('client', 'partner');
    ELSE
      RAISE EXCEPTION 'invalid_segment: %', p_segment;
  END CASE;

  -- 2026-09-23 (D3): comunicação comercial só a quem deu opt-in separado.
  IF v_marketing AND v_ids IS NOT NULL THEN
    SELECT array_agg(x) INTO v_ids
      FROM unnest(v_ids) AS x
     WHERE EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = x AND pu.marketing_opt_in);
  END IF;

  -- só contas que existem mesmo (guarda de órfãos, como antes)
  IF v_ids IS NOT NULL THEN
    SELECT array_agg(x) INTO v_ids
      FROM unnest(v_ids) AS x
     WHERE EXISTS (SELECT 1 FROM auth.users au WHERE au.id = x);
  END IF;

  RETURN COALESCE(v_ids, ARRAY[]::uuid[]);
END;
$function$;

REVOKE ALL ON FUNCTION public._admin_broadcast_alvos(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._admin_broadcast_alvos(text, text) TO service_role;

-- Aparelhos (tokens de push activos) de uma lista de pessoas, nas 3 tabelas.
CREATE OR REPLACE FUNCTION public._admin_broadcast_aparelhos(p_ids uuid[])
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT count(DISTINCT t.fcm_token)::int FROM (
    SELECT c.fcm_token FROM public.client_push_tokens c WHERE c.active AND c.user_id = ANY(p_ids)
    UNION ALL
    SELECT d.fcm_token FROM public.driver_push_tokens d WHERE d.active AND d.user_id = ANY(p_ids)
    UNION ALL
    SELECT pt.fcm_token
      FROM public.partner_push_tokens pt
      JOIN public.restaurants r ON r.id = pt.partner_id::text
     WHERE pt.active AND r.user_id = ANY(p_ids)
  ) t;
$function$;

REVOKE ALL ON FUNCTION public._admin_broadcast_aparelhos(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._admin_broadcast_aparelhos(uuid[]) TO service_role;

-- 3) Pré-visualização para a confirmação do painel.
CREATE OR REPLACE FUNCTION public.admin_broadcast_preview(p_segment text, p_kind text DEFAULT 'admin')
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ids uuid[];
  v_pessoas int;
  v_aparelhos int;
  v_marketing boolean := COALESCE(p_kind, 'admin') IN ('promo', 'cashback', 'referral');
BEGIN
  PERFORM public._admin_op_guard();

  IF p_segment IN ('all_clients', 'recent_clients_30d', 'drivers_online', 'partners', 'all_users') THEN
    v_ids := public._admin_broadcast_alvos(p_segment, p_kind);
    v_pessoas := COALESCE(array_length(v_ids, 1), 0);
    v_aparelhos := public._admin_broadcast_aparelhos(v_ids);
    RETURN jsonb_build_object('segmento', p_segment, 'pessoas', v_pessoas, 'aparelhos', v_aparelhos,
                              'so_opt_in', v_marketing, 'modo', 'imediato');
  ELSIF p_segment IN ('all', 'clients', 'drivers', 'partners') THEN
    SELECT count(DISTINCT x.pessoa)::int, count(DISTINCT x.fcm_token)::int
      INTO v_pessoas, v_aparelhos
      FROM (
        SELECT c.user_id::text AS pessoa, c.fcm_token FROM public.client_push_tokens c
         WHERE c.active AND p_segment IN ('all', 'clients')
        UNION ALL
        SELECT d.user_id::text, d.fcm_token FROM public.driver_push_tokens d
         WHERE d.active AND p_segment IN ('all', 'drivers')
        UNION ALL
        SELECT pt.partner_id::text, pt.fcm_token FROM public.partner_push_tokens pt
         WHERE pt.active AND p_segment IN ('all', 'partners')
      ) x;
    RETURN jsonb_build_object('segmento', p_segment, 'pessoas', COALESCE(v_pessoas, 0),
                              'aparelhos', COALESCE(v_aparelhos, 0), 'so_opt_in', false, 'modo', 'agendado');
  END IF;
  RAISE EXCEPTION 'invalid_segment: %', p_segment;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_broadcast_preview(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_broadcast_preview(text, text) TO authenticated, service_role;

-- 4) Envio "Imediato": sininho já, push pela fila com a lista EXATA.
CREATE OR REPLACE FUNCTION public.admin_broadcast_notification(p_segment text, p_kind text, p_title text, p_body text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin       RECORD;
  v_user_ids    uuid[];
  v_count       int := 0;
  v_fcm_segment text;
  v_marketing   boolean := p_kind IN ('promo', 'cashback', 'referral');
  v_bid         uuid;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  v_fcm_segment := CASE p_segment
    WHEN 'all_clients'        THEN 'clients'
    WHEN 'recent_clients_30d' THEN 'clients'
    WHEN 'drivers_online'     THEN 'drivers'
    WHEN 'partners'           THEN 'partners'
    WHEN 'all_users'          THEN 'all'
    ELSE NULL END;
  IF v_fcm_segment IS NULL THEN
    RAISE EXCEPTION 'invalid_segment: %', p_segment;
  END IF;

  v_user_ids := public._admin_broadcast_alvos(p_segment, p_kind);

  IF array_length(v_user_ids, 1) IS NOT NULL THEN
    INSERT INTO public.in_app_notifications (user_id, kind, title, body)
      SELECT u, p_kind, p_title, p_body FROM unnest(v_user_ids) AS u;
    GET DIAGNOSTICS v_count = ROW_COUNT;
  END IF;

  INSERT INTO public.push_broadcasts (segment, title, body, status, created_by,
                                      only_marketing_opt_in, target_user_ids, kind)
  VALUES (v_fcm_segment, left(p_title, 100),
          left(COALESCE(NULLIF(trim(COALESCE(p_body, '')), ''), p_title), 500), 'pending',
          v_admin.admin_id, v_marketing, v_user_ids, p_kind)
  RETURNING id INTO v_bid;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'broadcast_notification', 'push_broadcast', v_bid,
          jsonb_build_object('segmento', p_segment, 'kind', p_kind, 'title', p_title,
                             'in_app_count', v_count, 'pessoas', COALESCE(array_length(v_user_ids, 1), 0),
                             'only_marketing_opt_in', v_marketing));

  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_broadcast_notification(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_broadcast_notification(text, text, text, text) TO authenticated, service_role;

-- 5) Cancelar um agendado que ainda não saiu ('failed' com nota — o CHECK não tem 'cancelled').
CREATE OR REPLACE FUNCTION public.admin_cancel_broadcast(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_row public.push_broadcasts%ROWTYPE;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  UPDATE public.push_broadcasts
     SET status = 'failed',
         completed_at = now(),
         status_note = 'Cancelado no painel em '
                       || to_char(now() AT TIME ZONE 'Europe/Lisbon', 'DD/MM/YYYY HH24:MI')
                       || ' (hora de Lisboa), antes de sair.'
   WHERE id = p_id AND status = 'pending'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Esta notificação já não está à espera (já saiu ou já foi cancelada).');
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'broadcast_cancelar', 'push_broadcast', p_id,
          jsonb_build_object('segment', v_row.segment, 'title', v_row.title, 'scheduled_at', v_row.scheduled_at));

  RETURN jsonb_build_object('ok', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_cancel_broadcast(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_broadcast(uuid) TO authenticated, service_role;

-- 6) Histórico com a nota (v2).
CREATE OR REPLACE FUNCTION public.admin_list_broadcasts_v2(p_limit integer DEFAULT 50)
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
      SELECT b.id, b.segment, b.kind, b.title, b.body, b.status, b.status_note,
             b.sent_count, b.failed_count, b.scheduled_at, b.completed_at, b.created_at,
             b.only_marketing_opt_in,
             array_length(b.target_user_ids, 1) AS pessoas_alvo,
             au.email AS criado_por
        FROM public.push_broadcasts b
        LEFT JOIN auth.users au ON au.id = b.created_by
       ORDER BY b.created_at DESC
       LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 500))
    ) x;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_list_broadcasts_v2(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_broadcasts_v2(integer) TO authenticated, service_role;

-- 7) A fila: presos > 30 min passam a 'failed' com nota; se houver pendentes
--    vencidos, chama a Edge Function.
CREATE OR REPLACE FUNCTION public.broadcasts_processar_fila()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_presos int := 0;
  v_pendentes int := 0;
  v_req bigint;
BEGIN
  UPDATE public.push_broadcasts
     SET status = 'failed',
         completed_at = now(),
         status_note = COALESCE(status_note || ' · ', '')
                       || 'Ficou mais de 30 min em "a enviar" sem terminar; não se sabe quantos chegaram.'
   WHERE status = 'sending'
     AND COALESCE(claimed_at, scheduled_at) < now() - interval '30 minutes';
  GET DIAGNOSTICS v_presos = ROW_COUNT;

  SELECT count(*) INTO v_pendentes
    FROM public.push_broadcasts
   WHERE status = 'pending' AND scheduled_at <= now();

  IF v_pendentes > 0 THEN
    SELECT net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
             || '/functions/v1/execute-broadcast',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
        'Content-Type', 'application/json'),
      body := jsonb_build_object('origem', 'cron'),
      timeout_milliseconds := 60000
    ) INTO v_req;
  END IF;

  RETURN jsonb_build_object('presos_marcados', v_presos, 'pendentes', v_pendentes, 'pedido_http', v_req);
END;
$function$;

REVOKE ALL ON FUNCTION public.broadcasts_processar_fila() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.broadcasts_processar_fila() TO service_role;

-- Tarefa agendada: minutos ímpares (os */2 existentes correm nos pares).
DO $cron$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'execute-broadcast-queue') THEN
    PERFORM cron.schedule('execute-broadcast-queue', '1-59/2 * * * *',
                          'SELECT public.broadcasts_processar_fila();');
  END IF;
END
$cron$;
