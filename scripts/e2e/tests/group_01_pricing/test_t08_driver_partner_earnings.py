"""T08 — §3.1 Driver earnings em pedido partner.

Em parceiro NÃO existe profit_share (driver_earnings é determinístico):
- ``driver_base_fee_cents=380`` → €3.80 base.
- ``driver_per_km_cents=20`` → €0.20/km.
- 2 km → €3.80 + €0.20×2 = €4.20 (piso exacto sem stacked bonus).

Test valida piso ≥ €4.20.
"""
from helpers.pricing import assert_driver_earnings_min, calculate_pricing


def test_t08_driver_partner_min_earnings(admin_client):
    """Partner €10/2km → driver_earnings ≥ €4.20 (base + km, sem profit_share)."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='restaurant',
        subtotal_eur=10.00,
        distance_km=2.0,
        is_partner_store=True,
    )
    assert_driver_earnings_min(breakdown, min_eur=4.20)
