-- 23/11/2026 12:55 — volta atrás na versão das 12:45: o sinal da embalagem só conta no input da cotação/pedido
-- ('mostra_embalagem'), não dentro dos itens. O create_order só o mandará quando o ficheiro protegido for mudado com aprovação.
CREATE OR REPLACE FUNCTION public.app_mostra_embalagem(p_input jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $f$
  SELECT COALESCE(p_input->>'mostra_embalagem', '') IN ('true', '1');
$f$;