-- PROPOSTA — NÃO APLICADA (o classificador recusou a 01/11/2026; ver docs/TRANCAS.md).
-- Missão app-fechar-2026-11-01 · B8 suspensão e revisão humana (Diretiva UE 2024/2831).
-- Falhas encontradas pelo caminho, depois do gatilho trg_suspensao_so_com_humano (01/11):
--
-- 1) admin_set_user_role (painel → "papéis da pessoa") desligava limpeza/lavagem com
--    approval_status='suspended' sem pôr o motivo na linha nem na variável de sessão: o
--    gatilho recusava com SUSPENSAO_SEM_MOTIVO e o botão partia. Agora exige 10 letras ao
--    desligar, passa o motivo por bora.motivo_suspensao e grava-o em rejection_reason.
-- 2) Reativar por botões antigos (admin_reactivate_driver, admin_review_cleaner, lavagem,
--    is_active_admin=true, Casa) deixava o registo em prestador_suspensoes como 'ativa'.
--    Gatilho AFTER UPDATE nas 6 tabelas: quando a conta volta a ativa, o registo aberto
--    passa a 'revertida' (admin_reativar_prestador e a manutenção já o fazem por si; aqui
--    não encontram nada aberto ou sobrepõem depois).
-- Não mexe em valores nem em dinheiro.

CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_user_id uuid, p_papel text, p_ativo boolean, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_antes  text;
  v_depois text;
  v_aprovado_antes boolean;
  v_pid uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  IF length(trim(COALESCE(p_motivo, ''))) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_obrigatorio');
  END IF;
  -- 01/11/2026: desligar um papel é suspender — o prestador tem direito ao motivo por escrito.
  IF NOT p_ativo AND length(trim(COALESCE(p_motivo, ''))) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_obrigatorio', 'minimo', 10);
  END IF;
  IF p_papel NOT IN ('estafeta','limpeza','lavagem') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'papel_invalido');
  END IF;
  IF NOT p_ativo THEN
    PERFORM set_config('bora.motivo_suspensao', trim(p_motivo), true);
  END IF;

  IF p_papel = 'estafeta' THEN
    SELECT approval_status, approved_at IS NOT NULL INTO v_antes, v_aprovado_antes
      FROM drivers WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_perfil'); END IF;
    IF p_ativo THEN
      IF v_antes = 'approved' THEN
        v_depois := v_antes;
      ELSIF v_antes = 'rejected' AND v_aprovado_antes THEN
        UPDATE drivers SET approval_status = 'approved' WHERE user_id = p_user_id;
        v_depois := 'approved';
      ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'usa_aprovacao_normal', 'estado', v_antes);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM orders o WHERE o.assigned_driver_id = p_user_id::text
                   AND o.status IN ('driverAccepted','pickedUp','onTheWay')) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'trabalho_em_curso');
      END IF;
      IF v_antes = 'approved' THEN
        UPDATE drivers SET approval_status = 'rejected', is_online = false WHERE user_id = p_user_id;
      END IF;
      v_depois := CASE WHEN v_antes = 'approved' THEN 'rejected' ELSE v_antes END;
    END IF;

  ELSIF p_papel = 'limpeza' THEN
    SELECT id, approval_status INTO v_pid, v_antes FROM cleaners WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_perfil'); END IF;
    IF p_ativo THEN
      IF v_antes = 'approved' THEN
        v_depois := v_antes;
      ELSIF v_antes = 'suspended' THEN
        UPDATE cleaners SET approval_status = 'approved' WHERE id = v_pid;
        v_depois := 'approved';
      ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'usa_aprovacao_normal', 'estado', v_antes);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM cleaning_bookings b WHERE b.cleaner_id = v_pid
                   AND b.status IN ('on_the_way','in_progress')) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'trabalho_em_curso');
      END IF;
      IF v_antes = 'approved' THEN
        UPDATE cleaners SET approval_status = 'suspended', rejection_reason = trim(p_motivo) WHERE id = v_pid;
      END IF;
      v_depois := CASE WHEN v_antes = 'approved' THEN 'suspended' ELSE v_antes END;
    END IF;

  ELSE -- lavagem
    SELECT id, approval_status INTO v_pid, v_antes FROM washers WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'sem_perfil'); END IF;
    IF p_ativo THEN
      IF v_antes = 'approved' THEN
        v_depois := v_antes;
      ELSIF v_antes = 'suspended' THEN
        UPDATE washers SET approval_status = 'approved' WHERE id = v_pid;
        v_depois := 'approved';
      ELSE
        RETURN jsonb_build_object('ok', false, 'error', 'usa_aprovacao_normal', 'estado', v_antes);
      END IF;
    ELSE
      IF EXISTS (SELECT 1 FROM carwash_bookings b WHERE b.washer_id = v_pid
                   AND b.status IN ('on_the_way','picked_up','in_progress','delivering')) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'trabalho_em_curso');
      END IF;
      IF v_antes = 'approved' THEN
        UPDATE washers SET approval_status = 'suspended', rejection_reason = trim(p_motivo) WHERE id = v_pid;
      END IF;
      v_depois := CASE WHEN v_antes = 'approved' THEN 'suspended' ELSE v_antes END;
    END IF;
  END IF;

  PERFORM public.log_admin_action(
    CASE WHEN p_ativo THEN 'papel_ligado' ELSE 'papel_desligado' END,
    'user', p_user_id,
    jsonb_build_object('papel', p_papel, 'motivo', trim(p_motivo), 'antes', v_antes, 'depois', v_depois));

  RETURN jsonb_build_object('ok', true, 'papel', p_papel, 'antes', v_antes, 'depois', v_depois);
END $function$;

CREATE OR REPLACE FUNCTION public.fn_suspensao_fecha_ao_reativar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_old jsonb := to_jsonb(OLD);
  v_new jsonb := to_jsonb(NEW);
  v_volta boolean := false;
BEGIN
  IF COALESCE((v_old->>'is_banned')::boolean, false) AND NOT COALESCE((v_new->>'is_banned')::boolean, false) THEN
    v_volta := true;
  ELSIF TG_TABLE_NAME = 'drivers' AND (v_old->>'deleted_at') IS NOT NULL AND (v_new->>'deleted_at') IS NULL THEN
    v_volta := true;
  ELSIF (v_old->>'approval_status') IN ('suspended','banned','rejected') AND (v_new->>'approval_status') = 'approved' THEN
    v_volta := true;
  ELSIF TG_TABLE_NAME IN ('restaurants','service_providers')
        AND NOT COALESCE((v_old->>'is_active_admin')::boolean, true)
        AND COALESCE((v_new->>'is_active_admin')::boolean, true) THEN
    v_volta := true;
  END IF;
  IF NOT v_volta THEN RETURN NULL; END IF;

  UPDATE public.prestador_suspensoes
     SET estado = 'revertida', reativado_em = now(), reativado_por = auth.uid(),
         reativacao_nota = COALESCE(reativacao_nota, 'Reativado por outra rota do painel')
   WHERE entidade_tabela = TG_TABLE_NAME AND entidade_id = v_new->>'id'
     AND estado IN ('ativa','em_revisao','mantida','reduzida');
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.fn_suspensao_fecha_ao_reativar() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['drivers','cleaners','washers','casa_profissionais','restaurants','service_providers'] LOOP
    EXECUTE format('CREATE OR REPLACE TRIGGER trg_suspensao_fecha_ao_reativar AFTER UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_suspensao_fecha_ao_reativar()', t);
  END LOOP;
END $$;
