"""T02 — §2.2 Non-partner pricing: service_fee €2.50 fixo + commission ≥ €2.50.

Ao contrário do parceiro (5% percent), o não-parceiro paga taxa fixa €2.50
(``client_service_fee_pct`` + ``delivery_base_fee_cents``).
``platform_commission`` agrega ``non_partner_purchase_fee`` (€2.50) e a
quota apartment se aplicável.
``partner_markup_hidden`` deve ser €0 (não há markup escondido em
non-partner — o markup 15% já está embutido no subtotal_server).
"""
from helpers.pricing import assert_non_partner, calculate_pricing


def test_t02_non_partner_service_fee_fixed(admin_client):
    """Non-partner €10/2km → service_fee=€2.50 fixo + commission≥€2.50 + hidden=0."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='restaurant',
        subtotal_eur=10.00,
        distance_km=2.0,
        is_partner_store=False,
    )
    assert_non_partner(breakdown)
