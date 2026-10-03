-- ============================================================
-- TAKEAWAY PRO — Schema additions (foundation)
-- ============================================================
-- Aplicado via MCP em 2026-05-13 por Claude.ai.
-- Esta migration existe APENAS para versionamento (a DB de prod já
-- foi alterada). Todos os DDL são idempotentes (IF NOT EXISTS), pelo
-- que reaplicar em prod é seguro / no-op.
--
-- Origem da decisão: investigação takeaway PROMPT B/C, Danilo +
-- Claude.ai (2026-05-13).
-- Ref:
--   .claude/.ai/reports/2026-05-13_takeaway_investigation.md
--   .claude/.ai/reports/2026-05-13_prompt-B-execucao.md
--   .claude/.ai/reports/2026-05-13_prompt-C-plano.md
--
-- Conteúdo:
--   1) restaurants — 3 colunas (takeaway_enabled, curbside_enabled,
--      takeaway_default_prep_minutes)
--   2) orders — 6 colunas (takeaway_pickup_code, takeaway_ready_at,
--      takeaway_picked_up_at, takeaway_prep_minutes,
--      takeaway_is_curbside, takeaway_curbside_info)
--   3) Index — orders.takeaway_pickup_code (lookup rápido)
--
-- Coluna zombie REMOVIDA do servidor neste batch:
--   orders.is_takeaway  (boolean) — substituída por
--   service_type='takeaway' (single source of truth).
-- ============================================================

-- 1) Toggles em restaurants ─────────────────────────────────────
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS takeaway_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS curbside_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS takeaway_default_prep_minutes integer DEFAULT 15;

-- Documentação inline.
COMMENT ON COLUMN public.restaurants.takeaway_enabled IS
  'BR §14.9 — restaurante aceita pedidos takeaway. Default false.';
COMMENT ON COLUMN public.restaurants.curbside_enabled IS
  'BR §14.9b — restaurante suporta curbside (cliente espera no carro). '
  'Só efectivo se takeaway_enabled=true.';
COMMENT ON COLUMN public.restaurants.takeaway_default_prep_minutes IS
  'BR §14.9c — ETA default em minutos no ETA picker do parceiro. 3-60. '
  'Default 15.';

-- 2) Campos takeaway em orders ─────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS takeaway_pickup_code text;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS takeaway_ready_at timestamptz;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS takeaway_picked_up_at timestamptz;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS takeaway_prep_minutes integer;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS takeaway_is_curbside boolean NOT NULL DEFAULT false;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS takeaway_curbside_info text;

COMMENT ON COLUMN public.orders.takeaway_pickup_code IS
  'BR §14.11 — 6 chars [A-Z0-9] gerado pelo create_order quando '
  'service_type=takeaway. Cliente apresenta no balcão.';
COMMENT ON COLUMN public.orders.takeaway_ready_at IS
  'Timestamp = NOW() + takeaway_prep_minutes (definido por '
  'partner_takeaway_accept). NULL para delivery.';
COMMENT ON COLUMN public.orders.takeaway_picked_up_at IS
  'Timestamp definido por partner_takeaway_mark_picked_up. NULL até '
  'ao levantamento.';
COMMENT ON COLUMN public.orders.takeaway_prep_minutes IS
  'Minutos escolhidos pelo parceiro ao aceitar (3-60). NULL p/ delivery.';
COMMENT ON COLUMN public.orders.takeaway_is_curbside IS
  'Cliente vai esperar no carro. Default false. Imutável pós '
  'payment_status=paid (UI-only enforcement em Flutter).';
COMMENT ON COLUMN public.orders.takeaway_curbside_info IS
  'Texto livre do cliente (matrícula/cor/modelo). NULL se não curbside.';

-- 3) Index para lookup rápido por pickup_code (parceiro consulta)
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_takeaway_pickup_code
  ON public.orders (takeaway_pickup_code)
  WHERE takeaway_pickup_code IS NOT NULL;

-- Index complementar — pedidos takeaway activos por restaurante,
-- usado pelo painel do parceiro para listar.
CREATE INDEX IF NOT EXISTS idx_orders_takeaway_partner_active
  ON public.orders (restaurant_id, status)
  WHERE service_type = 'takeaway'
    AND status IN ('created', 'preparing', 'readyForPickup');

-- ============================================================
-- FIM da migration takeaway_pro_schema
-- ============================================================
