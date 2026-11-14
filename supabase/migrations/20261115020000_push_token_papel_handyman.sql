-- Missão fechar-app-15-11 — Bloco 3 (d).
--
-- O aparelho do profissional da Casa e manutenção (papel `handyman`) nunca
-- ficava registado para receber avisos.
--
-- MEDIDO (14/11/2026 18:19:57 UTC, e2e_log 8885): a app chamou
-- `register_push_token` seis vezes no mesmo segundo, uma por papel da pessoa;
-- cinco deram 200 e a do papel `handyman` deu 400 com `INVALID_ROLE: handyman`.
--
-- CAUSA: a migração casa_01 (31/10) abriu o papel nos dois CHECK
--   user_roles.role            → aceita 'handyman'
--   provider_push_tokens.role  → aceita 'handyman'
-- e a Edge Function `notify-handyman` já lê `provider_push_tokens` com
-- role='handyman'. Faltou a terceira linha: a lista de papéis de prestador
-- dentro desta função, que ficou em ('cleaner','washer'). O nome que a app
-- manda está certo; quem estava atrás era a função.
-- A 14/11 havia 2 pessoas com o papel em user_roles e 0 aparelhos guardados:
-- o `notify-handyman` não tinha a quem tocar.
--
-- O QUE MUDA: uma linha — `IN ('cleaner', 'washer')` passa a
-- `IN ('cleaner', 'washer', 'handyman')`. O resto do corpo é, byte a byte, o
-- que estava em produção a 14/11 (pg_get_functiondef). Não mexe em tabelas,
-- em dados, nem em dinheiro.
--
-- Fechada a quem não entrou: só `authenticated` e `service_role` (como já
-- estava). A guarda é `auth.uid()`, nunca `current_user`.

CREATE OR REPLACE FUNCTION public.register_push_token(
  p_role text,
  p_fcm_token text,
  p_device_label text DEFAULT NULL::text,
  p_platform text DEFAULT NULL::text
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id  uuid := auth.uid();
  v_token_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  IF p_fcm_token IS NULL OR length(trim(p_fcm_token)) = 0 THEN
    RAISE EXCEPTION 'FCM_TOKEN_REQUIRED';
  END IF;

  IF p_platform IS NOT NULL AND p_platform NOT IN ('android','ios','web') THEN
    RAISE EXCEPTION 'INVALID_PLATFORM';
  END IF;

  IF p_role = 'client' THEN
    INSERT INTO public.client_push_tokens (user_id, fcm_token, device_label, platform)
    VALUES (v_user_id, p_fcm_token, p_device_label, p_platform)
    ON CONFLICT (user_id, fcm_token) DO UPDATE
      SET active       = true,
          fail_count   = 0,
          last_fail_at = NULL,
          updated_at   = now(),
          last_used_at = now(),
          device_label = COALESCE(EXCLUDED.device_label, client_push_tokens.device_label),
          platform     = COALESCE(EXCLUDED.platform,     client_push_tokens.platform)
    RETURNING id INTO v_token_id;

  ELSIF p_role = 'driver' THEN
    INSERT INTO public.driver_push_tokens (user_id, fcm_token, device_label, platform)
    VALUES (v_user_id, p_fcm_token, p_device_label, p_platform)
    ON CONFLICT (user_id, fcm_token) DO UPDATE
      SET active       = true,
          fail_count   = 0,
          last_fail_at = NULL,
          updated_at   = now(),
          last_used_at = now(),
          device_label = COALESCE(EXCLUDED.device_label, driver_push_tokens.device_label),
          platform     = COALESCE(EXCLUDED.platform,     driver_push_tokens.platform)
    RETURNING id INTO v_token_id;

  ELSIF p_role = 'partner' THEN
    INSERT INTO public.partner_push_tokens (partner_id, fcm_token, device_label, platform)
    VALUES (v_user_id, p_fcm_token, p_device_label, p_platform)
    ON CONFLICT (partner_id, fcm_token) DO UPDATE
      SET active       = true,
          fail_count   = 0,
          last_fail_at = NULL,
          updated_at   = now(),
          last_used_at = now(),
          device_label = COALESCE(EXCLUDED.device_label, partner_push_tokens.device_label),
          platform     = COALESCE(EXCLUDED.platform,     partner_push_tokens.platform)
    RETURNING id INTO v_token_id;

  -- Papéis de prestador. Acrescentar um papel novo aqui é UMA linha nesta
  -- lista mais uma no CHECK da tabela — não é tabela nova.
  -- [15/11/2026] 'handyman' (Casa e manutenção): o CHECK já o aceitava desde
  -- 31/10; faltava esta lista.
  ELSIF p_role IN ('cleaner', 'washer', 'handyman') THEN
    INSERT INTO public.provider_push_tokens (user_id, role, fcm_token, device_label, platform)
    VALUES (v_user_id, p_role, p_fcm_token, p_device_label, p_platform)
    ON CONFLICT (user_id, role, fcm_token) DO UPDATE
      SET active       = true,
          fail_count   = 0,
          last_fail_at = NULL,
          updated_at   = now(),
          last_used_at = now(),
          device_label = COALESCE(EXCLUDED.device_label, provider_push_tokens.device_label),
          platform     = COALESCE(EXCLUDED.platform,     provider_push_tokens.platform)
    RETURNING id INTO v_token_id;

  ELSE
    RAISE EXCEPTION 'INVALID_ROLE: %', p_role;
  END IF;

  RETURN v_token_id;
END;
$function$;

-- Os dois caminhos de permissão fecham-se à parte: PUBLIC e o grant direto a
-- `anon` que o Supabase dá a cada função nova do schema public.
REVOKE ALL ON FUNCTION public.register_push_token(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.register_push_token(text, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text, text, text, text) TO authenticated, service_role;

-- A migração recusa-se a ficar aplicada se a base não ficar como se promete.
DO $verifica$
BEGIN
  IF has_function_privilege('anon', 'public.register_push_token(text, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'register_push_token ficou aberta a anon';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.register_push_token(text, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'register_push_token ficou fechada a authenticated';
  END IF;
  -- Função e CHECK têm de andar juntos: se o CHECK da tabela não aceitar o
  -- papel, a função aceitava-o e o INSERT rebentava com outro erro.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
     WHERE c.conrelid = 'public.provider_push_tokens'::regclass
       AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) LIKE '%handyman%'
  ) THEN
    RAISE EXCEPTION 'o CHECK de provider_push_tokens.role não aceita handyman';
  END IF;
END
$verifica$;

-- ROLLBACK (voltar ao que estava a 14/11): repor a linha
--   ELSIF p_role IN ('cleaner', 'washer') THEN
-- com este mesmo CREATE OR REPLACE. Os aparelhos entretanto guardados com
-- role='handyman' ficam na tabela (o CHECK aceita-os) e não fazem mal.
