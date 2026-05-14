-- ============================================================
-- TAKEAWAY PRO — create_order updates
-- ============================================================
-- Aplicado via MCP em 2026-05-13 por Claude.ai.
-- Esta migration é um **STUB documental** — o corpo completo de
-- `create_order` não está reproduzido aqui porque depende de
-- regras de pricing/wallet/settlement que são tocadas por outras
-- migrations independentes (zona proibida do PROMPT C).
--
-- ⚠️ ANTES de aplicar num ambiente novo (preview/dev), extrair o
--    source autoritativo via:
--      psql -c "\sf public.create_order"
--    ou Supabase MCP `get_function_definition`. Substituir o
--    placeholder abaixo pelo body real, depois aplicar.
--
-- ============================================================
-- DELTA INTRODUZIDO PELO PROMPT B/C (resumido):
-- ============================================================
-- create_order passou a aceitar service_type='takeaway' com efeitos:
--   * Zera todas as fees (delivery=0, service=0, bag=0)
--   * Cliente paga price = subtotal
--   * Calcula:
--       platform_commission = round(subtotal * 0.10, 2)   -- 10%
--       partner_markup_hidden = round(subtotal * 0.05, 2) -- 5%
--   * Gera takeaway_pickup_code: 6 chars [A-Z0-9] aleatórios
--     (uniqueness não enforçada — risco mínimo, ver investigation
--      report I7)
--   * Define status='created' (cliente paga; parceiro aceita depois
--     via partner_takeaway_accept)
--   * Lê do payload do RPC: takeaway_is_curbside, takeaway_curbside_info
--     (grava nas colunas correspondentes)
--   * NÃO aciona dispatch (takeaway não tem estafeta)
--
-- Ref: .claude/.ai/reports/2026-05-13_takeaway_investigation.md
-- ============================================================

-- TODO: substituir este DO block por:
--   CREATE OR REPLACE FUNCTION public.create_order(...)
--   <full body extracted from production via MCP>
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE 'takeaway_pro_create_order_update: STUB — body real em prod. '
               'Ver cabeçalho da migration para procedimento de extração.';
END
$$;

-- ============================================================
-- FIM da migration takeaway_pro_create_order_update (STUB)
-- ============================================================
