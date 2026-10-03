"""T13 — ``simulate_offer_accept`` persiste 4 campos em ``orders``.

Após aceitar a oferta, esperam-se preenchidos:
- ``current_driver_offer_id`` (TEXT) = ``driver_id``.
- ``driver_id`` (UUID) = ``driver.id``.
- ``assigned_driver_id`` (TEXT) = ``driver_id`` (PATCH B3.1 — RPC
  ``driver_cancel_order`` valida este campo).
- ``status`` = ``'driverAccepted'``.
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import create_test_order


def test_t13_offer_accept_persists_4_fields(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """Accept por Driver_A → 4 campos preenchidos coerentemente."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    simulate_offer_accept(admin_client, order_id, driver_a['id'])

    result = (
        admin_client.table("orders")
        .select("current_driver_offer_id, driver_id, assigned_driver_id, status")
        .eq("id", order_id)
        .single()
        .execute()
    )
    o = result.data or {}

    assert o.get('current_driver_offer_id') == driver_a['id'], (
        f"current_driver_offer_id esperado {driver_a['id']}, "
        f"recebido {o.get('current_driver_offer_id')!r}"
    )
    assert o.get('driver_id') == driver_a['id'], (
        f"driver_id esperado {driver_a['id']}, recebido {o.get('driver_id')!r}"
    )
    assert o.get('assigned_driver_id') == driver_a['id'], (
        f"assigned_driver_id esperado {driver_a['id']} (PATCH B3.1), "
        f"recebido {o.get('assigned_driver_id')!r}"
    )
    assert o.get('status') == 'driverAccepted', (
        f"status esperado 'driverAccepted', recebido {o.get('status')!r}"
    )
