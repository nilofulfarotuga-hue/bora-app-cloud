"""T36 — §8.3 Cliente cancela post-pickup → 100% retido (sem refund).

Pipeline:
1. Cliente cria order.
2. Avança ``status='pickedUp'`` (UPDATE directo — bypass dispatch).
3. Cliente chama Edge Fn ``client-cancel-order``.
4. Edge Fn aplica tier ``after_pickup`` → ``CANCEL_FEE_AFTER_PURCHASE_RATIO=1.00``
   ⇒ ``refund_eur = max(0, total − total × 1.00) = 0``.
5. Status final: ``cancelled``; ``refund_amount`` permanece NULL ou 0.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.cancellation import client_cancel_order, get_order_refund_state
from helpers.orders import advance_status, create_test_order, get_order_field


def test_t36_client_cancel_post_pickup_no_refund(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Cliente cancela em ``pickedUp`` → tier=after_pickup, refund=0."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        payment_method='cash',
    )
    advance_status(admin_client, order_id, 'pickedUp')

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = client_cancel_order(client_authed, order_id)

    assert response.get('ok') is True, f"Edge Fn falhou: {response}"
    assert response.get('tier') == 'after_pickup', (
        f"tier esperado 'after_pickup', recebido {response.get('tier')!r}"
    )
    assert response.get('refund_eur', 0) == 0, (
        f"refund_eur esperado €0 (cliente paga 100%), "
        f"recebido €{response.get('refund_eur')}"
    )

    assert get_order_field(admin_client, order_id, "status") == "cancelled"
    state = get_order_refund_state(admin_client, order_id)
    # refund_amount não deve aparecer (constraint refund_consistency)
    assert state.get('refund_amount') in (None, 0, 0.0), (
        f"refund_amount esperado None/0, recebido {state.get('refund_amount')}"
    )
