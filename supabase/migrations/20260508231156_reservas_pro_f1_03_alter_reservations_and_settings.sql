-- ═══════════════════════════════════════════════════════════
-- RESERVAS PRO F1 — Migration 3/3: ALTER reservations + settings
-- Data: 2026-05-08 / Sessao reservas-pro-F1-SCHEMA
--
-- 1. Adicionar 10 colunas a reservations (sem breaking changes)
-- 2. Adicionar 13 settings novos em platform_settings
-- 3. 2 indices reservations (availability + analytics)
--
-- Aplicada via MCP em prod antes do ficheiro local.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS floor_plan_id uuid REFERENCES public.restaurant_floor_plans(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS event_type text NOT NULL DEFAULT 'normal'
    CHECK (event_type IN ('normal','valentines','christmas','new_year','mothers_day','fathers_day','easter','custom')),
  ADD COLUMN IF NOT EXISTS special_requests text,
  ADD COLUMN IF NOT EXISTS occasion text
    CHECK (occasion IS NULL OR occasion IN ('birthday','romantic','business','family','celebration','first_date','other')),
  ADD COLUMN IF NOT EXISTS is_walk_in boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS seated_at timestamptz,
  ADD COLUMN IF NOT EXISTS finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_24h_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_2h_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS confirmation_sent_at timestamptz;

COMMENT ON COLUMN public.reservations.floor_plan_id IS
  'Floor plan activo na altura da reserva (snapshot — restaurante pode mudar layout depois sem afectar reservas existentes).';
COMMENT ON COLUMN public.reservations.event_type IS
  'Tipo evento. normal = dia normal. valentines/christmas/etc = ocasioes especiais com pacing/turn times proprios.';
COMMENT ON COLUMN public.reservations.is_walk_in IS
  'true = cliente chegou sem reserva e foi sentado pelo parceiro.';
COMMENT ON COLUMN public.reservations.seated_at IS
  'Quando cliente sentou-se a mesa (diferente de arrived_at — pode chegar e esperar).';
COMMENT ON COLUMN public.reservations.finished_at IS
  'Quando saiu da mesa. (finished_at - seated_at) = turn time real para analytics.';

CREATE INDEX IF NOT EXISTS idx_reservations_availability
  ON public.reservations(restaurant_id, reserved_for, status)
  WHERE status NOT IN ('cancelled','rejected_refunded','cancelled_refunded','cancelled_no_refund','no_show');

CREATE INDEX IF NOT EXISTS idx_reservations_analytics
  ON public.reservations(restaurant_id, seated_at)
  WHERE seated_at IS NOT NULL;

INSERT INTO public.platform_settings (key, value) VALUES
  ('reservation_default_slot_duration_minutes', to_jsonb(30)),
  ('reservation_default_walk_in_pct', to_jsonb(25)),
  ('reservation_default_turn_time_2', to_jsonb(90)),
  ('reservation_default_turn_time_4', to_jsonb(120)),
  ('reservation_default_turn_time_6_plus', to_jsonb(150)),
  ('reservation_waitlist_expiry_hours', to_jsonb(4)),
  ('reservation_notify_list_expiry_hours', to_jsonb(24)),
  ('reservation_max_advance_days', to_jsonb(60)),
  ('reservation_min_advance_minutes', to_jsonb(30)),
  ('reservation_no_show_threshold_count', to_jsonb(3)),
  ('reservation_late_cancel_threshold_count', to_jsonb(5)),
  ('reservation_reminder_24h_enabled', to_jsonb(true)),
  ('reservation_reminder_2h_enabled', to_jsonb(true))
ON CONFLICT (key) DO NOTHING;
