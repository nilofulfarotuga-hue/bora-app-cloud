"""T03 — §2.1 Delivery fee em função da distância.

- Até 4 km: €2.50 fixo (``delivery_base_fee_cents=250``).
- Acima de 4 km: €2.50 + €0.50 × (distance − 4).

3 cenários parametrizados:
- 3 km → €2.50
- 5 km → €3.00 (250 + 50 × 1)
- 8 km → €4.50 (250 + 50 × 4)
"""
import pytest

from helpers.pricing import assert_delivery_fee, calculate_pricing


@pytest.mark.parametrize(
    "distance_km, expected_eur",
    [
        (3.0, 2.50),
        (5.0, 3.00),
        (8.0, 4.50),
    ],
)
def test_t03_delivery_fee_by_distance(admin_client, distance_km, expected_eur):
    """Delivery fee ajusta acima de 4 km com €0.50/km adicional."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='restaurant',
        subtotal_eur=10.00,
        distance_km=distance_km,
        is_partner_store=True,
    )
    assert_delivery_fee(breakdown, distance_km=distance_km, apartment=False)
    # Sanity check explícito sobre o valor esperado
    assert abs(breakdown['delivery_fee'] - expected_eur) < 0.005, (
        f"delivery_fee@{distance_km}km esperado €{expected_eur:.2f}, "
        f"recebido €{breakdown['delivery_fee']:.2f}"
    )
