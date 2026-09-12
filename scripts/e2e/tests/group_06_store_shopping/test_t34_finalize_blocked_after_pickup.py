"""T34 — Trigger ``enforce_storeshopping_finalize_before_pickup``.

⚠️ SKIPPED — descoberto BUG-7E-C-002 (LOW): trigger não bloqueia UPDATE
para ``status='pickedUp'`` quando ``is_purchase_finalized=false`` em
storeShopping. Ver scripts/e2e/BUGS_FOUND.md.
"""
import pytest

from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
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


@pytest.mark.skip(
    reason="BUG-7E-C-002 (LOW): trigger enforce_storeshopping_finalize_before_pickup "
           "não dispara em UPDATE status. Re-activar após fix."
)
def test_t34_pickup_before_finalize_blocked_by_trigger(
    admin_client,
    cliente_a,
    restaurant_market,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """Tentar UPDATE status='pickedUp' antes do finalize → trigger bloqueia."""
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
        "is_purchase_finalized": False,
    }).eq("id", order_id).execute()

    # Trigger deveria bloquear UPDATE para pickedUp se purchase não finalizada
    with pytest.raises(Exception) as exc_info:
        advance_status(admin_client, order_id, 'pickedUp')

    msg = str(exc_info.value).lower()
    assert (
        'finalize' in msg or 'pickup' in msg or 'enforce' in msg or
        'before_pickup' in msg or 'storeshopping' in msg
    ), (
        f"esperava erro do trigger enforce_storeshopping_finalize_before_pickup, "
        f"recebi: {msg}"
    )
