-- Radar de videos v2 (04/10/2026): os temas deixam de viver no script do PC e passam a esta tabela,
-- gerida pelo Claude.ai por MCP a partir das conversas com o Danilo. O PC le-os com radar_pesquisas_do_dia().
-- Aplicada em producao por MCP (apply_migration, versao 20261004150308). Este ficheiro e a copia literal
-- da parte estrutural; as 48 sementes de temas vivem so em producao (tabela radar_pesquisas).
create table if not exists public.radar_pesquisas (
  id bigserial primary key,
  termo text not null unique,
  tema text not null,
  origem text not null default 'claude-ai',
  motivo text,
  ativo boolean not null default true,
  peso smallint not null default 1 check (peso between 1 and 3),
  vezes integer not null default 0,
  ultima_vez timestamptz,
  criado_em timestamptz not null default now()
);
comment on table public.radar_pesquisas is 'Temas que o radar de videos procura no YouTube. Gerido pelo Claude.ai (MCP) a partir das conversas com o Danilo; o PC le com radar_pesquisas_do_dia(). peso 3 = sai quase todos os dias, 1 = de 3 em 3 dias.';
alter table public.radar_pesquisas enable row level security;
create policy radar_pesquisas_admin_le on public.radar_pesquisas for select using (is_admin());

-- Cruzamento diario feito pelo Claude.ai: o que cada video vale para o Danilo.
alter table public.radar_videos
  add column if not exists veredito text,
  add column if not exists para text,
  add column if not exists acao text,
  add column if not exists revisto_em timestamptz;
comment on column public.radar_videos.veredito is 'ja_temos | novo | feito | rejeitado (pago, risco, ou nao serve)';
comment on column public.radar_videos.para is 'bora | em_dia | sistema | dinheiro';

create or replace function public.radar_pesquisas_do_dia(p_chave text, p_n integer default 8)
returns setof jsonb
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'radar_videos_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  return query
  with escolhidas as (
    select id from public.radar_pesquisas
     where ativo
     order by coalesce(ultima_vez, 'epoch'::timestamptz) + make_interval(days => 3 - peso), random()
     limit greatest(1, least(coalesce(p_n, 8), 20))
  ), marcadas as (
    update public.radar_pesquisas r
       set ultima_vez = now(), vezes = r.vezes + 1
      from escolhidas e
     where r.id = e.id
    returning r.termo, r.tema
  )
  select jsonb_build_object('termo', m.termo, 'tema', m.tema) from marcadas m;
end
$function$;
grant execute on function public.radar_pesquisas_do_dia(text, integer) to anon, authenticated, service_role;
