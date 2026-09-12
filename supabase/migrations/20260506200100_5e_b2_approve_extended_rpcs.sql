-- Sessão 5E B2 — Estender admin_approve_skill_suggestion (3 tipos) + criar admin_rollback_suggestion
-- BREAKING: retorno passa de uuid → jsonb. Flutter 5D usa SnackBar fire-and-forget; sem regressão.
-- Whitelist 8 SAFE keys (A1 confirmou colunas reais; chatbot_welcome_text NÃO welcome_text).
-- Hardcode 8 skills CRITICAL (OTP_RESEND defensivo — não existe na DB mas reservado).

-- ═══ admin_approve_skill_suggestion estendida ═══
-- DROP necessário: 5D retornava uuid; passa a retornar jsonb (PG 42P13)
DROP FUNCTION IF EXISTS public.admin_approve_skill_suggestion(uuid, text, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.admin_approve_skill_suggestion(
  p_suggestion_id  uuid,
  p_skill_name     text  DEFAULT NULL,
  p_category       text  DEFAULT NULL,
  p_mode           text  DEFAULT 'read_only',
  p_playbook_md    text  DEFAULT NULL,
  p_allowed_tools  jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_suggestion        skill_suggestions;
  v_skill_id          uuid;
  v_target_skill_name text;
  v_old_value         text;
  v_data_type         text;
  v_playbook          text;
  v_safe_keys         text[] := ARRAY[
    'chatbot_welcome_text','sla_hours',
    'max_messages_per_session','rate_limit_per_user_day',
    'max_output_tokens_per_call','max_user_message_chars',
    'max_tool_iterations','skill_analysis_min_messages'
  ];
  v_critical_skills   text[] := ARRAY[
    'CANCEL_PRE_PURCHASE','CANCEL_DURING_PURCHASE',
    'RESERVATION_CANCEL','PASSWORD_RESET','ACCOUNT_UPDATE',
    'UPDATE_DELIVERY_INSTRUCTIONS','UPDATE_DELIVERY_ADDRESS',
    'OTP_RESEND'  -- defensivo: skill ainda não existe (A2), reservada CRITICAL se criada
  ];
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  IF p_mode NOT IN ('read_only','write_shadow','escalate') THEN
    RAISE EXCEPTION 'INVALID_MODE: %', p_mode;
  END IF;

  SELECT * INTO v_suggestion
  FROM skill_suggestions
  WHERE id = p_suggestion_id AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUGGESTION_NOT_FOUND_OR_NOT_PENDING';
  END IF;

  CASE v_suggestion.proposal_type

    -- ─── Tipo 1: NEW_SKILL (5D preservado) ───
    WHEN 'new_skill' THEN
      IF p_skill_name IS NULL OR length(trim(p_skill_name)) = 0 THEN
        RAISE EXCEPTION 'INVALID_SKILL_NAME';
      END IF;
      IF p_category IS NULL OR length(trim(p_category)) = 0 THEN
        RAISE EXCEPTION 'INVALID_CATEGORY';
      END IF;
      IF EXISTS (SELECT 1 FROM support_skills WHERE skill_name = p_skill_name) THEN
        RAISE EXCEPTION 'SKILL_NAME_ALREADY_EXISTS: %', p_skill_name;
      END IF;

      v_playbook := coalesce(
        p_playbook_md,
        v_suggestion.suggested_playbook_md,
        '## ' || p_skill_name || E'\n\n(Playbook a completar)'
      );

      INSERT INTO support_skills (
        skill_name, version, category, mode,
        requires_human_handoff, playbook_md,
        allowed_tools, examples, active
      ) VALUES (
        p_skill_name, 1, p_category, p_mode,
        (p_mode = 'escalate'), v_playbook,
        p_allowed_tools, '[]'::jsonb, true
      ) RETURNING id INTO v_skill_id;

    -- ─── Tipo 2: PLAYBOOK_UPDATE ───
    WHEN 'playbook_update' THEN
      IF v_suggestion.zone_type = 'critical' THEN
        RAISE EXCEPTION 'CRITICAL_ZONE — manual SQL update required';
      END IF;

      SELECT skill_name INTO v_target_skill_name
      FROM support_skills WHERE id = v_suggestion.target_skill_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'TARGET_SKILL_NOT_FOUND';
      END IF;

      IF v_target_skill_name = ANY(v_critical_skills) THEN
        RAISE EXCEPTION 'CRITICAL_SKILL — playbook_update requires manual: %', v_target_skill_name;
      END IF;

      -- Capturar previous_value
      SELECT playbook_md INTO v_old_value
      FROM support_skills WHERE id = v_suggestion.target_skill_id;

      UPDATE skill_suggestions
      SET previous_value = v_old_value
      WHERE id = p_suggestion_id;

      v_playbook := coalesce(
        p_playbook_md,
        v_suggestion.suggested_playbook_md,
        v_old_value
      );

      UPDATE support_skills
      SET playbook_md = v_playbook,
          version     = version + 1
      WHERE id = v_suggestion.target_skill_id;

      v_skill_id := v_suggestion.target_skill_id;

    -- ─── Tipo 3: SETTINGS_UPDATE ───
    WHEN 'settings_update' THEN
      IF v_suggestion.zone_type = 'critical' THEN
        RAISE EXCEPTION 'CRITICAL_ZONE';
      END IF;

      -- Defesa SQL injection: regex (já garantido por CHECK constraint, mas double-check)
      IF v_suggestion.target_setting_key !~ '^[a-z_]+$' THEN
        RAISE EXCEPTION 'INVALID_KEY_FORMAT';
      END IF;

      -- Whitelist
      IF NOT (v_suggestion.target_setting_key = ANY(v_safe_keys)) THEN
        RAISE EXCEPTION 'SETTING_NOT_IN_SAFE_WHITELIST: %', v_suggestion.target_setting_key;
      END IF;

      -- data_type para cast
      SELECT data_type INTO v_data_type
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='support_settings'
        AND column_name = v_suggestion.target_setting_key;

      IF v_data_type IS NULL THEN
        RAISE EXCEPTION 'SETTING_COLUMN_NOT_FOUND: %', v_suggestion.target_setting_key;
      END IF;

      -- Capturar previous_value (cast ::text universal)
      EXECUTE format('SELECT %I::text FROM support_settings WHERE id=1',
                     v_suggestion.target_setting_key)
        INTO v_old_value;

      UPDATE skill_suggestions
      SET previous_value = v_old_value
      WHERE id = p_suggestion_id;

      -- Aplicar novo valor com cast type-aware + EXCEPTION wrapper
      BEGIN
        EXECUTE format('UPDATE support_settings SET %I = $1::%s WHERE id=1',
                       v_suggestion.target_setting_key, v_data_type)
          USING v_suggestion.target_setting_value;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'CAST_FAILED — value "%" cannot become %: %',
          v_suggestion.target_setting_value, v_data_type, SQLERRM;
      END;

    ELSE
      RAISE EXCEPTION 'UNKNOWN_PROPOSAL_TYPE: %', v_suggestion.proposal_type;
  END CASE;

  -- Marcar implemented (todos os tipos)
  UPDATE skill_suggestions
  SET status               = 'implemented',
      reviewed_at          = now(),
      reviewed_by          = auth.uid(),
      implemented_skill_id = v_skill_id,  -- NULL para settings_update (correto)
      implemented_at       = now()
  WHERE id = p_suggestion_id;

  RETURN jsonb_build_object(
    'type',         v_suggestion.proposal_type,
    'skill_id',     v_skill_id,
    'skill_name',   coalesce(v_target_skill_name, p_skill_name),
    'setting_key',  v_suggestion.target_setting_key,
    'old_value',    v_old_value,
    'new_value',    v_suggestion.target_setting_value,
    'data_type',    v_data_type
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_skill_suggestion(uuid, text, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_skill_suggestion(uuid, text, text, text, text, jsonb)
  TO authenticated;


-- ═══ admin_rollback_suggestion ═══
-- Reverte playbook_update e settings_update. new_skill RAISE explícito (DELETE manual).
CREATE OR REPLACE FUNCTION public.admin_rollback_suggestion(
  p_suggestion_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_suggestion skill_suggestions;
  v_data_type  text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  SELECT * INTO v_suggestion
  FROM skill_suggestions
  WHERE id = p_suggestion_id
    AND status = 'implemented'
    AND previous_value IS NOT NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SUGGESTION_NOT_ROLLBACKABLE';
  END IF;

  CASE v_suggestion.proposal_type

    WHEN 'playbook_update' THEN
      UPDATE support_skills
      SET playbook_md = v_suggestion.previous_value,
          version     = GREATEST(version - 1, 1)  -- evita version<1
      WHERE id = v_suggestion.target_skill_id;

    WHEN 'settings_update' THEN
      IF v_suggestion.target_setting_key !~ '^[a-z_]+$' THEN
        RAISE EXCEPTION 'INVALID_KEY_FORMAT';
      END IF;

      SELECT data_type INTO v_data_type
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='support_settings'
        AND column_name = v_suggestion.target_setting_key;

      IF v_data_type IS NULL THEN
        RAISE EXCEPTION 'SETTING_COLUMN_NOT_FOUND';
      END IF;

      BEGIN
        EXECUTE format('UPDATE support_settings SET %I = $1::%s WHERE id=1',
                       v_suggestion.target_setting_key, v_data_type)
          USING v_suggestion.previous_value;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'ROLLBACK_CAST_FAILED: %', SQLERRM;
      END;

    ELSE
      RAISE EXCEPTION
        'ROLLBACK_NOT_SUPPORTED_FOR_TYPE: % — use manual DELETE for new_skill',
        v_suggestion.proposal_type;
  END CASE;

  UPDATE skill_suggestions
  SET status = 'rolled_back'
  WHERE id = p_suggestion_id;

  RETURN jsonb_build_object(
    'rolled_back', true,
    'type', v_suggestion.proposal_type,
    'restored_value', v_suggestion.previous_value
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_rollback_suggestion(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_rollback_suggestion(uuid) TO authenticated;
