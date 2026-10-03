-- 2026-05-14 — Reservation realtime fix (H4).
-- Adiciona public.reservations a publication supabase_realtime para que
-- INSERT/UPDATE/DELETE sejam entregues a clientes Supabase Realtime
-- subscritos via .stream() ou .channel().
-- Pre-requisito para ReservationStore.subscribeMyReservations() funcionar
-- (caso contrario o stream e' aberto mas nunca recebe eventos).

ALTER PUBLICATION supabase_realtime ADD TABLE public.reservations;
