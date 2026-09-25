-- Cenário do emulador (20→21/09) — contido às contas DEMO, com a REGRA de 14/09 aplicada:
--   ⚠️ um pedido sintético em 'solicitada' com motoristas reais online pode fugir: quando a oferta
--   ao demo expira ou é recusada, o sweep (15 s) roda, espera a pausa de 35 s, LIMPA tried_driver_ids
--   e oferece ao real mais próximo (Valdemir, 14/09 16:51). Esta noite o único real vivo era o Danilo,
--   a meio da reserva da meia-noite (elegível para sobreposição!). Protocolo:
--   1) TODOS os reais em tried_driver_ids (Danilo, Erika, Euliney, Rui E2E, Valdemir) — cobre até à pausa;
--   2) cada oferta sintética é ACEITE pelo demo dentro do prazo, ou a corrida é CANCELADA por SQL
--      (status='cancelada_cliente') em menos de 30 s depois de expirar/recusar;
--   3) reserva sintética: aceite pelo demo dentro dos 5 min (senão o sweep das reservas também limpa
--      os tentados e chama TODOS os aprovados, mesmo offline);
--   4) tudo apagado no fim, confirmado por SELECT; demo volta a motorcycle + offline.
-- Motorista: Estafeta Demo (user dede0000-0000-4000-8000-000000000001; vehicle_type=carro_passageiros só durante a prova)
-- Cliente:   demo@bora.app (d5b0c0a1-f49e-4593-a919-147edfc069c2) — is_demo_user → não acorda o admin.

-- 0) demo passa a carro de passageiros
update public.drivers set vehicle_type = 'carro_passageiros' where user_id = 'dede0000-0000-4000-8000-000000000001';

-- REAIS (tried) — nunca recebem nada:
--   '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7' Danilo · 'fdbc749d-afa4-4455-bff4-87bd82de8f8b' Erika ·
--   '49300a68-fef3-48c3-b132-f3bb12774cdc' Euliney · '320d716e-0dd8-4c7f-a5e7-009426319efd' Rui E2E ·
--   'e355fde0-b634-48ba-bce1-e2a4466c4cc2' Valdemir

-- P1a) RB — o demo já leva um passageiro (a caminho). Realtime → ecrã da corrida abre.
insert into public.tvde_rides (id, client_id, driver_id, status, is_queued, origin_lat, origin_lng, origin_label,
  dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status, customer_note)
values ('33333333-0000-4000-8000-000000000001', 'd5b0c0a1-f49e-4593-a919-147edfc069c2', 'dede0000-0000-4000-8000-000000000001',
  'motorista_a_caminho', false, 40.5396704, -7.2841737, 'Campo de Ténis do IPG (teste)',
  40.5381819, -7.2653492, 'Garden Shopping (teste)', 2.96, 500, 400, 'mbway', 'succeeded', 'TESTE OFERTA SOBREPOSTA 20/09');

-- P1b) S1 — corrida nova em 'solicitada' (cash → o trigger de INSERT chama tvde_offer_to_next → o único
--      elegível é o demo, OCUPADO em prio 2 → oferta + push pela Edge). Origem a 1,6 km do destino de RB.
insert into public.tvde_rides (id, client_id, status, is_queued, origin_lat, origin_lng, origin_label, dest_lat, dest_lng, dest_label,
  est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status, tried_driver_ids, customer_note)
values ('33333333-0000-4000-8000-000000000002', 'd5b0c0a1-f49e-4593-a919-147edfc069c2', 'solicitada', false,
  40.5285237, -7.2516061, 'Intermarché Guarda (teste)', 40.5407818, -7.2677839, 'Rua Francisco de Passos 75 (teste)',
  4.54, 500, 400, 'cash', 'pending',
  ARRAY['4f61dd31-5e9e-4a7c-a557-7d53d2ceded7','fdbc749d-afa4-4455-bff4-87bd82de8f8b','49300a68-fef3-48c3-b132-f3bb12774cdc','320d716e-0dd8-4c7f-a5e7-009426319efd','e355fde0-b634-48ba-bce1-e2a4466c4cc2']::uuid[],
  'TESTE OFERTA SOBREPOSTA 20/09');

-- P2) RES — oferta de RESERVA ao demo (o caso de hoje), com o ecrã da corrida por cima. Sem passar pela rotação:
--     campos da oferta postos directamente; o push da oferta dispara-se à mão com tvde_reservation_push.
insert into public.tvde_rides (id, client_id, status, reservation_status, scheduled_at, is_queued, origin_lat, origin_lng, origin_label,
  dest_lat, dest_lng, dest_label, est_distance_km, est_fare_cents, driver_earn_cents, payment_method, payment_status,
  reservation_offer_driver_id, reservation_offer_expires_at, reservation_tried_driver_ids, customer_note)
values ('33333333-0000-4000-8000-000000000003', 'd5b0c0a1-f49e-4593-a919-147edfc069c2', 'agendada', 'a_procurar', now() + interval '3 hours', false,
  40.5396704, -7.2841737, 'Santa Casa (teste)', 40.5381819, -7.2653492, 'Pingo Doce novo (teste)', 2.5, 600, 480, 'cash', 'pending',
  'dede0000-0000-4000-8000-000000000001', now() + interval '5 minutes',
  ARRAY['4f61dd31-5e9e-4a7c-a557-7d53d2ceded7','fdbc749d-afa4-4455-bff4-87bd82de8f8b','49300a68-fef3-48c3-b132-f3bb12774cdc','320d716e-0dd8-4c7f-a5e7-009426319efd','e355fde0-b634-48ba-bce1-e2a4466c4cc2']::uuid[],
  'TESTE OFERTA SOBREPOSTA 20/09');
select public.tvde_reservation_push('dede0000-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000003', 'reservation_offer');

-- P3/P4/P5) S2, S3, S4 — mesmas colunas de S1, ids …0004/…0005/…0006 (noutro ecrã; expira a olhar; em segundo plano).

-- CANCELAR à pressa (depois de expirar/recusar): nunca deixar uma sintética viva em 'solicitada'
-- update public.tvde_rides set status='cancelada_cliente', current_offer_driver_id=null, offer_expires_at=null, no_driver_since=null where id='…';

-- LIMPEZA (fim): apagar eventos e corridas '33333333-…'; demo → motorcycle + offline; confirmar por SELECT.
