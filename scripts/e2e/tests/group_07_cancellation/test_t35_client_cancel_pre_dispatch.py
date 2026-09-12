"""T35 — §8.3 Cliente cancela pre-dispatch → fee €1.00 retido.

Pipeline:
1. Cliente cria order (status=``created``).
2. Cliente autenticado chama Edge Fn ``client-cancel-order``.
3. Edge Fn aplica tier ``before_dispatch`` (created/preparing/callingDriver)
   e fee €1.00.
4. Persiste em ``orders.cancel_fee=1.00`` + ``orders.status='cancelled'``.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.cancellation import client_cancel_order, get_cancel_fee_retained
from helpers.orders import create_test_order, get_order_field


def test_t35_client_cancel_pre_dispatch_fee_1eur(
    admin_client, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Cliente cancela em ``created`` → tier=before_dispatch + fee €1.00."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        payment_method='cash',
    )

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = client_cancel_order(client_authed, order_id)

    assert response.get('ok') is True, f"Edge Fn falhou: {response}"
    assert response.get('tier') == 'before_dispatch', (
        f"tier esperado 'before_dispatch', recebido {response.get('tier')!r}"
    )
    assert abs(response.get('fee_eur', 0) - 1.00) < 0.005, (
        f"fee_eur esperado €1.00, recebido €{response.get('fee_eur')}"
    )

    # Persistência
    fee_retido = get_cancel_fee_retained(admin_client, order_id)
    assert abs(fee_retido - 1.00) < 0.005, (
        f"orders.cancel_fee esperado €1.00, recebido €{fee_retido}"
    )
    assert get_order_field(admin_client, order_id, "status") == "cancelled"
