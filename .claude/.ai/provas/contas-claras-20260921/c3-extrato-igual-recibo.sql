-- Bloco C3 (21/09, 09h25–09h45 UTC) — o extrato da app mostra as MESMAS parcelas do recibo.
-- Migration aplicada: contas_claras_c3_parcelas_do_acerto_2026_09_21 (repo 20260921092110_..._2026_09_21.sql):
--   NOVA driver_settlement_parcelas(...) · weekly_closeout_compile chama-a · extrato_prestador devolve 'parcelas'.

-- 1) o recibo compilado pela função nova é IGUAL ao breakdown já gravado (ROLLBACK: pus as 3 linhas de
--    estafeta da semana 14–20/09 em 'pending', corri weekly_closeout_compile('2026-09-13'), comparei, desfiz)
-- SAÍDA: iguais=3/3 diferencas=nenhuma
--        valdemir_depois=[{"qty":1,"label":"Entregas","value_cents":500},{"qty":13,"label":"Corridas","value_cents":5200},
--                         {"label":"Dinheiro que recebeu em mão (devolve à Bora)","value_cents":-4000}]

-- 2) extrato do VALDEMIR (JWT dele por set_config: sub e355fde0-b634-48ba-bce1-e2a4466c4cc2) × recibo gravado
-- SAÍDA: semana=14/09–20/09 | parcelas_app = parcelas_recibo → IGUAIS=t
--        liquido_app=1700 liquido_recibo=1700 soma_parcelas=1700  (500 + 5200 − 4000 = 1700 = 17,00 EUR)
--        previsao (semana em curso, segunda de manhã): net 0.00, parcelas [] · n_acertos=4

-- 3) extrato do DANILO (sub 4f61dd31…) × recibo — as 5 parcelas, pela ordem do recibo
-- SAÍDA: IGUAIS=t | labels_app = Entregas · Corridas · Compras que adiantou do bolso · Tokens convertidos ·
--        Dinheiro que recebeu em mão (devolve à Bora) | liquido_app=4352 liquido_recibo=4352 soma=4352

-- 4) repo = servidor depois do C2 e C3: 26/26 funções IGUAL (diff_repo_vs_servidor.py, corpo a corpo).

-- 5) Flutter: lib/widgets/extrato_prestador_section.dart lê `parcelas` (previsão e acertos) e não tem os nomes
--    escritos à mão; teste test/contas_claras_c3_extrato_parcelas_test.dart 4/4 verde.
