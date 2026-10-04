-- ============================================================================
-- APLICADA EM PRODUÇÃO a 04/10/2026 (versão 20261004205343).
-- Painel admin — ronda 04/10/2026 (agente admin-geral), parte 2.
--  · Escalamentos do suporte (o aviso "Cliente precisa de ti" abria "Página não
--    encontrada"): listar, ver a conversa, responder — a resposta entra na
--    conversa do suporte e no sininho do cliente; auditado.
--  · Opções/variantes de produto: ver por loja e editar um item (nome,
--    disponível, acréscimo de preço) com auditoria antes/depois.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_support_escalations_list(p_status text DEFAULT NULL, p_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(x ORDER BY x.pendente DESC, x.created_at DESC), '[]'::jsonb) INTO r
    FROM (
      SELECT e.id, e.session_id, e.user_id, e.user_role, e.question, e.persona_name, e.status,
             e.danilo_reply, e.created_at, e.answered_at, (e.status = 'pending') AS pendente,
             COALESCE(NULLIF(u.name, ''), au.email) AS nome, au.email, u.phone
        FROM public.support_escalations e
        LEFT JOIN public.users u ON u.id = e.user_id
        LEFT JOIN auth.users au ON au.id = e.user_id
       WHERE p_status IS NULL OR e.status = p_status
       ORDER BY e.created_at DESC
       LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 200), 1000))
    ) x;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_support_escalations_list(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_support_escalations_list(text, integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_support_escalation_conversa(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r jsonb; v_sess uuid;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT session_id INTO v_sess FROM public.support_escalations WHERE id = p_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('role', m.role, 'content', m.content, 'created_at', m.created_at)
                            ORDER BY m.created_at), '[]'::jsonb)
    INTO r
    FROM public.support_chatbot_messages m
   WHERE m.session_id = v_sess AND m.role IN ('user', 'assistant');
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_support_escalation_conversa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_support_escalation_conversa(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_support_escalation_responder(p_id uuid, p_resposta text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_e public.support_escalations%ROWTYPE;
  v_txt text := trim(COALESCE(p_resposta, ''));
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF length(v_txt) < 2 OR length(v_txt) > 2000 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'A resposta tem de ter entre 2 e 2000 letras.');
  END IF;

  UPDATE public.support_escalations
     SET status = 'answered', danilo_reply = v_txt, answered_at = now()
   WHERE id = p_id
  RETURNING * INTO v_e;
  IF v_e.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Escalamento não encontrado.');
  END IF;

  -- A resposta aparece na conversa do suporte...
  IF v_e.session_id IS NOT NULL THEN
    INSERT INTO public.support_chatbot_messages (session_id, role, content)
    VALUES (v_e.session_id, 'assistant', v_txt);
  END IF;
  -- ...e no sininho da pessoa.
  IF v_e.user_id IS NOT NULL THEN
    INSERT INTO public.in_app_notifications (user_id, kind, title, body, related_id)
    VALUES (v_e.user_id, 'admin', 'Resposta do apoio Bora', left(v_txt, 500), v_e.id::text);
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'suporte_responder', 'support_escalation', p_id,
          jsonb_build_object('pergunta', left(v_e.question, 300), 'resposta', left(v_txt, 500)));
  RETURN jsonb_build_object('ok', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_support_escalation_responder(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_support_escalation_responder(uuid, text) TO authenticated, service_role;

-- Opções/variantes de uma loja (grupos + itens + nome do produto).
CREATE OR REPLACE FUNCTION public.admin_opcoes_loja(p_restaurant_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(jsonb_agg(x ORDER BY x.produto, x.sort_order), '[]'::jsonb) INTO r
    FROM (
      SELECT g.id, g.product_id, p.name AS produto, g.name, g.description, g.is_required,
             g.min_choices, g.max_choices, g.sort_order,
             COALESCE((SELECT jsonb_agg(jsonb_build_object(
                         'id', i.id, 'name', i.name, 'price_add', i.price_add,
                         'is_available', i.is_available, 'sort_order', i.sort_order)
                       ORDER BY i.sort_order, i.name)
                  FROM public.product_option_items i WHERE i.group_id = g.id), '[]'::jsonb) AS itens
        FROM public.product_option_groups g
        JOIN public.products p ON p.id = g.product_id
       WHERE p.restaurant_id = p_restaurant_id
    ) x;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_opcoes_loja(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_opcoes_loja(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_opcao_item_atualizar(
  p_item_id text, p_name text, p_price_add numeric, p_is_available boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD;
  v_antes public.product_option_items%ROWTYPE;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  SELECT * INTO v_antes FROM public.product_option_items WHERE id = p_item_id;
  IF v_antes.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Opção não encontrada.');
  END IF;
  IF p_price_add IS NOT NULL AND (p_price_add < 0 OR p_price_add > 500) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Acréscimo entre 0 e 500 €.');
  END IF;
  IF p_name IS NOT NULL AND length(trim(p_name)) < 1 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'O nome não pode ficar vazio.');
  END IF;

  UPDATE public.product_option_items
     SET name = COALESCE(trim(p_name), name),
         price_add = COALESCE(p_price_add, price_add),
         is_available = COALESCE(p_is_available, is_available)
   WHERE id = p_item_id;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'opcao_produto_editada', 'product_option_item', p_item_id,
          jsonb_build_object('antes', jsonb_build_object('name', v_antes.name, 'price_add', v_antes.price_add,
                                                         'is_available', v_antes.is_available),
                             'depois', jsonb_build_object('name', COALESCE(trim(p_name), v_antes.name),
                                                          'price_add', COALESCE(p_price_add, v_antes.price_add),
                                                          'is_available', COALESCE(p_is_available, v_antes.is_available))));
  RETURN jsonb_build_object('ok', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_opcao_item_atualizar(text, text, numeric, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_opcao_item_atualizar(text, text, numeric, boolean) TO authenticated, service_role;
