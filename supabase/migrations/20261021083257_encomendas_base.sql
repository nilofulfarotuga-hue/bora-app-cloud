-- 2026-10-21 · super-missão fechar-pendencias-2026-10-20 · BLOCO A1 (1/3)
-- Encomendas = cópia exacta do Bora Motorista (TVDE), só com outras palavras.
-- Desenho do MISSAO.md de 20/10 ("um motor só"): a corrida ganha o tipo
-- (ride_kind 'passageiros' | 'encomendas'); preço, despacho, pagamentos,
-- reservas, cancelamento e acerto são os MESMOS (as mesmas funções).
--
-- Esta migração é só ADITIVA:
--   0. cópia das 6 funções que as migrações 2 e 3 vão trocar (regra: backup antes);
--   1. coluna tvde_rides.ride_kind (as 293 corridas antigas ficam 'passageiros');
--   2. interruptores tvde_passageiros_enabled (TRUE) e tvde_encomendas_enabled (FALSE);
--   3. tipo DECLARADO do próximo pedido (tvde_tipo_pedido) — só para o caminho do
--      cartão/MB Way, que passa pela Edge Function tvde-payment (intocável) e por
--      isso não consegue mandar o p_ride_kind às RPCs. A app grava-o mesmo antes
--      de chamar a Edge; a RPC consome-o ao criar a corrida (vale 5 minutos);
--   4. _tvde_ride_kind_resolver: regra única do tipo (parâmetro > declarado >
--      'passageiros') + portão das encomendas (interruptor; o admin passa);
--   5. a volta do pacote ida-e-volta herda SEMPRE o tipo da ida (gatilho).
-- Nenhum valor de preço é criado nem lido de forma diferente.

-- 0. Backup ---------------------------------------------------------------------
create table if not exists public.bkp_fn_encomendas_20261021 as
  select p.proname::text                          as nome,
         pg_get_function_identity_arguments(p.oid) as assinatura,
         pg_get_functiondef(p.oid)                 as definicao,
         md5(p.prosrc)                             as prosrc_md5,
         p.proacl::text                            as acl,
         now()                                     as copiado_em
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('tvde_request_ride', 'tvde_schedule_ride', 'tvde_schedule_roundtrip',
                       'fn_notify_tvde_client_on_status', 'admin_tvde_rides_list_v2',
                       'admin_tvde_reservations_list');
alter table public.bkp_fn_encomendas_20261021 enable row level security;
revoke all on table public.bkp_fn_encomendas_20261021 from public, anon, authenticated;

-- 1. A marca da corrida ----------------------------------------------------------
alter table public.tvde_rides
  add column if not exists ride_kind text not null default 'passageiros';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'tvde_rides_ride_kind_check'
                    and conrelid = 'public.tvde_rides'::regclass) then
    alter table public.tvde_rides
      add constraint tvde_rides_ride_kind_check
      check (ride_kind in ('passageiros', 'encomendas'));
  end if;
end $$;

comment on column public.tvde_rides.ride_kind is
  'passageiros (Bora Motorista) | encomendas (Bora Encomendas). Mesmo motor, mesmo preço, mesmo despacho; só muda o texto. 21/10/2026 (fechar-pendencias A1).';

create index if not exists tvde_rides_encomendas_idx
  on public.tvde_rides (created_at desc) where ride_kind = 'encomendas';

-- 2. Interruptores ------------------------------------------------------------------
insert into public.platform_settings (key, value, category, description) values
  ('tvde_passageiros_enabled', 'true'::jsonb, 'tvde',
   'Bora Motorista (passageiros) ligado. Nesta versão ainda NENHUM código lê esta chave: existe para o painel. Não fecha nada (ordem do Danilo: nunca fechar o Bora Motorista a clientes).'),
  ('tvde_encomendas_enabled', 'false'::jsonb, 'tvde',
   'Bora Encomendas: encomendas no MESMO motor do Bora Motorista (mesmo preço, despacho, pagamentos, reservas e cancelamento; só mudam as palavras). Desligado: o ladrilho Enviar Encomenda abre o fluxo antigo e o servidor recusa encomendas (encomendas_desligadas), salvo admin.')
on conflict (key) do nothing;

