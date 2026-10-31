-- 20261031_decisoes_motor_claude.sql
-- Missao motor-claude-2026-10-31 (Bloco 2). NAO aplicado: vai para o passo PUBLICAR, junto com a
-- Edge Function decidir (que passa a pedir ao Claude primeiro e grava motor = 'claude').
-- Medido a 31/10 (SELECT pg_get_constraintdef): decisoes_motor_check so aceita jev, gemini, fallback, nenhum.
-- Enquanto isto nao for aplicado, a decidir grava as respostas do Claude como motor 'gemini' com o
-- modelo verdadeiro (claude-...) e a nota "motor real: claude" no campo erro.
-- So mexe no check desta tabela de decisoes em sombra: nada de precos, dinheiro, pedidos ou estafetas.

begin;
alter table public.decisoes drop constraint if exists decisoes_motor_check;
alter table public.decisoes add constraint decisoes_motor_check
  check (motor = any (array['claude'::text, 'jev'::text, 'gemini'::text, 'fallback'::text, 'nenhum'::text]));
commit;

-- Prova depois de aplicar (so leitura):
--   select pg_get_constraintdef(oid) from pg_constraint where conname = 'decisoes_motor_check';
