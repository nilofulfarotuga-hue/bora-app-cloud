"""T38 — §12.5 Admin cancela qualquer status → success + reason_code obrigatório.

FIX B11.6: Edge Fn ``admin-cancel-order`` rejeita service_role JWT
(faz ``auth.getUser()`` que falha). Refactorado para usar a RPC
``admin_cancel_order`` directamente, autenticada com user
``e2e_admin@boraapp.test`` (``app_metadata.role='admin'``).

Pipeline:
1. Cliente cria order (status=``created``).
2. Admin (user com role admin) chama RPC ``admin_cancel_order`` com
   ``reason_code='client_request'`` + ``reason``.
3. RPC valida via ``_admin_op_guard()`` + actualiza ``orders``.
4. Status final: ``cancelled``.

reason_code enum aceite: ``client_request`` | ``partner_unable`` |
``driver_unavailable`` | ``payment_failed`` | ``fraud_suspected`` |
``address_invalid`` | ``food_quality_issue`` | ``system_error`` | ``other``.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.cancellation import get_order_refund_state
from helpers.orders import create_test_order, get_order_field


def test_t38_admin_cancel_created_order(
    admin_client, admin_user, cliente_a, restaurant_partner, cleanup_test_orders
):
    """Admin cancela order ``created`` via RPC → success + status=cancelled."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        payment_method='cash',
    )

    admin_authed = login_as_user(admin_user['email'], TEST_PASSWORD)

    result = admin_authed.rpc(
        'admin_cancel_order',
        {
            'p_order_id': order_id,
            'p_reason_code': 'client_request',
            'p_reason': 'E2E test admin cancel any status',
        },
    ).execute()
    response = result.data

    assert response is not None and isinstance(response, dict), (
        f"admin_cancel_order devolveu shape inesperado: {response!r}"
    )
    assert response.get('success') is True, (
        f"admin_cancel_order esperado success=true, recebido {response!r}"
    )

    assert get_order_field(admin_client, order_id, "status") == "cancelled"
    state = get_order_refund_state(admin_client, order_id)
    assert 'E2E test admin cancel' in (state.get('cancel_reason') or ''), (
        f"cancel_reason não persistido: {state.get('cancel_reason')!r}"
    )
