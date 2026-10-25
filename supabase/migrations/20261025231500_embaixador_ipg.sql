-- Embaixador Bora no Politécnico (IPG) — missão guarda-primeiro-2026-10-26.
--
-- Autorização do Danilo, 25/10/2026 22:43 e 22:57 ("Autorizo para os três." /
-- "Eu autorizo tudo aí, caramba."): 2 € ao embaixador por cliente que use o código
-- E faça o 1.º pedido pago entregue; teto 20 €/semana; o próprio embaixador e contas
-- repetidas (mesmo telemóvel/morada) não contam.
--
-- Esta migração NÃO paga nada a ninguém. Cria:
--   1) os códigos IPG1 (ligado) e IPG2..IPG5 (desligados), iguais ao BEMVINDO;
--   2) a ficha de cada embaixador (public.embaixadores);
--   3) a conta, só de leitura (public.vw_embaixador_ipg);
--   4) as funções do painel (resumo por semana e guardar a ficha).

-- 1) Códigos — mesmo tipo e valor do BEMVINDO, 1 por pessoa, teto 100 usos.
insert into public.promo_codes (code, type, value_cents, max_uses, max_uses_per_user, min_order_cents, is_active)
select v.code, b.type, b.value_cents, 100, 1, 0, v.ativo
from (values ('IPG1', true), ('IPG2', false), ('IPG3', false), ('IPG4', false), ('IPG5', false)) as v(code, ativo)
cross join public.promo_codes b
where b.code = 'BEMVINDO'
on conflict (code) do nothing;

-- 2) Ficha do embaixador. O valor por cliente e o teto ficam aqui (não no código das funções).
create table if not exists public.embaixadores (
  code text primary key references public.promo_codes(code) on update cascade,
  nome text,
  user_id uuid references auth.users(id) on delete set null,
  telefone text,
  valor_por_cliente_cents integer not null default 200 check (valor_por_cliente_cents >= 0),
  teto_semana_cents integer not null default 2000 check (teto_semana_cents >= 0),
  notas text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
alter table public.embaixadores enable row level security;
revoke all on public.embaixadores from public, anon, authenticated;

insert into public.embaixadores (code)
values ('IPG1'), ('IPG2'), ('IPG3'), ('IPG4'), ('IPG5')
on conflict (code) do nothing;

-- 3) A conta, cliente a cliente. motivo_exclusao vazio = conta para o pagamento.
--    "Pago entregue" = status delivered + payment_status paid (dinheiro, MB Way ou cartão).
--    Telemóvel compara pelos últimos 9 dígitos; morada sem maiúsculas nem espaços a mais.
create or replace view public.vw_embaixador_ipg with (security_invoker = true) as
with usos as (
  select u.code, u.user_id, min(u.used_at) as usou_em
  from public.promo_code_uses u
  join public.embaixadores e on e.code = u.code
  group by u.code, u.user_id
),
entregues as (
  select o.user_id,
         o.id as pedido_id,
         coalesce(o.delivered_at, o.created_at) as entregue_em,
         right(regexp_replace(coalesce(o.client_phone, ''), '\D', '', 'g'), 9) as tel9,
         lower(regexp_replace(trim(coalesce(o.dropoff_address, '')), '\s+', ' ', 'g')) as morada
  from public.orders o
  where o.status = 'delivered'
    and o.payment_status = 'paid'
    and coalesce(o.is_test_order, false) = false
    and o.user_id is not null
),
primeiro as (
  select distinct on (user_id) * from entregues order by user_id, entregue_em
),
base as (
  select us.code,
         e.nome as embaixador,
         us.user_id,
         cu.name as cliente,
         us.usou_em,
         p.pedido_id,
         p.entregue_em,
         coalesce(nullif(p.tel9, ''), right(regexp_replace(coalesce(cu.phone, ''), '\D', '', 'g'), 9)) as tel9,
         coalesce(p.morada, '') as morada,
         e.user_id as emb_user_id,
         right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 9) as emb_tel9
  from usos us
  join public.embaixadores e on e.code = us.code
  left join primeiro p on p.user_id = us.user_id
  left join public.users cu on cu.id = us.user_id
)
select b.code,
       b.embaixador,
       b.user_id,
       b.cliente,
       b.usou_em,
       b.pedido_id,
       b.entregue_em,
       (date_trunc('week', b.entregue_em at time zone 'Europe/Lisbon'))::date as semana,
       case
         when b.pedido_id is null then 'ainda sem pedido pago entregue'
         when b.entregue_em < b.usou_em then 'já tinha pedido antes de usar o código'
         when b.emb_user_id is not null and b.user_id = b.emb_user_id then 'é o próprio embaixador'
         when b.emb_tel9 <> '' and b.tel9 = b.emb_tel9 then 'telemóvel do embaixador'
         when b.emb_user_id is not null and b.morada <> '' and exists (
                select 1 from entregues x where x.user_id = b.emb_user_id and x.morada = b.morada)
           then 'morada do embaixador'
         when exists (
                select 1 from entregues x
                where x.user_id <> b.user_id
                  and x.entregue_em < b.entregue_em
                  and ((b.tel9 <> '' and x.tel9 = b.tel9) or (b.morada <> '' and x.morada = b.morada)))
           then 'conta repetida (telemóvel ou morada de outra conta)'
       end as motivo_exclusao
