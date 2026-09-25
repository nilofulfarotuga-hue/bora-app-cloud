-- Presença Digital Bora — avença para negócios locais (missão agente-avenca-preparacao-2026-09-24).
--
-- O que é: a Bora passa a vender aos negócios da Guarda (raio 20 km) o trabalho que os robôs já
-- fazem para ela própria — publicações no Instagram e Facebook, mini-site, ficha Google e
-- atendimento por WhatsApp. Referência de mercado em Portugal: 150 a 600 €/mês.
--
-- ESTA MIGRAÇÃO SÓ GUARDA PREPARAÇÃO. Não cria produto nem preço no Stripe, não cobra nada a
-- ninguém e não manda nada para fora. Três tabelas: os negócios encontrados (só dados públicos do
-- próprio negócio), a amostra que se fez para cada um, e o rascunho da proposta.
--
-- RLS: só o admin lê. Quem escreve é o robô do PC, por RPC com chave no Vault
-- ('prospects_presenca_key') — a mesma receita do radar de vídeos.

create table if not exists public.prospects_presenca (
  id             bigint generated always as identity primary key,
  fonte_id       text unique,              -- id da fonte pública (ex.: osm:node/123456)
  nome           text not null,
  categoria      text,                     -- restaurante | cafe | cabeleireiro | barbearia | oficina | pneus | ginasio | clinica | alojamento | loja | outro
  morada         text,
  concelho       text,
  lat            double precision,
  lon            double precision,
  km_da_guarda   numeric(5,1),
  -- contactos e presença, todos públicos e do próprio negócio
  telefone       text,
  email          text,
  website        text,
  instagram      text,
  facebook       text,
  -- o que falta (é isto que dá a oportunidade)
  sem_site       boolean not null default false,
  sem_telefone   boolean not null default false,
  sem_horario    boolean not null default false,
  ficha_google   text,                     -- completa | incompleta | sem_ficha | por_ver
  instagram_parado_dias integer,           -- null = não verificado
  pontuacao      smallint check (pontuacao between 0 and 100),
  estado         text not null default 'novo'
                 check (estado in ('novo','amostra_pronta','proposta_rascunho','aprovado_danilo','enviado','cliente','recusado','descartado')),
  notas          text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now()
);
create index if not exists prospects_presenca_pont_idx on public.prospects_presenca (pontuacao desc nulls last);
create index if not exists prospects_presenca_estado_idx on public.prospects_presenca (estado, categoria);
alter table public.prospects_presenca enable row level security;
drop policy if exists prospects_presenca_admin_le on public.prospects_presenca;
create policy prospects_presenca_admin_le on public.prospects_presenca for select to authenticated using (public.is_admin());
comment on table public.prospects_presenca is 'Negocios da Guarda (raio 20 km) com presenca digital fraca, so com dados publicos do proprio negocio. Preparacao da avenca Presenca Digital Bora. So admin le.';

create table if not exists public.prospect_amostras (
  id            bigint generated always as identity primary key,
  prospect_id   bigint not null references public.prospects_presenca(id) on delete cascade,
  link_unico    text not null unique,      -- a pagina privada que se mostra ao negocio
  mini_site     text,                      -- caminho/URL da demonstracao
  publicacoes   jsonb not null default '[]'::jsonb,  -- as 2 pecas prontas
  diagnostico_google jsonb,                -- o que falta na ficha
  criado_em     timestamptz not null default now()
);
alter table public.prospect_amostras enable row level security;
drop policy if exists prospect_amostras_admin_le on public.prospect_amostras;
create policy prospect_amostras_admin_le on public.prospect_amostras for select to authenticated using (public.is_admin());

create table if not exists public.prospect_propostas (
  id            bigint generated always as identity primary key,
  prospect_id   bigint not null references public.prospects_presenca(id) on delete cascade,
  canal         text not null default 'email' check (canal in ('email','whatsapp','presencial')),
  assunto       text,
  texto         text not null,
  preco_mes_eur numeric(7,2) not null default 149,
  estado        text not null default 'rascunho' check (estado in ('rascunho','aprovado_danilo','enviado')),
  criado_em     timestamptz not null default now()
);
alter table public.prospect_propostas enable row level security;
drop policy if exists prospect_propostas_admin_le on public.prospect_propostas;
create policy prospect_propostas_admin_le on public.prospect_propostas for select to authenticated using (public.is_admin());
comment on table public.prospect_propostas is 'Rascunhos das propostas de avenca, em nome da Bora. Nada sai daqui sem o sim do Danilo: o estado comeca sempre em rascunho.';

