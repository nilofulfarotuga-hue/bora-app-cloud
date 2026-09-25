-- Painel admin — estado de recuperação de palavra-passe de um utilizador.
--
-- O painel precisa de mostrar ao Danilo quando foi o último email de
-- recuperação enviado, para ele saber se o cliente já pediu antes de disparar
-- outro. Esse dado vive em auth.users.recovery_sent_at, que o cliente Flutter
-- não pode ler directamente — daí SECURITY DEFINER com a guarda de admin
-- normal (_admin_op_guard, a mesma de admin_ban_client/admin_unban_client).
--
-- Só LÊ. O envio em si é feito pela Edge Fn support-password-reset, que é
-- quem regista em admin_audit_log ('password_reset_sent').

CREATE OR REPLACE FUNCTION public.admin_auth_recovery_status(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
  v_user  RECORD;
  v_last_admin_send timestamptz;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  SELECT id, email, recovery_sent_at, last_sign_in_at, email_confirmed_at
    INTO v_user
    FROM auth.users
   WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;

  -- Último envio disparado a partir do painel (distinto de recovery_sent_at,
  -- que também sobe quando é o próprio utilizador a pedir na app).
  SELECT max(created_at) INTO v_last_admin_send
    FROM public.admin_audit_log
   WHERE action = 'password_reset_sent'
     AND entity_id = p_user_id
     AND COALESCE((details->>'ok')::boolean, true);

  RETURN jsonb_build_object(
    'user_id',            v_user.id,
    'email',              v_user.email,
    'recovery_sent_at',   v_user.recovery_sent_at,
    'last_sign_in_at',    v_user.last_sign_in_at,
    'email_confirmed_at', v_user.email_confirmed_at,
    'last_admin_send_at', v_last_admin_send
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_auth_recovery_status(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_auth_recovery_status(uuid) TO authenticated;

COMMENT ON FUNCTION public.admin_auth_recovery_status(uuid) IS
  'Painel admin: estado de recuperação de palavra-passe (recovery_sent_at) de um utilizador. Read-only, guardado por _admin_op_guard.';
