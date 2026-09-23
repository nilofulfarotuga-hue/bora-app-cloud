-- =============================================================================
-- ronda-fecho-2026-09-22 · A2 (d) — o evento 'finalizada' da volta da Stela
-- Neves (1d24a5c2, 18/09) passa a dizer a verdade dos 2,43 km.
--
-- A linha da corrida já tinha sido corrigida por MCP a 18/09 (final_distance_km
-- 2,43, driver_earn_cents 350, final_distance_source
-- 'corrigido_mcp_2026_09_18_endereco_errado', evento correcao_manual), mas o
-- evento 'finalizada' ficou com settle_cents -3950 / driver_earn_cents 3950 /
-- final_distance_km 50,32 — e é ESSE evento que extrato_prestador.corridas,
-- admin_extrato_dono ("corridas fora do acerto") e vigia_tvde_saldo somam.
-- Os valores errados ficam guardados dentro do próprio evento (valores_errados),
-- com a referência ao evento correcao_manual. Idempotente: só corre se o settle
-- ainda for -3950. NÃO toca em tvde_driver_balances (dinheiro real).
-- =============================================================================
UPDATE public.tvde_ride_events e
   SET meta = e.meta || jsonb_build_object(
         'settle_cents', -350, 'driver_earn_cents', 350, 'final_distance_km', 2.43,
         'corrigido', true, 'corrigido_em', now(),
         'corrigido_por', 'ronda-fecho-2026-09-22 (A2a)',
         'valores_errados', jsonb_build_object('settle_cents', -3950, 'driver_earn_cents', 3950,
                                               'final_distance_km', 50.32),
         'ref_correcao_manual', (SELECT c.id FROM public.tvde_ride_events c
                                  WHERE c.ride_id = e.ride_id AND c.status = 'correcao_manual'
                                  ORDER BY c.at LIMIT 1))
 WHERE e.ride_id = '1d24a5c2-4cdb-4ec5-a926-235200c3d6d8'
   AND e.status = 'finalizada'
   AND (e.meta->>'settle_cents')::int = -3950;
