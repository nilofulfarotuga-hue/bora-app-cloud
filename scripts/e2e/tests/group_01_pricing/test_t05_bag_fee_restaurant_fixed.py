"""T05 — §2.x Bag fee restaurante: €0.30 FIXO (não × bag_count).

Comportamento ACTUAL confirmado via MCP — é a regra documentada em
``platform_settings.bag_fee_restaurant_cents=30``. A interpretação inicial
"€0.30 × bag_count" do prompt original era leitura errada; o
comportamento actual está correcto e estável.

RPC pura — ``pricing_calculate`` ignora ``bag_count`` (este só entra em
``create_order``).
"""
from helpers.pricing import assert_bag_fee_restaurant_fixed_30c, calculate_pricing


def test_t05_restaurant_bag_fee_fixed_30_cents(admin_client):
    """restaurant subtotal €10, 2km → bag_fee=€0.30 fixo."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='restaurant',
        subtotal_eur=10.00,
        distance_km=2.0,
        is_partner_store=True,
    )
    assert_bag_fee_restaurant_fixed_30c(breakdown)
