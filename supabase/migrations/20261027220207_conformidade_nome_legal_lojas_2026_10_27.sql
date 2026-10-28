-- 27/10/2026 (Claude.ai; reportado pela sessão Boom Burger no F3). _conformidade_em_falta aceitava o
-- campo "name" como nome legal. Numa loja ou prestador de serviços (linhas com business_hours) o "name" é
-- o nome comercial ("Boom! Burger"), não o nome legal que o DAC7 pede. Aí passa a exigir legal_name.
-- Estafetas, limpeza e lavagem (pessoas) continuam a aceitar o name. Resto igual.
CREATE OR REPLACE FUNCTION public._conformidade_em_falta(p_row jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY(
    SELECT x FROM unnest(ARRAY[
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'legal_name',
                                      CASE WHEN p_row ? 'business_hours' THEN NULL ELSE p_row->>'name' END,
                                      '')), '') IS NULL THEN 'nome' END,
      CASE WHEN regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[0-9]{9}$' THEN 'nif' END,
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'address', p_row->>'base_address', '')), '') IS NULL THEN 'morada' END,
      CASE WHEN upper(regexp_replace(COALESCE(p_row->>'iban', ''), '\s', '', 'g')) !~ '^PT[0-9]{23}$' THEN 'iban' END,
      CASE WHEN NULLIF(p_row->>'birth_date', '') IS NULL
            AND regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[5679][0-9]{8}$'
           THEN 'data_nascimento' END,
      CASE WHEN NULLIF(p_row->>'dsa_self_certified_at', '') IS NULL THEN 'autocertificacao' END
    ]) AS x WHERE x IS NOT NULL);
$function$;
