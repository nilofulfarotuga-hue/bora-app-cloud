-- =============================================================================
-- farmacias-2026-11-11 · 04 · "Repetir todos os meses" + tarefas agendadas
-- O lembrete mensal NUNCA faz pedido nem cobra: só avisa; o toque abre o formulário já preenchido.
-- Depende de 03.
-- =============================================================================

create table if not exists public.farmacia_lembretes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  prescricao_id uuid references public.pedidos_prescricao(id) on delete set null,
  order_id text,
  dia_do_mes integer not null check (dia_do_mes between 1 and 28),
  ativo boolean not null default true,
  proximo_em date not null,
  ultimo_aviso_em timestamptz
);
create index if not exists farmacia_lembretes_proximo_idx on public.farmacia_lembretes (proximo_em) where ativo;
alter table public.farmacia_lembretes enable row level security;
revoke all on public.farmacia_lembretes from public, anon;
grant select on public.farmacia_lembretes to authenticated;
drop policy if exists farmacia_lembretes_ver on public.farmacia_lembretes;
create policy farmacia_lembretes_ver on public.farmacia_lembretes for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create or replace function public._farmacia_proximo_dia(p_dia integer, p_desde date)
returns date language sql immutable as $$
  select case
    when make_date(extract(year from p_desde)::int, extract(month from p_desde)::int, p_dia) > p_desde
      then make_date(extract(year from p_desde)::int, extract(month from p_desde)::int, p_dia)
    else (make_date(extract(year from p_desde)::int, extract(month from p_desde)::int, p_dia) + interval '1 month')::date
  end;
$$;