-- ---------------------------------------------------------------- escrita pelo robo do PC
create or replace function public.prospect_registar(p_chave text, p_linha jsonb)
returns bigint
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text; v_id bigint;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'prospects_presenca_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  insert into public.prospects_presenca (fonte_id, nome, categoria, morada, concelho, lat, lon, km_da_guarda,
         telefone, email, website, instagram, facebook, sem_site, sem_telefone, sem_horario, ficha_google,
         instagram_parado_dias, pontuacao, notas)
  values (p_linha->>'fonte_id', coalesce(p_linha->>'nome','(sem nome)'), p_linha->>'categoria', p_linha->>'morada',
          p_linha->>'concelho', nullif(p_linha->>'lat','')::double precision, nullif(p_linha->>'lon','')::double precision,
          nullif(p_linha->>'km_da_guarda','')::numeric, p_linha->>'telefone', p_linha->>'email', p_linha->>'website',
          p_linha->>'instagram', p_linha->>'facebook', coalesce((p_linha->>'sem_site')::boolean,false),
          coalesce((p_linha->>'sem_telefone')::boolean,false), coalesce((p_linha->>'sem_horario')::boolean,false),
          coalesce(p_linha->>'ficha_google','por_ver'), nullif(p_linha->>'instagram_parado_dias','')::integer,
          nullif(p_linha->>'pontuacao','')::smallint, p_linha->>'notas')
  on conflict (fonte_id) do update
     set nome = excluded.nome, categoria = coalesce(excluded.categoria, prospects_presenca.categoria),
         morada = coalesce(excluded.morada, prospects_presenca.morada),
         telefone = coalesce(excluded.telefone, prospects_presenca.telefone),
         email = coalesce(excluded.email, prospects_presenca.email),
         website = coalesce(excluded.website, prospects_presenca.website),
         instagram = coalesce(excluded.instagram, prospects_presenca.instagram),
         facebook = coalesce(excluded.facebook, prospects_presenca.facebook),
         sem_site = excluded.sem_site, sem_telefone = excluded.sem_telefone, sem_horario = excluded.sem_horario,
         ficha_google = coalesce(excluded.ficha_google, prospects_presenca.ficha_google),
         pontuacao = coalesce(excluded.pontuacao, prospects_presenca.pontuacao),
         notas = coalesce(excluded.notas, prospects_presenca.notas),
         atualizado_em = now()
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.prospect_registar(text, jsonb) from public;
grant execute on function public.prospect_registar(text, jsonb) to anon, authenticated, service_role;

create or replace function public.prospect_amostra_registar(p_chave text, p_prospect bigint, p_linha jsonb)
returns bigint
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text; v_id bigint;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'prospects_presenca_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  insert into public.prospect_amostras (prospect_id, link_unico, mini_site, publicacoes, diagnostico_google)
  values (p_prospect, p_linha->>'link_unico', p_linha->>'mini_site',
          coalesce(p_linha->'publicacoes','[]'::jsonb), p_linha->'diagnostico_google')
  on conflict (link_unico) do update
     set mini_site = excluded.mini_site, publicacoes = excluded.publicacoes,
         diagnostico_google = excluded.diagnostico_google
  returning id into v_id;
  update public.prospects_presenca set estado = 'amostra_pronta', atualizado_em = now()
   where id = p_prospect and estado = 'novo';
  return v_id;
end $$;
revoke all on function public.prospect_amostra_registar(text, bigint, jsonb) from public;
grant execute on function public.prospect_amostra_registar(text, bigint, jsonb) to anon, authenticated, service_role;

create or replace function public.prospect_proposta_registar(p_chave text, p_prospect bigint, p_linha jsonb)
returns bigint
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text; v_id bigint;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'prospects_presenca_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  -- o estado fica SEMPRE em rascunho: quem envia e o Danilo, nunca o robo.
  insert into public.prospect_propostas (prospect_id, canal, assunto, texto, preco_mes_eur, estado)
  values (p_prospect, coalesce(p_linha->>'canal','email'), p_linha->>'assunto', p_linha->>'texto',
          coalesce(nullif(p_linha->>'preco_mes_eur','')::numeric, 149), 'rascunho')
  returning id into v_id;
  update public.prospects_presenca set estado = 'proposta_rascunho', atualizado_em = now()
   where id = p_prospect and estado in ('novo','amostra_pronta');
  return v_id;
end $$;
revoke all on function public.prospect_proposta_registar(text, bigint, jsonb) from public;
grant execute on function public.prospect_proposta_registar(text, bigint, jsonb) to anon, authenticated, service_role;

create or replace function public.prospects_ler(p_chave text)
returns setof jsonb
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'prospects_presenca_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  return query select to_jsonb(p) from public.prospects_presenca p order by p.pontuacao desc nulls last, p.id;
end $$;
revoke all on function public.prospects_ler(text) from public;
grant execute on function public.prospects_ler(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------- painel admin (PT-BR)
create or replace function public.admin_prospects_presenca(p_estado text default null, p_limite integer default 300)
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(p) || jsonb_build_object(
           'amostras', (select count(*) from public.prospect_amostras a where a.prospect_id = p.id),
           'propostas', (select count(*) from public.prospect_propostas r where r.prospect_id = p.id))
  from public.prospects_presenca p
  where public.is_admin() and (p_estado is null or p.estado = p_estado)
  order by p.pontuacao desc nulls last, p.id
  limit greatest(1, least(coalesce(p_limite, 300), 2000));
$$;
revoke all on function public.admin_prospects_presenca(text, integer) from public;
grant execute on function public.admin_prospects_presenca(text, integer) to authenticated, service_role;

create or replace function public.admin_prospect_detalhe(p_id bigint)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'prospect', (select to_jsonb(p) from public.prospects_presenca p where p.id = p_id),
    'amostras', coalesce((select jsonb_agg(to_jsonb(a) order by a.criado_em desc) from public.prospect_amostras a where a.prospect_id = p_id), '[]'::jsonb),
    'propostas', coalesce((select jsonb_agg(to_jsonb(r) order by r.criado_em desc) from public.prospect_propostas r where r.prospect_id = p_id), '[]'::jsonb)
  ) end;
$$;
revoke all on function public.admin_prospect_detalhe(bigint) from public;
grant execute on function public.admin_prospect_detalhe(bigint) to authenticated, service_role;

create or replace function public.admin_prospects_resumo()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'total', (select count(*) from public.prospects_presenca),
    'sem_site', (select count(*) from public.prospects_presenca where sem_site),
    'por_estado', (select jsonb_object_agg(estado, n) from (select estado, count(*) as n from public.prospects_presenca group by estado) s),
    'amostras', (select count(*) from public.prospect_amostras),
    'propostas_rascunho', (select count(*) from public.prospect_propostas where estado = 'rascunho')
  ) end;
$$;
revoke all on function public.admin_prospects_resumo() from public;
grant execute on function public.admin_prospects_resumo() to authenticated, service_role;
