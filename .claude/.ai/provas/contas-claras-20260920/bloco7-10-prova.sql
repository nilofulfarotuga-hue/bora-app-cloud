-- Blocos 7 a 10 (adendo de 20/09 à noite) — corridas TVDE sem tarifa — provas em produção 20/09 22h20–23h20.

-- 7.1 as corridas finalizadas com tarifa a zero (final e estimada), com o que o evento de fecho diz
select r.id, r.created_at::date, r.source, r.payment_method, r.is_return_leg, r.roundtrip_credit_id is not null as prepaid, r.used_subscription_ride, r.driver_earn_cents, r.bora_cut_cents
from tvde_rides r where r.status='finalizada' and coalesce(r.final_fare_cents,0)=0 and coalesce(r.est_fare_cents,0)=0 order by r.created_at;
-- SAÍDA: 11 linhas → 10 voltas de pacote (is_return_leg=t, roundtrip_credit_id, earn 350, cut 0, evento prepaid=true) + 1 corrida de plano
--        (5680dd97 14/08, used_subscription_ride=t, earn 340, cut 60). Nenhuma de balcão. Todas fechadas pelo driver (actor 'driver').

-- 7.2 os pares ida/volta dos pacotes (tvde_roundtrip_credits) — a ida é que leva o dinheiro
-- SAÍDA: 10 créditos de 800; nas idas a dinheiro (rt_cash=true: 2bdc3f15, f51f7c17, 466bb4bc, 762c7c39) settle=+400 (motorista deve 4,00 = 8,00 − 4,00);
--        nas idas MB Way settle=−400; em TODAS as voltas settle=−350 (Bora deve 3,50 ao motorista da volta) e fare=0.
--        Idas com fare=0 gravado: 466bb4bc (31/08), 762c7c39 (03/09), ff0336d1, 79235511, 9b411aaf, 1b522c7b (setembro) — as de 30/08 têm fare=800.

-- 7.3 a causa no código (pg_proc tvde_finish_ride, linhas 45–90)
--   IF v_prepaid THEN ... IF is_return_leg THEN v_fare := v_stops_fee + v_extra_fare (l.66) ELSE v_fare := v_stops_fee (l.71) ...
--   ELSIF v_covered THEN v_fare := v_stops_fee (l.80/85)
--   → final_fare_cents NÃO é o que o passageiro pagou nos pacotes e planos; o pacote está em tvde_roundtrip_credits.paid_cents.

-- 7.4 quanto erra a regra "tarifa em falta = ganho + corte" (formula) contra a verdade dos eventos (earn + settle)
-- SAÍDA: Danilo 41 corridas, 11 erradas, formula 15580 vs verdade 8780 (erro +6800); Valdemir 21 corridas, 2 erradas que se anulam (6800 = 6800);
--        Erika 0/1; Rui 0/1. Detalhe Danilo: 9 voltas f=350 v=0; plano 5680dd97 f=400 v=0; ida 466bb4bc f=450 v=800; 1d24a5c2 f=350 v=−3600 (evento velho de 50 km).

-- 8.1 depois da migration contas_claras_b8_dinheiro_em_mao_corrida: coluna × verdade dos eventos
-- SAÍDA: Danilo 41 corridas, 0 sem valor, 0 deduzidas, em_mao 12380, 1 difere (1d24a5c2: coluna 0, evento −3600 — o evento é o errado);
--        Erika 1/0/0 (0=0); Rui 1/0/0 (900=900); Valdemir 21/0/0 (6800=6800).

-- 8.2 gatilho ao vivo, em rollback: corrida normal a dinheiro finalizada SEM tarifa (earn 400, cut 100)
-- SAÍDA: cash_in_hand=500 fare_deduced=t achado_vigia=1 (RESULT ... esperado 500/t/1) — tudo desfeito pelo RAISE.

-- 10. as 5 corridas antigas com ganho + corte ≠ tarifa
select left(r.id::text,8), r.created_at::date, r.payment_method, r.roundtrip_credit_id is not null as prepaid, r.used_subscription_ride as plano, r.final_fare_cents, r.driver_earn_cents, r.bora_cut_cents, r.extra_stops_fee_cents, r.extra_stops_driver_cents
from tvde_rides r where r.status='finalizada' and coalesce(r.final_fare_cents,0) > 0 and r.final_fare_cents <> coalesce(r.driver_earn_cents,0) + coalesce(r.bora_cut_cents,0) order by r.created_at;
-- SAÍDA: f51f7c17 31/07 cash pacote 800/400/50 · f7c7ebb6 30/08 cash pacote 800/400/50 · f1f5c9c5 30/08 mbway pacote 800/400/50 · 2bdc3f15 30/08 cash pacote 800/400/50
--        (8,00 = 4,00 + 0,50 + 3,50 de reserva para o motorista da volta) · e3478429 14/08 cash plano fare 200 (só paragens), earn 440 = 340 plano + 100 paragens, cut 160 = 60 + 100.