from base b;

revoke all on public.vw_embaixador_ipg from public, anon, authenticated;

-- 4a) Resumo para o painel: códigos, semanas (com teto) e clientes.
create or replace function public.admin_embaixador_resumo(p_semanas integer default 8)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_desde date := (date_trunc('week', now() at time zone 'Europe/Lisbon'))::date
                  - (greatest(coalesce(p_semanas, 8), 1) - 1) * 7;
  v jsonb;
begin
  perform public._admin_op_guard();

  select jsonb_build_object(
    'codigos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', e.code, 'nome', e.nome, 'user_id', e.user_id, 'telefone', e.telefone,
               'notas', e.notas, 'ativo', pc.is_active, 'usos', pc.uses_count,
               'max_usos', pc.max_uses, 'valor_por_cliente_cents', e.valor_por_cliente_cents,
               'teto_semana_cents', e.teto_semana_cents)
             order by e.code)
      from public.embaixadores e
      join public.promo_codes pc on pc.code = e.code), '[]'::jsonb),
    'semanas', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.semana desc, s.code)
      from (
        select v.semana,
               v.code,
               count(*) filter (where v.motivo_exclusao is null) as elegiveis,
               count(*) filter (where v.motivo_exclusao is not null) as excluidos,
               least(count(*) filter (where v.motivo_exclusao is null) * max(e.valor_por_cliente_cents),
                     max(e.teto_semana_cents)) as a_pagar_cents
        from public.vw_embaixador_ipg v
        join public.embaixadores e on e.code = v.code
        where v.semana is not null and v.semana >= v_desde
        group by v.semana, v.code
      ) s), '[]'::jsonb),
    'clientes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', v.code, 'cliente', v.cliente, 'usou_em', v.usou_em,
               'entregue_em', v.entregue_em, 'semana', v.semana,
               'motivo_exclusao', v.motivo_exclusao)
             order by v.usou_em desc)
      from public.vw_embaixador_ipg v), '[]'::jsonb)
  ) into v;

  return v;
end;
$$;

-- 4b) Guardar a ficha e ligar/desligar o código. Não mexe no valor nem no teto.
create or replace function public.admin_embaixador_guardar(
  p_code text,
  p_nome text,
  p_telefone text,
  p_email text,
  p_notas text,
  p_ativo boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(p_code));
  v_user uuid;
begin
  perform public._admin_op_guard();

  if not exists (select 1 from public.embaixadores where code = v_code) then
    return jsonb_build_object('ok', false, 'motivo', 'codigo_nao_e_de_embaixador');
  end if;

  if nullif(trim(coalesce(p_email, '')), '') is not null then
    select id into v_user from public.users where lower(email) = lower(trim(p_email)) limit 1;
    if v_user is null then
      return jsonb_build_object('ok', false, 'motivo', 'email_sem_conta');
    end if;
  end if;

  update public.embaixadores
     set nome = nullif(trim(coalesce(p_nome, '')), ''),
         telefone = nullif(trim(coalesce(p_telefone, '')), ''),
         user_id = v_user,
         notas = nullif(trim(coalesce(p_notas, '')), ''),
         atualizado_em = now()
   where code = v_code;

  if p_ativo is not null then
    update public.promo_codes set is_active = p_ativo where code = v_code;
  end if;

  perform public.log_admin_action('embaixador_atualizado', 'promo_code', v_code,
    jsonb_build_object('code', v_code, 'nome', p_nome, 'ativo', p_ativo, 'conta_ligada', v_user is not null));

  return jsonb_build_object('ok', true, 'code', v_code, 'conta_ligada', v_user is not null);
end;
$$;

revoke all on function public.admin_embaixador_resumo(integer) from public, anon;
revoke all on function public.admin_embaixador_guardar(text, text, text, text, text, boolean) from public, anon;
grant execute on function public.admin_embaixador_resumo(integer) to authenticated;
grant execute on function public.admin_embaixador_guardar(text, text, text, text, text, boolean) to authenticated;
