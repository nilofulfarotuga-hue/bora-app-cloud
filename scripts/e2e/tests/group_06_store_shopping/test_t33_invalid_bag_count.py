"""T33 — storeShopping: bag_count > 5 → erro ``invalid_bag_count``.

Cenário:
1. Order ``service_type='storeShopping'``.
2. finalize com ``bag_count=6`` → RPC raise ``invalid_bag_count: 6 (must be 0-5)``.
3. Valida exception contém 'invalid_bag_count' ou '0-5'.
"""
import pytest

from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order
from helpers.store import (
    assign_driver_to_order,
    attach_items_to_order,
    build_items_status,
    finalize_purchase,
)


def _driver_email(driver_dict: dict) -> str:
    suffix = driver_dict['name'][-1].lower()
    digit = {'a': '1', 'b': '2', 'c': '3'}[suffix]
    return f"91000090{digit}@driver.bora.app"


def test_t33_bag_count_above_5_rejected(
    admin_client,
    cliente_a,
    restaurant_market,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """bag_count=6 → RPC raise constraint."""
    items = [{'productId': 'p1', 'name': 'Item', 'price': 2.00, 'quantity': 1}]
    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_market['id'],
        vendor_name=restaurant_market['name'],
        subtotal_eur=2.00,
        service_type='storeShopping',
        is_partner_store=True,
        bag_count=0,
        payment_method='card',
    )

    attach_items_to_order(admin_client, order_id, items)
    assign_driver_to_order(admin_client, order_id, driver_a['id'])
    admin_client.table("orders").update({
        "payment_status": "paid",
        "stripe_charge_cents": 500,
        "payment_buffer_total": 5.00,
    }).eq("id", order_id).execute()

    driver_authed = login_as_user(_driver_email(driver_a), TEST_PASSWORD)

    with pytest.raises(Exception) as exc_info:
        finalize_purchase(
            driver_authed,
            order_id=order_id,
            items_status=build_items_status(bought_ids=['p1']),
            items_added=None,
            bag_count=6,
        )

    msg = str(exc_info.value).lower()
    assert 'invalid_bag_count' in msg or '0-5' in msg or 'must be' in msg, (
        f"esperava erro 'invalid_bag_count', recebi: {msg}"
    )