create or replace function public.farmacia_lembrete_definir(p_restaurant_id text, p_prescricao_id uuid default null,
                                                            p_order_id text default null, p_dia integer default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_dia integer;
begin
  if v_uid is null then raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501'; end if;
  if not public.farmacia_botoes_visiveis(p_restaurant_id) then
    raise exception 'FARMACIA_INDISPONIVEL: Este serviço ainda não está disponível nesta farmácia.' using errcode = 'P0001';
  end if;
  v_dia := coalesce(p_dia, least(28, extract(day from (now() at time zone 'Europe/Lisbon'))::int));
  if v_dia < 1 or v_dia > 28 then raise exception 'DIA_INVALIDO: Escolha um dia entre 1 e 28.' using errcode = 'P0001'; end if;
  if p_prescricao_id is not null and not exists (
       select 1 from public.pedidos_prescricao where id = p_prescricao_id and user_id = v_uid) then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if (select count(*) from public.farmacia_lembretes where user_id = v_uid and ativo) >= 10 then
    raise exception 'DEMASIADOS_LEMBRETES: Já tem 10 lembretes ligados.' using errcode = 'P0001';
  end if;
  insert into public.farmacia_lembretes (user_id, restaurant_id, prescricao_id, order_id, dia_do_mes, proximo_em)
  values (v_uid, p_restaurant_id, p_prescricao_id, p_order_id, v_dia,
          public._farmacia_proximo_dia(v_dia, (now() at time zone 'Europe/Lisbon')::date))
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.farmacia_lembrete_definir(text, uuid, text, integer) from public, anon;
grant execute on function public.farmacia_lembrete_definir(text, uuid, text, integer) to authenticated;

create or replace function public.farmacia_lembrete_desligar(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  update public.farmacia_lembretes set ativo = false where id = p_id and (user_id = auth.uid() or public.is_admin());
  if not found then raise exception 'NAO_ENCONTRADO: Lembrete não encontrado.' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.farmacia_lembrete_desligar(uuid) from public, anon;
grant execute on function public.farmacia_lembrete_desligar(uuid) to authenticated;

-- Diária: avisa quem tem lembrete para hoje (ou atrasado) e marca o próximo mês. Só avisa.
create or replace function public.farmacia_lembretes_disparar()
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record; n integer := 0; v_url text; v_key text;
  v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  for r in select l.*, rs.name as loja from public.farmacia_lembretes l join public.restaurants rs on rs.id = l.restaurant_id
            where l.ativo and l.proximo_em <= v_hoje
  loop
    update public.farmacia_lembretes set ultimo_aviso_em = now(),
           proximo_em = public._farmacia_proximo_dia(r.dia_do_mes, v_hoje) where id = r.id;
    begin
      perform public._push_in_app_notification(r.user_id, 'farmacia_lembrete_mensal',
        'Está na altura de repetir o seu pedido', 'Toque para pedir outra vez na ' || r.loja || '.',
        coalesce(r.prescricao_id::text, r.restaurant_id));
      if v_url is not null and v_key is not null then
        perform net.http_post(url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('clientId', r.user_id, 'orderId', coalesce(r.prescricao_id::text, ''),
                                     'type', 'farmacia_lembrete_mensal', 'status', 'farmacia_lembrete_mensal',
                                     'kind', r.restaurant_id,
                                     'title', 'Está na altura de repetir o seu pedido',
                                     'body', 'Toque para pedir outra vez na ' || r.loja || '. Nada é pedido sem a sua confirmação.'));
      end if;
    exception when others then raise notice 'lembrete mensal: %', sqlerrm;
    end;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.farmacia_lembretes_disparar() from public, anon, authenticated;

-- Limpeza dos dados de saúde: devolve o que a Edge prescricoes-limpeza tem de apagar no Storage
-- e, depois de apagado, a Edge chama prescricao_marcar_dados_apagados.
create or replace function public.prescricao_para_limpar(p_limite integer default 200)
returns table (id uuid, caminhos text[])
language sql stable security definer
set search_path = public, pg_temp
as $$
  select pp.id, array_remove(array[pp.receita_foto_path, pp.pedido_foto_path, pp.assinatura_path], null)
    from public.pedidos_prescricao pp
   where pp.dados_apagados_em is null
     and pp.estado in ('entregue', 'recusado', 'expirado', 'cancelado', 'confirmado')
     and coalesce(pp.entregue_em, pp.cancelado_em, pp.respondido_em, pp.confirmado_em, pp.expira_em, pp.created_at)
         <= now() - make_interval(days => public._setting_int('pharmacy_prescription_retention_days', 30))
   limit greatest(1, least(coalesce(p_limite, 200), 1000));
$$;
revoke all on function public.prescricao_para_limpar(integer) from public, anon, authenticated;
grant execute on function public.prescricao_para_limpar(integer) to service_role;

create or replace function public.prescricao_marcar_dados_apagados(p_ids uuid[])
returns integer
language sql security definer
set search_path = public, pg_temp
as $$
  with u as (
    update public.pedidos_prescricao set
      receita_foto_path = null, pedido_foto_path = null, assinatura_path = null,
      receita_numero = null, receita_codigo_acesso = null, receita_codigo_opcao = null,
      dados_apagados_em = now()
    where id = any (p_ids) and dados_apagados_em is null
    returning 1)
  select count(*)::int from u;
$$;
revoke all on function public.prescricao_marcar_dados_apagados(uuid[]) from public, anon, authenticated;
grant execute on function public.prescricao_marcar_dados_apagados(uuid[]) to service_role;

-- ---- pg_cron (corre em UTC; Lisboa no inverno = UTC, no verão = UTC+1 → às 10:00 de Lisboa no verão) ----
do $$
begin
  if exists (select 1 from cron.job where jobname = 'farmacias-prescricao-vigiar') then
    perform cron.unschedule('farmacias-prescricao-vigiar');
  end if;
  perform cron.schedule('farmacias-prescricao-vigiar', '* * * * *', 'select public.prescricao_vigiar();');

  if exists (select 1 from cron.job where jobname = 'farmacias-lembretes-mensais') then
    perform cron.unschedule('farmacias-lembretes-mensais');
  end if;
  perform cron.schedule('farmacias-lembretes-mensais', '0 9 * * *', 'select public.farmacia_lembretes_disparar();');

  if exists (select 1 from cron.job where jobname = 'farmacias-prescricoes-limpeza') then
    perform cron.unschedule('farmacias-prescricoes-limpeza');
  end if;
  perform cron.schedule('farmacias-prescricoes-limpeza', '40 3 * * *', $c$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/prescricoes-limpeza',
      headers := jsonb_build_object('Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                                    'Content-Type', 'application/json'),
      body := '{}'::jsonb);
  $c$);
end $$;
