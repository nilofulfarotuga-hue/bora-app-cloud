"""T11 — Todos os 3 drivers rejeitam → ``find_nearest`` devolve ``None``.

Cenário batch reject — simula que dispatch tentou os 3 e todos
recusaram. ``tried_driver_ids = [A, B, C]``.

Esperado:
- ``find_nearest_driver(exclude_ids=[A,B,C])`` → ``None``.
- ``orders.status == 'callingDriver'`` (volta ao pool).
- ``tried_driver_ids`` contém os 3 IDs.

Push notification ao admin ("all rejected" warning) está fora do
escopo 7E-B; testado em 7E-D push log validation.
"""
from helpers.dispatch import find_nearest_driver, simulate_offer_reject
from helpers.orders import create_test_order, get_order_field


def test_t11_all_3_drivers_reject_returns_none(
    admin_client,
    cliente_a,
    restaurant_partner,
    dispatch_setup,
    cleanup_test_orders,
):
    """Reject sequencial dos 3 → find_nearest com exclude=todos = None."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    drivers = (
        admin_client.table("drivers")
        .select("id, name")
        .ilike("name", "E2E_TEST_%")
        .eq("is_online", True)
        .execute()
    )
    driver_ids = [d['id'] for d in drivers.data]
    assert len(driver_ids) == 3, (
        f"Esperava 3 drivers E2E online, recebido {len(driver_ids)}"
    )

    for did in driver_ids:
        simulate_offer_reject(admin_client, order_id, did)

    nearest = find_nearest_driver(
        admin_client,
        pickup_lat=40.5378,
        pickup_lng=-7.2682,
        exclude_ids=driver_ids,
    )
    assert nearest is None, (
        f"Esperava None (todos excluídos), recebido {nearest}"
    )

    status = get_order_field(admin_client, order_id, 'status')
    assert status == 'callingDriver', (
        f"Status esperado 'callingDriver', recebido {status!r}"
    )

    tried = get_order_field(admin_client, order_id, 'tried_driver_ids') or []
    for did in driver_ids:
        assert did in tried, (
            f"Driver {did} deveria constar de tried_driver_ids: {tried}"
        )
