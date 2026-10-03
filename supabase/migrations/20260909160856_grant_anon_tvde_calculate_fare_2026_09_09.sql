-- Bug do "Valor estimado €-0,01": tvde_calculate_fare nao tinha EXECUTE para anon.
-- Na web sem sessao, a RPC devolvia 42501 e o app caia no sentinela -1 (= -0,01 EUR).
-- Funcao e SECURITY DEFINER read-only (so calcula tarifa a partir de platform_settings),
-- nao expoe dados de ninguem, e as irmas (tvde_quote_roundtrip, tvde_roundtrip_price_for_km)
-- ja tinham anon -- era so esta que ficou de fora.
grant execute on function public.tvde_calculate_fare(numeric) to anon;