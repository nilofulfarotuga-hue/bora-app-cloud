"""T14 — §3 Stacking: driver aceita 2 partner orders sequencialmente.

Cenário (comportamento ACTUAL — pode falhar se enforcement implementado):
1. Cria order A (partner) → driver_a aceita.
2. Cria order B (partner, mesmo vendor) → driver_a aceita.
3. Valida ambas com ``assigned_driver_id = driver_a.id``.
4. Documenta comportamento actual: server NÃO impede 2nd accept (capacity
   logic vive em ``DriverCapacityService`` Flutter-side apenas).

⚠️ NOTA: §3 docs dizem "Order stacking up to 3" mas regra Bora real é:
   - partner: max 2
   - non-partner: max 3 (mesmo vendor)
   - logistics: 1
Se Bora server-side enforce esta regra, este test descobre. Caso contrário
documenta gap (capacity só em Flutter, fácil bypass via Edge Fn directa).
"""
from helpers.dispatch import simulate_offer_accept
from helpers.orders import create_test_order, get_order_field


def test_t14_two_partner_orders_sequential(
    admin_client,
    cliente_a,
    cliente_b,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """Driver_A aceita 2 orders partner do mesmo vendor sequencialmente."""
    order_a = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    simulate_offer_accept(admin_client, order_a, driver_a['id'])

    order_b = create_test_order(
        admin_client,
        user_id=cliente_b['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=12.00,
    )
    simulate_offer_accept(admin_client, order_b, driver_a['id'])

    assert get_order_field(admin_client, order_a, 'assigned_driver_id') == driver_a['id'], (
        f"order A devia ter assigned_driver_id={driver_a['id']}"
    )
    assert get_order_field(admin_client, order_b, 'assigned_driver_id') == driver_a['id'], (
        f"order B (2nd partner) devia ter assigned_driver_id={driver_a['id']} — "
        f"comportamento actual aceita stacking server-side"
    )
