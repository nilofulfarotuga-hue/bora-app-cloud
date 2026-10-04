-- [ronda 04/10 · app-estafeta #7] Prova de entrega com foto (padrão Uber
-- Eats/Glovo "deixar à porta"). As colunas orders.deixar_a_porta,
-- orders.foto_entrega_url e orders.foto_entrega_em já existiam mas nada as
-- usava. A app do estafeta:
--   1. pergunta `estafeta_entrega_precisa_foto(pedido)` → mostra "Deixar à
--      porta" no cartão e, se for preciso, pede a foto no botão de entregar;
--   2. sobe a foto pela Edge Function `upload-order-photo` (bucket
--      order-photos, pasta = id do estafeta);
--   3. grava-a com `estafeta_registar_foto_entrega(pedido, url)`.
-- A foto é exigida quando o cliente pediu "deixar à porta" OU quando
-- platform_settings.foto_entrega_obrigatoria = true (hoje false).
-- Só o estafeta atribuído ao pedido (user_id) pode ler/gravar; a URL tem de ser
-- da pasta dele no bucket order-photos (não se aceita link de fora).

CREATE OR REPLACE FUNCTION public.estafeta_entrega_precisa_foto(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.orders%ROWTYPE;
  v_global boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF COALESCE(v_o.assigned_driver_id, '') <> v_uid::text AND NOT public.is_admin() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT COALESCE((value #>> '{}')::boolean, false) INTO v_global
    FROM public.platform_settings WHERE key = 'foto_entrega_obrigatoria';
  RETURN jsonb_build_object(
    'ok', true,
    'deixar_a_porta', COALESCE(v_o.deixar_a_porta, false),
    'exigida', COALESCE(v_o.deixar_a_porta, false) OR COALESCE(v_global, false),
    'ja_tem_foto', v_o.foto_entrega_url IS NOT NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.estafeta_registar_foto_entrega(p_order_id text, p_foto_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.orders%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_o FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF COALESCE(v_o.assigned_driver_id, '') <> v_uid::text THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF v_o.status NOT IN ('pickedUp', 'onTheWay', 'delivered') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_invalido');
  END IF;
  IF p_foto_url IS NULL
     OR position(('/storage/v1/object/public/order-photos/' || v_uid::text || '/') IN p_foto_url) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'url_invalida');
  END IF;
  UPDATE public.orders
     SET foto_entrega_url = p_foto_url,
         foto_entrega_em  = now()
   WHERE id = p_order_id;
  RETURN jsonb_build_object('ok', true, 'foto_entrega_em', now());
END $function$;

REVOKE ALL ON FUNCTION public.estafeta_entrega_precisa_foto(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_entrega_precisa_foto(text) TO authenticated;
REVOKE ALL ON FUNCTION public.estafeta_registar_foto_entrega(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.estafeta_registar_foto_entrega(text, text) TO authenticated;
