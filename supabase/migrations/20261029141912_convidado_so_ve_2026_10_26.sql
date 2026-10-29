create or replace function public.is_conta_convidado()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from auth.users u
    where u.id = auth.uid() and lower(u.email) = 'guest@bora.com'
  );
$$;
revoke all on function public.is_conta_convidado() from public, anon;
grant execute on function public.is_conta_convidado() to authenticated, service_role;
create or replace function public.trg_convidado_so_ve()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_conta_convidado() then
    raise exception 'convidado_sem_conta: entra ou cria conta para continuar'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.trg_convidado_so_ve() from public, anon;
do $$
declare t text;
begin
  foreach t in array array[
    'tvde_rides', 'appointments', 'reservations', 'carwash_bookings', 'cleaning_bookings',
    'reservation_waitlist', 'reservation_notify_list', 'tvde_access_requests', 'ratings',
    'complaints', 'support_tickets', 'client_addresses', 'client_favorites', 'users',
    'client_push_tokens'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format(
        'create or replace trigger trg_convidado_so_ve before insert or update on public.%I '
        'for each row execute function public.trg_convidado_so_ve()', t);
    end if;
  end loop;
end $$;
do $$
declare t text;
begin
  foreach t in array array[
    'tvde_rides', 'tvde_roundtrip_credits', 'tvde_access_requests', 'ratings', 'in_app_notifications',
    'client_addresses', 'client_favorites', 'client_live_locations', 'client_search_history',
    'carrinhos_abandonados', 'assistant_client_memory', 'complaints', 'support_tickets',
    'reservations', 'reservation_waitlist', 'reservation_notify_list', 'appointments',
    'carwash_bookings', 'cleaning_bookings', 'blocked_users', 'preferencias_papel'
  ] loop
    if to_regclass('public.' || t) is not null
       and (select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)) then
      if not exists (select 1 from pg_policies
                     where schemaname = 'public' and tablename = t and policyname = 'convidado_so_ve') then
        execute format(
          'create policy convidado_so_ve on public.%I as restrictive for all to authenticated '
          'using (not (select public.is_conta_convidado())) with check (not (select public.is_conta_convidado()))', t);
      end if;
    end if;
  end loop;
end $$;
insert into public.platform_settings (key, value, description, category, is_secret)
values
  ('visitantes_sem_conta', 'true'::jsonb,
   'Visitantes podem ver a app sem conta (lojas, produtos, carrinho). A conta só se pede ao finalizar.',
   'cliente', false),
  ('sessao_convidado_ativa', 'false'::jsonb,
   'Sessão de convidado (guest@bora.com) pela Edge sessao-convidado. Ligar só depois de aplicada a guarda de pedidos (create_order).',
   'cliente', false)
on conflict (key) do nothing;
