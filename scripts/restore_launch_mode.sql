-- ============================================================================
-- RESTORE LAUNCH MODE — Bora App
-- Gerado: 2026-06-10 (sessão autónoma) · NÃO EXECUTADO automaticamente.
-- Este é o "botão de launch" do Danilo: executar MANUALMENTE no SQL Editor
-- do Supabase (ou via psql service_role) quando decidir lançar.
--
-- O que faz:
--   1. Recria os 6 crons apagados no incidente do loop (22, 25, 36–39),
--      com comandos recuperados de cron.job_run_details (fiéis ao original).
--   2. Reativa os 9 crons inativos (23, 27, 29–35).
--   3. Restaura os horários dos 18 restaurantes a partir de
--      _backup_business_hours_2026_06_05.
--   4. Verificações no fim (contagens esperadas + diff de horários).
--
-- ESCALONAMENTO: todos os schedules foram redistribuídos por offsets de
-- minuto para NUNCA dispararem no mesmo minuto (causa das 415 falhas
-- "job startup timeout" durante o incidente). Mapa de minutos na hora:
--   :00/:15/:30/:45  cleanup_payment_drafts(24) + appt-auto-noshow(42) [ativos, intocados]
--   :00/:30          appt-reminders-2h(41) [ativo, intocado]
--   :01,:11,…        bora-dispatch-maintenance (10 em 10)
--   :02,:32          watchdog orphan orders (30 em 30)
--   :03,:13,…        mark-stale-drivers-offline (10 em 10)
--   :04,:34          watchdog stripe failures (30 em 30)
--   :05,:20,:35,:50  reservas reminders 2h (15 em 15)
--   :06,:36          watchdog ghost drivers (30 em 30)
--   :07,:17,…        execute-broadcast (10 em 10)
--   :08              auto_close_no_show_reservations (hora a hora)
--   :09,:19,…        reservas pending-too-long (10 em 10; era 5/5 — ver nota N2)
--   :14,:44          reservas reminders 24h (30 em 30)
--   :16              reservas expire lists (hora a hora)
--   :18              robot-b (hora a hora)
--   Mon 08:18        robot-b-weekly-digest (semanal — digest sino admin)
--   03:12            auto-archive-old-suggestions (diário)
--   08:10            reservas morning summary (diário)
--   09:09            wallet_overdue_alerts (diário)
--
-- NOTAS:
--  N1. pg_cron atribui jobids NOVOS aos crons recriados — os números 22/25/36–39
--      deixam de existir; a identidade passa a ser o jobname.
--  N2. reservas_pro_pending_alert era */5 min; passa a 10/10 min (não havia
--      slot mod-5 livre sem colisão). Latência máx. do alerta: 10 min. Reverter
--      se crítico: cron.alter_job(<jobid>, schedule => '3-59/5 * * * *').
--  N3. O dispatch-engine v57 + bora_dispatch_maintenance v2 (migration
--      20260609230518) já honram TTLs e têm claim anti-duplicação — recriar o
--      cron 22 é SEGURO e necessário (é o safety net do dispatch).
--  N4. Colisões PRÉ-EXISTENTES entre crons ativos (não tocados por este script,
--      reportadas como sugestão): 2+20 (Mon 03:00), 24+42 (*/15).
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1) RECRIAR os 6 crons apagados (comandos fiéis a cron.job_run_details)
-- ────────────────────────────────────────────────────────────────────────────

-- (ex-22) Safety net do dispatch: TTLs + rotação de ofertas + reinvocação
SELECT cron.schedule(
  'bora-dispatch-maintenance',
  '1-59/10 * * * *',
  $$SELECT public.bora_dispatch_maintenance()$$
);

-- (ex-25) Estafetas com heartbeat morto → offline
SELECT cron.schedule(
  'mark-stale-drivers-offline',
  '3-59/10 * * * *',
  $$SELECT public.mark_stale_drivers_offline();$$
);

-- (ex-36) Watchdog: pedidos órfãos
SELECT cron.schedule(
  'watchdog-orphan-orders',
  '2,32 * * * *',
  $$SELECT public._cron_check_orphan_orders();$$
);

-- (ex-37) Watchdog: falhas Stripe
SELECT cron.schedule(
  'watchdog-stripe-failures',
  '4,34 * * * *',
  $$SELECT public._cron_check_stripe_failures();$$
);

-- (ex-38) Watchdog: ghost drivers
SELECT cron.schedule(
  'watchdog-ghost-drivers',
  '6,36 * * * *',
  $$SELECT public._cron_check_ghost_drivers();$$
);

