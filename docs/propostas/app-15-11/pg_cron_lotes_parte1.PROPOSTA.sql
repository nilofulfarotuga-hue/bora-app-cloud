-- PROPOSTA (missão app-15-11, 15/11/2026; pedido da Claude.ai 11:55, varredura 9166 n.º 1 ALTA).
-- Nome sugerido: 20261115124000_pg_cron_lotes_parte1. Aplica a Claude.ai DEPOIS da
-- 20261115020100_cron_desencontrar_minutos_redondos (caixa 43), que já tira 10 tarefas do minuto redondo.
--
-- MEDIDO em produção (SELECT 15/11 ~12:30):
--   * 95 tarefas ativas, todas como postgres; ~44 100 execuções por dia.
--   * O grosso: 3 tarefas de 15 em 15 s (17 280/dia), 9 de minuto a minuto (12 960/dia),
--     2 de 30 em 30 s (5 760/dia), 6 de 2 em 2 min (4 320/dia).
--   * max_connections = 60 e cron.use_background_workers = off: CADA execução abre uma ligação nova.
--   * 24 h: falhas espalhadas por quase todas as tarefas frequentes (casa_tick 7, restaurante-do-dia 7,
--     vigia_pago_sem_pedido 7, drivers-heartbeat-expire 6, …) = falta de ligações, não uma tarefa estragada.
--
-- IDEIA: juntar tarefas que correm ao mesmo ritmo num LOTE que corre numa só ligação. Cada função do
-- lote corre dentro da sua própria proteção: se uma falhar, as outras correm na mesma e a falha fica
-- registada em public.cron_lote_falhas. As funções são AS MESMAS, com os mesmos horários; só deixam de
-- abrir uma ligação cada uma.
--
-- ESTA PARTE 1 só junta tarefas que NÃO tocam em dinheiro nem em despacho:
--   lote "minuto-arrumar"  (de minuto a minuto): prescricao_vigiar() + mover_pedidos_demo()
--   lote "impar-2min-avisos" (minutos ímpares, de 2 em 2): drivers_sem_sinal_avisar() + broadcasts_processar_fila()
-- Poupa 1 440 + 720 = 2 160 ligações por dia e tira 1 arranque ao minuto :00. É pouco de propósito:
-- o grosso (≈ 25 000 ligações/dia e o pico do :00 de ~27 para ~17) está na PARTE 2
-- (pg_cron_lotes_parte2_despacho.PROPOSTA.sql), que toca em tarefas de despacho e de dinheiro e
-- precisa de ordem explícita.
--
-- A SOLUÇÃO DE FUNDO (fora do SQL, decisão de quem gere o projeto Supabase): ligar
-- cron.use_background_workers (as tarefas deixam de abrir ligações) ou subir o tamanho da máquina
-- (max_connections 60 → 90/120). Os lotes aliviam enquanto isso não se decide.
--
-- REVERSÍVEL: as tarefas substituídas ficam guardadas em public.bkp_cron_job_20261115 (nome,
-- horário e comando). Para voltar atrás: ver o bloco ROLLBACK no fim deste ficheiro.

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

-- Corre, por ordem, chamadas do tipo 'public.nome_da_funcao()' (só isso: nada de texto livre).
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

-- Troca cada PAR pelo seu lote só se as duas tarefas ainda estiverem como foram medidas
-- (repetível e cuidadoso: se uma delas tiver sido mudada por alguém, esse lote não se cria e as
-- duas ficam como estão — nunca a mesma função a correr a dobrar).
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

-- PROVA (depois de aplicar):
--   select jobname, schedule from cron.job where jobname like 'lote-%';           -- 2 lotes
--   select count(*) from cron.job where active;                                  -- 95 - 4 + 2 = 93
--   select * from public.cron_lote_falhas order by id desc limit 20;              -- falhas por função
--   e, ao fim de 1 h, as duas funções continuam a correr: select lote, count(*) ... (sem linhas = sem falhas)
--
-- ROLLBACK (se for preciso voltar atrás):
--   select cron.unschedule('lote-minuto-arrumar'); select cron.unschedule('lote-impar-2min-avisos');
--   select cron.schedule(jobname, schedule, command) from public.bkp_cron_job_20261115
--    where jobname in ('farmacias-prescricao-vigiar', 'mover-pedidos-demo', 'drivers-sem-sinal-avisar', 'execute-broadcast-queue');
