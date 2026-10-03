-- 2026-09-13 -- BUG achado na prova em rollback da auditoria FABLE.
--
-- O gatilho BEFORE INSERT fn_tvde_apply_promo_credit (migracao do ChatGPT de
-- 12/09) marca o credito como usado com used_ride_id = NEW.id ANTES de a
-- corrida existir. A chave estrangeira tvde_promo_credits_used_ride_id_fkey
-- rebentava (23503) e a cliente 93a6d3ff, com o credito de 5 EUR por usar,
-- NAO CONSEGUIA PEDIR CORRIDA NENHUMA -- o pedido inteiro falhava.
--
-- Correccao minima, sem mudar a logica: a chave passa a ser verificada no fim
-- da transaccao, quando a corrida ja existe. Se a insercao falhar por outra
-- razao, tudo reverte junto (o credito nunca fica preso a uma corrida fantasma).
ALTER TABLE public.tvde_promo_credits
  ALTER CONSTRAINT tvde_promo_credits_used_ride_id_fkey DEFERRABLE INITIALLY DEFERRED;
