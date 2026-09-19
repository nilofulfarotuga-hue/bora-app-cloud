"""T69 — Partner rejeita order → status='rejected' + full refund.

Cenário:
1. Order criada (cliente_a, restaurant_partner) — status='created'.
2. Admin força ``status='rejected'`` (simula partner rejection — o
   caminho real é UPDATE directo desde o Flutter app do partner).
3. Validar:
   - status='rejected'
   - cancelled_at preenchido (rejected é estado terminal)
   - driver_id NULL (driver nunca foi atribuído)

⚠️ Bora não tem RPC dedicada para partner_reject (o partner faz UPDATE
directo via app, com RLS). Test usa UPDATE admin para simular.
"""
from helpers.lifecycle import assert_status_terminal
from helpers.orders import advance_status, create_test_order, get_order


def test_t69_partner_reject_terminates_order(
    admin_client,
    cliente_a,
    restaurant_partner,
    cleanup_test_orders,
):
    """Order created → status='rejected' (partner rejection)."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )

    # Partner rejects — UPDATE directo (não há RPC dedicada).
    # Em prod o partner faz isto via Flutter app com JWT partner.
    advance_status(admin_client, order_id, 'rejected')

    order = assert_status_terminal(admin_client, order_id, 'rejected')

    # rejected é estado terminal — não há driver atribuído
    assert order.get('driver_id') is None or order.get('driver_id') == '', (
        f"driver_id devia ser NULL após rejection, recebido {order.get('driver_id')!r}"
    )
    # delivered_at NÃO preenchido (não foi entregue)
    assert order.get('delivered_at') is None, (
        f"delivered_at devia ser NULL após rejection, "
        f"recebido {order.get('delivered_at')!r}"
    )
