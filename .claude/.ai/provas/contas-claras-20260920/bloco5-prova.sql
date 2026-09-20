-- Bloco 5 — o vigia que grita — provas em produção a 20/09/2026.

-- 5.1 dry (o que encontraria hoje, sem escrever nem gritar)
select public.vigia_dinheiro_diario(false, true);
-- SAÍDA (21h40 UTC): casos=10 → Isabel 309 (saldo_vs_historico, já registada no B1) · 4 compensações fora do acerto (Demo 569, Danilo 150, Danilo 150, Valdemir 150)
--   · Sabores do Brasil ledger 1029 × order_financials 0 · 3 payouts parados (Goola 2180, Goola 1980, Danilo-estafeta 1590) · Danilo TVDE −1420. cron 'vigia-dinheiro-diario' agendado (10 6 * * *).

-- 5.2 desacerto plantado, em rollback (1 cêntimo a mais na carteira do Valdemir), corrida a sério sem Telegram, RAISE no fim
-- SAÍDA: plantado_detectado={kind saldo_vs_historico, quem valdemirvasconcelos28@gmail.com, saldo 1, historico 0, amount -1}
--   run: casos=11 novos=10 reabertos=0 conhecidos_calados=1 gritou=false | findings antes=23 depois=33 | isabel_linhas=1 (sem duplicar)
--   (tudo desfeito pelo RAISE — findings continuou em 23 depois)

-- 5.3 primeira corrida real (escreve + grita)
select public.vigia_dinheiro_diario(true, false);
-- SAÍDA: casos=10, novos=9, gritou=true, conhecidos_calados=1 (Isabel). notification_failures (_telegram_admin, 5 min): 0.

-- 5.4 segunda corrida: com a base igual, cala-se
select public.vigia_dinheiro_diario(true, false);
-- SAÍDA: casos=10, novos=0, gritou=false, conhecidos_calados=10.

-- 5.5 painel: admin_vigia_achados / admin_vigia_resolver / admin_vigia_correr_agora (só admin) — ecrã lib/screens/admin/admin_vigia_dinheiro_screen.dart
-- flutter analyze: 0 errors (250 infos pré-existentes). RAM na altura: 135 MB (llama-server do Ollama com 5,3 GB, não meu) — avancei com timeout; correu em 11 s.
