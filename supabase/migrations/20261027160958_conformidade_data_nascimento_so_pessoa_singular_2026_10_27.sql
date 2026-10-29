-- 27/10/2026 (Claude.ai). _conformidade_em_falta pedia data de nascimento também a EMPRESAS.
-- No DAC7 (Lei 36/2023) a data de nascimento é só de pessoa singular; NIF de pessoa coletiva
-- começa por 5, 6, 7 ou 9. Resto igual.
CREATE OR REPLACE FUNCTION public._conformidade_em_falta(p_row jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY(
    SELECT x FROM unnest(ARRAY[
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'legal_name', p_row->>'name', '')), '') IS NULL THEN 'nome' END,
      CASE WHEN regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[0-9]{9}$' THEN 'nif' END,
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'address', p_row->>'base_address', '')), '') IS NULL THEN 'morada' END,
      CASE WHEN upper(regexp_replace(COALESCE(p_row->>'iban', ''), '\s', '', 'g')) !~ '^PT[0-9]{23}$' THEN 'iban' END,
      CASE WHEN NULLIF(p_row->>'birth_date', '') IS NULL
            AND regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[5679][0-9]{8}$'
           THEN 'data_nascimento' END,
      CASE WHEN NULLIF(p_row->>'dsa_self_certified_at', '') IS NULL THEN 'autocertificacao' END
    ]) AS x WHERE x IS NOT NULL);
$function$;

-- Portão novo: loja PARCEIRA aprovada que ABRE ao público (coming_soon passa a false) ou é criada
-- já aberta tem de ter os dados do DAC7. Antes só se verificava quando approval_status passava a
-- 'approved' — a Boom! Burger (criada já aprovada, em "Em breve") abriria sem NIF/IBAN.
-- Só is_partner = true; mesmo interruptor e mesma saída de emergência do portão antigo.
CREATE OR REPLACE FUNCTION public.fn_conformidade_abrir_loja_parceira()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_falta text[];
  v_obrig boolean := COALESCE((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);
  v_abre  boolean;
BEGIN
  IF NOT COALESCE(NEW.is_partner, false)
     OR NEW.approval_status IS DISTINCT FROM 'approved'
     OR COALESCE(NEW.coming_soon, false) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    v_abre := true;
  ELSE
    v_abre := COALESCE(OLD.coming_soon, false) AND NOT COALESCE(NEW.coming_soon, false);
  END IF;
  IF NOT v_abre THEN
    RETURN NEW;
  END IF;
  v_falta := public._conformidade_em_falta(to_jsonb(NEW));
  IF array_length(v_falta, 1) > 0 THEN
    IF v_obrig AND COALESCE(current_setting('bora.forcar_ativacao', true), '') <> '1' THEN
      RAISE EXCEPTION 'conformidade_incompleta: faltam %', array_to_string(v_falta, ', ')
        USING HINT = 'Antes de abrir a loja parceira ao público: nome legal, NIF, morada, IBAN, data de nascimento (só pessoa singular) e autocertificação (DAC7, Lei 36/2023).';
    ELSE
      RAISE NOTICE 'conformidade_incompleta (nao bloqueante): restaurants % faltam %', NEW.id, array_to_string(v_falta, ', ');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE TRIGGER trg_conformidade_abrir_loja_parceira
  BEFORE INSERT OR UPDATE OF coming_soon ON public.restaurants
  FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_abrir_loja_parceira();
