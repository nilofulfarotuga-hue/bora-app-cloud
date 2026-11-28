-- Missão limpeza-planos-empresas-2026-11-28, Bloco E (fonte certa: provider_atividade + documentos_verificacoes).
-- JÁ APLICADA no servidor pela Claude.ai (versão 20261128113738, e2e 17564). Cópia fiel de schema_migrations.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.documentos_verificacoes
ADD COLUMN IF NOT EXISTS codigos_atividade text[];

COMMENT ON COLUMN public.documentos_verificacoes.codigos_atividade IS
'Códigos de atividade (CAE/CIRS) lidos pelo robô num comprovativo de atividade das Finanças (28/11/2026).';

DROP FUNCTION IF EXISTS public.admin_cleaners_activity_status();

CREATE FUNCTION public.admin_cleaners_activity_status()
RETURNS TABLE (
cleaner_id uuid, name text, approval_status text, tem_comprovativo boolean,
atividade_status text, codigos text[], codigo_certo boolean, sem_atividade_aberta boolean,
verificado_em timestamptz, estado text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
PERFORM public._admin_op_guard();
RETURN QUERY
WITH base AS (
SELECT c.id, c.name, c.approval_status, c.docs,
pa.documento_path, pa.atividade_status AS a_status,
dv.codigos_atividade, dv.created_at AS dv_em
FROM cleaners c
LEFT JOIN provider_atividade pa ON pa.user_id = c.user_id
LEFT JOIN LATERAL (
SELECT d.codigos_atividade, d.created_at
FROM documentos_verificacoes d
WHERE d.user_id = c.user_id
AND d.tipo_documento_esperado = 'comprovativo_atividade_AT'
AND d.codigos_atividade IS NOT NULL
ORDER BY d.created_at DESC
LIMIT 1) dv ON true
)
SELECT b.id, b.name, b.approval_status,
b.documento_path IS NOT NULL,
b.a_status,
COALESCE(b.codigos_atividade, '{}'),
EXISTS (SELECT 1 FROM cleaner_activity_codes a
WHERE a.accepted AND a.code = ANY (COALESCE(b.codigos_atividade, '{}'))),
COALESCE((b.docs ->> 'sem_atividade_aberta')::boolean, false),
b.dv_em,
CASE
WHEN b.documento_path IS NULL THEN 'falta o comprovativo'
WHEN b.codigos_atividade IS NULL THEN 'comprovativo por ler'
WHEN EXISTS (SELECT 1 FROM cleaner_activity_codes a
WHERE a.accepted AND a.preferred AND a.code = ANY (b.codigos_atividade))
THEN 'código certo'
WHEN EXISTS (SELECT 1 FROM cleaner_activity_codes a
WHERE a.accepted AND a.code = ANY (b.codigos_atividade))
THEN 'aceite, falta o 81210'
ELSE 'código errado'
END
FROM base b
ORDER BY (b.approval_status = 'approved') DESC, b.name;
END $$;

REVOKE ALL ON FUNCTION public.admin_cleaners_activity_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_cleaners_activity_status() TO authenticated;
