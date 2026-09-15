-- F4B (MISSAO TOTAL 2026-08-15): UMA verdade de presenca em driver_locations.
-- Chave canonica = drivers.user_id. Orfas apagadas; duplicadas fundidas
-- (freshest ganha); presas por drivers.id re-keyed.
-- APLICADA em producao a 2026-08-16 (driver_locations_chave_canonica_user_id_f4b_2026_08_16).
-- Backup: bkp_driver_locations_20260816 (RLS on, 10 linhas).

DELETE FROM public.driver_locations dl
WHERE NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = dl.driver_id)
  AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = dl.driver_id);

UPDATE public.driver_locations canon
SET latitude = presa.latitude, longitude = presa.longitude,
    heading = presa.heading, speed_kmh = presa.speed_kmh,
    is_online = presa.is_online, last_updated = presa.last_updated
FROM public.driver_locations presa, public.drivers d
WHERE presa.driver_id = d.id AND d.user_id IS DISTINCT FROM d.id
  AND canon.driver_id = d.user_id
  AND presa.last_updated > canon.last_updated;

DELETE FROM public.driver_locations presa
USING public.drivers d
WHERE presa.driver_id = d.id AND d.user_id IS DISTINCT FROM d.id
  AND EXISTS (SELECT 1 FROM public.driver_locations l2 WHERE l2.driver_id = d.user_id);

UPDATE public.driver_locations dl
SET driver_id = d.user_id
FROM public.drivers d
WHERE dl.driver_id = d.id AND d.user_id IS NOT NULL
  AND d.user_id IS DISTINCT FROM d.id
  AND NOT EXISTS (SELECT 1 FROM public.driver_locations l2 WHERE l2.driver_id = d.user_id);
