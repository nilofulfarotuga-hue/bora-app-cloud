"""T40 — submit_rating partner 4★ → trigger ``_update_restaurant_avg_rating``.

Cenário:
1. Order delivered (cliente_a + restaurant_partner).
2. Reset ``restaurants.avg_rating`` + ``ratings_count``.
3. Cliente submit_rating(partner, stars=4).
4. Trigger actualiza restaurants.avg_rating ≈ 4.0 + ratings_count = 1.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
from helpers.ratings import (
    assert_rating_created,
    delete_ratings_for_order,
    submit_rating,
)


def test_t40_partner_rating_4stars_updates_avg(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """submit_rating(partner, 4) → restaurants.avg_rating ≈ 4.0."""
    # Reset restaurant avg_rating + ratings_count
    admin_client.table("restaurants").update(
        {"avg_rating": None, "ratings_count": 0}
    ).eq("id", restaurant_partner['id']).execute()

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
        subject_type='partner',
        subject_id=restaurant_partner['id'],
        stars=4,
    )
    assert_rating_created(response)

    # Verifica trigger actualizou restaurants.avg_rating
    rest_row = (
        admin_client.table("restaurants")
        .select("avg_rating, ratings_count")
        .eq("id", restaurant_partner['id'])
        .single()
        .execute()
    ).data or {}

    actual_count = rest_row.get('ratings_count', 0) or 0
    actual_avg = float(rest_row.get('avg_rating') or 0)
    assert actual_count == 1, (
        f"restaurants.ratings_count esperado 1, recebido {actual_count}"
    )
    assert 3.5 <= actual_avg <= 4.5, (
        f"restaurants.avg_rating esperado ~4.0, recebido {actual_avg}"
    )

    # Cleanup
    delete_ratings_for_order(admin_client, order_id)
    admin_client.table("restaurants").update(
        {"avg_rating": None, "ratings_count": 0}
    ).eq("id", restaurant_partner['id']).execute()
