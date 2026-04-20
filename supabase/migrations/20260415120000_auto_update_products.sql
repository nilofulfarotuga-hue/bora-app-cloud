-- Auto-update products via pg_cron + pg_net
-- Requires: pg_cron and pg_net extensions enabled in Supabase dashboard

-- Mercadona: Monday at 3h UTC
SELECT cron.schedule(
  'update-mercadona',
  '0 3 * * 1',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "mercadona"}'::jsonb
  )$$
);

-- Continente: Tuesday at 3h UTC
SELECT cron.schedule(
  'update-continente',
  '0 3 * * 2',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "continente"}'::jsonb
  )$$
);

-- Pingo Doce: Wednesday at 3h UTC
SELECT cron.schedule(
  'update-pingodoce',
  '0 3 * * 3',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "pingodoce"}'::jsonb
  )$$
);

-- Lidl: Thursday at 3h UTC
SELECT cron.schedule(
  'update-lidl',
  '0 3 * * 4',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "lidl"}'::jsonb
  )$$
);

-- Auchan: Friday at 3h UTC
SELECT cron.schedule(
  'update-auchan',
  '0 3 * * 5',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "auchan"}'::jsonb
  )$$
);

-- Intermarché: Saturday at 3h UTC
SELECT cron.schedule(
  'update-intermarche',
  '0 3 * * 6',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "intermarche"}'::jsonb
  )$$
);

-- Restaurants: 1st of each month at 3h UTC
SELECT cron.schedule(
  'update-restaurants',
  '0 3 1 * *',
  $$SELECT net.http_post(
    url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/update-products',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := '{"market": "restaurants"}'::jsonb
  )$$
);
