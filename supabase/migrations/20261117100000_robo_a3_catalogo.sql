-- Robô do catálogo da A3 Guarda — missão a3-guarda-16-11, parte 2 (pontos 1 e 6 da caixa 114).
-- Lê a loja online da A3 (a3guarda.com/loja) às 07:00 de Lisboa e copia PREÇO e ESGOTADO; mete
-- produtos novos com a foto já no nosso Storage; nunca pisa o que foi mudado à mão na Bora.
-- Também acaba de copiar as fotos que ainda apontem para a3guarda.com.
-- O trabalho é da Edge robo-a3-catalogo; aqui ficam o registo, o liga/desliga, o agendamento e as
-- funções do painel (PT-BR: Lojas › Robô A3). Molde: robô Glovo das farmácias (20261117000000).
--
-- fator_preco = 1,15: a regra conferida pela Claude.ai a 16/11 21:35 (preço = balcão × 1,15,
-- ex.: 9,99 → 11,49). NÃO é editável no painel (mexe em dinheiro): muda-se só por migração.

create table if not exists public.robo_a3_config (
  id int primary key default 1 check (id = 1),
  ligado boolean not null default true,
  fator_preco numeric not null default 1.15 check (fator_preco between 1 and 2),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);
insert into public.robo_a3_config (id) values (1) on conflict (id) do nothing;

create table if not exists public.robo_a3_corridas (
  id bigserial primary key,
  origem text not null default 'agendado', -- agendado | manual
  pedido_por uuid,
  estado text not null default 'a_correr' check (estado in ('a_correr', 'ok', 'abortada', 'erro')),
  iniciada_em timestamptz not null default now(),
  terminada_em timestamptz,
  lock_ate timestamptz,
  progresso jsonb,
  lidos int, conhecidos int, cobertura numeric,
  mudou_preco int, esgotou int, voltou int, desapareceu int, novos int, mao int, suspeitos int,
  fotos_copiadas int, fotos_falhas int,
  exemplos jsonb,
  erro text
);
create index if not exists robo_a3_corridas_estado_idx on public.robo_a3_corridas (estado, id);

-- O que o robô pôs da última vez em cada produto: se a base já tem outro valor, foi mão humana
-- (a A3 no painel do parceiro, ou nós no admin) e o robô não pisa.
create table if not exists public.robo_a3_estado (
  product_id text primary key,
  loja text not null default 'a3-guarda',
  ext_id text not null,
  ultimo_balcao_robo numeric,
  ultimo_disp_robo boolean,
  ignorar boolean not null default false,
  motivo_ignorar text,
  ultima_vez_visto timestamptz
);
create index if not exists robo_a3_estado_loja_idx on public.robo_a3_estado (loja);

alter table public.robo_a3_config enable row level security;
alter table public.robo_a3_corridas enable row level security;
alter table public.robo_a3_estado enable row level security;
revoke all on public.robo_a3_config, public.robo_a3_corridas, public.robo_a3_estado from public, anon, authenticated;
grant select, insert, update on public.robo_a3_config, public.robo_a3_corridas, public.robo_a3_estado to service_role;
grant usage, select on sequence public.robo_a3_corridas_id_seq to service_role;

