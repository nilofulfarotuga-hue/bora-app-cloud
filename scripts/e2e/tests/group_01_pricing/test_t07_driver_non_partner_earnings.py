"""T07 — §3.1 Driver earnings em pedido non-partner.

Cálculo aproximado em prod (settings reais):
- ``driver_base_fee_cents=380`` → €3.80 base.
- ``driver_per_km_cents=20`` → €0.20/km.
- Non-partner adiciona ``profit_share`` (sobre markup 15% líquido) — boost
  acima do piso, valor variável.
- 2 km → €3.80 + €0.20×2 = €4.20 (sem profit_share); piso conservador €4.00.

Test valida apenas o piso; o teto sobe com profit_share dinâmico.
"""
from helpers.pricing import assert_driver_earnings_min, calculate_pricing


def test_t07_driver_non_partner_min_earnings(admin_client):
    """Non-partner €10/2km → driver_earnings ≥ €4.00 (base + km)."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='restaurant',
        subtotal_eur=10.00,
        distance_km=2.0,
        is_partner_store=False,
    )
    assert_driver_earnings_min(breakdown, min_eur=4.00)
