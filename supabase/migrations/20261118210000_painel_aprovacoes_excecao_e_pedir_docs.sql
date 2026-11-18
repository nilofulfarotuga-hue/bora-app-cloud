-- Missão painel-aprovacoes-2026-11-18 (autorização do Danilo 18/11/2026 20:29).
--
-- 1) Exceção do dono: o Danilo já mandou aprovar gente sem o comprovativo de
--    atividade aprovado (Felipe 16/11, Shelen 18/11 — esta por SQL à mão).
--    A regra provider_atividade_obrigatoria continua ligada para os outros: a
--    trava fn_atividade_antes_de_ativar só deixa passar quando é a RPC
--    admin_aprovar_prestador_excecao a pedir, para ESSA pessoa, com um admin
--    autenticado, e fica registado quem e porquê (admin_audit_log + evento em
--    provider_atividade_eventos).
-- 2) "Pedir documentos em falta" passa a ter uma porta própria: o aviso na
--    app tem kind 'documentos_em_falta' e related_id = papel, para o toque
--    abrir o ecrã de pendências da pessoa (onde consegue enviar), em vez de
--    só marcar como lido.

-- ── 1a. A trava, com a porta da exceção (nunca desligada) ────────────────────
CREATE OR REPLACE FUNCTION public.fn_atividade_antes_de_ativar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cfg record;
  v_st  text;
BEGIN
  IF NEW.user_id IS NULL OR NEW.created_at IS NULL THEN RETURN NEW; END IF;
  -- 18/11/2026: exceção do admin. A marca só existe dentro da transação de
  -- admin_aprovar_prestador_excecao (set_config local) e vale só para esta
  -- pessoa; is_admin() confirma que quem chama é mesmo admin.
  IF COALESCE(current_setting('bora.excecao_atividade', true), '') = NEW.user_id::text
     AND public.is_admin() THEN
    RETURN NEW;
  END IF;
  SELECT * INTO v_cfg FROM public._provider_atividade_config();
  IF NOT COALESCE(v_cfg.ligado, false) OR v_cfg.corte IS NULL OR NEW.created_at < v_cfg.corte THEN
    RETURN NEW;
  END IF;
  SELECT a.atividade_status INTO v_st FROM public.provider_atividade a WHERE a.user_id = NEW.user_id;
  IF COALESCE(v_st, 'por_enviar') <> 'aprovada' THEN
    RAISE EXCEPTION 'atividade_por_aprovar'
      USING HINT = 'Aprova primeiro o comprovativo de atividade (painel: Comprovativo de atividade), ou usa "Aprovar mesmo assim (exceção do admin)".';
  END IF;
  RETURN NEW;
END $function$;

