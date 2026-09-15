-- 2026-06-06: colunas aditivas em products (já aplicadas via MCP; aqui para sync repo↔remoto).
-- sort_order: ordem de exibição (sequência da fonte, ex. Glovo). NULL = sem ordem definida.
-- removal_reason: motivo de soft-delete (is_available=false), ex. not_in_source_glovo_guarda / price_error_unconfirmed.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sort_order integer;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS removal_reason text;
COMMENT ON COLUMN public.products.sort_order IS 'Ordem de exibição (sequência da fonte, ex. Glovo). NULL = sem ordem definida.';
COMMENT ON COLUMN public.products.removal_reason IS 'Motivo de soft-delete (is_available=false).';
