-- PROPOSTA — PARTE 2 (missão app-15-11, 15/11/2026, varredura 9166 n.º 1 ALTA).
-- ZONA DE DESPACHO E DINHEIRO: aplicar SÓ com ordem explícita (regra das zonas protegidas).
-- Precisa da PARTE 1 aplicada antes (usa public.cron_lote e public._cron_trocar_por_lote).
-- Nome sugerido: 20261115124100_pg_cron_lotes_parte2_despacho.
--
-- O QUE FAZ: as mesmas funções, nos mesmos ritmos, passam a correr em lote numa só ligação.
-- Nenhuma função muda; nenhum horário muda; só deixam de abrir uma ligação cada uma.
--
--   lote "minuto-despacho" (de minuto a minuto, 7 tarefas → 1):
--     agendados_nao_parceiros_despachar, casa_tick, _cleaning_cron_offer_reping,
--     expire_stale_driver_presence, encomendas_telefone_relogio, tvde_reservations_sweep,
--     tvde_roundtrip_sweep_orfaos                                   → poupa 6 × 1 440 = 8 640 ligações/dia
--   lote "15s-despacho" (de 15 em 15 s, 3 tarefas → 1):
--     bora_dispatch_maintenance, dispatch_fases_sweep, tvde_dispatch_sweep
--                                                                   → poupa 2 × 5 760 = 11 520 ligações/dia
--   lote "par-2min" (minutos pares, de 2 em 2, 3 tarefas → 1):
--     _carwash_cron_offer_timeout, _carwash_cron_retry_unoffered, tvde_dest_change_sweep_kick
--                                                                   → poupa 2 × 720 = 1 440 ligações/dia
-- TOTAL PARTE 2: 21 600 ligações/dia a menos (de ~44 100). Com a parte 1: 23 760 (54 %).
-- Pico do minuto :00 (depois da 20261115020100): menos 10 arranques simultâneos.
--
-- NÃO JUNTA: decisor-varrer (30 s) e embeddings-gte-manter (2 min), que não são uma função simples
-- (pedem uma Edge por net.http_post); partner-auto-dispatch (30 s) fica sozinha (não há com quem juntar).
--
-- O QUE MUDA NA PRÁTICA (para decidir): dentro de cada lote as funções correm uma a seguir à outra.
-- Hoje cada uma demora ~0,05 s, por isso o lote demora < 1 s. Se uma demorar muito, as seguintes
-- do MESMO lote atrasam-se nesse ciclo (antes corriam em paralelo). Uma falha numa função não impede
-- as outras: fica registada em public.cron_lote_falhas.
--
-- REVERSÍVEL: as originais ficam em public.bkp_cron_job_20261115 (ver ROLLBACK no fim).

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

-- PROVA (depois de aplicar):
--   select jobname, schedule from cron.job where jobname like 'lote-%' order by 1;  -- 5 lotes (2 + 3)
--   select count(*) from cron.job where active;                                      -- 93 - 13 + 3 = 83
--   1 h depois: select status, count(*) from cron.job_run_details d join cron.job j using (jobid)
--               where j.jobname like 'lote-%' and d.start_time > now() - interval '1 hour' group by 1;
--   e as falhas por função: select lote, chamada, count(*) from public.cron_lote_falhas
--               where criado_em > now() - interval '1 hour' group by 1, 2;
--
-- ROLLBACK:
--   select cron.unschedule('lote-minuto-despacho'); select cron.unschedule('lote-15s-despacho');
--   select cron.unschedule('lote-par-2min');
--   select cron.schedule(jobname, schedule, command) from public.bkp_cron_job_20261115
--    where jobname in ('agendados-nao-parceiros', 'casa_tick', 'cleaning-offer-reping', 'drivers-heartbeat-expire',
--                      'encomendas-telefone-relogio', 'tvde-reservations-sweep', 'tvde-roundtrip-orfaos',
--                      'bora_dispatch_maintenance', 'dispatch_fases_sweep', 'tvde_dispatch_sweep',
--                      'carwash-offer-timeout', 'carwash-retry-unoffered', 'tvde-dest-change-sweep');
