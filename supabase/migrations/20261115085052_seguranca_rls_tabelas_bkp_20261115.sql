-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115085052); antes não estava em supabase/migrations.

-- 15/11: Danilo mandou proteger as tabelas de cópia de segurança (bkp_*) que estavam sem RLS.
-- Liga RLS sem políticas (só o servidor lê) e tira o acesso direto de anon/authenticated. Não apaga nada.
do $$
declare r record;
begin
  for r in
    select c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'bkp\_%'
  loop
    execute format('alter table public.%I enable row level security', r.relname);
    execute format('revoke all on table public.%I from anon, authenticated', r.relname);
  end loop;
end $$;
