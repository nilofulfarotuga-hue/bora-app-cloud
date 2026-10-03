"""T18 — Stacking: non-partner orders ao mesmo vendor permitidas (cap 3).

Regra documentada (§3): non-partner driver pode aceitar até 3 orders
**desde que sejam todas do mesmo vendor**. Vendors diferentes → reject.

Cenário (comportamento ACTUAL):
1. Cria 2 orders non-partner do mesmo restaurante (NonPartnerRest).
2. driver_a aceita ambas.
3. Valida ambas atribuídas.
4. Documenta gap (capacity Flutter-only, server aceita qualquer combo).
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import create_test_order, get_order_field


def test_t18_non_partner_same_vendor_two_orders(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_non_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """2 non-partner do mesmo vendor — driver aceita ambas."""
    order_a = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_non_partner['id'],
        vendor_name=restaurant_non_partner['name'],
        subtotal_eur=8.00,
        is_partner_store=False,
    )
    simulate_offer_accept(admin_client, order_a, driver_a['id'])

    order_b = create_test_order(
        admin_client,
        user_id=cliente_b['user_id'],
        restaurant_id=restaurant_non_partner['id'],
        vendor_name=restaurant_non_partner['name'],
        subtotal_eur=9.50,
        is_partner_store=False,
    )
    simulate_offer_accept(admin_client, order_b, driver_a['id'])

    assert get_order_field(admin_client, order_a, 'assigned_driver_id') == driver_a['id']
    assert get_order_field(admin_client, order_b, 'assigned_driver_id') == driver_a['id'], (
        "non-partner mesmo vendor: driver aceita 2 ✅ (regra §3 permite até 3)"
    )
