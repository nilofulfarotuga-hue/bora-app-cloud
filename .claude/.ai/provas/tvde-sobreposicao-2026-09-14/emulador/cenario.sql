-- Cenário do emulador (14/09), contido às contas DEMO — como CORREU de facto.
-- Motorista: Estafeta Demo (user dede…0001, vehicle_type posto em carro_passageiros só durante a prova)
-- Cliente: demo@bora.app (d5b0c0a1…). Emulador emdia (API 34) com GPS fixo no Garden Shopping.
--
-- ⚠️ LIÇÃO (incidente às 16:51): meter uma corrida sintética em 'solicitada' com oferta ao demo
-- e os motoristas reais em tried_driver_ids NÃO chega. A Edge notify-tvde-driver re-ancora o
-- offer_expires_at para +40 s depois do push (linha "Reancora o TTL"); a oferta ao demo expirou,
-- o sweep esperou os 35 s de pausa, limpou tried_driver_ids e ofereceu ao motorista REAL mais
-- próximo (Valdemir aceitou; cancelei 37 s depois com push de cancelamento, taxa 0).
-- Enquanto houver motoristas reais online, um pedido sintético só é seguro SEM passar por oferta:
-- atribuir/pôr em fila directamente (é o que os passos 2 e 4 fazem).

-- 0) demo passa a carro de passageiros (restaurado a 'motorcycle' + offline no fim)
update public.drivers set vehicle_type = 'carro_passageiros' where user_id = 'dede0000-0000-4000-8000-000000000001';

-- 1) RB: o demo já leva um passageiro (a caminho). O realtime abre o ecrã da corrida na app.
insert into public.tvde_rides (id, client_id, driver_id, status, is_queued, origin_lat, origin_lng, origin_label,
  dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status)
values ('11111111-0000-4000-8000-000000000001', 'd5b0c0a1-f49e-4593-a919-147edfc069c2', 'dede0000-0000-4000-8000-000000000001',
  'motorista_a_caminho', false, 40.5396704, -7.2841737, 'Campo de Ténis do IPG (teste)',
  40.5381819, -7.2653492, 'Garden Shopping (teste)', 2.96, 500, 400, 'mbway', 'succeeded');

-- 2) Oferta sobreposta (item 5) — o que fiz e que provou a faixa (capturas 17/18) MAS fugiu para
--    um motorista real (ver lição acima). NÃO REPETIR com motoristas reais online.
--    (S em 'solicitada' + UPDATE current_offer_driver_id = demo → push + realtime → faixa.)

-- 3) Corrida em FILA directa (segura): S2 atrás de RB. A app mostra o cartão "Próxima corrida"
--    + linha tracejada; o cliente vê "a terminar uma corrida aqui perto · chega em ~9 min".
insert into public.tvde_rides (id, client_id, driver_id, status, is_queued, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
  est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status, tried_driver_ids)
values ('11111111-0000-4000-8000-000000000003', 'd5b0c0a1-f49e-4593-a919-147edfc069c2', 'dede0000-0000-4000-8000-000000000001', 'motorista_atribuido', true,
  40.5285237, -7.2516061, 'Intermarché Guarda (teste)', 40.5407818, -7.2677839, 'Rua Francisco de Passos 75 (teste)',
  4.54, 500, 400, 'mbway', 'succeeded', '{}');

-- 4) (na app) Cheguei → Iniciar → Finalizar RB → o ecrã abre S2 sozinho (P3; vídeo P3_transicao_automatica.mp4
--    foi gravado na 2.ª volta, com S3 '…0004' atrás de S2, porque o 1.º screenrecord perdeu o caminho /sdcard
--    por causa do Git Bash — usar MSYS_NO_PATHCONV=1).

-- LIMPEZA feita no fim (tudo confirmado por SELECT): corridas e eventos '11111111-0000…' apagados,
-- tvde_driver_balances do demo reposto a 0,00 (tinha ficado -8,00 pelas duas finalizações),
-- drivers do demo: vehicle_type='motorcycle', is_online=false.
