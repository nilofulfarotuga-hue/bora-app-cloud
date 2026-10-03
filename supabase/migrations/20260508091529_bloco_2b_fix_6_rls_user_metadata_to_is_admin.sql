-- ═══════════════════════════════════════════════════════════
-- BLOCO 2b — Fix 6 RLS policies user_metadata → is_admin()
-- Data: 2026-05-08 / Sessão 7-SEC-1
-- Razão: user_metadata é editável pelo próprio utilizador → leak.
--        is_admin() usa app_metadata (só backend pode escrever).
-- ═══════════════════════════════════════════════════════════

-- ─── 1. client_wallets ──────────────────────────
DROP POLICY IF EXISTS "wallet_select_admin" ON public.client_wallets;
CREATE POLICY "wallet_select_admin" ON public.client_wallets
  FOR SELECT TO authenticated USING (is_admin());

-- ─── 2. wallet_transactions ─────────────────────
DROP POLICY IF EXISTS "wallet_tx_select_admin" ON public.wallet_transactions;
CREATE POLICY "wallet_tx_select_admin" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (is_admin());

-- ─── 3. cancellation_requests ───────────────────
DROP POLICY IF EXISTS "cancel_req_select_admin" ON public.cancellation_requests;
CREATE POLICY "cancel_req_select_admin" ON public.cancellation_requests
  FOR SELECT TO authenticated USING (is_admin());

-- ─── 4. referral_codes ──────────────────────────
DROP POLICY IF EXISTS "ref_codes_select_admin" ON public.referral_codes;
CREATE POLICY "ref_codes_select_admin" ON public.referral_codes
  FOR SELECT TO authenticated USING (is_admin());

-- ─── 5. referral_invites ────────────────────────
DROP POLICY IF EXISTS "ref_invites_select_admin" ON public.referral_invites;
CREATE POLICY "ref_invites_select_admin" ON public.referral_invites
  FOR SELECT TO authenticated USING (is_admin());

-- ─── 6. promo_code_uses (próprio user OR admin) ─
DROP POLICY IF EXISTS "promo_uses_select_self" ON public.promo_code_uses;
CREATE POLICY "promo_uses_select_self" ON public.promo_code_uses
  FOR SELECT TO authenticated
  USING ((user_id = auth.uid()) OR is_admin());
