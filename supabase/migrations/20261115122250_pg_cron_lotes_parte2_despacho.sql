-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115122250); antes não estava em supabase/migrations.
-- Origem: docs/propostas/app-15-11/pg_cron_lotes_parte2_despacho.PROPOSTA.sql (o mesmo SQL, com comentários); abaixo, o texto exato que correu.

select public._cron_trocar_por_lote('minuto-despacho', '* * * * *',
  array['agendados-nao-parceiros', 'casa_tick', 'cleaning-offer-reping', 'drivers-heartbeat-expire',
        'encomendas-telefone-relogio', 'tvde-reservations-sweep', 'tvde-roundtrip-orfaos'],
  array['public.agendados_nao_parceiros_despachar()', 'public.casa_tick()', 'public._cleaning_cron_offer_reping()',
        'public.expire_stale_driver_presence()', 'public.encomendas_telefone_relogio()',
        'public.tvde_reservations_sweep()', 'public.tvde_roundtrip_sweep_orfaos()']);

select public._cron_trocar_por_lote('15s-despacho', '15 seconds',
  array['bora_dispatch_maintenance', 'dispatch_fases_sweep', 'tvde_dispatch_sweep'],
  array['public.bora_dispatch_maintenance()', 'public.dispatch_fases_sweep()', 'public.tvde_dispatch_sweep()']);

select public._cron_trocar_por_lote('par-2min', '*/2 * * * *',
  array['carwash-offer-timeout', 'carwash-retry-unoffered', 'tvde-dest-change-sweep'],
  array['public._carwash_cron_offer_timeout()', 'public._carwash_cron_retry_unoffered()',
        'public.tvde_dest_change_sweep_kick()']);
