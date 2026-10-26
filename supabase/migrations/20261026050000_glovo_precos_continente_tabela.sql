-- 26/10/2026 (geral-sabado-24-10, bloco 5): tabela de apoio com a fotografia dos preços do
-- Continente no Glovo da Guarda (robô do PC, API pública). Aplicada por execute_sql antes da
-- paridade; os dados entram pelo robô (.claude/.ai/provas/geral-sabado-2026-10-24/glovo_precos_continente.js).
create table if not exists public.glovo_precos_continente (
  capturado_em timestamptz not null,
  external_id  text not null,
  nome         text,
  preco_glovo  numeric(10,2) not null,
  link         text,
  primary key (capturado_em, external_id)
);
comment on table public.glovo_precos_continente is 'Fotografia dos precos do Continente no Glovo da Guarda (robo do PC, missao geral-sabado-24-10 bloco 5). So leitura de apoio a paridade "so subir".';
alter table public.glovo_precos_continente enable row level security;
revoke all on public.glovo_precos_continente from public, anon, authenticated;