-- 3. Tipo declarado do próximo pedido (caminho cartão/MB Way) ------------------------
create table if not exists public.tvde_tipo_pedido (
  client_id   uuid primary key,
  ride_kind   text not null check (ride_kind in ('passageiros', 'encomendas')),
  definido_em timestamptz not null default now()
);
alter table public.tvde_tipo_pedido enable row level security;
revoke all on table public.tvde_tipo_pedido from public, anon, authenticated;
drop policy if exists tvde_tipo_pedido_proprio on public.tvde_tipo_pedido;
create policy tvde_tipo_pedido_proprio on public.tvde_tipo_pedido
  for select to authenticated using (client_id = auth.uid());
comment on table public.tvde_tipo_pedido is
  'Tipo (passageiros/encomendas) do PRÓXIMO pedido de corrida do cliente quando o pedido passa pela Edge tvde-payment (cartão/MB Way). A app grava-o com tvde_definir_tipo_pedido mesmo antes; a RPC que cria a corrida consome-o (vale 5 minutos). 21/10/2026.';

create or replace function public.tvde_definir_tipo_pedido(p_ride_kind text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_ride_kind is null or p_ride_kind not in ('passageiros', 'encomendas') then
    raise exception 'invalid_ride_kind: %', p_ride_kind;
  end if;
  if p_ride_kind = 'encomendas'
     and not coalesce((public.get_setting('tvde_encomendas_enabled') #>> '{}')::boolean, false)
     and not public.is_admin() then
    raise exception 'encomendas_desligadas';
  end if;
  insert into public.tvde_tipo_pedido (client_id, ride_kind, definido_em)
  values (v_uid, p_ride_kind, now())
  on conflict (client_id) do update
    set ride_kind = excluded.ride_kind, definido_em = excluded.definido_em;
  return p_ride_kind;
end $$;
revoke all on function public.tvde_definir_tipo_pedido(text) from public, anon;
grant execute on function public.tvde_definir_tipo_pedido(text) to authenticated, service_role;

-- 4. Regra única do tipo ----------------------------------------------------------
-- p_ride_kind dito pela app manda; senão o declarado há menos de 5 min; senão
-- 'passageiros' (= tudo o que existe hoje e todas as versões instaladas).
-- Consome sempre o declarado (não sobra para o pedido seguinte).
create or replace function public._tvde_ride_kind_resolver(p_uid uuid, p_ride_kind text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_decl text; v_kind text;
begin
  if p_ride_kind is not null and p_ride_kind not in ('passageiros', 'encomendas') then
    raise exception 'invalid_ride_kind: %', p_ride_kind;
  end if;
  if p_uid is not null then
    delete from public.tvde_tipo_pedido t
     where t.client_id = p_uid
    returning case when t.definido_em > now() - interval '5 minutes' then t.ride_kind end
         into v_decl;
  end if;
  v_kind := coalesce(p_ride_kind, v_decl, 'passageiros');
  if v_kind = 'encomendas'
     and not coalesce((public.get_setting('tvde_encomendas_enabled') #>> '{}')::boolean, false)
     and not public.is_admin() then
    raise exception 'encomendas_desligadas';
  end if;
  return v_kind;
end $$;
revoke all on function public._tvde_ride_kind_resolver(uuid, text) from public, anon, authenticated;
grant execute on function public._tvde_ride_kind_resolver(uuid, text) to service_role;

-- 5. A volta do pacote herda o tipo da ida -------------------------------------------
create or replace function public.fn_tvde_ride_kind_da_volta()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_kind text;
begin
  if coalesce(new.is_return_leg, false) and new.roundtrip_credit_id is not null then
    select r.ride_kind into v_kind
      from public.tvde_roundtrip_credits c
      join public.tvde_rides r on r.id = c.outbound_ride_id
     where c.id = new.roundtrip_credit_id;
    if v_kind is not null then new.ride_kind := v_kind; end if;
  end if;
  return new;
end $$;
revoke all on function public.fn_tvde_ride_kind_da_volta() from public, anon, authenticated;

drop trigger if exists trg_tvde_ride_kind_da_volta on public.tvde_rides;
create trigger trg_tvde_ride_kind_da_volta
  before insert on public.tvde_rides
  for each row execute function public.fn_tvde_ride_kind_da_volta();
