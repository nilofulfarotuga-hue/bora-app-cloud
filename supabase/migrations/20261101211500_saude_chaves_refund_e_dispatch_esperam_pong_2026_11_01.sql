-- 01/11/2026 (missão zona-vermelha-2026-11-01): refund v28 e dispatch-engine v64 passaram a responder
-- {"pong":true} ao ping do vigia (respostaAoPing). O vigia passa a exigir o pong nas duas (espera_pong=true),
-- como nas outras. finalize-order-from-intent continua sem ping (false). Só muda a lista; o resto fica igual.
-- Aplicada em produção a 01/11/2026 via MCP apply_migration (nome saude_chaves_refund_e_dispatch_esperam_pong_2026_11_01).
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
    ('update-products',            true,  null),
    ('finalize-order-from-intent', false, null),
    ('refund',                     true,  null),
    ('dispatch-engine',            true,  '{"ping":true,"orderId":"00000000-0000-0000-0000-000000000000"}'::jsonb)
  ) as f(funcao, espera_pong, corpo);
$function$;
