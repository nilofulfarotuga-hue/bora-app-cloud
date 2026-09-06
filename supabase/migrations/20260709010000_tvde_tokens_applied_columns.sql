-- TVDE + Bora Tokens (2026-07-09) — FUNDAÇÃO (só colunas aditivas).
-- Objetivo: permitir GASTAR Bora Tokens numa corrida TVDE, à semelhança do
-- delivery (orders.tokens_applied_count / tokens_applied_value_cents), com o
-- mesmo teto de 50% (platform_settings.token_payment_max_pct).
--
-- ⚠️ ESTA MIGRATION É APENAS A FUNDAÇÃO: adiciona duas colunas nullable/DEFAULT 0
--    em tvde_rides. NÃO altera nenhuma RPC de cobrança nem debita tokens.
--    É aditiva e reversível (ver rollback no fim). O threading do desconto nas
--    RPCs tvde_request_ride / tvde_ride_charge_cents e o débito real de tokens
--    ficam na PROPOSTA (docs) e SÓ avançam com aprovação do Danilo (🔴 dinheiro).
--
-- NÃO mexe na lógica de GANHO de tokens (que é zero para TVDE) — só prepara o GASTO.

ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS tokens_applied_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tokens_applied_value_cents INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.tvde_rides.tokens_applied_count IS
  'Nº de Bora Tokens gastos nesta corrida (1 token = €0,005 = meio cêntimo de desconto, BRTokens.TOKEN_VALUE_EUR). Espelha orders.tokens_applied_count.';
COMMENT ON COLUMN public.tvde_rides.tokens_applied_value_cents IS
  'Valor (cêntimos) do desconto por tokens aplicado a esta corrida. Teto: token_payment_max_pct (50%) do valor cobrado online. Espelha orders.tokens_applied_value_cents.';

-- ── ROLLBACK (se necessário) ────────────────────────────────────────────────
-- ALTER TABLE public.tvde_rides
--   DROP COLUMN IF EXISTS tokens_applied_count,
--   DROP COLUMN IF EXISTS tokens_applied_value_cents;
