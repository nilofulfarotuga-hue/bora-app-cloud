-- Mesmo buraco do tvde_calculate_fare: cotacao read-only de preco sem EXECUTE para anon.
-- Na web sem sessao o ecra dos planos ficaria sem preco (ou com sentinela).
-- tvde_plan_price_cents ja tinha anon; esta ficou de fora.
grant execute on function public.tvde_quote_plan(text, numeric) to anon;