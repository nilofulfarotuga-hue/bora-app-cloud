-- 26/10/2026 (geral-sabado-24-10, bloco 5): lista do Glovo da Guarda de 23/10 (McDonald's e BK),
-- tirada da migração 20261023223000, numa tabela de apoio para a desativação e o acerto.
-- Aplicada por execute_sql; os 187 nomes/preços entraram por REST a partir desse ficheiro.
create table if not exists public.glovo_precos_restaurantes (
  capturado_em date not null, loja text not null, nome text not null, preco_glovo numeric(10,2) not null,
  primary key (capturado_em, loja, nome));
comment on table public.glovo_precos_restaurantes is 'Lista do Glovo da Guarda usada na paridade de 23/10 (McDonalds/BK), tirada da migracao 20261023223000. Apoio, so leitura.';
alter table public.glovo_precos_restaurantes enable row level security;
revoke all on public.glovo_precos_restaurantes from public, anon, authenticated;
