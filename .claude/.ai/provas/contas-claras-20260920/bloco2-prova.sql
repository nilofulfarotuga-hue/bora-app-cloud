-- Bloco 2 — extrato do estafeta/motorista — provas em produção a 20/09/2026 (identidade real do Valdemir, JWT simulado).

select set_config('request.jwt.claims', '{"sub":"e355fde0-b634-48ba-bce1-e2a4466c4cc2","role":"authenticated"}', true);
with x as (select public.extrato_prestador(26) as j)
select j->'pessoa'->>'nome', j->'resumo'->'semana', jsonb_array_length(j->'trabalhos'),
  (j->'entregas')::jsonb - 'nota'::text, (j->'corridas')::jsonb - 'nota'::text,
  j->'carteira'->>'saldo_cents', j->'dinheiro_em_mao'->>'total_recebido_cents', j->'dinheiro_em_mao'->>'total_fica_para_a_bora_cents',
  j->'deve_lhe_a_bora', j->'deve_a_bora', j->>'saldo_cents', j->'taloes'->0->>'texto'
from x;
-- SAÍDA (20h49 UTC): Valdemir Vasconcelos · semana {ganho 5700, trabalhos 14, entregas 500, corridas 5200, tokens 40} · 27 trabalhos (26 sem)
--   entregas: ganhos_total 2494, ficou_para_a_bora 2366, tokens_conv 0, saldo_historico 128, saldo_arca 128, bate=true  ← = driver_balances (Bloco 0)
--   corridas: bora_deve 5150, deve_a_bora 2000, saldo_historico 3150, saldo_arca 3150, bate=true             ← = −tvde_driver_balances (Bloco 0)
--   carteira 0 · dinheiro em mão recebido 11692, é da Bora 3966 (14 linhas) · 4 acertos, último 14/09–20/09 pending 500
--   deve_lhe_a_bora: [Esta semana (fecha na segunda-feira) 500, Corridas TVDE pagas na app 3150] = 3650 · deve_a_bora 0 · saldo 3650
--   talão: "Reembolso pago por MB Way a 19/09"

-- ecrã antigo (driver_earnings_summary) × extrato: têm de dar o mesmo
with a as (select public.driver_earnings_summary() as s), b as (select public.extrato_prestador(4) as e)
select a.s->'dia'->>'total_cents', b.e->'resumo'->'hoje'->>'ganho_cents', a.s->'semana'->>'total_cents', b.e->'resumo'->'semana'->>'ganho_cents',
       a.s->'semana_passada'->>'total_cents', b.e->'resumo'->'semana_passada'->>'ganho_cents' from a, b;
-- SAÍDA: hoje 1700=1700 · semana 5700=5700 · semana passada 2321=2321

-- previsão da semana em curso (v0, via get_driver_current_week_summary) sem persistir
-- SAÍDA: semana_em_curso {net_balance 5, direction bora_pays_driver, persisted false, total_deliveries 1}; driver_weekly_settlements do Valdemir: 4 antes, 4 depois

-- flutter analyze (PC, Flutter 3.47): 0 errors (250 infos/warnings pré-existentes no repo)
