"""T67 — Happy path completo: created → delivered (5 transições).

Cenário:
1. ``run_happy_path`` cria order + faz transições até delivered.
2. Validar invariantes:
   - status='delivered'
   - delivered_at preenchido
   - cancelled_at NULL
   - assigned_driver_id == driver
"""
from helpers.lifecycle import (
    assert_driver_assigned,
    assert_lifecycle_invariants,
    run_happy_path,
)


def test_t67_full_happy_path_to_delivered(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """5 transições: created→preparing→callingDriver→driverAccepted→pickedUp→onTheWay→delivered."""
    order_id = run_happy_path(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        driver_id=driver_a['id'],
        subtotal_eur=10.00,
    )

    assert_lifecycle_invariants(
        admin_client,
        order_id=order_id,
        expected_final_status='delivered',
    )
    assert_driver_assigned(admin_client, order_id, driver_a['id'])
