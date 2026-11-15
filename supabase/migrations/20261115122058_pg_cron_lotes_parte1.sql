-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115122058); antes não estava em supabase/migrations.
-- Origem: docs/propostas/app-15-11/pg_cron_lotes_parte1.PROPOSTA.sql (o mesmo SQL, com comentários); abaixo, o texto exato que correu.

create table if not exists public.cron_lote_falhas (
  id bigserial primary key,
  criado_em timestamptz not null default now(),
  lote text not null,
  chamada text not null,
  erro text
);
alter table public.cron_lote_falhas enable row level security;
revoke all on public.cron_lote_falhas from public, anon, authenticated;

create table if not exists public.bkp_cron_job_20261115 (
  jobname text primary key,
  schedule text not null,
  command text not null,
  guardado_em timestamptz not null default now()
);
alter table public.bkp_cron_job_20261115 enable row level security;
revoke all on public.bkp_cron_job_20261115 from public, anon, authenticated;

create or replace function public.cron_lote(p_lote text, p_chamadas text[])
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  c text;
begin
  foreach c in array p_chamadas loop
    if c !~ '^public\.[a-z0-9_]+\(\)$' then
      insert into public.cron_lote_falhas (lote, chamada, erro) values (p_lote, left(c, 200), 'chamada recusada');
      continue;
    end if;
    begin
      execute 'select ' || c;
    exception when others then
      insert into public.cron_lote_falhas (lote, chamada, erro) values (p_lote, c, left(sqlerrm, 500));
    end;
  end loop;
end $function$;
revoke all on function public.cron_lote(text, text[]) from public, anon, authenticated;

create or replace function public._cron_trocar_por_lote(
  p_lote text, p_horario text, p_tarefas text[], p_chamadas text[])
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
begin
  if (select count(*) from cron.job j
       where j.jobname = any (p_tarefas) and j.schedule = p_horario and j.active) <> cardinality(p_tarefas) then
    raise notice 'lote %: tarefas não estão como medidas, fica como está', p_lote;
    return false;
  end if;
  for r in select j.jobid, j.jobname, j.schedule, j.command from cron.job j where j.jobname = any (p_tarefas) loop
    insert into public.bkp_cron_job_20261115 (jobname, schedule, command)
    values (r.jobname, r.schedule, r.command)
    on conflict (jobname) do nothing;
    perform cron.unschedule(r.jobid);
  end loop;
  perform cron.schedule('lote-' || p_lote, p_horario,
    format('select public.cron_lote(%L, %L::text[])', p_lote, p_chamadas));
  return true;
end $function$;
revoke all on function public._cron_trocar_por_lote(text, text, text[], text[]) from public, anon, authenticated;

select public._cron_trocar_por_lote('minuto-arrumar', '* * * * *',
  array['farmacias-prescricao-vigiar', 'mover-pedidos-demo'],
  array['public.prescricao_vigiar()', 'public.mover_pedidos_demo()']);
select public._cron_trocar_por_lote('impar-2min-avisos', '1-59/2 * * * *',
  array['drivers-sem-sinal-avisar', 'execute-broadcast-queue'],
  array['public.drivers_sem_sinal_avisar()', 'public.broadcasts_processar_fila()']);
