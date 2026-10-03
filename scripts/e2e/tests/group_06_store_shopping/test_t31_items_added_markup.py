"""T31 — storeShopping: items_added têm markup +15% (substituições driver).

Cenário:
1. Order com 1 item bought (200c).
2. Driver adiciona 1 item via items_added: ``price_base_cents=300``,
   qty=1, reason='driver_substitution'.
3. Markup default 15% (``platform_settings.non_partner_markup_pct``).
4. Final price item adicionado = 300 × 1.15 = 345c.
5. Valida ``items_added_count == 1`` no resultado.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import create_test_order
from helpers.store import (
    assign_driver_to_order,
    assert_finalize_success,
    attach_items_to_order,
    build_added_item,
    build_items_status,
    finalize_purchase,
)


def _driver_email(driver_dict: dict) -> str:
    suffix = driver_dict['name'][-1].lower()
    digit = {'a': '1', 'b': '2', 'c': '3'}[suffix]
    return f"91000090{digit}@driver.bora.app"


def test_t31_items_added_markup_15pct(
    admin_client,
    cliente_a,
    restaurant_market,
    driver_a,
    dispatch_setup,
    cleanup_test_orders,
):
    """items_added: base 300c × 1.15 = 345c (visível em final_total)."""
    items = [{'productId': 'p1', 'name': 'Original', 'price': 2.00, 'quantity': 1}]

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_market['id'],
        vendor_name=restaurant_market['name'],
        subtotal_eur=2.00,
        service_type='storeShopping',
        is_partner_store=True,
        bag_count=1,
        payment_method='card',
    )

    attach_items_to_order(admin_client, order_id, items)
    assign_driver_to_order(admin_client, order_id, driver_a['id'])
    # NOTA: ``wallet_negative_enabled`` é platform_settings key, não
    # coluna de orders. Removido. Default=true em prod → extra_charge
    # vai para wallet (extraRequired) em vez de raise.
    admin_client.table("orders").update({
        "payment_status": "paid",
        "stripe_charge_cents": 1000,
        "payment_buffer_total": 10.00,
    }).eq("id", order_id).execute()

    driver_authed = login_as_user(_driver_email(driver_a), TEST_PASSWORD)

    items_status = build_items_status(bought_ids=['p1'])
    items_added = [build_added_item(name='Substituto', price_base_cents=300, qty=1)]

    result = finalize_purchase(
        driver_authed,
        order_id=order_id,
        items_status=items_status,
        items_added=items_added,
        bag_count=1,
    )

    assert_finalize_success(result)
    assert result.get('items_added_count') == 1, (
        f"items_added_count esperado 1, recebido {result.get('items_added_count')!r}"
    )
    # markup_pct espelha platform_settings (default 0.15)
    markup = result.get('markup_pct')
    assert markup is not None, f"markup_pct ausente em result: {result!r}"
    assert abs(float(markup) - 0.15) < 0.01, (
        f"markup_pct esperado ~0.15, recebido {markup!r}"
    )
