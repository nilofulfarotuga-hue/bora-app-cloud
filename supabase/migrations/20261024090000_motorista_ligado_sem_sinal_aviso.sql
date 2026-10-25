-- Motorista "ligado sem sinal" — aviso por push (missão geral-sabado-24-10, bloco 1).
--
-- Porquê: o Valdemir aparece ligado desde 20/10 03:01 sem mandar sinal (o
-- serviço de fundo do telemóvel morreu). Nada o acordava nem o avisava: o
-- _cron_check_ghost_drivers existe mas nunca foi agendado e só avisava o admin.
--
-- Regra que NÃO muda (25/09): só o botão do motorista o põe desligado. Isto só
-- AVISA o motorista; não toca em drivers nem em dispatch_heartbeat_offline_seconds.
--
-- Compasso: primeiro aviso aos 10 min sem sinal; depois de 30 em 30 min até às
-- 6 h; depois de 6 em 6 h. Interruptor: platform_settings
-- drivers_sem_sinal_aviso_ligado (painel → Configurações → dispatch).

create table if not exists public.driver_sinal_avisos (
  id                bigint generated always as identity primary key,
  user_id           uuid not null,
  enviado_em        timestamptz not null default now(),
  sinal_desde       timestamptz,
  minutos_sem_sinal int,
  origem            text not null default 'automatico'
                    check (origem in ('automatico', 'painel')),
  pedido_por        uuid,
  request_id        bigint
);
create index if not exists driver_sinal_avisos_user_idx
  on public.driver_sinal_avisos (user_id, enviado_em desc);
alter table public.driver_sinal_avisos enable row level security;
create policy driver_sinal_avisos_admin_le on public.driver_sinal_avisos
  for select to authenticated using (public.is_admin());
revoke all on public.driver_sinal_avisos from public, anon, authenticated;
grant select on public.driver_sinal_avisos to authenticated;

insert into public.platform_settings (key, value, description, category)
values ('drivers_sem_sinal_aviso_ligado', 'true'::jsonb,
        'Avisar por notificação o motorista/estafeta que está LIGADO mas sem sinal do telemóvel: aos 10 min, de 30 em 30 min até 6 h, depois de 6 em 6 h. Desligar = deixa de avisar (não muda quem está online).',
        'dispatch')
on conflict (key) do nothing;

-- Decisão pura: este aviso já é devido? (testável sem relógio)
create or replace function public.sinal_aviso_devido(
  p_sem_sinal interval, p_desde_ultimo_aviso interval)
returns boolean
language sql immutable
set search_path to 'public'
as $$
  select case
    when p_sem_sinal is null or p_sem_sinal < interval '10 minutes' then false
    when p_desde_ultimo_aviso is null then true
    -- 1 min de folga: o cron corre de 2 em 2 min e não pode empurrar o aviso
    when p_sem_sinal < interval '6 hours' then p_desde_ultimo_aviso >= interval '29 minutes'
    else p_desde_ultimo_aviso >= interval '359 minutes'
  end
$$;

-- Envia UM aviso (Edge notify-driver-assigned, type driver_wake) e regista-o.
create or replace function public._enviar_aviso_sem_sinal(
  p_user_id uuid, p_sinal_desde timestamptz, p_origem text, p_por uuid)
returns bigint
language plpgsql security definer
set search_path to 'public'
as $$
declare
  v_local timestamp := p_sinal_desde at time zone 'Europe/Lisbon';
  v_hoje  date := (now() at time zone 'Europe/Lisbon')::date;
  v_hora  text;
  v_body  text;
  v_req   bigint;
