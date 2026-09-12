-- ============================================================================
-- PAINEL DOS PAPEIS — ver quem tem o que, dar, tirar, e as candidaturas
--
-- Nao existia para categoria nenhuma. Havia paineis por papel (estafetas,
-- faxineiros, lavadores), mas nenhum sitio onde o Danilo visse UMA pessoa e os
-- papeis todos dela, nem onde acrescentasse ou tirasse um papel a mao.
--
-- ── O que isto NAO faz, de proposito ───────────────────────────────────────
-- Nao decide candidaturas. Aprovar e recusar ja tem funcao propria por papel,
-- provada e com aviso ao candidato: `admin_approve_driver`,
-- `admin_reject_driver`, `admin_review_cleaner`, `admin_update_washer`. O
-- painel LISTA as candidaturas e CHAMA essas. Copiar a logica de aprovacao
-- para aqui criava gemeos numa decisao que manda avisos e muda estado.
--
-- Nao mexe em dinheiro nenhum.
--
-- ── A diferenca entre "ter o papel" e "estar aprovado" ─────────────────────
-- `user_roles` diz o que a pessoa PODE ser (e o que a RLS le). A tabela do
-- papel diz se ela esta aprovada para o exercer. Tirar o papel a mao nao
-- apaga a candidatura nem o historico — so lhe fecha a porta.
-- ============================================================================

-- ── 1. A lista: uma linha por pessoa, com os papeis todos ──────────────────
CREATE OR REPLACE FUNCTION public.admin_papeis_listar(
  p_busca text DEFAULT NULL,
  p_papel text DEFAULT NULL,
  p_limite integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out jsonb; v_busca text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  v_busca := NULLIF(trim(COALESCE(p_busca, '')), '');

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'nome'), '[]'::jsonb) INTO v_out
  FROM (
    SELECT jsonb_build_object(
      'user_id', ur.user_id,
      'email', u.email,
      'nome', COALESCE(
        (SELECT d.name FROM drivers  d WHERE d.user_id = ur.user_id LIMIT 1),
        (SELECT c.name FROM cleaners c WHERE c.user_id = ur.user_id LIMIT 1),
        (SELECT w.name FROM washers  w WHERE w.user_id = ur.user_id LIMIT 1),
        u.email, '(sem nome)'),
      'telefone', COALESCE(
        (SELECT d.phone FROM drivers  d WHERE d.user_id = ur.user_id LIMIT 1),
        (SELECT c.phone FROM cleaners c WHERE c.user_id = ur.user_id LIMIT 1),
        (SELECT w.phone FROM washers  w WHERE w.user_id = ur.user_id LIMIT 1), ''),
      'papeis', (SELECT jsonb_agg(r.role ORDER BY r.role)
                   FROM user_roles r WHERE r.user_id = ur.user_id),
      -- O estado da candidatura de cada papel de prestador, para se ver de
      -- relance quem tem o papel mas ainda nao esta aprovado.
      'estado_driver',  (SELECT d.approval_status FROM drivers  d WHERE d.user_id = ur.user_id LIMIT 1),
      'estado_cleaner', (SELECT c.approval_status FROM cleaners c WHERE c.user_id = ur.user_id LIMIT 1),
      'estado_washer',  (SELECT w.approval_status FROM washers  w WHERE w.user_id = ur.user_id LIMIT 1)
    ) AS x
    FROM (SELECT DISTINCT user_id FROM user_roles) ur
    LEFT JOIN auth.users u ON u.id = ur.user_id
    WHERE (p_papel IS NULL
           OR EXISTS (SELECT 1 FROM user_roles r
                       WHERE r.user_id = ur.user_id AND r.role = p_papel))
      AND (v_busca IS NULL
           OR u.email ILIKE '%' || v_busca || '%'
           OR EXISTS (SELECT 1 FROM drivers  d WHERE d.user_id = ur.user_id AND d.name ILIKE '%' || v_busca || '%')
           OR EXISTS (SELECT 1 FROM cleaners c WHERE c.user_id = ur.user_id AND c.name ILIKE '%' || v_busca || '%')
           OR EXISTS (SELECT 1 FROM washers  w WHERE w.user_id = ur.user_id AND w.name ILIKE '%' || v_busca || '%'))
    LIMIT GREATEST(COALESCE(p_limite, 100), 1)
  ) t;

  RETURN jsonb_build_object(
    'ok', true,
    'papeis_possiveis', jsonb_build_array('client','driver','delivery','partner','cleaner','washer','admin'),
    'itens', v_out);
END $function$;

