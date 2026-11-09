-- =============================================================================
-- O AMIGO — O ROSTO (missão m11-amigo-rosto-2026-11-09, ordem do Danilo
-- 09/11/2026 05:11: "Ele vai ser um rosto... tem que ter as expressões")
--
--   1. Cópia das definições do assistente ANTES de mexer (nada é apagado).
--   2. Cinco definições novas (painel /admin/assistente, separador Amigo Bora):
--      amigo_rosto_ativo, amigo_rosto_variante, amigo_voz_ligada_por_defeito,
--      amigo_voz_velocidade, amigo_mosaico_categorias. Os clientes leem-nas
--      como as outras do assistente (não são segredos).
--   3. assistant_amigo_eventos — a contagem de uso do rosto (abriu o ecrã,
--      falou por voz ou por escrita, quanto tempo ficou). RLS: o dono insere e
--      lê o seu; o admin lê tudo. Sem dados de conversa, só contagens.
--   4. admin_amigo_rosto_overview — os números e os interruptores do rosto
--      para o painel (só admin). A admin_amigo_overview de 08/11 fica igual.
--
-- Zona verde: nenhuma escrita em pedidos nem em dinheiro. Idempotente.
-- =============================================================================

-- ─── 1. Cópia antes de mexer ──────────────────────────────────────────────────
create table if not exists public.bkp_platform_settings_amigo_20261109 as
  select * from public.platform_settings
   where category = 'assistente' or key like 'assistant\_%' or key like 'amigo\_%';

-- ─── 2. Definições ────────────────────────────────────────────────────────────
insert into public.platform_settings (key, value, description, category)
values
  ('amigo_rosto_ativo', 'true'::jsonb,
   'O Amigo como rosto vivo que fala: rostinho na home e ecrã do Amigo com voz e expressões. Desligado = volta o botão "Ajuda-me a escolher" e o chat escrito de 08/11.',
   'assistente'),
  ('amigo_rosto_variante', '"rosto_camisa"'::jsonb,
   'Desenho do Amigo no ecrã: "rosto" (só a cara) ou "rosto_camisa" (cara + camisa verde com o logótipo da Bora ao peito). Na home aparece sempre só a cara.',
   'assistente'),
  ('amigo_voz_ligada_por_defeito', 'true'::jsonb,
   'O Amigo fala em voz alta (voz pt-PT do telemóvel/navegador). O cliente pode desligar o som e fica lembrado no aparelho. Sem voz pt-PT no aparelho, fala só por legenda.',
   'assistente'),
  ('amigo_voz_velocidade', '1.0'::jsonb,
   'Velocidade da voz do Amigo (0,5 a 2; 1 = normal).',
   'assistente'),
  ('amigo_mosaico_categorias', 'true'::jsonb,
   'Mosaico "Amigo" com o rostinho animado no início da grelha de categorias da home.',
   'assistente')
on conflict (key) do nothing;

-- ─── 3. Uso do rosto ──────────────────────────────────────────────────────────
create table if not exists public.assistant_amigo_eventos (
  id         bigserial primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  tipo       text not null check (tipo in ('abrir', 'voz', 'escrita', 'fim')),
  duracao_s  integer check (duracao_s is null or (duracao_s >= 0 and duracao_s <= 86400)),
  plataforma text check (plataforma is null or plataforma in ('android', 'ios', 'web')),
  criado_em  timestamptz not null default now()
);
comment on table public.assistant_amigo_eventos is
  'O rosto do Amigo (m11, 09/11/2026): aberturas do ecrã, mensagens por voz/escrita e tempo de conversa. Só contagens, sem texto.';

create index if not exists assistant_amigo_eventos_criado_idx
  on public.assistant_amigo_eventos (criado_em desc);
create index if not exists assistant_amigo_eventos_user_idx
  on public.assistant_amigo_eventos (user_id, criado_em desc);

alter table public.assistant_amigo_eventos enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'assistant_amigo_eventos' and policyname = 'amigo_eventos_dono_insere') then
    create policy amigo_eventos_dono_insere on public.assistant_amigo_eventos
      for insert to authenticated
      with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'assistant_amigo_eventos' and policyname = 'amigo_eventos_dono_ou_admin_le') then
    create policy amigo_eventos_dono_ou_admin_le on public.assistant_amigo_eventos
      for select to authenticated
      using (user_id = (select auth.uid()) or coalesce((select public.is_admin()), false));
  end if;
end $$;

revoke all on public.assistant_amigo_eventos from public, anon;
grant select, insert on public.assistant_amigo_eventos to authenticated;
grant usage, select on sequence public.assistant_amigo_eventos_id_seq to authenticated;
grant all on public.assistant_amigo_eventos to service_role;

-- ─── 4. Painel admin ──────────────────────────────────────────────────────────
create or replace function public.admin_amigo_rosto_overview(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_dias  integer := greatest(1, least(coalesce(p_dias, 30), 365));
  v_desde timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 365)));
  v jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;

  with e as (
    select * from public.assistant_amigo_eventos where criado_em >= v_desde
  )
  select jsonb_build_object(
    'dias', v_dias,
    'aberturas', (select count(*) from e where tipo = 'abrir'),
    'clientes', (select count(distinct user_id) from e where tipo = 'abrir'),
    'mensagens_voz', (select count(*) from e where tipo = 'voz'),
    'mensagens_escrita', (select count(*) from e where tipo = 'escrita'),
    'pct_voz', (select case when count(*) = 0 then 0
                            else round(100.0 * count(*) filter (where tipo = 'voz') / count(*), 1) end
                  from e where tipo in ('voz', 'escrita')),
    'tempo_medio_s', (select coalesce(round(avg(duracao_s)), 0) from e
                       where tipo = 'fim' and duracao_s between 1 and 3600),
    'tempo_total_min', (select coalesce(round(sum(duracao_s) / 60.0, 1), 0) from e
                         where tipo = 'fim' and duracao_s between 1 and 3600),
    'por_plataforma', coalesce((select jsonb_agg(jsonb_build_object('plataforma', coalesce(plataforma, '?'), 'n', n) order by n desc)
                                  from (select plataforma, count(*) as n from e where tipo = 'abrir' group by 1) x), '[]'::jsonb),
    'por_dia', coalesce((select jsonb_agg(jsonb_build_object('dia', dia, 'aberturas', n) order by dia)
                           from (select to_char(criado_em at time zone 'Europe/Lisbon', 'YYYY-MM-DD') as dia, count(*) as n
                                   from e where tipo = 'abrir' group by 1) d), '[]'::jsonb),
    'interruptores', jsonb_build_object(
       'amigo_rosto_ativo', (select value from public.platform_settings where key = 'amigo_rosto_ativo'),
       'amigo_rosto_variante', (select value from public.platform_settings where key = 'amigo_rosto_variante'),
       'amigo_voz_ligada_por_defeito', (select value from public.platform_settings where key = 'amigo_voz_ligada_por_defeito'),
       'amigo_voz_velocidade', (select value from public.platform_settings where key = 'amigo_voz_velocidade'),
       'amigo_mosaico_categorias', (select value from public.platform_settings where key = 'amigo_mosaico_categorias'))
  ) into v;
  return v;
end;
$$;

revoke all on function public.admin_amigo_rosto_overview(integer) from public, anon;
grant execute on function public.admin_amigo_rosto_overview(integer) to authenticated;
