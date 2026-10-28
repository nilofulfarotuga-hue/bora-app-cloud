-- 20261026090000_convidado_so_ve.sql
-- Missão melhorias-paridade-2026-10-26, item 2 — a conta partilhada guest@bora.com só VÊ.
--
-- Porquê: a conta de convidado é partilhada por todos os visitantes. A 31/08/2026 pediu corridas
-- TVDE reais e todos os convidados viam as linhas uns dos outros (mesmo auth.uid()). A partir de
-- agora a sessão volta (Edge sessao-convidado, palavra-passe só no servidor), mas o banco recusa
-- ao convidado:
--   · ler, criar, mudar ou apagar dados de cliente (moradas, favoritos, avaliações, corridas…);
--   · criar corridas, marcações, reservas e lavagens/limpezas, mesmo pelas funções SECURITY DEFINER
--     (gatilho BEFORE INSERT, que corre sempre).
-- Os pedidos (orders/create_order) ficam no pacote da publicação: zona protegida, só se prepara
-- (.claude/.ai/reports/melhorias-paridade-2026-10-26/pendente_create_order.sql).
--
-- Só aditivo: uma função, um gatilho, políticas RESTRICTIVE (só tiram acesso ao convidado) e duas
-- definições novas. Não muda dados. Reverter: ver o bloco REVERTER no fim.

-- 1. Quem é o convidado (pelo email, sem ids escritos à mão).
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

-- 2. Gatilho: o convidado não cria nem muda linhas destas tabelas (corre também dentro de RPCs).
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

-- 3. Políticas RESTRICTIVE: o convidado não lê nem escreve dados de cliente pela API.
--    (Só se aplicam a tabelas com RLS ligada; para os outros papéis não muda nada.)
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

-- 4. Definições (texto, não dinheiro). Ficam visíveis a anon pela get_setting (is_secret=false).
insert into public.platform_settings (key, value, description, category, is_secret)
values
  ('visitantes_sem_conta', 'true'::jsonb,
   'Visitantes podem ver a app sem conta (lojas, produtos, carrinho). A conta só se pede ao finalizar.',
   'cliente', false),
  ('sessao_convidado_ativa', 'false'::jsonb,
   'Sessão de convidado (guest@bora.com) pela Edge sessao-convidado. Ligar só depois de aplicada a guarda de pedidos (create_order).',
   'cliente', false)
on conflict (key) do nothing;

-- REVERTER (à mão, se preciso):
--   do $$ declare t text; begin foreach t in array array[<lista do passo 2>] loop
--     if to_regclass('public.'||t) is not null then
--       execute format('drop trigger if exists trg_convidado_so_ve on public.%I', t); end if; end loop; end $$;
--   do $$ declare t text; begin foreach t in array array[<lista do passo 3>] loop
--     if to_regclass('public.'||t) is not null then
--       execute format('drop policy if exists convidado_so_ve on public.%I', t); end if; end loop; end $$;
--   drop function if exists public.trg_convidado_so_ve(); drop function if exists public.is_conta_convidado();
--   delete from public.platform_settings where key in ('visitantes_sem_conta','sessao_convidado_ativa');
