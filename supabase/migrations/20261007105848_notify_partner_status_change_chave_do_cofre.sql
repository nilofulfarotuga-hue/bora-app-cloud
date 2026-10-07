-- [Auditoria 3 plataformas · 07/10/2026] _notify_partner_status_change nunca avisava o
-- parceiro. Chamada por admin_set_partner_override, admin_clear_partner_override e
-- admin_update_partner_hours (o admin força a loja aberta/fechada ou muda o horário).
-- Dois defeitos: (1) `extensions.net.http_post` é lido pelo Postgres como referência a
-- outra base de dados — erro engolido pelo EXCEPTION, nenhum pedido enfileirado;
-- (2) mandava a chave ANÓNIMA, e o notify-partner só aceita service_role, o dono da loja
-- ou um admin (403 forbidden). Passa a ler o endereço e a chave de serviço do cofre, como
-- _order_edit_http. Provado em transacção desfeita antes de aplicar: antiga 0 pedidos,
-- nova 1 pedido com role=service_role e o corpo certo.
CREATE OR REPLACE FUNCTION public._notify_partner_status_change(p_restaurant_id text, p_title text, p_body text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_token text; v_url text; v_key text;
BEGIN
  SELECT fcm_token INTO v_token FROM public.restaurants WHERE id = p_restaurant_id;
  IF v_token IS NULL OR v_token = '' THEN RETURN; END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE WARNING '_notify_partner_status_change: segredos em falta, aviso nao enviado'; RETURN;
  END IF;
  PERFORM net.http_post(
    url := v_url || '/functions/v1/notify-partner',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
    body := jsonb_build_object('restaurant_id', p_restaurant_id, 'title', p_title, 'body', p_body, 'kind', 'status_change'));
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_notify_partner_status_change: %', SQLERRM;
END;
$fn$;

REVOKE ALL ON FUNCTION public._notify_partner_status_change(text,text,text) FROM PUBLIC, anon, authenticated;
