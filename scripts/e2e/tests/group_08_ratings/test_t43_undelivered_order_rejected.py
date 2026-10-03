"""T43 — submit_rating em order não-delivered → ``ORDER_NOT_DELIVERED``.

Cenário:
1. Order com status='created' (não-delivered).
2. Cliente tenta submit_rating(driver) → RPC raise.
3. Valida exception contém 'ORDER_NOT_DELIVERED'.
"""
import pytest

from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order
from helpers.ratings import submit_rating


def test_t43_submit_rating_rejects_undelivered_order(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """submit_rating com status='created' → raise ORDER_NOT_DELIVERED."""
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    # NÃO avança status — fica em 'created' (default).

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)

    with pytest.raises(Exception) as exc_info:
        submit_rating(
            client_authed,
            order_id=order_id,
            subject_type='driver',
            subject_id=driver_a['id'],
            stars=5,
        )

    msg = str(exc_info.value).upper()
    assert 'ORDER_NOT_DELIVERED' in msg or 'NOT_DELIVERED' in msg or 'NOT_OWNED' in msg, (
        f"esperava 'ORDER_NOT_DELIVERED_OR_NOT_OWNED', recebi: {msg}"
    )
