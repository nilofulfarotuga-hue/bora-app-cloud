-- Item 100 do goal paridade-admin-360: GDPR — export de dados + anonimização.
-- Export = read-only (direito de acesso/portabilidade, art. 15/20 RGPD).
-- Anonimização = direito ao esquecimento (art. 17) SEM quebrar integridade
-- financeira: orders/ledger ficam (obrigação legal de faturação), mas os campos
-- pessoais são substituídos. NUNCA hard-delete de linhas financeiras.

-- ===== EXPORT =====
CREATE OR REPLACE FUNCTION public.admin_gdpr_export(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin_only'; END IF;

  SELECT jsonb_build_object(
    'gerado_em', now(),
    'perfil', (SELECT to_jsonb(u) - 'fcm_token' FROM users u WHERE u.id = p_user_id),
    'enderecos', (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
                    FROM client_addresses a WHERE a.user_id = p_user_id),
    'pedidos', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'id', o.id, 'criado', o.created_at, 'estado', o.status,
                  'total', o.total, 'morada_recolha', o.pickup_address,
                  'morada_entrega', o.dropoff_address,
                  'tipo', o.service_type)), '[]'::jsonb)
                  FROM orders o WHERE o.user_id = p_user_id),
    'tokens', (SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                 FROM bora_tokens t WHERE t.user_id = p_user_id),
    'movimentos_wallet', (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]'::jsonb)
                            FROM wallet_transactions w WHERE w.user_id = p_user_id),
    'avaliacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
                     FROM ratings r WHERE r.rater_user_id = p_user_id)
  ) INTO v;

  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), 'gdpr_export', 'user', p_user_id::text,
          jsonb_build_object('motivo', 'pedido do titular (art. 15/20 RGPD)'));

  RETURN v;
END;
$$;

-- ===== ANONIMIZAÇÃO (direito ao esquecimento) =====
-- Exige confirmação textual exata para evitar toques acidentais no admin.
CREATE OR REPLACE FUNCTION public.admin_gdpr_anonymize(
  p_user_id uuid, p_confirm text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_email text; v_orders int;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin_only'; END IF;
  IF p_confirm IS DISTINCT FROM 'APAGAR DADOS' THEN
    RAISE EXCEPTION 'confirmacao_invalida (escreve exatamente: APAGAR DADOS)';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'razao_obrigatoria (min 10 chars)';
  END IF;

  SELECT email INTO v_email FROM users WHERE id = p_user_id;
  IF v_email IS NULL THEN RAISE EXCEPTION 'utilizador_nao_encontrado'; END IF;

  -- bloqueio: pedidos em curso impedem anonimização
  SELECT count(*) INTO v_orders FROM orders
   WHERE user_id = p_user_id
     AND status NOT IN ('delivered','rejected','cancelled');
  IF v_orders > 0 THEN
    RAISE EXCEPTION 'utilizador_tem_pedidos_em_curso (%)', v_orders;
  END IF;

  -- perfil: substitui campos pessoais (linha fica para integridade referencial)
  UPDATE users SET
    name = 'Utilizador removido',
    email = 'gdpr-' || left(p_user_id::text, 8) || '@removed.bora.app',
    phone = NULL, fcm_token = NULL, photo_url = NULL
  WHERE id = p_user_id;

  DELETE FROM client_addresses WHERE user_id = p_user_id;

  -- pedidos: manter valores (obrigação fiscal), remover moradas/nome
  UPDATE orders SET
    pickup_address = 'removido (RGPD)',
    dropoff_address = 'removido (RGPD)',
    customer_name = 'Utilizador removido'
  WHERE user_id = p_user_id;

  INSERT INTO admin_audit_log (admin_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), 'gdpr_anonymize', 'user', p_user_id::text,
          jsonb_build_object('email_original_hash', md5(v_email), 'reason', p_reason));

  RETURN jsonb_build_object('ok', true, 'user_id', p_user_id,
    'nota', 'Perfil anonimizado; conta Auth deve ser desativada no dashboard Supabase (ação manual).');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_gdpr_export(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_gdpr_anonymize(uuid, text, text) FROM anon;
