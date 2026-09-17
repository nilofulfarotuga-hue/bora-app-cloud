-- Aplicada em produção pela Claude.ai (MCP apply_migration) a 2026-09-16 17:24:28 UTC,
-- versão 20260916172428. Trazida para o repo pela missão estafeta-web-2026-09-16 (bloco 7.1),
-- SQL literal lido de supabase_migrations.schema_migrations. NÃO reaplicar.
-- (A migração 20260916224051 desta missão substitui esta função: passa a aceitar
-- pré-atribuição a estafeta ligado quando o pedido ainda não está pronto.)

-- 2026-09-16 (Claude.ai): caminho ÚNICO e seguro para AGENTES (ChatGPT, OpenCode, Hermes, Claude Code)
-- atribuírem ou passarem pedidos de entrega. Motivo: a 16/09 o ChatGPT fez UPDATE direto em orders,
-- pôs o pedido da Goola no estafeta Ney (desligado, sem notificações) e o pedido ficou preso.
-- Recusa: estafeta que não vai receber (desligado, sem sinal há +90 s, sem notificações, banido)
-- e pedido que ainda não está pronto — salvo p_forcar = true por ordem expressa do Danilo.
-- Por dentro usa admin_reassign_order (mesma lógica e mesmo aviso ao estafeta) com a identidade do admin.
CREATE OR REPLACE FUNCTION public.ops_reassign_order(
  p_order_id text,
  p_new_driver text,
  p_motivo text,
  p_agente text,
  p_forcar boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_o record;
  v_d record;
  v_online boolean;
  v_push boolean;
  v_pronto boolean;
  v_claims_antes text;
  v_res jsonb;
  c_admin_uid constant text := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
BEGIN
  IF coalesce(btrim(p_agente), '') = '' OR coalesce(btrim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'agente_e_motivo_obrigatorios');
  END IF;

  SELECT id, status, assigned_driver_id INTO v_o FROM orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  IF v_o.status IN ('delivered', 'cancelled', 'rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_ja_terminal', 'status', v_o.status);
  END IF;

  SELECT d.id, d.user_id, d.name, d.approval_status, d.is_online, d.last_heartbeat_at, d.fcm_token, d.is_banned
    INTO v_d
  FROM drivers d
  WHERE d.id::text = p_new_driver OR d.user_id::text = p_new_driver
  LIMIT 1;
  IF v_d.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado');
  END IF;
  IF coalesce(v_d.is_banned, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_banido', 'estafeta', v_d.name);
  END IF;

  v_online := coalesce(v_d.is_online, false)
              AND v_d.last_heartbeat_at IS NOT NULL
              AND v_d.last_heartbeat_at > now() - interval '90 seconds';
  v_push := v_d.fcm_token IS NOT NULL
            OR EXISTS (SELECT 1 FROM driver_push_tokens t
                       WHERE t.user_id::text = coalesce(v_d.user_id, v_d.id)::text
                         AND t.active);
  v_pronto := v_o.status IN ('callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay');

  IF NOT p_forcar AND (NOT v_online OR NOT v_push OR NOT v_pronto) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', CASE WHEN NOT v_pronto THEN 'pedido_ainda_nao_pronto' ELSE 'estafeta_nao_vai_receber' END,
      'estafeta', v_d.name,
      'online_agora', v_online,
      'tem_notificacoes', v_push,
      'status_pedido', v_o.status,
      'o_que_fazer', 'Não atribuas por outro caminho. Diz ao Danilo o motivo em palavras simples. Só repetir com p_forcar => true se o Danilo mandar expressamente depois de saber o motivo.');
  END IF;

  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c_admin_uid, 'role', 'authenticated',
                      'email', 'nilofulfarotuga@gmail.com',
                      'app_metadata', json_build_object('role', 'admin'))::text, true);
  BEGIN
    v_res := public.admin_reassign_order(p_order_id, p_new_driver,
                                         left('[agente ' || p_agente || '] ' || p_motivo, 500));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);

  INSERT INTO admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('order_reassigned_by_agent', 'order', p_order_id, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'motivo', p_motivo,
                             'de', v_o.assigned_driver_id,
                             'para', coalesce(v_d.user_id, v_d.id), 'estafeta', v_d.name,
                             'forcado', p_forcar, 'online_agora', v_online,
                             'tem_notificacoes', v_push, 'status_pedido', v_o.status,
                             'resultado', v_res));

  RETURN coalesce(v_res, '{}'::jsonb)
         || jsonb_build_object('agente', p_agente, 'forcado', p_forcar,
                               'online_agora', v_online, 'tem_notificacoes', v_push);
END $function$;

REVOKE ALL ON FUNCTION public.ops_reassign_order(text, text, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ops_reassign_order(text, text, text, text, boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_reassign_order(text, text, text, text, boolean) TO service_role;

COMMENT ON FUNCTION public.ops_reassign_order(text, text, text, text, boolean) IS
'Único caminho para agentes (ChatGPT, OpenCode, Hermes, Claude Code) atribuírem/passarem pedidos. Nunca UPDATE direto em orders. Regras: página regras-operacao-agentes em public.claude_ai_memoria.';