begin
  v_hora := case
    when p_sinal_desde is null then null
    when v_local::date = v_hoje then to_char(v_local, 'HH24:MI')
    else to_char(v_local, 'DD/MM "às" HH24:MI')
  end;
  v_body := case
    when v_hora is null then 'A Bora não recebe sinal do teu telemóvel.'
    else 'A Bora não recebe sinal do teu telemóvel desde ' || v_hora || '.'
  end || ' Toca aqui para voltares a receber pedidos (ou desliga o botão se já não estás a trabalhar).';

  select net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver-assigned',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(public._service_role_key(), '')),
    body    := jsonb_build_object(
      'driverId', p_user_id::text, 'orderId', null, 'type', 'driver_wake',
      'title', 'Estás ligado, mas sem sinal', 'body', v_body))
  into v_req;

  insert into public.driver_sinal_avisos
    (user_id, sinal_desde, minutos_sem_sinal, origem, pedido_por, request_id)
  values
    (p_user_id, p_sinal_desde,
     case when p_sinal_desde is null then null
          else (extract(epoch from now() - p_sinal_desde) / 60)::int end,
     p_origem, p_por, v_req);
  return v_req;
end;
$$;

-- Cron: quem está ligado sem sinal há 10 min ou mais e já tem aviso devido.
create or replace function public.drivers_sem_sinal_avisar()
returns integer
language plpgsql security definer
set search_path to 'public'
as $$
declare
  r   record;
  v_n integer := 0;
begin
  if coalesce((public.get_setting('drivers_sem_sinal_aviso_ligado') #>> '{}')::boolean, true) = false then
    return 0;
  end if;
  for r in
    select d.user_id, d.last_heartbeat_at,
           coalesce(now() - d.last_heartbeat_at, interval '100 years') as sem_sinal,
           (select max(a.enviado_em) from public.driver_sinal_avisos a
             where a.user_id = d.user_id
               and a.enviado_em > coalesce(d.last_heartbeat_at, '-infinity'::timestamptz)) as ultimo
      from public.drivers d
     where d.is_online
       and d.user_id is not null
       and d.approval_status = 'approved'
       and coalesce(d.is_banned, false) = false
       and (d.last_heartbeat_at is null or d.last_heartbeat_at < now() - interval '10 minutes')
  loop
    continue when not public.sinal_aviso_devido(r.sem_sinal, now() - r.ultimo);
    perform public._enviar_aviso_sem_sinal(r.user_id, r.last_heartbeat_at, 'automatico', null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Painel: botão "Enviar aviso agora" (só admin; fica no admin_audit_log).
create or replace function public.admin_driver_avisar_sem_sinal(p_user_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $$
declare
  d     record;
  v_req bigint;
begin
  if not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select user_id, name, is_online, last_heartbeat_at into d
    from public.drivers where user_id = p_user_id limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'Motorista não encontrado.');
  end if;
  if not coalesce(d.is_online, false) then
    return jsonb_build_object('ok', false,
      'motivo', 'Está desligado (botão desligado) — não há aviso a mandar.');
  end if;
  v_req := public._enviar_aviso_sem_sinal(d.user_id, d.last_heartbeat_at, 'painel', auth.uid());
  insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'driver_aviso_sem_sinal', 'driver', d.user_id::text,
          jsonb_build_object('nome', d.name, 'sinal_desde', d.last_heartbeat_at, 'request_id', v_req));
  return jsonb_build_object('ok', true, 'request_id', v_req, 'sinal_desde', d.last_heartbeat_at);
end;
$$;

revoke all on function public.sinal_aviso_devido(interval, interval) from public, anon;
revoke all on function public._enviar_aviso_sem_sinal(uuid, timestamptz, text, uuid) from public, anon, authenticated;
revoke all on function public.drivers_sem_sinal_avisar() from public, anon, authenticated;
revoke all on function public.admin_driver_avisar_sem_sinal(uuid) from public, anon;
grant execute on function public.admin_driver_avisar_sem_sinal(uuid) to authenticated;

select cron.schedule('drivers-sem-sinal-avisar', '*/2 * * * *',
                     'SELECT public.drivers_sem_sinal_avisar();');