-- (ex-39) Fila de broadcasts FCM (push_broadcasts pending → envio)
SELECT cron.schedule(
  'execute-broadcast-queue',
  '7-59/10 * * * *',
  $$
  SELECT net.http_post(
    url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
               || '/functions/v1/execute-broadcast',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
      'Content-Type',  'application/json'
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- ────────────────────────────────────────────────────────────────────────────
-- 2) REATIVAR os 9 crons inativos (com schedule escalonado)
-- ────────────────────────────────────────────────────────────────────────────

SELECT cron.alter_job(23, schedule => '8 * * * *',       active => true);  -- auto_close_no_show_reservations (era 0 * * * *)
SELECT cron.alter_job(27, schedule => '9 9 * * *',       active => true);  -- wallet_overdue_alerts (era 0 9 * * *)
SELECT cron.alter_job(29, schedule => '12 3 * * *',      active => true);  -- auto-archive-old-suggestions (era 0 3 * * *)
SELECT cron.alter_job(30, schedule => '14-59/30 * * * *', active => true); -- reservas_pro_reminders_24h (era */30)
SELECT cron.alter_job(31, schedule => '5-59/15 * * * *',  active => true); -- reservas_pro_reminders_2h (era */15)
SELECT cron.alter_job(32, schedule => '9-59/10 * * * *',  active => true); -- reservas_pro_pending_alert (era 3-59/5 — ver N2)
SELECT cron.alter_job(33, schedule => '10 8 * * *',      active => true);  -- reservas_pro_morning_summary (era 0 8 * * *)
SELECT cron.alter_job(34, schedule => '16 * * * *',      active => true);  -- reservas_pro_expire_lists (era 0 * * * *)
SELECT cron.alter_job(35, schedule => '18 * * * *',      active => true);  -- robot-b-hourly (era 0 * * * *)
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'robot-b-weekly-digest'),
                      active => true);  -- robot-b digest semanal (Mon 08:18 UTC; criado 2026-06-10 Robot B v4)

-- ────────────────────────────────────────────────────────────────────────────
-- 3) RESTAURAR horários de funcionamento (18 restaurantes do backup 2026-06-05)
-- ────────────────────────────────────────────────────────────────────────────

UPDATE public.restaurants r
   SET business_hours = b.business_hours
  FROM public._backup_business_hours_2026_06_05 b
 WHERE r.id = b.id
   AND r.business_hours IS DISTINCT FROM b.business_hours;

-- ────────────────────────────────────────────────────────────────────────────
-- 4) VERIFICAÇÕES (correr após o script; valores esperados nos comentários)
-- ────────────────────────────────────────────────────────────────────────────

-- 4a. Crons ativos — esperado: 25
--     (10 que já estavam ativos + 6 recriados + 9 reativados)
SELECT count(*) AS crons_ativos_esperado_25 FROM cron.job WHERE active;

-- 4b. Lista completa para revisão visual
SELECT jobid, jobname, schedule, active FROM cron.job ORDER BY jobname;

-- 4c. Colisões de minuto (crons de alta frequência) — esperado: 0 linhas
--     (verifica se algum minuto da hora tem mais de um cron */N agendado)
WITH expanded AS (
  SELECT jobname, schedule,
         generate_series(0,59) AS m
    FROM cron.job WHERE active AND schedule ~ '^[0-9*/,-]+ \* \* \* \*$'
), hits AS (
  SELECT jobname, m FROM expanded
   WHERE CASE
     WHEN split_part(schedule,' ',1) = '*' THEN true
     WHEN split_part(schedule,' ',1) ~ '^\d+$' THEN m = split_part(schedule,' ',1)::int
     WHEN split_part(schedule,' ',1) ~ '^\d+-59/\d+$' THEN
       m >= split_part(split_part(schedule,' ',1),'-',1)::int
       AND (m - split_part(split_part(schedule,' ',1),'-',1)::int)
           % split_part(split_part(schedule,' ',1),'/',2)::int = 0
     WHEN split_part(schedule,' ',1) ~ '^\*/\d+$' THEN
       m % split_part(split_part(schedule,' ',1),'/',2)::int = 0
     WHEN split_part(schedule,' ',1) ~ '^[\d,]+$' THEN
       m::text = ANY(string_to_array(split_part(schedule,' ',1), ','))
     ELSE false END
)
SELECT m AS minuto, count(*) AS n_crons, array_agg(jobname) AS crons
  FROM hits GROUP BY m HAVING count(*) > 1 ORDER BY m;

-- 4d. Horários restaurados — esperado: 0 divergências
SELECT count(*) AS horarios_divergentes_esperado_0
  FROM public._backup_business_hours_2026_06_05 b
  JOIN public.restaurants r ON r.id = b.id
 WHERE r.business_hours IS DISTINCT FROM b.business_hours;

-- 4e. Sanidade do dispatch pós-restore (esperado: 0 presos além do TTL)
SELECT count(*) AS pedidos_presos_alem_ttl_esperado_0
  FROM public.orders
 WHERE status = 'callingDriver'
   AND assigned_driver_id IS NULL
   AND dispatch_calling_since < NOW() - INTERVAL '1800 seconds';
