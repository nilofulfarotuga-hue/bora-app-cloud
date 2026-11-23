-- 23/11/2026 12:45 — a app nova avisa que mostra a embalagem pela chave 'mostra_embalagem' no input OU em qualquer
-- item do carrinho (igual ao 'deposit_units' do Volta), porque o ficheiro que monta o input do create_order é zona protegida.
CREATE OR REPLACE FUNCTION public.app_mostra_embalagem(p_input jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $f$
  SELECT COALESCE(p_input->>'mostra_embalagem', '') IN ('true', '1')
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_input->'items') = 'array'
                                                         THEN p_input->'items' ELSE '[]'::jsonb END) x
                  WHERE jsonb_typeof(x) = 'object' AND COALESCE(x->>'mostra_embalagem', '') IN ('true', '1'));
$f$;