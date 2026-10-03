"""T41 — submit_rating com ``is_private=true`` NÃO conta para AVG.

Cenário:
1. Order delivered.
2. Reset driver avg.
3. submit_rating(driver, 1, is_private=True).
4. Valida ``ratings_count == 0`` (trigger skip private).
5. Mas ``ratings`` table tem a row (rating_id retornado).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
from helpers.ratings import (
    assert_avg_unchanged,
    assert_rating_created,
    delete_ratings_for_order,
    get_rating_row,
    reset_driver_avg,
    submit_rating,
)


def test_t41_private_rating_does_not_update_avg(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """is_private=True → trigger NÃO actualiza ratings_count."""
    reset_driver_avg(admin_client, driver_a['id'])

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    admin_client.table("orders").update({
        "assigned_driver_id": driver_a['id'],
        "driver_id": driver_a['id'],
    }).eq("id", order_id).execute()
    advance_status(admin_client, order_id, 'delivered')

    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)
    response = submit_rating(
        client_authed,
        order_id=order_id,
        subject_type='driver',
        subject_id=driver_a['id'],
        stars=1,
        is_private=True,
    )
    rating_id = assert_rating_created(response)

    # Trigger skip — count permanece 0
    assert_avg_unchanged(
        admin_client,
        driver_id=driver_a['id'],
        expected_count=0,
    )

    # Mas a row foi inserida com is_private=True
    row = get_rating_row(admin_client, rating_id)
    assert row.get('is_private') is True, (
        f"row criada deveria ter is_private=True, row: {row}"
    )

    delete_ratings_for_order(admin_client, order_id)
