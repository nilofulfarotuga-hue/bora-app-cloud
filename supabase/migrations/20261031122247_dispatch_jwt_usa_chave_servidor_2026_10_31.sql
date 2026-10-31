-- 31/10/2026 (Claude.ai via MCP, autorizado pelo Danilo 12:19) — AVISO AO PASSAGEIRO TVDE NUNCA CHEGAVA.
-- _dispatch_jwt() devolvia a chave ANÓNIMA (vault dispatch_anon_jwt). Desde a troca de chaves (16/10),
-- as Edge Functions (_shared/chaves.ts) recusam um bearer anónimo com 401 — notify-tvde-client deu
-- 401 em 10/10 chamadas nas últimas 24 h (passageiro sem "motorista a caminho"). Chamadores afectados:
-- fn_notify_tvde_client_on_status, fn_notify_tvde_driver_on_offer, tvde_add_stop, tvde_reservation_push,
-- _tvde_dest_change_apply, admin_tvde_dest_change_counter, tvde_reservations_sweep.
-- Correção: _dispatch_jwt() passa a devolver a chave de SERVIDOR (a mesma que notify_admin_urgent_push
-- e as outras 70 rotinas já usam com sucesso), com a anónima só como último recurso.
CREATE OR REPLACE FUNCTION public._dispatch_jwt()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
DECLARE
  v_jwt text;
BEGIN
  v_jwt := nullif(public._service_role_key(), '');
  IF v_jwt IS NOT NULL THEN
    RETURN v_jwt;
  END IF;
  SELECT decrypted_secret INTO v_jwt
  FROM vault.decrypted_secrets
  WHERE name = 'dispatch_anon_jwt';
  IF v_jwt IS NULL THEN
    RAISE EXCEPTION 'dispatch_jwt_not_in_vault: run vault.create_secret first';
  END IF;
  RETURN v_jwt;
END;
$function$;;
