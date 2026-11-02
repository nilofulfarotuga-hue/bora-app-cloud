-- 02/11/2026 (missão chaves-varredura-2026-10-31) — ecrã do painel "Saúde das chaves"
-- (/admin/system-health, deep-link do aviso "🔑 CHAVE RECUSADA"). Aplicada em produção por execute_sql
-- e registada à mão em supabase_migrations.schema_migrations (o apply_migration expirava sem ninguém ao PC).

create or replace function public.admin_saude_chaves(p_dias int default 7)
returns table (ronda uuid, criado_em timestamptz, funcao text, modo text, status_code int, resultado text, alertado boolean)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
-- 02/11/2026 (missão chaves-varredura-2026-10-31): ecrã /admin/system-health — as rondas do vigia
-- diário das chaves (saude_chaves_pings). Só leitura; só admin.
begin
  if auth.uid() is null then
    raise exception 'auth_required' using errcode = '42501';
  end if;
  if not public.is_admin() then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  return query
  select s.ronda, s.criado_em, s.funcao, s.modo, s.status_code,
         coalesce(s.resultado, 'por_verificar'), s.alertado
    from public.saude_chaves_pings s
   where s.criado_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 60)))
   order by s.criado_em desc, s.funcao, s.modo
   limit 3000;
end;
$$;

create or replace function public.admin_saude_chaves_correr()
returns uuid
language plpgsql
volatile
security definer
set search_path to 'public'
as $$
-- Botão "Correr o vigia agora" do painel: a mesma ronda das 07:00; o verificador de hora a hora
-- (minuto 6) lê as respostas. Só admin.
begin
  if auth.uid() is null then
    raise exception 'auth_required' using errcode = '42501';
  end if;
  if not public.is_admin() then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  return public._cron_saude_chaves_funcoes();
end;
$$;

grant execute on function public.admin_saude_chaves(int) to authenticated;
grant execute on function public.admin_saude_chaves_correr() to authenticated;
