"""T01 — §2.4 Partner pricing 10+5+5 = 20% total cliente.

Valida que ``pricing_calculate`` com ``is_partner_store=true`` devolve:
- ``service_fee`` = 5% × subtotal (€0.50 em €10)
- ``platform_commission`` = 10% × subtotal (€1.00 em €10) — visível ao parceiro
- ``partner_markup_hidden`` = 5% × subtotal (€0.50 em €10) — escondido

RPC pura — não cria order.
"""
from helpers.pricing import assert_partner_hybrid, calculate_pricing


def test_t01_partner_commission_hybrid_20pct(admin_client):
    """Parceiro €10/2km → 10% visible + 5% hidden + 5% service = 20% total."""
    breakdown = calculate_pricing(
        admin_client,
        service_type='restaurant',
        subtotal_eur=10.00,
        distance_km=2.0,
        is_partner_store=True,
    )
    assert_partner_hybrid(breakdown, subtotal_eur=10.00)