REVOKE ALL ON FUNCTION public.admin_papeis_listar(text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_papeis_listar(text, text, integer) TO authenticated;


-- ── 2. Dar um papel a mao ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_papel_dar(p_user_id uuid, p_papel text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF p_user_id IS NULL OR NULLIF(trim(COALESCE(p_papel,'')),'') IS NULL THEN
    RAISE EXCEPTION 'faltam_argumentos';
  END IF;
  -- O CHECK da tabela e que manda no que e papel valido. Nao se repete aqui a
  -- lista: duas listas divergem, e foi assim que o `washer` ficou de fora.
  INSERT INTO public.user_roles (user_id, role)
  VALUES (p_user_id, p_papel)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM public.log_admin_action('papel_dar', 'pessoa', p_user_id::text,
    jsonb_build_object('papel', p_papel, 'linhas', n));
  RETURN jsonb_build_object('ok', true, 'novo', n > 0);
END $function$;

REVOKE ALL ON FUNCTION public.admin_papel_dar(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_papel_dar(uuid, text) TO authenticated;


-- ── 3. Tirar um papel a mao ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_papel_tirar(p_user_id uuid, p_papel text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  -- Tirar o papel a alguem com trabalho em curso deixa o cliente pendurado.
  IF p_papel = 'cleaner' AND EXISTS (
     SELECT 1 FROM cleaning_bookings b
      JOIN cleaners c ON c.id = b.cleaner_id
     WHERE c.user_id = p_user_id
       AND b.status IN ('accepted','on_the_way','in_progress')) THEN
    RAISE EXCEPTION 'tem_trabalho_em_curso';
  END IF;
  IF p_papel = 'washer' AND EXISTS (
     SELECT 1 FROM carwash_bookings b
      JOIN washers w ON w.id = b.washer_id
     WHERE w.user_id = p_user_id
       AND b.status IN ('accepted','on_the_way','picked_up','in_progress','delivering')) THEN
    RAISE EXCEPTION 'tem_trabalho_em_curso';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = p_user_id AND role = p_papel;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM public.log_admin_action('papel_tirar', 'pessoa', p_user_id::text,
    jsonb_build_object('papel', p_papel, 'linhas', n));
  RETURN jsonb_build_object('ok', true, 'removido', n > 0);
END $function$;

REVOKE ALL ON FUNCTION public.admin_papel_tirar(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_papel_tirar(uuid, text) TO authenticated;


-- ── 4. As candidaturas, dos tres papeis, num sitio so ──────────────────────
CREATE OR REPLACE FUNCTION public.admin_candidaturas_listar(
  p_estado text DEFAULT 'pending'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'criada_em' DESC), '[]'::jsonb) INTO v_out
  FROM (
    SELECT jsonb_build_object(
      'tipo', 'driver', 'id', d.id, 'user_id', d.user_id, 'nome', d.name,
      'telefone', d.phone, 'email', d.email, 'estado', d.approval_status,
      'criada_em', d.created_at, 'motivo', NULL) AS x
    FROM drivers d
    WHERE p_estado IS NULL OR d.approval_status = p_estado
    UNION ALL
    SELECT jsonb_build_object(
      'tipo', 'cleaner', 'id', c.id, 'user_id', c.user_id, 'nome', c.name,
      'telefone', c.phone, 'email', c.email, 'estado', c.approval_status,
      'criada_em', c.created_at, 'motivo', c.rejection_reason)
    FROM cleaners c
    WHERE p_estado IS NULL OR c.approval_status = p_estado
    UNION ALL
    SELECT jsonb_build_object(
      'tipo', 'washer', 'id', w.id, 'user_id', w.user_id, 'nome', w.name,
      'telefone', w.phone, 'email', w.email, 'estado', w.approval_status,
      'criada_em', w.created_at, 'motivo', w.rejection_reason)
    FROM washers w
    WHERE p_estado IS NULL OR w.approval_status = p_estado
  ) t;

  RETURN jsonb_build_object('ok', true, 'estado', p_estado, 'itens', v_out);
END $function$;

REVOKE ALL ON FUNCTION public.admin_candidaturas_listar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_candidaturas_listar(text) TO authenticated;


-- ── 5. Decidir uma candidatura de LAVADOR ──────────────────────────────────
-- Os outros dois papeis ja tem porta propria: `admin_approve_driver` /
-- `admin_reject_driver` e `admin_review_cleaner`. O lavador so tinha o
-- `admin_update_washer(p_id, p_patch)`, que e generico. Esta funcao e uma
-- fachada fina sobre ele — mesma escrita, um nome que diz o que faz — para o
-- painel nao ter de montar o patch a mao em cada sitio.
CREATE OR REPLACE FUNCTION public.admin_rever_lavador(
  p_washer_id uuid,
  p_accao text,
  p_motivo text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_estado text;
BEGIN
  v_estado := CASE p_accao
    WHEN 'approve'    THEN 'approved'
    WHEN 'reject'     THEN 'rejected'
    WHEN 'suspend'    THEN 'suspended'
    WHEN 'reactivate' THEN 'approved'
    ELSE NULL END;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'invalid_action'; END IF;

  -- O guarda de admin e o de trabalho em curso vivem la dentro.
  RETURN public.admin_update_washer(p_washer_id, jsonb_build_object(
    'approval_status', v_estado,
    'rejection_reason', CASE WHEN v_estado IN ('rejected','suspended')
                             THEN NULLIF(p_motivo,'') ELSE NULL END));
END $function$;

REVOKE ALL ON FUNCTION public.admin_rever_lavador(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_rever_lavador(uuid, text, text) TO authenticated;
