"""T44 — submit_rating preserva ``tags`` (array de strings) na ordem.

Cenário:
1. Order delivered.
2. submit_rating(driver, 5, tags=['rapido', 'simpatico', 'profissional']).
3. Lê ratings.tags → confirma array igual ao input (ordem + valores).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
from helpers.ratings import (
    assert_rating_created,
    assert_tags_preserved,
    delete_ratings_for_order,
    submit_rating,
)


def test_t44_submit_rating_preserves_tags_order(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """tags ['rapido','simpatico','profissional'] → ratings.tags igual."""
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
    expected_tags = ['rapido', 'simpatico', 'profissional']

    response = submit_rating(
        client_authed,
        order_id=order_id,
        subject_type='driver',
        subject_id=driver_a['id'],
        stars=5,
        tags=expected_tags,
    )
    rating_id = assert_rating_created(response)
    assert_tags_preserved(admin_client, rating_id, expected_tags)

    delete_ratings_for_order(admin_client, order_id)
