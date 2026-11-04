-- embeddings-supabase-2026-11-03 — parte 3: produtos novos entram nos dois motores, sozinhos.
--   embeddings-gte-manter   (de 2 em 2 min): gte dos produtos e trechos do manual que faltam
--                           (~8 por volta: o gte gasta processador da função; ver embeddings-gte)
--   embeddings-gemini-novos (de hora a hora, ao minuto 17): Gemini dos produtos criados nos últimos
--                           14 dias, 20 de cada vez (a quota diária dos lotes do Gemini é pequena)
-- A chave do servidor vem do cofre (vault.service_role_key), como os outros agendamentos.
select cron.schedule('embeddings-gte-manter', '*/2 * * * *', $cron$
  select net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/embeddings-gte',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
    body := jsonb_build_object('acao', 'manter'),
    timeout_milliseconds := 60000);
$cron$);

select cron.schedule('embeddings-gemini-novos', '17 * * * *', $cron$
  select net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/embeddings-gte',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
    body := jsonb_build_object('acao', 'gemini_novos', 'limite', 20, 'dias', 14),
    timeout_milliseconds := 60000);
$cron$);
