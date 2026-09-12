-- 2026-09-07 — cicatriz da identidade (PADRAO_BORA 1.9).
-- A tabela do estafeta aponta ora para a PESSOA (drivers.user_id) ora para a
-- LINHA (drivers.id); as da limpeza, lavagem e servicos apontam para a linha.
-- Juntar por identificador as cegas manda o comprovativo de um a outro. Esta
-- funcao resolve isso num so sitio, para nunca mais se resolver a olho.
CREATE OR REPLACE FUNCTION public.settlement_subject_user_id(p_type text, p_subject_id text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v uuid;
BEGIN
  IF p_type = 'driver' THEN
    SELECT d.user_id INTO v FROM drivers d
     WHERE d.id::text = p_subject_id OR d.user_id::text = p_subject_id LIMIT 1;
  ELSIF p_type = 'partner' THEN
    SELECT COALESCE(r.user_id, r.user_) INTO v FROM restaurants r
     WHERE r.id::text = p_subject_id OR r.user_id::text = p_subject_id LIMIT 1;
  ELSIF p_type = 'cleaner' THEN
    SELECT c.user_id INTO v FROM cleaners c
     WHERE c.id::text = p_subject_id OR c.user_id::text = p_subject_id LIMIT 1;
  ELSIF p_type = 'washer' THEN
    SELECT wa.user_id INTO v FROM washers wa
     WHERE wa.id::text = p_subject_id OR wa.user_id::text = p_subject_id LIMIT 1;
  ELSIF p_type = 'provider' THEN
    SELECT sp.user_id INTO v FROM service_providers sp
     WHERE sp.id::text = p_subject_id OR sp.user_id::text = p_subject_id LIMIT 1;
  END IF;
  RETURN v;
END $function$;

REVOKE ALL ON FUNCTION public.settlement_subject_user_id(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.settlement_subject_user_id(text,text) TO service_role;;
