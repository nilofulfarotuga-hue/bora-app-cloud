-- Robô Glovo das farmácias — missão noite-farmacia-17-11 (1.1). Prometido à farmácia.
-- Lê as lojas da Glovo da Sé e da Teixeira às 07:30 e 14:00 (Lisboa) e copia PREÇO e ESGOTADO.
-- O trabalho é da Edge robo-glovo-farmacias; aqui ficam o registo, o liga/desliga, o agendamento
-- e as funções do painel (PT-BR: Farmácias › Robô Glovo).

create table if not exists public.robo_glovo_config (
  id int primary key default 1 check (id = 1),
  ligado boolean not null default true,
  lojas text[] not null default array['farmacia-se-guarda', 'farmacia-teixeira-guarda'],
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);
insert into public.robo_glovo_config (id) values (1) on conflict (id) do nothing;

create table if not exists public.robo_glovo_corridas (
  id bigserial primary key,
  loja text not null,
  origem text not null default 'agendado', -- agendado | manual
  pedido_por uuid,
  estado text not null default 'a_correr' check (estado in ('a_correr', 'ok', 'abortada', 'erro')),
  iniciada_em timestamptz not null default now(),
  terminada_em timestamptz,
  lock_ate timestamptz,
  progresso jsonb,
  lidos int, conhecidos int, cobertura numeric, pedidos_glovo int, falhas int,
  mudou_preco int, esgotou int, voltou int, novos int, mao int, suspeitos int,
  exemplos jsonb,
  erro text
);
create index if not exists robo_glovo_corridas_estado_idx on public.robo_glovo_corridas (estado, id);
create index if not exists robo_glovo_corridas_loja_idx on public.robo_glovo_corridas (loja, id desc);

-- O que o robô pôs da última vez em cada produto: se a base já tem outro valor, foi a farmácia
-- (à mão, no painel) e o robô não pisa.
create table if not exists public.robo_glovo_estado (
  product_id text primary key,
  loja text not null,
  glovo_id text not null,
  ultimo_preco_robo numeric,
  ultimo_disp_robo boolean,
  robo_esgotou boolean not null default false,
  ignorar boolean not null default false,
  motivo_ignorar text,
  ultima_vez_visto timestamptz
);
create index if not exists robo_glovo_estado_loja_idx on public.robo_glovo_estado (loja);

-- Os 5 produtos da Sé que ficaram fora a 11/11 por a Glovo não ter foto real.
insert into public.robo_glovo_estado (product_id, loja, glovo_id, ignorar, motivo_ignorar) values
  ('fse-4611686018581478511', 'farmacia-se-guarda', '4611686018581478511', true, 'sem foto real na Glovo (11/11)'),
  ('fse-4611686018581483572', 'farmacia-se-guarda', '4611686018581483572', true, 'sem foto real na Glovo (11/11)'),
  ('fse-4611686018581483668', 'farmacia-se-guarda', '4611686018581483668', true, 'sem foto real na Glovo (11/11)'),
  ('fse-4611686018581478623', 'farmacia-se-guarda', '4611686018581478623', true, 'sem foto real na Glovo (11/11)'),
  ('fse-4611686018581474521', 'farmacia-se-guarda', '4611686018581474521', true, 'sem foto real na Glovo (11/11)')
on conflict (product_id) do nothing;

alter table public.robo_glovo_config enable row level security;
alter table public.robo_glovo_corridas enable row level security;
alter table public.robo_glovo_estado enable row level security;
revoke all on public.robo_glovo_config, public.robo_glovo_corridas, public.robo_glovo_estado from public, anon, authenticated;
grant select, insert, update on public.robo_glovo_config, public.robo_glovo_corridas, public.robo_glovo_estado to service_role;
grant usage, select on sequence public.robo_glovo_corridas_id_seq to service_role;

-- Aviso no Telegram do admin (a Edge chama com a service role).
create or replace function public.robo_glovo_avisar(p_texto text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._telegram_admin(left(coalesce(p_texto, ''), 3500));
end $$;
revoke all on function public.robo_glovo_avisar(text) from public, anon, authenticated;
grant execute on function public.robo_glovo_avisar(text) to service_role;

-- Chama a Edge (sem esperar a resposta: o trabalho continua lá).
create or replace function public._robo_glovo_chamar()
returns void language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/robo-glovo-farmacias',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := '{}'::jsonb,
    timeout_milliseconds := 160000);
end $$;
revoke all on function public._robo_glovo_chamar() from public, anon, authenticated;

