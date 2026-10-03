-- ============================================================================
-- TOKENS DE NOTIFICAÇÃO PARA FAXINEIRO E LAVADOR
--
-- O buraco: `register_push_token` só sabia escrever em três tabelas —
-- client_push_tokens, driver_push_tokens e partner_push_tokens. Qualquer
-- outro papel levava com INVALID_ROLE. E as tabelas `cleaners` e `washers`
-- não têm sequer coluna `fcm_token`, ao contrário de `drivers`.
--
-- Resultado, medido a 2026-08-28: a limpeza está no ar e **nunca conseguiu
-- chamar ninguém**. Não havia caminho — nem o novo (tabela de tokens) nem o
-- antigo (coluna na tabela do papel). Sem token guardado não há push, e sem
-- push não há aviso persistente que valha.
--
-- Porque UMA tabela e não duas: acrescentar `cleaner_push_tokens` e
-- `washer_push_tokens` seria repetir exactamente o padrão que criou este
-- problema — cada papel novo obrigava a nova tabela, novas políticas, novo
-- ramo na RPC e nova consulta em cada Edge Function. Aqui o papel é uma
-- COLUNA. O próximo papel não precisa de migration nenhuma do lado da
-- tabela; precisa só de ser aceite na RPC, que é uma linha.
--
-- As três tabelas antigas ficam onde estão. Estão em uso, têm 293 tokens
-- reais entre elas e são lidas por Edge Functions em produção — mexer nelas
-- era risco sem retorno.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.provider_push_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- O papel a que este aparelho responde. A mesma pessoa no mesmo telemóvel
  -- pode ter uma linha por papel: é assim que se toca a um faxineiro que
  -- está no ecrã de motorista.
  role          text NOT NULL CHECK (role IN ('cleaner', 'washer')),
  fcm_token     text NOT NULL,
  device_label  text,
  platform      text CHECK (platform IN ('android', 'ios', 'web')),
  active        boolean NOT NULL DEFAULT true,
  fail_count    smallint NOT NULL DEFAULT 0,
  last_fail_at  timestamptz,
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  -- Multi-aparelho: uma linha por (pessoa, papel, aparelho). Re-registar
  -- nunca apaga o telemóvel antigo — a pessoa pode ter dois.
  CONSTRAINT provider_push_tokens_unicos UNIQUE (user_id, role, fcm_token)
);

-- Índice de envio: "dá-me os aparelhos activos deste faxineiro".
CREATE INDEX IF NOT EXISTS provider_push_tokens_envio_idx
  ON public.provider_push_tokens (user_id, role)
  WHERE active;

ALTER TABLE public.provider_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS provider_own_tokens ON public.provider_push_tokens;
CREATE POLICY provider_own_tokens ON public.provider_push_tokens
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS service_role_all_provider_tokens ON public.provider_push_tokens;
CREATE POLICY service_role_all_provider_tokens ON public.provider_push_tokens
  FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE public.provider_push_tokens IS
  'Tokens FCM dos papéis de prestador (faxineiro, lavador). O papel é coluna, '
  'não tabela: papel novo não precisa de migration. As tabelas client_/driver_/'
  'partner_push_tokens ficam como estão — em uso e em produção.';


-- ── A RPC passa a aceitar os papéis novos ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.register_push_token(
  p_role         text,
  p_fcm_token    text,
  p_device_label text DEFAULT NULL,
  p_platform     text DEFAULT NULL
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
  ELSIF p_role IN ('cleaner', 'washer') THEN
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


-- ── Quem me deve ser chamado: os papéis desta pessoa ────────────────────────
-- Serve o cliente (para registar o aparelho em TODOS os papéis que a pessoa
-- tem, e não só no que estiver no metadata) e as Edge Functions.
--
-- Lê de `user_roles`, que é a única fonte que já aguenta acumulação — o
-- `bora_role` do metadata guarda UM valor só e por isso nunca poderia
-- descrever quem é motorista e faxineiro ao mesmo tempo.
CREATE OR REPLACE FUNCTION public.meus_papeis()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    array_agg(DISTINCT ur.role ORDER BY ur.role)
      FILTER (WHERE ur.role IS NOT NULL),
    ARRAY[]::text[]
  )
  FROM public.user_roles ur
  WHERE ur.user_id = auth.uid();
$function$;

REVOKE ALL ON FUNCTION public.meus_papeis() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.meus_papeis() TO authenticated;

COMMENT ON FUNCTION public.meus_papeis() IS
  'Todos os papéis do utilizador autenticado, de user_roles. O bora_role do '
  'metadata guarda um valor só e não serve para quem acumula papéis.';
