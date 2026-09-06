-- =====================================================================
-- C3 — Motor de Conhecimento: estado do digest visível na Central de Autonomia
--
-- Porque é preciso: o digest e o `digest-status.json` vivem no DISCO DO PC.
-- O app Flutter não consegue lê-los. Esta tabela é a ponte: o consolidador
-- (que corre no PC, 04:00 e 16:00) escreve aqui o estado, e o admin lê.
--
-- Zona VERDE: nada aqui toca dinheiro. As 2 chaves de toggle já existem em
-- platform_settings (categoria 'knowledge', criadas no C1) e NÃO são chaves
-- financeiras (stripe_/pricing_/commission_/fee_/token_).
-- =====================================================================

-- 1. Tabela de estado — UMA linha só (id fixo a true).
create table if not exists public.knowledge_digest_status (
  id             boolean primary key default true check (id),
  gerado_em      timestamptz,
  tamanho_bytes  integer,
  licoes         integer,
  armadilhas     integer,
  em_aberto      integer,
  regras         integer,
  cortadas       integer,
  cadencia       text,
  preview        text,          -- primeiros ~2 KB do digest, para o cartão
  atualizado_em  timestamptz not null default now()
);

alter table public.knowledge_digest_status enable row level security;

-- Leitura: qualquer autenticado (mesmo padrão do platform_settings, que só tem
-- policy de SELECT para `authenticated`). Escrita: NENHUMA policy -> só service_role
-- (o consolidador) consegue escrever. O app nunca escreve aqui.
drop policy if exists knowledge_digest_status_select_authed on public.knowledge_digest_status;
create policy knowledge_digest_status_select_authed
  on public.knowledge_digest_status for select to authenticated using (true);

-- 2. Leitura para o admin: estado + os 2 toggles, numa só chamada.
create or replace function public.admin_knowledge_digest_status()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_st record; v_on boolean; v_cad text;
begin
  perform public._admin_op_guard();
  select * into v_st from public.knowledge_digest_status where id limit 1;
  select (value #>> '{}')::boolean into v_on
    from public.platform_settings where key = 'knowledge_consolidator_enabled';
  select (value #>> '{}') into v_cad
    from public.platform_settings where key = 'knowledge_consolidator_cadence';
  return jsonb_build_object(
    'ligado',        coalesce(v_on, true),
    'cadencia',      coalesce(v_cad, '2x'),
    'gerado_em',     v_st.gerado_em,
    'tamanho_bytes', v_st.tamanho_bytes,
    'licoes',        v_st.licoes,
    'armadilhas',    v_st.armadilhas,
    'em_aberto',     v_st.em_aberto,
    'regras',        v_st.regras,
    'cortadas',      v_st.cortadas,
    'preview',       v_st.preview
  );
end; $$;

-- 3. Toggle do consolidador. RPC PRÓPRIA, com whitelist própria — de propósito
-- NÃO se mexe na `admin_autonomy_set_switch`, que é o kill switch do Robot B.
-- Alargar a whitelist dela punha o botão do Cérebro no mesmo caminho do botão
-- que trava a autonomia toda; um erro ali teria consequência muito maior.
create or replace function public.admin_knowledge_set_switch(p_key text, p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public._admin_op_guard();
  if p_key <> 'knowledge_consolidator_enabled' then
    raise exception 'CHAVE_NAO_PERMITIDA: só o toggle do consolidador';
  end if;
  insert into public.platform_settings(key, value, updated_at)
    values (p_key, to_jsonb(p_enabled), now())
    on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true, 'key', p_key, 'enabled', p_enabled);
end; $$;

-- 4. Cadência 2x/dia <-> 1x/dia (a corrida das 16h auto-salta em '1x').
create or replace function public.admin_knowledge_set_cadence(p_cadence text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  perform public._admin_op_guard();
  if p_cadence not in ('1x','2x') then
    raise exception 'CADENCIA_INVALIDA: use 1x ou 2x';
  end if;
  insert into public.platform_settings(key, value, updated_at)
    values ('knowledge_consolidator_cadence', to_jsonb(p_cadence), now())
    on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true, 'cadencia', p_cadence);
end; $$;

revoke all on function public.admin_knowledge_digest_status() from public, anon;
revoke all on function public.admin_knowledge_set_switch(text, boolean) from public, anon;
revoke all on function public.admin_knowledge_set_cadence(text) from public, anon;
grant execute on function public.admin_knowledge_digest_status() to authenticated;
grant execute on function public.admin_knowledge_set_switch(text, boolean) to authenticated;
grant execute on function public.admin_knowledge_set_cadence(text) to authenticated;
