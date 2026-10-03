-- MEGA-FIX 2026-07-18 Parte 9 — banner fantasma da volta TVDE.
--
-- Bug provado: `tvde_active_roundtrip_credit()` era `LANGUAGE sql RETURNS tvde_roundtrip_credits`
-- (tipo composto). Quando o SELECT não encontra vale, uma função sql que devolve composto
-- devolve uma LINHA DE NULLs (não NULL) → o app via `res is Map` e mostrava "Tens uma volta
-- garantida" com a tabela vazia por baixo.
--
-- Fix: reescrita em plpgsql com `RETURN NULL` explícito quando não há vale — vazio de verdade.
-- Ver .claude/.ai/knowledge/wiki/licoes/licao-rpc-composite-null-row.md

CREATE OR REPLACE FUNCTION public.tvde_active_roundtrip_credit()
 RETURNS tvde_roundtrip_credits
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.tvde_roundtrip_credits;
BEGIN
  SELECT * INTO v_row
    FROM public.tvde_roundtrip_credits
   WHERE client_id = auth.uid() AND status = 'ativo' AND now() <= expires_at
   ORDER BY created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN NULL;  -- NULL de verdade, não uma linha de NULLs.
  END IF;
  RETURN v_row;
END;
$function$;
