"""T15 — Stacking: partner order + non-partner order misturadas.

Cenário (comportamento ACTUAL):
1. Cria order A (partner restaurant).
2. driver_a aceita A.
3. Cria order B (non-partner restaurant) — vendor diferente.
4. driver_a aceita B.
5. Valida que ambas estão atribuídas ao driver_a.

Documenta: capacity logic ``DriverCapacityService`` Flutter-side apenas.
Server-side aceita qualquer combinação se ``simulate_offer_accept`` for
chamado directo. Isto é FAIL legitimamente esperado se Bora introduzir
guard no Edge Fn ``dispatch-engine``.
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import create_test_order, get_order_field


def test_t15_partner_plus_non_partner(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_partner,
    restaurant_non_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """1 partner + 1 non-partner — ambas assigned a driver_a (actual)."""
    order_partner = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        is_partner_store=True,
    )
    simulate_offer_accept(admin_client, order_partner, driver_a['id'])

    order_non_partner = create_test_order(
        admin_client,
        user_id=cliente_b['user_id'],
        restaurant_id=restaurant_non_partner['id'],
        vendor_name=restaurant_non_partner['name'],
        subtotal_eur=8.00,
        is_partner_store=False,
    )
    simulate_offer_accept(admin_client, order_non_partner, driver_a['id'])

    assert get_order_field(admin_client, order_partner, 'assigned_driver_id') == driver_a['id']
    assert get_order_field(admin_client, order_non_partner, 'assigned_driver_id') == driver_a['id']
