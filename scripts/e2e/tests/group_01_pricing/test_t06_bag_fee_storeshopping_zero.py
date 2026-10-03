"""T06 — storeShopping bag_fee=€0 (BUG-7E-B-003).

Comportamento ACTUAL: ``bag_fee=0`` em ``storeShopping`` mesmo com
``bag_count>0``. A regra antiga (``business_rules.ts``) dizia €0.10/saco
— discrepância documentada como BUG-7E-B-003 (severidade LOW). Test
valida o comportamento ACTUAL.
"""
from helpers.pricing import assert_bag_fee_zero_market, calculate_pricing


def test_t06_storeshopping_bag_fee_zero(admin_client):
    """storeShopping subtotal €20, 3km → bag_fee=€0.00 (BUG-7E-B-003)."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='storeShopping',
        subtotal_eur=20.00,
        distance_km=3.0,
        is_partner_store=False,
    )
    assert_bag_fee_zero_market(breakdown)
