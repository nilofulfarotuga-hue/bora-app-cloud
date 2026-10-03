"""T30 — storeShopping: 3 bought + 2 unavailable → refund parcial.

Cenário:
1. Cliente cria order ``service_type='storeShopping'`` com 5 items
   (cada €2.00 = 200c) → subtotal €10.
2. Admin atribui driver_a à order.
3. Driver_a autentica via JWT.
4. Driver_a chama ``finalize_storeshopping_purchase``:
   - 3 items 'bought' (600c)
   - 2 items 'unavailable' (400c)
   - bag_count=2 (10c × 2 = 20c)
5. Valida ``final_total < orig_total`` ⇒ ``refund_cents > 0``.
6. Valida bag_fee_cents = 20.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order
from helpers.store import (
    assign_driver_to_order,
    assert_bag_fee_market,
    assert_finalize_success,
    assert_refund_for_unavailable,
    attach_items_to_order,
    build_items_status,
    finalize_purchase,
)


def _driver_email(driver_dict: dict) -> str:
    """Helper: email sintético do driver (E2E_TEST_Driver_X → 910000090X@driver.bora.app)."""
    # Mapping fixo dos 3 drivers E2E (seed.py).
    name = driver_dict['name']
    suffix = name[-1].lower()  # 'a', 'b', ou 'c'
    digit_map = {'a': '1', 'b': '2', 'c': '3'}
    return f"91000090{digit_map[suffix]}@driver.bora.app"


def test_t30_bought_unavailable_refund(
    admin_client,
    cliente_a,
    restaurant_market,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """3 bought + 2 unavailable + 2 sacos → refund parcial, bag_fee=20c."""
    # Items: 5x produtos a €2.00 (subtotal €10)
    items = [
        {'productId': f'p{i}', 'name': f'Item {i}', 'price': 2.00, 'quantity': 1}
        for i in range(1, 6)
    ]

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_market['id'],
        vendor_name=restaurant_market['name'],
        subtotal_eur=10.00,
        service_type='storeShopping',
        is_partner_store=True,
        bag_count=2,
        payment_method='card',  # facilita refund stripe
    )

    attach_items_to_order(admin_client, order_id, items)
    assign_driver_to_order(admin_client, order_id, driver_a['id'])

    # Force payment_status='paid' + stripe_charge_cents para refund kick in
    admin_client.table("orders").update({
        "payment_status": "paid",
        "stripe_charge_cents": 1000,  # €10 (orig)
        "payment_buffer_total": 10.00,
    }).eq("id", order_id).execute()

    driver_authed = login_as_user(_driver_email(driver_a), TEST_PASSWORD)

    items_status = build_items_status(
        bought_ids=['p1', 'p2', 'p3'],
        unavailable_ids=['p4', 'p5'],
    )
    result = finalize_purchase(
        driver_authed,
        order_id=order_id,
        items_status=items_status,
        items_added=None,
        bag_count=2,
    )

    assert_finalize_success(result)
    assert_bag_fee_market(result, bag_count=2)
    # final < orig ⇒ refund > 0. Magnitude depende de delivery/service fees
    # (não setados no fixture, ficam 0 → final ≈ bought + bag = 620c, orig 1000c).
    # Validamos apenas que houve refund positivo (>0c), comportamento correcto.
    assert_refund_for_unavailable(result, min_refund_cents=50)
