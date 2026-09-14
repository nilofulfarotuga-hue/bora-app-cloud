-- 2026-09-14 — correcao a quente da migration anterior (aplicada em producao
-- 46 segundos depois): o CASE com NEW.partner_id / NEW.cleaner_id era validado
-- em TODAS as tabelas e rebentava com "record new has no field partner_id" —
-- o que travaria todos os inserts de acerto, reais incluidos, mesmo antes do
-- cron das 01:05. Le-se o campo pelo nome, via to_jsonb(NEW).
--
-- Prova depois de aplicar (01:47 UTC-1): recalculo do estafeta demo devolve
-- settlement_id = null (linha nao entra) e grava 'acerto_demo_ignorado' no
-- historico; recalculo do Danilo mantem 1,10 na mesma linha a28d6ad1.
CREATE OR REPLACE FUNCTION public._acerto_ignora_demo()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_type text := TG_ARGV[0];
  v_col  text;
  v_id   text;
  v_row  jsonb := to_jsonb(NEW);
BEGIN
  v_col := CASE v_type
    WHEN 'driver'   THEN 'driver_id'
    WHEN 'partner'  THEN 'partner_id'
    WHEN 'provider' THEN 'provider_id'
    WHEN 'cleaner'  THEN 'cleaner_id'
    WHEN 'washer'   THEN 'washer_id'
  END;
  v_id := v_row ->> v_col;
  IF v_id IS NOT NULL AND public.is_demo_subject(v_type, v_id) THEN
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('acerto_demo_ignorado', 'settlement', v_id,
            jsonb_build_object('tipo', v_type, 'week_start_at', v_row ->> 'week_start_at', 'tabela', TG_TABLE_NAME));
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;
