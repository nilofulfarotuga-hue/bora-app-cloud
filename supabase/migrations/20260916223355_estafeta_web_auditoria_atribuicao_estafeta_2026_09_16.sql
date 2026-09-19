-- ============================================================================
-- Missão estafeta-web-2026-09-16 · BLOCO 1.2 — barreira no banco (fase 1: REGISTO)
--
-- Porque existe: a 16/09 um agente pôs um pedido no nome de um estafeta com um
-- UPDATE directo em orders, por fora dos caminhos oficiais. O estafeta estava
-- desligado, o pedido ficou preso 10 minutos depois de pronto, e não ficou
-- rasto nenhum (nem edge_logs, nem order_status_events, nem admin_audit_log).
--
-- O que isto faz:
--   1. Colunas novas em orders (aditivas, nunca lidas pelo dinheiro):
--        driver_assigned_at    — quando assigned_driver_id passou a ter valor
--        preassigned_driver_id — estafeta ESCOLHIDO antes de o pedido estar
--                                pronto (user_id manda). Vira oferta normal
--                                quando a loja marca pronto (bloco 2).
--        preassigned_at / preassigned_by
--   2. Tabela order_driver_assignment_audit: TODA mudança de assigned_driver_id
--      ou driver_id fica registada (valor antigo/novo, utilizador da ligação,
--      application_name, papel do JWT, caminho oficial declarado, origem).
--   3. Trigger zzz_audit_driver_assignment (BEFORE, corre por último): regista,
--      carimba driver_assigned_at, e quando a mudança vem de ligação SQL directa
--      (sem JWT da app, sem caminho oficial, sem ser pg_cron) avisa o admin
--      pelo Telegram + push. Se orders_driver_direct_update_block = true,
--      RECUSA com a mensagem "Usa public.ops_reassign_order".
--   4. platform_settings:
--        orders_driver_direct_update_block = false  (liga-se só com o inventário
--                                                    dos caminhos oficiais 100% verde)
--        dispatch_preassign_release_seconds = 180   (rede de segurança do bloco 2)
--
-- Caminhos oficiais declaram-se com
--   set_config('bora.caminho_oficial', '<nome>', true)
-- ou já vêm com JWT (app/PostgREST/Edge Functions) ou correm no pg_cron.
-- ============================================================================

alter table public.orders
  add column if not exists driver_assigned_at    timestamptz,
  add column if not exists preassigned_driver_id text,
  add column if not exists preassigned_at        timestamptz,
  add column if not exists preassigned_by        text;

comment on column public.orders.preassigned_driver_id is
  'Estafeta escolhido antes do pedido estar pronto (user_id). Ao passar a callingDriver vira oferta normal; se não aceitar ou estiver desligado, limpa-se e o pedido segue para o dispatch normal.';
comment on column public.orders.driver_assigned_at is
  'Carimbo de quando assigned_driver_id passou a ter valor (rede de segurança: callingDriver com estafeta há mais de dispatch_preassign_release_seconds sem aceitar → liberta).';

-- ---------------------------------------------------------------------------
-- Tabela de auditoria
-- ---------------------------------------------------------------------------
create table if not exists public.order_driver_assignment_audit (
  id                     bigserial primary key,
  order_id               text        not null,
  changed_at             timestamptz not null default now(),
  op                     text        not null,
  old_assigned_driver_id text,
  new_assigned_driver_id text,
  old_driver_id          uuid,
  new_driver_id          uuid,
  old_status             text,
  new_status             text,
  db_user                text,
  sess_user              text,
  application_name       text,
  jwt_role               text,
  jwt_sub                text,
  caminho_oficial        text,
  transition_source      text,
  origem_direta          boolean     not null default false,
  bloqueio_ligado        boolean     not null default false,
  client_addr            text,
  query_snippet          text
);

create index if not exists order_driver_assignment_audit_order_idx
  on public.order_driver_assignment_audit (order_id, changed_at desc);
create index if not exists order_driver_assignment_audit_direta_idx
  on public.order_driver_assignment_audit (changed_at desc) where origem_direta;

alter table public.order_driver_assignment_audit enable row level security;
revoke all on public.order_driver_assignment_audit from public;
revoke all on public.order_driver_assignment_audit from anon;
grant select on public.order_driver_assignment_audit to authenticated;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                   and tablename = 'order_driver_assignment_audit'
                   and policyname = 'admin_select_order_driver_assignment_audit') then
    create policy admin_select_order_driver_assignment_audit
      on public.order_driver_assignment_audit for select
      to authenticated using (public.is_admin());
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Definições
-- ---------------------------------------------------------------------------
insert into public.platform_settings (key, value, description, category)
values
  ('orders_driver_direct_update_block', 'false'::jsonb,
   'Barreira: recusar mudanças de assigned_driver_id/driver_id feitas por ligação SQL directa (sem JWT da app, fora dos caminhos oficiais). false = só regista e avisa.',
   'dispatch'),
  ('dispatch_preassign_release_seconds', '180'::jsonb,
   'Rede de segurança: pedido em callingDriver com estafeta atribuído sem aceitar há mais do que isto é libertado e volta ao dispatch normal (aviso ao admin).',
   'dispatch')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Trigger de auditoria + barreira
