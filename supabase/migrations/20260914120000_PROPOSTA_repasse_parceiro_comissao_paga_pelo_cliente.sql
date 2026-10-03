-- ============================================================================
-- PROPOSTA — NÃO APLICADA. Missão leonidas-guarda-loja-e-site (2026-09-14).
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
--
-- O PROBLEMA, medido em produção a 2026-09-14:
--   partner_store_share(subtotal) = round(subtotal * (1 - 0,10) / (1 + 0,05), 2)
--   = subtotal * 0,857142…  — e não lê restaurants.partner_commission_billing.
--   Essa coluna ('partner' | 'client') hoje é só um rótulo do painel admin:
--   nenhuma função de dinheiro a consulta (confirmado com grep em pg_proc e no repo).
--
--   Leonidas (modelo prometido por escrito): cliente paga balcão + 10 %; a loja
--   recebe o balcão exacto. Com a fórmula actual, price = balcão * 1,10 dá à loja
--   balcão * 1,10 * 0,857142 = balcão * 0,942857 → a loja recebe MENOS 5,71 %.
--   Exemplo: Ballotin 250 g, balcão 14,95 € → cliente paga 16,45 € → a loja
--   receberia 14,10 € em vez de 14,95 € (desvio de 0,85 € por caixa).
--
--   Goola (também 'client') foi gravada com price = balcão * 1,05 / 0,90 (= +16,67 %)
--   precisamente para que a fórmula actual lhe devolva o balcão ao cêntimo
--   (9,22 € → 7,90 €). Ou seja: hoje "comissão paga pelo cliente" custa ao
--   cliente +16,67 %, não +10 %.
--
-- AS DUAS SAÍDAS POSSÍVEIS (decisão do Danilo, não do executor):
--   A) Manter a fórmula e gravar a Leonidas como a Goola: price = balcão * 1,05 / 0,90.
--      Cliente paga +16,67 %; a loja recebe o balcão exacto. Contraria o "+10 %"
--      que foi escrito à dona.  (SQL: update products set price = round(partner_shelf_price*1.05/0.90,2) where restaurant_id='leonidas-guarda';)
--   B) Esta migration: a função passa a olhar para partner_commission_billing.
--      'client' → a loja recebe subtotal / 1,10 (o balcão, quando price = balcão * 1,10).
--      'partner' → fórmula actual, sem mudança para os restaurantes normais.
--      Efeito colateral: a Goola passaria a receber 9,22 / 1,10 = 8,38 € (mais do que
--      os 7,90 € de balcão) — teria de ser regravada para price = balcão * 1,10
--      (8,69 € e 10,89 €), o que também baixa o preço ao cliente dela.
--
-- O que está gravado HOJE para a Leonidas: price = balcão * 1,10 (o que foi prometido),
-- coming_soon = true (não vende). Enquanto não houver decisão, nenhum pedido acontece.
-- ============================================================================

BEGIN;

-- 1) A função canónica ganha uma sobrecarga com o restaurante.
CREATE OR REPLACE FUNCTION public.partner_store_share(p_subtotal numeric, p_restaurant_id text)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN (SELECT r.partner_commission_billing FROM public.restaurants r WHERE r.id = p_restaurant_id) = 'client'
      THEN ROUND(p_subtotal / (1 + COALESCE((SELECT (value::text)::NUMERIC FROM public.platform_settings
                                              WHERE key = 'partner_visible_commission_pct'), 0.10)), 2)
    ELSE public.partner_store_share(p_subtotal)
  END;
$function$;

-- 2) Os dois chamadores passam a enviar o restaurante:
--    apply_order_financial_split:  v_restaurant := public.partner_store_share(v_base, NEW.restaurant_id);
--    post_order_to_ledger:         v_restaurant_earn := public.partner_store_share(v_base, v_vendor_ref);
--    (as duas funções são CREATE OR REPLACE completas — copiar o corpo actual de
--     pg_get_functiondef e trocar só esta linha; deixado por fazer de propósito, para
--     o diff ser revisto com o "vai".)

-- 3) Prova depois de aplicar (tem de dar 14.95):
--    select public.partner_store_share(16.45, 'leonidas-guarda');

COMMIT;
