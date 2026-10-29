-- 20261026092000_home_banners_no_repo.sql
-- Missão melhorias-paridade-2026-10-26, item 21 — a tabela home_banners existe em produção
-- (ecrã admin_home_banners_screen.dart e banners da página inicial) mas não tinha migração no
-- repositório. Este ficheiro descreve-a TAL COMO ESTÁ em produção (lida a 26/10/2026 por
-- information_schema / pg_policies / pg_constraint).
--
-- IDEMPOTENTE e NÃO PARA APLICAR em produção (já lá está): serve para o repo bater certo com o
-- banco e para um banco novo (ramo, local) nascer igual. Correr duas vezes não muda nada.

create table if not exists public.home_banners (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null,
  subtitulo     text,
  imagem_url    text,
  cor_inicio    text default '#16A34A',
  cor_fim       text default '#F97316',
  tipo_destino  text not null default 'nenhum',
  destino       text,
  ordem         integer not null default 100,
  ativo         boolean not null default true,
  inicio        timestamptz,
  fim           timestamptz,
  patrocinado   boolean not null default false,
  parceiro_id   text,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conname = 'home_banners_tipo_destino_check'
                   and conrelid = 'public.home_banners'::regclass) then
    alter table public.home_banners
      add constraint home_banners_tipo_destino_check
      check (tipo_destino = any (array['loja','categoria','cozinha','produto','codigo','nenhum']));
  end if;
end $$;

alter table public.home_banners enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'home_banners' and policyname = 'home_banners_admin_escrever') then
    create policy home_banners_admin_escrever on public.home_banners
      for all to public using (public.is_admin()) with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'home_banners' and policyname = 'home_banners_ler_ativas') then
    create policy home_banners_ler_ativas on public.home_banners
      for select to public using (
        (ativo and (inicio is null or inicio <= now()) and (fim is null or fim > now()))
        or public.is_admin()
      );
  end if;
end $$;
