"""T68 — Cancel em cada step pré-pickup (parametrizado).

Cenário (4 variantes):
- ``created`` → tier=before_dispatch, fee=€1.50
- ``preparing`` → tier=before_dispatch, fee=€1.50
- ``callingDriver`` → tier=before_dispatch, fee=€1.50
- ``driverAccepted`` → tier=after_accept, fee=€2.50

Fee values vêm de ``platform_settings``:
- ``cancel_fee_before_dispatch_cents=150`` (€1.50, validado em prod
  via BUG-7E-B-006 fix).
- ``cancel_fee_after_accept_cents=250`` (€2.50).

Para cada step:
1. Criar order + avançar até step.
2. Cliente_a chama Edge Fn ``client-cancel-order``.
3. Validar tier + fee retornados pela Edge Fn.

⚠️ NÃO inclui ``pickedUp`` (after_pickup) — coberto por T36.
"""
import pytest

from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.cancellation import client_cancel_order
from helpers.lifecycle import advance_to_step
from helpers.orders import create_test_order


@pytest.mark.parametrize("step,expected_tier,expected_fee_eur", [
    ('created', 'before_dispatch', 1.5),
    ('preparing', 'before_dispatch', 1.5),
    ('callingDriver', 'before_dispatch', 1.5),
    ('driverAccepted', 'after_accept', 2.5),
])
def test_t68_cancel_at_step_returns_correct_tier(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
    step,
    expected_tier,
    expected_fee_eur,
):
    """Cancel em ``step`` retorna tier + fee §8.3 correctos."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
        payment_method='cash',
    )

    advance_to_step(
        admin_client,
        order_id=order_id,
        target_step=step,
        driver_id=driver_a['id'],
    )

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = client_cancel_order(client_authed, order_id)

    assert response.get('ok') is True, f"Edge Fn falhou: {response!r}"
    assert response.get('tier') == expected_tier, (
        f"step={step!r}: tier esperado {expected_tier!r}, "
        f"recebido {response.get('tier')!r}"
    )
    actual_fee = float(response.get('fee_eur') or 0)
    assert abs(actual_fee - expected_fee_eur) < 0.01, (
        f"step={step!r}: fee_eur esperado {expected_fee_eur}, "
        f"recebido {actual_fee}"
    )
