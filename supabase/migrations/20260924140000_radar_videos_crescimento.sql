-- Radar de vídeos de crescimento (missão radar-videos-crescimento-2026-09-24).
-- Guarda os ~20 vídeos/dia do YouTube (crescer em IG/FB/Reels/TikTok; ganhar dinheiro online e
-- marketing de apps) que o PC do Danilo recolhe com yt-dlp (legendas só saem de IP de casa), com
-- o resumo e as 3 ideias práticas escritas por GLM/Gemini, e o «livro de regras» que se destila
-- semanalmente (regra só entra vista em >= 3 vídeos, com os links como prova).
-- RLS: só admin lê. Quem escreve é o robô do PC pela RPC radar_videos_registar (chave no Vault
-- 'radar_videos_key'). Nada aqui toca em dinheiro, dispatch ou dados de pessoas.

create table if not exists public.radar_videos (
  youtube_id      text primary key,
  titulo          text not null,
  canal           text,
  visualizacoes   bigint,
  publicado_em    date,
  duracao_s       integer,
  link            text not null,
  lingua          text,
  tema            text,                     -- crescer_redes | ganhar_dinheiro | marketing_apps | outro
  pesquisa        text,                     -- a pesquisa que o encontrou
  tem_transcricao boolean not null default false,
  transcricao_resumida text,
  ideias          jsonb,                    -- ["...", "...", "..."]
  nota_utilidade  smallint check (nota_utilidade between 0 and 10),
  motor_resumo    text,                     -- glm-5.2 | gemini-... | ollama-... | nenhum
  recolhido_em    timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index if not exists radar_videos_recolhido_idx on public.radar_videos (recolhido_em desc);
create index if not exists radar_videos_tema_idx on public.radar_videos (tema, nota_utilidade desc);
alter table public.radar_videos enable row level security;
drop policy if exists radar_videos_admin_le on public.radar_videos;
create policy radar_videos_admin_le on public.radar_videos for select to authenticated using (public.is_admin());
comment on table public.radar_videos is 'Radar diário de vídeos do YouTube sobre crescer nas redes e ganhar dinheiro online (recolha no PC, resumo por GLM/Gemini). Só admin lê.';

create table if not exists public.playbook_redes (
  id            bigint generated always as identity primary key,
  versao        integer not null,
  regra         text not null,
  categoria     text,                       -- gancho | duracao | legendas | horarios | frequencia | cta | formato | outro
  provas        jsonb not null default '[]'::jsonb,   -- [{"youtube_id":..., "link":..., "titulo":...}]
  n_videos      integer not null default 0,
  ativa         boolean not null default true,
  criado_em     timestamptz not null default now()
);
alter table public.playbook_redes enable row level security;
drop policy if exists playbook_redes_admin_le on public.playbook_redes;
create policy playbook_redes_admin_le on public.playbook_redes for select to authenticated using (public.is_admin());
comment on table public.playbook_redes is 'Livro de regras das redes (destilado do radar de vídeos): cada regra com >= 3 vídeos como prova. Só admin lê; os robôs leem o ficheiro docs/marketing/PLAYBOOK-REDES.md.';

-- Escrita pelo robô do PC (chave no Vault; vault.create_secret('<chave>', 'radar_videos_key')).
create or replace function public.radar_videos_registar(p_chave text, p_linha jsonb)
returns text
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'radar_videos_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  insert into public.radar_videos (youtube_id, titulo, canal, visualizacoes, publicado_em, duracao_s, link, lingua, tema,
                                   pesquisa, tem_transcricao, transcricao_resumida, ideias, nota_utilidade, motor_resumo)
  values (p_linha->>'youtube_id', coalesce(p_linha->>'titulo','(sem título)'), p_linha->>'canal',
          nullif(p_linha->>'visualizacoes','')::bigint, nullif(p_linha->>'publicado_em','')::date,
          nullif(p_linha->>'duracao_s','')::integer, coalesce(p_linha->>'link', 'https://www.youtube.com/watch?v=' || (p_linha->>'youtube_id')),
          p_linha->>'lingua', p_linha->>'tema', p_linha->>'pesquisa', coalesce((p_linha->>'tem_transcricao')::boolean, false),
          p_linha->>'transcricao_resumida', p_linha->'ideias', nullif(p_linha->>'nota_utilidade','')::smallint, p_linha->>'motor_resumo')
  on conflict (youtube_id) do update
     set visualizacoes = excluded.visualizacoes, transcricao_resumida = coalesce(excluded.transcricao_resumida, radar_videos.transcricao_resumida),
         ideias = coalesce(excluded.ideias, radar_videos.ideias), nota_utilidade = coalesce(excluded.nota_utilidade, radar_videos.nota_utilidade),
         motor_resumo = coalesce(excluded.motor_resumo, radar_videos.motor_resumo), tema = coalesce(excluded.tema, radar_videos.tema),
         tem_transcricao = excluded.tem_transcricao or radar_videos.tem_transcricao, atualizado_em = now();
  return p_linha->>'youtube_id';
end $$;
revoke all on function public.radar_videos_registar(text, jsonb) from public;
grant execute on function public.radar_videos_registar(text, jsonb) to anon, authenticated, service_role;

-- Ids já conhecidos (para o robô não repetir) e as ideias recentes (para destilar o playbook).
create or replace function public.radar_videos_ler(p_chave text, p_dias integer default 30)
returns setof jsonb
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'radar_videos_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  return query select jsonb_build_object('youtube_id', youtube_id, 'titulo', titulo, 'canal', canal, 'link', link, 'tema', tema,
                 'ideias', ideias, 'nota_utilidade', nota_utilidade, 'recolhido_em', recolhido_em, 'tem_transcricao', tem_transcricao)
    from public.radar_videos where recolhido_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 365)))
    order by recolhido_em desc;
end $$;
revoke all on function public.radar_videos_ler(text, integer) from public;
grant execute on function public.radar_videos_ler(text, integer) to anon, authenticated, service_role;

create or replace function public.playbook_redes_registar(p_chave text, p_versao integer, p_regras jsonb)
returns integer
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text; r jsonb; n integer := 0;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'radar_videos_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  update public.playbook_redes set ativa = false where ativa and versao < p_versao;
  for r in select * from jsonb_array_elements(p_regras) loop
    insert into public.playbook_redes (versao, regra, categoria, provas, n_videos)
    values (p_versao, r->>'regra', r->>'categoria', coalesce(r->'provas', '[]'::jsonb), coalesce((r->>'n_videos')::integer, jsonb_array_length(coalesce(r->'provas','[]'::jsonb))));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.playbook_redes_registar(text, integer, jsonb) from public;
grant execute on function public.playbook_redes_registar(text, integer, jsonb) to anon, authenticated, service_role;

-- Painel admin (PT-BR): o dia, filtro por tema, e o playbook atual.
create or replace function public.admin_radar_videos(p_dias integer default 7, p_tema text default null)
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(v) from public.radar_videos v
  where public.is_admin() and v.recolhido_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 365)))
    and (p_tema is null or v.tema = p_tema)
  order by v.recolhido_em desc, v.nota_utilidade desc nulls last;
$$;
revoke all on function public.admin_radar_videos(integer, text) from public;
grant execute on function public.admin_radar_videos(integer, text) to authenticated, service_role;

create or replace function public.admin_playbook_redes()
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(p) from public.playbook_redes p where public.is_admin() and p.ativa order by p.categoria, p.n_videos desc, p.id;
$$;
revoke all on function public.admin_playbook_redes() from public;
grant execute on function public.admin_playbook_redes() to authenticated, service_role;
