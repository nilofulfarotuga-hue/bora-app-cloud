-- 2026-09-07 — utilitario de manutencao.
-- As migrations aplicadas pelo assistente ficam na base mas nao no repositorio,
-- e o repositorio e onde a historia se le. Esta funcao devolve o texto das
-- migrations de um dia para se poderem gravar como ficheiros. Nao le nem
-- escreve dados de negocio; so a historia do schema. So o servidor a chama.
CREATE OR REPLACE FUNCTION public.dump_migrations_do_dia(p_prefixo text)
 RETURNS TABLE (version text, name text, sql text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.version, m.name, array_to_string(m.statements, E';\n\n') || ';'
    FROM supabase_migrations.schema_migrations m
   WHERE m.version LIKE p_prefixo || '%'
   ORDER BY m.version;
$function$;

REVOKE ALL ON FUNCTION public.dump_migrations_do_dia(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dump_migrations_do_dia(text) FROM anon;
REVOKE ALL ON FUNCTION public.dump_migrations_do_dia(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.dump_migrations_do_dia(text) TO service_role;;