-- Aviso no Telegram do admin (a Edge chama com a service role).
create or replace function public.robo_a3_avisar(p_texto text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._telegram_admin(left(coalesce(p_texto, ''), 3500));
end $$;
revoke all on function public.robo_a3_avisar(text) from public, anon, authenticated;
grant execute on function public.robo_a3_avisar(text) to service_role;

-- Chama a Edge (sem esperar a resposta).
create or replace function public._robo_a3_chamar(p_corpo jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/robo-a3-catalogo',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := coalesce(p_corpo, '{}'::jsonb),
    timeout_milliseconds := 160000);
end $$;
revoke all on function public._robo_a3_chamar(jsonb) from public, anon, authenticated;

create or replace function public.robo_a3_iniciar(p_origem text default 'agendado', p_por uuid default null)
returns int language plpgsql security definer set search_path = public as $$
begin
  if not coalesce((select ligado from public.robo_a3_config where id = 1), false) then return 0; end if;
  if exists (select 1 from public.robo_a3_corridas where estado = 'a_correr') then return 0; end if;
  insert into public.robo_a3_corridas (origem, pedido_por) values (p_origem, p_por);
  perform public._robo_a3_chamar();
  return 1;
end $$;
revoke all on function public.robo_a3_iniciar(text, uuid) from public, anon, authenticated;

-- 07:00 em Lisboa (o cron é UTC: corre às duas horas possíveis, a função escolhe).
create or replace function public._cron_robo_a3_agendado()
returns void language plpgsql security definer set search_path = public as $$
begin
  if extract(hour from (now() at time zone 'Europe/Lisbon'))::int = 7 then
    perform public.robo_a3_iniciar('agendado', null);
  end if;
end $$;
revoke all on function public._cron_robo_a3_agendado() from public, anon, authenticated;

-- De minuto a minuto: continua a corrida a meio; fecha as paradas há mais de 90 min.
create or replace function public._cron_robo_a3_tick()
returns void language plpgsql security definer set search_path = public as $$
declare v_paradas int;
begin
  if not exists (select 1 from public.robo_a3_corridas where estado = 'a_correr') then return; end if;
  update public.robo_a3_corridas
     set estado = 'erro', erro = 'parada há mais de 90 minutos', terminada_em = now(), lock_ate = null
   where estado = 'a_correr' and iniciada_em < now() - interval '90 minutes';
  get diagnostics v_paradas = row_count;
  if v_paradas > 0 then
    perform public._telegram_admin('⚠️ Robô da A3 Guarda: corrida parada há mais de 90 minutos. Ver no painel (Lojas › Robô A3).');
  end if;
  if coalesce((select ligado from public.robo_a3_config where id = 1), false)
     and exists (select 1 from public.robo_a3_corridas
                  where estado = 'a_correr' and (lock_ate is null or lock_ate < now())) then
    perform public._robo_a3_chamar();
  end if;
end $$;
revoke all on function public._cron_robo_a3_tick() from public, anon, authenticated;

-- Painel (só admin)
create or replace function public.admin_robo_a3_estado(p_limite int default 20)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'ligado', c.ligado,
    'fator_preco', c.fator_preco,
    'atualizado_em', c.atualizado_em,
    'produtos', (select count(*) from public.products where restaurant_id = 'a3-guarda'),
    'fotos_fora', (select count(*) from public.products where restaurant_id = 'a3-guarda' and photo_url ilike '%a3guarda.com%'),
    'ignorados', (select count(*) from public.robo_a3_estado where ignorar),
    'corridas', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.id desc) from (
        select id, origem, estado, iniciada_em, terminada_em, lidos, conhecidos, cobertura,
               mudou_preco, esgotou, voltou, desapareceu, novos, mao, suspeitos,
               fotos_copiadas, fotos_falhas, exemplos, erro
          from public.robo_a3_corridas order by id desc limit greatest(1, least(p_limite, 100))) x), '[]'::jsonb))
  into v from public.robo_a3_config c where c.id = 1;
  return v;
end $$;
revoke all on function public.admin_robo_a3_estado(int) from public, anon;
grant execute on function public.admin_robo_a3_estado(int) to authenticated;

create or replace function public.admin_robo_a3_ligar(p_ligado boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  update public.robo_a3_config set ligado = p_ligado, atualizado_em = now(), atualizado_por = auth.uid() where id = 1;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'robo_a3_ligar', 'robo', 'robo-a3-catalogo', jsonb_build_object('ligado', p_ligado));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
end $$;
revoke all on function public.admin_robo_a3_ligar(boolean) from public, anon;
grant execute on function public.admin_robo_a3_ligar(boolean) to authenticated;

create or replace function public.admin_robo_a3_agora()
returns int language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  if not (select ligado from public.robo_a3_config where id = 1) then
    raise exception 'O robô está desligado. Ligue primeiro.' using errcode = 'P0001';
  end if;
  return public.robo_a3_iniciar('manual', auth.uid());
end $$;
revoke all on function public.admin_robo_a3_agora() from public, anon;
grant execute on function public.admin_robo_a3_agora() to authenticated;

select cron.schedule('robo-a3-catalogo-0700', '0 6,7 * * *', 'select public._cron_robo_a3_agendado();');
select cron.schedule('robo-a3-catalogo-tick', '* * * * *', 'select public._cron_robo_a3_tick();');
