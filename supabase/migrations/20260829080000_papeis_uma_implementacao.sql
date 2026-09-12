-- ============================================================================
-- OS PAPEIS TEM UMA IMPLEMENTACAO SO
--
-- Ficaram dois conjuntos de funcoes a fazer o mesmo: as antigas
-- (`admin_add_user_role`, `admin_remove_user_role`) e as que eu criei a 28/08
-- (`admin_papel_dar`, `admin_papel_tirar`). Gemeos, e ja divergiram:
--
--   `admin_add_user_role` tem a lista de papeis CRAVADA no corpo —
--   ('client','driver','partner','cleaner','admin') — e por isso **recusa
--   `delivery` e `washer`**, que existem em `user_roles` desde 28/08. Quem
--   tentasse dar o papel de lavador pelo painel levava "papel invalido".
--
-- A correccao nao e escolher um nome: e ter uma implementacao. As funcoes
-- antigas ficam com o nome (ha codigo que as chama) e passam a delegar nas
-- novas, que leem a lista do CHECK da propria tabela e travam a remocao de
-- quem tem trabalho a decorrer.
--
-- Nao mexe em dinheiro.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_add_user_role(p_user_id uuid, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Sem lista propria: quem manda no que e papel valido e o CHECK da tabela.
  -- Duas listas divergem, e foi assim que `washer` ficou de fora desta.
  RETURN public.admin_papel_dar(p_user_id, p_role);
END $function$;

CREATE OR REPLACE FUNCTION public.admin_remove_user_role(p_user_id uuid, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_restantes int; v_out jsonb;
BEGIN
  v_out := public.admin_papel_tirar(p_user_id, p_role);

  SELECT count(*) INTO v_restantes
    FROM public.user_roles WHERE user_id = p_user_id;
  IF v_restantes = 0 THEN
    RAISE EXCEPTION 'nao da para tirar o ultimo papel do utilizador';
  END IF;

  -- `users.role` tem de continuar a apontar para um papel que ele ainda tem.
  UPDATE public.users u SET role = (
    SELECT ur.role FROM public.user_roles ur
     WHERE ur.user_id = p_user_id ORDER BY ur.created_at LIMIT 1)
   WHERE u.id = p_user_id AND u.role = p_role;

  RETURN v_out;
END $function$;


-- ── O estado de aprovacao de CADA papel, nao so de dois ────────────────────
-- Faltavam a lavagem e o parceiro. Um painel que mostra o estado de dois dos
-- cinco papeis diz mais ou menos a verdade, que e a pior maneira de a dizer.
CREATE OR REPLACE FUNCTION public.admin_user_role_flags(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN jsonb_build_object(
    'papeis', COALESCE((SELECT jsonb_agg(ur.role ORDER BY ur.role)
                          FROM user_roles ur WHERE ur.user_id = p_user_id), '[]'::jsonb),
    'driver_status',  (SELECT approval_status FROM drivers  WHERE user_id = p_user_id LIMIT 1),
    'cleaner_status', (SELECT approval_status FROM cleaners WHERE user_id = p_user_id LIMIT 1),
    'washer_status',  (SELECT approval_status FROM washers  WHERE user_id = p_user_id LIMIT 1),
    'partner_status', COALESCE(
        (SELECT r.approval_status FROM restaurants r
          WHERE COALESCE(r.user_id, r.user_) = p_user_id LIMIT 1),
        (SELECT sp.approval_status FROM service_providers sp
          WHERE sp.user_id = p_user_id LIMIT 1))
  );
END $function$;
