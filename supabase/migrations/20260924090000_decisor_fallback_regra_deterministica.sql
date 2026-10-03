-- Decisor (Jev/Gemini) — motor 'fallback' (missão fecho-manha-2026-09-24, bloco 2).
--
-- A 23/09 23:07 a Gemini devolveu 429/503 e o Jev não tem chave: a varredura gravava
-- motor='nenhum' sem resposta. A partir de agora, quando os dois motores falham, a Edge
-- Function `decidir` devolve a regra determinística de hoje (despacho: o candidato mais
-- perto; no-show: nível 0; Robot B: 'sim' = fica para o Danilo; suporte: 'nao') e grava
-- a linha com motor='fallback' e o erro dos motores no campo `erro`.
-- Nada aqui toca em preços, comissões, dispatch_engine nem RLS de dinheiro: só a lista de
-- valores permitidos na coluna `motor` da tabela de observação `decisoes`.
ALTER TABLE public.decisoes DROP CONSTRAINT IF EXISTS decisoes_motor_check;
ALTER TABLE public.decisoes
  ADD CONSTRAINT decisoes_motor_check CHECK (motor IN ('jev','gemini','fallback','nenhum'));
COMMENT ON COLUMN public.decisoes.motor IS
  'jev | gemini | fallback (os dois motores falharam: regra determinística de hoje, ver erro) | nenhum (diagnóstico de um motor só)';
