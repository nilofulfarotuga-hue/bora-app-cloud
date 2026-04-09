-- ============================================================
-- BORA APP — Migração: Backend Dispatch Engine
-- Executar no Supabase SQL Editor
-- ============================================================

-- 1. Coluna: driver atualmente com a oferta (fonte única da verdade)
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS current_driver_offer_id UUID REFERENCES drivers(id) ON DELETE SET NULL;

-- 2. Coluna: quando a oferta expira
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS offer_expires_at TIMESTAMPTZ;

-- 3. Coluna: histórico de drivers já tentados neste pedido
--    Substitui o driverOfferHistory que estava no Flutter.
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS tried_driver_ids UUID[] DEFAULT '{}';

-- 4. Índice para a query de dispatch (status + driver + expiração)
CREATE INDEX IF NOT EXISTS idx_orders_dispatch
  ON orders (status, current_driver_offer_id, offer_expires_at)
  WHERE status = 'callingDriver';

-- 5. Coluna is_available nos drivers (separada de is_online)
--    is_online  = está logado e com localização ativa
--    is_available = não está em entrega ativa
ALTER TABLE drivers
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT TRUE;

-- 6. pg_cron: chamar a Edge Function a cada 10 segundos
--    Requer extensão pg_cron habilitada no Supabase.
--    Ativar em: Dashboard → Database → Extensions → pg_cron

SELECT cron.schedule(
  'bora-dispatch-engine',          -- nome do job (único)
  '10 seconds',                    -- intervalo
  $$
    SELECT net.http_post(
      url := current_setting('app.supabase_url') || '/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.service_role_key')
      ),
      body := '{}'::jsonb
    );
  $$
);

-- Alternativa ao pg_cron: usar o Supabase Scheduled Functions
-- na dashboard em Edge Functions → Schedule, intervalo de 10s.

-- ============================================================
-- Remover coluna antiga se existir no Flutter/Model
-- (só executar se confirmar que não há outro uso)
-- ALTER TABLE orders DROP COLUMN IF EXISTS driver_offer_history;
-- ============================================================