-- ── 1b. Aprovar mesmo assim (exceção do admin) ───────────────────────────────
-- p_id é texto: service_providers.id é TEXT; os outros papéis são uuid e
-- convertem-se só no ramo do papel pedido (IF, não CASE de expressão, para
-- o Postgres não planear os outros ramos com o tipo errado).
CREATE OR REPLACE FUNCTION public.admin_aprovar_prestador_excecao(
  p_papel text, p_id text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin  record;
  v_uid    uuid;
  v_estado text;
  v_motivo text := NULLIF(trim(COALESCE(p_motivo, '')), '');
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_papel NOT IN ('driver', 'cleaner', 'washer', 'handyman', 'service_provider') THEN
    RAISE EXCEPTION 'papel_invalido: %', p_papel USING ERRCODE = '22023';
  END IF;
  IF v_motivo IS NULL OR length(v_motivo) < 10 THEN
    RAISE EXCEPTION 'motivo_excecao_curto' USING ERRCODE = '22023';
  END IF;

  IF p_papel <> 'service_provider'
     AND COALESCE(p_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION 'prestador_nao_encontrado';
  END IF;
  IF p_papel = 'driver' THEN
    SELECT d.user_id INTO v_uid FROM public.drivers d WHERE d.id = p_id::uuid;
  ELSIF p_papel = 'cleaner' THEN
    SELECT c.user_id INTO v_uid FROM public.cleaners c WHERE c.id = p_id::uuid;
  ELSIF p_papel = 'washer' THEN
    SELECT w.user_id INTO v_uid FROM public.washers w WHERE w.id = p_id::uuid;
  ELSIF p_papel = 'handyman' THEN
    SELECT h.user_id INTO v_uid FROM public.casa_profissionais h WHERE h.id = p_id::uuid;
  ELSE
    SELECT s.user_id INTO v_uid FROM public.service_providers s WHERE s.id = p_id;
  END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'prestador_nao_encontrado'; END IF;

  PERFORM public._provider_atividade_garantir(v_uid);
  SELECT a.atividade_status INTO v_estado FROM public.provider_atividade a WHERE a.user_id = v_uid;

  -- A marca vale só até ao fim desta transação e só para esta pessoa.
  PERFORM set_config('bora.excecao_atividade', v_uid::text, true);
  CASE p_papel
    WHEN 'driver' THEN
      PERFORM public.admin_approve_driver(p_id::uuid, true, 'Exceção do admin: ' || v_motivo);
    WHEN 'cleaner' THEN
      PERFORM public.admin_review_cleaner(p_id::uuid, 'approve', 'Exceção do admin: ' || v_motivo);
    WHEN 'washer' THEN
      PERFORM public.admin_rever_lavador(p_id::uuid, 'approve', 'Exceção do admin: ' || v_motivo);
    WHEN 'handyman' THEN
      PERFORM public.admin_casa_decidir_profissional(p_id::uuid, 'aprovar', 'Exceção do admin: ' || v_motivo);
    WHEN 'service_provider' THEN
      PERFORM public.admin_appointment_provider_approve(p_id);
  END CASE;
  PERFORM set_config('bora.excecao_atividade', '', true);

  PERFORM public._provider_atividade_evento(v_uid, 'excecao_admin', v_estado, v_estado, v_motivo,
    v_admin.admin_id, 'admin',
    jsonb_build_object('papel', p_papel, 'entidade_id', p_id, 'admin_email', v_admin.admin_email,
                       'via', COALESCE(current_setting('bora.agente', true), 'painel')));
  PERFORM public.log_admin_action('prestador_aprovado_excecao', p_papel, p_id,
    jsonb_build_object('user_id', v_uid, 'motivo', v_motivo, 'atividade_status', v_estado,
                       'admin_email', v_admin.admin_email));

  RETURN jsonb_build_object('ok', true, 'papel', p_papel, 'id', p_id, 'user_id', v_uid,
                            'atividade_status', v_estado);
END $function$;

REVOKE ALL ON FUNCTION public.admin_aprovar_prestador_excecao(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_aprovar_prestador_excecao(text, text, text) TO authenticated;

COMMENT ON FUNCTION public.admin_aprovar_prestador_excecao(text, text, text) IS
  'Aprovar mesmo assim (exceção do admin): aprova o prestador sem o comprovativo de atividade aprovado, com motivo (>=10 letras), registo em admin_audit_log e evento excecao_admin. A regra provider_atividade_obrigatoria continua ligada para os outros.';

-- ── 2. Pedir documentos em falta (aviso que abre o ecrã de pendências) ───────
CREATE OR REPLACE FUNCTION public.admin_pedir_documentos_em_falta(
  p_user_id uuid, p_papel text, p_titulo text, p_texto text, p_itens text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'vault'
AS $function$
DECLARE
  v_url text;
  v_key text;
  v_tem_aparelho boolean;
  v_notif uuid;
BEGIN
  PERFORM public._admin_op_guard();
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user_obrigatorio'; END IF;
  IF p_papel NOT IN ('driver', 'cleaner', 'washer', 'handyman') THEN
    RAISE EXCEPTION 'papel_invalido: %', p_papel USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(COALESCE(p_titulo, '')), '') IS NULL OR NULLIF(trim(COALESCE(p_texto, '')), '') IS NULL THEN
    RAISE EXCEPTION 'texto_obrigatorio' USING ERRCODE = '22023';
  END IF;

  -- No sino da app: kind próprio + papel em related_id (o toque abre as pendências).
  v_notif := public._push_in_app_notification(p_user_id, 'documentos_em_falta', p_titulo, p_texto, p_papel);

  SELECT EXISTS (
    SELECT 1 FROM public.driver_push_tokens   WHERE user_id = p_user_id AND active
    UNION ALL SELECT 1 FROM public.provider_push_tokens WHERE user_id = p_user_id AND active
    UNION ALL SELECT 1 FROM public.client_push_tokens   WHERE user_id = p_user_id AND active
    UNION ALL SELECT 1 FROM public.users WHERE id = p_user_id AND fcm_token IS NOT NULL
  ) INTO v_tem_aparelho;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := v_url || '/functions/v1/notify-admin-message',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object(
        'targetUserId', p_user_id::text,
        'title', p_titulo,
        'body', p_texto,
        'kind', 'documentos_em_falta',
        'relatedId', p_papel));
  END IF;

  PERFORM public.log_admin_action('pedir_documentos_em_falta', 'user', p_user_id::text,
    jsonb_build_object('papel', p_papel, 'itens', to_jsonb(COALESCE(p_itens, '{}'::text[])),
                       'notificacao_id', v_notif, 'tem_aparelho', v_tem_aparelho));

  RETURN jsonb_build_object('ok', true, 'notificacao_id', v_notif, 'fcm_token_found', v_tem_aparelho);
END $function$;

REVOKE ALL ON FUNCTION public.admin_pedir_documentos_em_falta(uuid, text, text, text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_pedir_documentos_em_falta(uuid, text, text, text, text[]) TO authenticated;
