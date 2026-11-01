-- 01/11/2026: cópia de segurança do catálogo (products) antes da limpeza de duplicados/preços/categorias
-- e tabela de registo das mudanças dessa limpeza.
-- (Aplicada em produção a 01/11/2026 — versão 20261101201135; espelho no repo escrito na missão
--  zona-vermelha-2026-11-01, SQL lido de schema_migrations.statements.)
create table public.bkp_products_20261101 as select * from public.products;
create table public.catalogo_dedupe_log_20261101 (
  id bigserial primary key,
  criado_em timestamptz default now(),
  loja text,
  tipo text,            -- 'dedupe' | 'preco' | 'categoria' | 'needs_review'
  nome text,
  id_mantido text,
  ids_desligados text[],
  precos_grupo numeric[],
  preco_antes numeric,
  preco_depois numeric,
  categoria_antes text,
  categoria_depois text,
  fonte text,
  detalhe jsonb
);
