"""T32 — storeShopping: bag_fee = bag_count × per_bag_cents (10c default).

Cenário (parametrizado):
- bag_count=0 → bag_fee_cents=0
- bag_count=3 → bag_fee_cents=30
- bag_count=5 (max) → bag_fee_cents=50
"""
import pytest

from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order
from helpers.store import (
    DEFAULT_PER_BAG_CENTS,
    assign_driver_to_order,
    assert_bag_fee_market,
    assert_finalize_success,
    attach_items_to_order,
    build_items_status,
    finalize_purchase,
)


def _driver_email(driver_dict: dict) -> str:
    suffix = driver_dict['name'][-1].lower()
    digit = {'a': '1', 'b': '2', 'c': '3'}[suffix]
    return f"91000090{digit}@driver.bora.app"


@pytest.mark.parametrize("bag_count", [0, 3, 5])
def test_t32_bag_fee_count_variants(
    admin_client,
    cliente_a,
    restaurant_market,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
    bag_count,
):
    """bag_count={0,3,5} → bag_fee igual a bag_count × 10c."""
    items = [{'productId': 'p1', 'name': 'Item', 'price': 2.00, 'quantity': 1}]

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_market['id'],
        vendor_name=restaurant_market['name'],
        subtotal_eur=2.00,
        service_type='storeShopping',
        is_partner_store=True,
        bag_count=bag_count,
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

    result = finalize_purchase(
        driver_authed,
        order_id=order_id,
        items_status=build_items_status(bought_ids=['p1']),
        items_added=None,
        bag_count=bag_count,
    )

    assert_finalize_success(result)
    assert_bag_fee_market(
        result, bag_count=bag_count, per_bag_cents=DEFAULT_PER_BAG_CENTS
    )
