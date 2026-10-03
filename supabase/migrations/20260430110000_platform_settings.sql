-- ============================================================================
-- BORA — Platform Settings (Feature 8)
-- ============================================================================
-- Tabela de fonte de verdade configurável para regras de pricing/tokens/wallet.
-- Substitui constantes hardcoded em pricing_calculate (refactor HIGH-RISK em
-- branch separada draft/pricing-from-settings — NÃO mergeada por esta migration).
-- ============================================================================

BEGIN;

-- ── Table ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.platform_settings (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL,
  description TEXT,
  category    TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_platform_settings_category
  ON public.platform_settings (category);

COMMENT ON TABLE public.platform_settings IS
  'Configurable platform parameters (pricing, fees, wallet split, referral). Source of truth for pricing_calculate refactor.';

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

-- Read: any authenticated user (regras públicas, não há segredos aqui)
DROP POLICY IF EXISTS "platform_settings_select_authed" ON public.platform_settings;
CREATE POLICY "platform_settings_select_authed"
  ON public.platform_settings FOR SELECT TO authenticated USING (true);

-- Writes: nenhuma política → só via RPC SECURITY DEFINER

-- ── Seeds (replicação business_rules.md + novos da Feature 1/10/11) ─────────
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('delivery_base_fee_cents',              '250',  'Taxa base entrega (até 4km)',           'delivery'),
  ('delivery_per_km_cents',                '50',   'Taxa €/km adicional além de 4km',       'delivery'),
  ('delivery_base_distance_km',            '4',    'Distância grátis incluída na taxa base','delivery'),
  ('partner_visible_commission_pct',       '0.10', '10% comissão visível parceiro',         'partners'),
  ('partner_hidden_markup_pct',            '0.05', '5% markup escondido no preço',          'partners'),
  ('client_service_fee_pct',               '0.05', '5% taxa serviço cliente (visível)',     'partners'),
  ('non_partner_markup_pct',               '0.15', '15% markup não-parceiros',              'partners'),
  ('driver_base_fee_cents',                '380',  'Driver base entrega',                   'drivers'),
  ('driver_per_km_cents',                  '20',   'Driver €/km',                           'drivers'),
  ('driver_surcharge_cents',               '80',   'Bónus storeShopping/carry/send',        'drivers'),
  ('partner_driver_stacking_bonus_cents',  '300',  'Bónus driver stacked partner orders',   'drivers'),
  ('driver_profit_share_pct',              '0.30', '30% partilha lucro Bora não-parceiro',  'drivers'),
  ('bag_fee_restaurant_cents',             '30',   'Saco restaurante fixo',                 'fees'),
  ('bag_fee_supermarket_per_bag_cents',    '10',   'Saco mercado por unidade',              'fees'),
  ('max_cash_amount_cents',                '4000', 'Máx pagamento em dinheiro',             'limits'),
  ('token_normal_cents_value',             '50',   'Token normal driver delivery',          'tokens'),
  ('token_partner_driver_cents_value',     '50',   'Token partner driver delivery',         'tokens'),
  ('client_token_award_pct',               '3',    'x do valor pedido em tokens cliente',   'tokens'),
  ('token_value_cents_x100',               '5',    'Valor 1 token em cents*100 (=0.05)',    'tokens'),
  ('wallet_split_free_pct',                '0.80', 'Wallet refund: % saldo livre (resto tokens)','wallet'),
  ('wallet_max_use_pct_per_order',         '1.00', 'Saldo livre cobre 100% do pedido (vs tokens 50%)','wallet'),
  ('referral_referrer_reward_cents',       '500',  'Reward referrer no 1º pedido invited',  'referral'),
  ('referral_invited_reward_cents',        '500',  'Reward invited no 1º pedido',           'referral'),
  ('referral_min_first_order_cents',       '1000', 'Mínimo €10 do 1º pedido para ganhar',   'referral'),
  ('referral_invite_expires_days',         '30',   'Convite expira em N dias',              'referral'),
  ('cashback_pct',                         '0.01', '1% cashback default em saldo livre',    'cashback')
ON CONFLICT (key) DO NOTHING;

-- ── RPC: admin_update_setting (audit obrigatório) ───────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_setting(
  p_key   TEXT,
  p_value JSONB
)
RETURNS public.platform_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_old   JSONB;
  v_new   public.platform_settings;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_key IS NULL OR length(trim(p_key)) = 0 THEN
    RAISE EXCEPTION 'key_required' USING ERRCODE='23502';
  END IF;
  IF p_value IS NULL THEN
    RAISE EXCEPTION 'value_required' USING ERRCODE='23502';
  END IF;

  SELECT value INTO v_old FROM public.platform_settings WHERE key = p_key;
  IF v_old IS NULL THEN
    RAISE EXCEPTION 'unknown_setting: %', p_key USING ERRCODE='23503';
  END IF;

  UPDATE public.platform_settings
  SET value = p_value, updated_at = now(), updated_by = v_admin.admin_id
  WHERE key = p_key
  RETURNING * INTO v_new;

  PERFORM public.log_admin_action(
    'platform_setting_updated', 'platform_setting', NULL,
    jsonb_build_object('key', p_key, 'old', v_old, 'new', p_value)
  );

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_setting(TEXT, JSONB) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_setting(TEXT, JSONB) TO authenticated;

-- ── RPC: admin_list_settings (lista por categoria) ──────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_settings(
  p_category TEXT DEFAULT NULL
)
RETURNS SETOF public.platform_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
    SELECT * FROM public.platform_settings
    WHERE p_category IS NULL OR category = p_category
    ORDER BY category, key;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_settings(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_settings(TEXT) TO authenticated;

-- ── Helper: get_setting (sem auth — qualquer authenticated lê) ──────────────
CREATE OR REPLACE FUNCTION public.get_setting(p_key TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT value FROM public.platform_settings WHERE key = p_key;
$$;
REVOKE ALL ON FUNCTION public.get_setting(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_setting(TEXT) TO authenticated;

COMMIT;
