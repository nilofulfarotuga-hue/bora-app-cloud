"""T10 — Após reject, próxima ronda exclui o driver e adiciona-o a ``tried_driver_ids``.

Pipeline:
1. Cliente cria order.
2. ``simulate_offer_reject(driver_a)`` — adiciona ``driver_a.id`` a
   ``tried_driver_ids``, status volta a ``callingDriver``.
3. ``find_nearest_driver`` com ``exclude_ids=[driver_a.id]`` devolve
   Driver_B ou Driver_C (não Driver_A).
4. Asserções: nearest ≠ driver_a, ``driver_a.id ∈ tried_driver_ids``.
"""
from helpers.dispatch import find_nearest_driver, simulate_offer_reject
from helpers.orders import create_test_order, get_order_field


def test_t10_reject_excludes_driver_from_next_round(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """Reject Driver_A → próximo find_nearest devolve B ou C + tried contém A."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    simulate_offer_reject(admin_client, order_id, driver_a['id'])

    nearest = find_nearest_driver(
        admin_client,
        pickup_lat=40.5378,
        pickup_lng=-7.2682,
        max_radius_km=5.0,
        exclude_ids=[driver_a['id']],
    )

    assert nearest is not None, "Esperava B ou C disponíveis após reject de A"
    assert nearest['id'] != driver_a['id'], (
        f"Driver_A deveria estar excluído, recebido {nearest['name']!r}"
    )
    assert nearest['name'] in ('E2E_TEST_Driver_B', 'E2E_TEST_Driver_C')

    tried = get_order_field(admin_client, order_id, 'tried_driver_ids') or []
    assert driver_a['id'] in tried, (
        f"driver_a.id deveria constar de tried_driver_ids: {tried}"
    )
