-- 01/11/2026 (missão seguranca-05) — os cron jobs que chamam a Edge Function update-products
-- passam a mandar a chave do servidor.
--
-- PORQUÊ: a função update-products (v23) estava ABERTA (verify_jwt=false e sem exigir chave):
-- qualquer pessoa podia reescrever os preços dos mercados. A v24 passa a exigir servidor/admin
-- (_shared/chaves.ts, exigirServidorOuAdmin). Os únicos chamadores são os jobs 20
-- `update-products-continente` (seg 03:00) e 21 `update-products-auchan` (ter 03:00), que até hoje
-- mandavam SÓ Content-Type — sem esta migração a v24 responderia 403 e os robôs morriam em silêncio.
-- Padrão copiado dos outros jobs (robot-b-hourly, weekly-closeout-digest, decisor-varrer):
-- URL do cofre + `Authorization: Bearer <service_role_key do cofre>`.
-- A chave legada em Bearer é aceite por chaves.ts depois de confirmada no Auth (ver chaves.ts, topo).
--
-- Também entra na lista do vigia diário das chaves (_saude_chaves_lista) com ping, para se saber
-- no dia seguinte se a chave deixou de passar nesta porta.
--
-- Idempotente: cron.alter_job só muda o comando; correr duas vezes dá o mesmo resultado.
-- Ordem de aplicar: PRIMEIRO esta migração, DEPOIS publicar a v24 (assim nunca há janela sem chave).

do $mig$
declare
  v_cmd_cnt text := $cmd$
    SELECT net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
             || '/functions/v1/update-products',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
        'Content-Type', 'application/json'
      ),
      body := '{"market":"continente","pages":60,"sleepMs":1000,"maxUpdates":500}'::jsonb,
      timeout_milliseconds := 150000
    );
  $cmd$;
  v_cmd_auc text := $cmd$
    SELECT net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
             || '/functions/v1/update-products',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
        'Content-Type', 'application/json'
      ),
      body := '{"market":"auchan","pages":60,"sleepMs":1000,"maxUpdates":500}'::jsonb,
      timeout_milliseconds := 150000
    );
  $cmd$;
  v_id bigint;
begin
  select jobid into v_id from cron.job where jobname = 'update-products-continente';
  if v_id is null then
    perform cron.schedule('update-products-continente', '0 3 * * 1', v_cmd_cnt);
  else
    perform cron.alter_job(job_id := v_id, command := v_cmd_cnt);
  end if;

  select jobid into v_id from cron.job where jobname = 'update-products-auchan';
  if v_id is null then
    perform cron.schedule('update-products-auchan', '0 3 * * 2', v_cmd_auc);
  else
    perform cron.alter_job(job_id := v_id, command := v_cmd_auc);
  end if;
end
$mig$;

-- Vigia diário das chaves: update-products entra na ronda das 07:00 com {"ping":true} → {"pong":true}.
CREATE OR REPLACE FUNCTION public._saude_chaves_lista()
 RETURNS TABLE(funcao text, espera_pong boolean, corpo jsonb)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select f.funcao, f.espera_pong, coalesce(f.corpo, '{"ping":true}'::jsonb)
  from (values
    ('notify-client',              true,  null::jsonb),
    ('notify-driver',              true,  null),
    ('notify-partner',             true,  null),
    ('notify-admin-urgent',        true,  null),
    ('notify-tvde-client',         true,  null),
    ('notify-tvde-driver',         true,  null),
    ('notify-cleaner',             true,  null),
    ('notify-washer',              true,  null),
    ('notify-service-provider',    true,  null),
    ('notify-chat-message',        true,  null),
    ('notify-driver-assigned',     true,  null),
    ('notify-partner-low-rating',  true,  null),
    ('ocr-receipt',                true,  null),
    ('settlement-receipt',         true,  null),
    ('push-clientes-alvo',         true,  null),
    ('payments-reconciler',        true,  null),
    ('tvde-payment',               true,  null),
    ('decidir',                    true,  null),
    ('support-password-reset',     true,  null),
    ('weekly-closeout-digest',     true,  null),
    ('monthly-partner-statement',  true,  null),
    ('update-products',            true,  null),   -- 01/11/2026 seguranca-05: porta fechada na v24
    ('finalize-order-from-intent', false, null),
    ('refund',                     false, null),
    ('dispatch-engine',            false, '{"ping":true,"orderId":"00000000-0000-0000-0000-000000000000"}'::jsonb)
  ) as f(funcao, espera_pong, corpo);
$function$;

-- PROVA (correr depois de aplicar):
--   select jobname, active, command ilike '%Authorization%' as tem_chave, command ilike '%vault.decrypted_secrets%' as le_cofre
--     from cron.job where jobname like 'update-products-%';
--   -- esperado: 2 linhas, tem_chave = true, le_cofre = true
--   select * from public._saude_chaves_lista() where funcao = 'update-products';
--   -- esperado: 1 linha, espera_pong = true
--   -- Depois de publicar a v24, prova viva (sem mexer em nada): chamada sem chave tem de dar 403 e
--   -- a ronda saude_chaves do dia seguinte tem de mostrar update-products com status 200 / pong.