-- ---------------------------------------------------------------------------
create or replace function public._audit_order_driver_assignment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_claims  jsonb;
  v_role    text;
  v_sub     text;
  v_app     text;
  v_oficial text;
  v_src     text;
  v_direta  boolean := false;
  v_block   boolean := false;
  v_msg     text;
begin
  -- Só interessa quando o estafeta do pedido muda.
  if tg_op = 'UPDATE'
     and new.assigned_driver_id is not distinct from old.assigned_driver_id
     and new.driver_id          is not distinct from old.driver_id then
    return new;
  end if;
  if tg_op = 'INSERT' and new.assigned_driver_id is null and new.driver_id is null then
    return new;
  end if;

  begin
    v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  exception when others then
    v_claims := null;
  end;
  v_role    := coalesce(v_claims ->> 'role', nullif(current_setting('request.jwt.claim.role', true), ''));
  v_sub     := v_claims ->> 'sub';
  v_app     := current_setting('application_name', true);
  v_oficial := nullif(current_setting('bora.caminho_oficial', true), '');
  v_src     := nullif(current_setting('app.order_transition_source', true), '');

  -- Ligação SQL directa = sem JWT da app, sem caminho oficial declarado,
  -- sem origem de transição da app, e não é o pg_cron.
  v_direta := v_role is null
              and v_oficial is null
              and v_src is null
              and coalesce(v_app, '') not ilike 'pg_cron%';

  -- Carimbo do momento da atribuição (rede de segurança do bloco 2 lê isto).
  if tg_op = 'INSERT' or new.assigned_driver_id is distinct from old.assigned_driver_id then
    new.driver_assigned_at := case when new.assigned_driver_id is null then null else now() end;
  end if;

  if v_direta then
    select coalesce((value #>> '{}')::boolean, false) into v_block
      from public.platform_settings where key = 'orders_driver_direct_update_block';
    v_block := coalesce(v_block, false);
  end if;

  insert into public.order_driver_assignment_audit (
    order_id, op,
    old_assigned_driver_id, new_assigned_driver_id,
    old_driver_id, new_driver_id,
    old_status, new_status,
    db_user, sess_user, application_name,
    jwt_role, jwt_sub, caminho_oficial, transition_source,
    origem_direta, bloqueio_ligado, client_addr, query_snippet
  ) values (
    new.id::text, tg_op,
    case when tg_op = 'UPDATE' then old.assigned_driver_id end, new.assigned_driver_id,
    case when tg_op = 'UPDATE' then old.driver_id end, new.driver_id,
    case when tg_op = 'UPDATE' then old.status end, new.status,
    current_user::text, session_user::text, v_app,
    v_role, v_sub, v_oficial, v_src,
    v_direta, v_block, inet_client_addr()::text, left(current_query(), 600)
  );

  if v_direta then
    v_msg := 'ATENCAO Bora: pedido ' || upper(substr(replace(new.id::text, '-', ''), 1, 6))
          || ' mudou de estafeta por ligacao SQL directa (' || coalesce(v_app, 'app desconhecida')
          || ', utilizador ' || current_user::text || '). De '
          || coalesce(case when tg_op = 'UPDATE' then old.assigned_driver_id end, 'ninguem')
          || ' para ' || coalesce(new.assigned_driver_id, 'ninguem') || '.'
          || case when v_block then ' BLOQUEADO. ' else ' Ficou registado. ' end
          || 'Caminho certo: public.ops_reassign_order.';
    begin
      perform public._telegram_admin(v_msg);
    exception when others then
      raise warning '_audit_order_driver_assignment: telegram falhou: %', sqlerrm;
    end;
    begin
      perform public.notify_admin_urgent_push(
        'order_driver_direct_update', v_msg, 'order', new.id::text,
        jsonb_build_object('de', case when tg_op = 'UPDATE' then old.assigned_driver_id end,
                           'para', new.assigned_driver_id, 'db_user', current_user::text,
                           'application_name', v_app, 'bloqueado', v_block),
        '/admin/orders/' || new.id::text);
    exception when others then
      raise warning '_audit_order_driver_assignment: push admin falhou: %', sqlerrm;
    end;

    if v_block then
      raise exception 'Usa public.ops_reassign_order'
        using errcode = '42501',
              hint = 'Mudanças de estafeta por ligação SQL directa estão bloqueadas. '
                     'Chama select public.ops_reassign_order(pedido, user_id_do_estafeta, motivo, agente) '
                     'ou, para devolver o pedido a todos, public.ops_release_order_driver(pedido, motivo, agente).';
    end if;
  end if;

  return new;
end;
$$;

-- Corre por ÚLTIMO entre os BEFORE (ordem alfabética): vê o NEW já
-- transformado pelos outros triggers (p.ex. a conversão pré-atribuição→oferta).
create or replace trigger zzz_audit_driver_assignment
  before insert or update on public.orders
  for each row execute function public._audit_order_driver_assignment();
