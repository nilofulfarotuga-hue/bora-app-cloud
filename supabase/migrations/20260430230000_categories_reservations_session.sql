-- Sessão Categorias+Reservas — 2026-04-30. Consolidated migration.
-- Idempotente. Aplicado via MCP em prod; este ficheiro replay-safe.

-- T1: category_mapping table + auto_map function (v2 word boundaries)
CREATE TABLE IF NOT EXISTS public.category_mapping (
  category_root text PRIMARY KEY,
  taxonomy_section text NOT NULL,
  confidence numeric(3,2) NOT NULL DEFAULT 1.0 CHECK (confidence BETWEEN 0 AND 1),
  reviewed_by_admin boolean NOT NULL DEFAULT false,
  notes text,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_category_mapping_section ON public.category_mapping (taxonomy_section);
ALTER TABLE public.category_mapping ENABLE ROW LEVEL SECURITY;

-- _normalize_for_match, auto_map_category v2, _category_mapping_touch trigger,
-- _products_set_taxonomy_section trigger, admin_list_category_mappings,
-- admin_update_category_mapping, admin_category_mapping_stats
-- — definitions complete em prod via MCP. Schema acima garante idempotência da tabela.

-- T2: Reservations pré-pagamento
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('reservation_prepayment_cents', '300'::jsonb, 'Pré-pagamento por reserva (cents)', 'reservations'),
  ('reservation_cancel_window_hours', '2'::jsonb, 'Horas antes para cancelar com refund', 'reservations'),
  ('reservation_no_show_grace_minutes', '60'::jsonb, 'Minutos após reserved_for até no_show', 'reservations'),
  ('reservation_credit_expiry_days', '30'::jsonb, 'Dias até crédito menu expirar', 'reservations')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.restaurant_menu_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  restaurant_id text NOT NULL,
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  source_reservation_id uuid REFERENCES public.reservations(id),
  used_at timestamptz,
  used_in_order_id text,
  expires_at timestamptz NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  created_at timestamptz NOT NULL DEFAULT NOW()
);
ALTER TABLE public.restaurant_menu_credits ENABLE ROW LEVEL SECURITY;

-- RPCs lifecycle (client_confirm_reservation_payment, client_cancel_reservation,
-- partner_decide_reservation, partner_mark_arrival, auto_close_no_show_reservations,
-- consume_menu_credit_for_order, admin_reservations_metrics, admin_reservations_today)
-- — todas aplicadas via MCP em prod.

-- pg_cron schedule
SELECT cron.schedule(
  'auto_close_no_show_reservations',
  '0 * * * *',
  'SELECT public.auto_close_no_show_reservations();'
)
WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='auto_close_no_show_reservations');

COMMENT ON TABLE public.category_mapping IS 'T1: 281 category_root → 23 taxonomy_section, admin-reviewable';
COMMENT ON TABLE public.restaurant_menu_credits IS 'T2/§18: Menu credits from reservation arrivals';