-- Começa uma corrida por loja (se a loja não tiver já uma a correr).
create or replace function public.robo_glovo_iniciar(p_origem text default 'agendado', p_por uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_cfg public.robo_glovo_config; v_loja text; v_n int := 0;
begin
  select * into v_cfg from public.robo_glovo_config where id = 1;
  if v_cfg is null or not v_cfg.ligado then return 0; end if;
  foreach v_loja in array v_cfg.lojas loop
    if not exists (select 1 from public.robo_glovo_corridas where loja = v_loja and estado = 'a_correr') then
      insert into public.robo_glovo_corridas (loja, origem, pedido_por) values (v_loja, p_origem, p_por);
      v_n := v_n + 1;
    end if;
  end loop;
  if v_n > 0 then perform public._robo_glovo_chamar(); end if;
  return v_n;
end $$;
revoke all on function public.robo_glovo_iniciar(text, uuid) from public, anon, authenticated;

-- Agendado: o pg_cron corre em UTC; a função só arranca se em Lisboa for a hora certa
-- (assim acerta no inverno e no verão).
create or replace function public._cron_robo_glovo_agendado(p_hora int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if extract(hour from (now() at time zone 'Europe/Lisbon'))::int = p_hora then
    perform public.robo_glovo_iniciar('agendado', null);
  end if;
end $$;
revoke all on function public._cron_robo_glovo_agendado(int) from public, anon, authenticated;

-- De minuto a minuto: continua a corrida que está a meio; fecha as que pararam há mais de 90 min.
create or replace function public._cron_robo_glovo_tick()
returns void language plpgsql security definer set search_path = public as $$
declare v_paradas int;
begin
  if not exists (select 1 from public.robo_glovo_corridas where estado = 'a_correr') then return; end if;
  update public.robo_glovo_corridas
     set estado = 'erro', erro = 'parada há mais de 90 minutos', terminada_em = now(), lock_ate = null
   where estado = 'a_correr' and iniciada_em < now() - interval '90 minutes';
  get diagnostics v_paradas = row_count;
  if v_paradas > 0 then
    perform public._telegram_admin('⚠️ Robô Glovo das farmácias: ' || v_paradas || ' corrida(s) paradas há mais de 90 minutos. Ver no painel (Farmácias › Robô Glovo).');
  end if;
  if (select ligado from public.robo_glovo_config where id = 1)
     and exists (select 1 from public.robo_glovo_corridas
                  where estado = 'a_correr' and (lock_ate is null or lock_ate < now())) then
    perform public._robo_glovo_chamar();
  end if;
end $$;
revoke all on function public._cron_robo_glovo_tick() from public, anon, authenticated;

-- Painel (só admin)
create or replace function public.admin_robo_glovo_estado(p_limite int default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'ligado', c.ligado,
    'lojas', c.lojas,
    'atualizado_em', c.atualizado_em,
    'corridas', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.id desc) from (
        select id, loja, origem, estado, iniciada_em, terminada_em, lidos, conhecidos, cobertura,
               pedidos_glovo, falhas, mudou_preco, esgotou, voltou, novos, mao, suspeitos, exemplos, erro,
               case when estado = 'a_correr' then progresso->'i' end as categoria_atual,
               case when estado = 'a_correr' then jsonb_array_length(coalesce(progresso->'fila', '[]'::jsonb)) end as categorias
          from public.robo_glovo_corridas order by id desc limit greatest(1, least(p_limite, 100))) x), '[]'::jsonb),
    'ignorados', (select count(*) from public.robo_glovo_estado where ignorar))
  into v from public.robo_glovo_config c where c.id = 1;
  return v;
end $$;
revoke all on function public.admin_robo_glovo_estado(int) from public, anon;
grant execute on function public.admin_robo_glovo_estado(int) to authenticated;

create or replace function public.admin_robo_glovo_ligar(p_ligado boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  update public.robo_glovo_config set ligado = p_ligado, atualizado_em = now(), atualizado_por = auth.uid() where id = 1;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'robo_glovo_ligar', 'robo', 'robo-glovo-farmacias', jsonb_build_object('ligado', p_ligado));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
end $$;
revoke all on function public.admin_robo_glovo_ligar(boolean) from public, anon;
grant execute on function public.admin_robo_glovo_ligar(boolean) to authenticated;

create or replace function public.admin_robo_glovo_agora()
returns int language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  if not (select ligado from public.robo_glovo_config where id = 1) then
    raise exception 'O robô está desligado. Ligue primeiro.' using errcode = 'P0001';
  end if;
  return public.robo_glovo_iniciar('manual', auth.uid());
end $$;
revoke all on function public.admin_robo_glovo_agora() from public, anon;
grant execute on function public.admin_robo_glovo_agora() to authenticated;

-- 07:30 e 14:00 em Lisboa (o cron é UTC: corre às duas horas possíveis, a função escolhe)
select cron.schedule('robo-glovo-farmacias-0730', '30 6,7 * * *', 'select public._cron_robo_glovo_agendado(7);');
select cron.schedule('robo-glovo-farmacias-1400', '0 13,14 * * *', 'select public._cron_robo_glovo_agendado(14);');
select cron.schedule('robo-glovo-farmacias-tick', '* * * * *', 'select public._cron_robo_glovo_tick();');
