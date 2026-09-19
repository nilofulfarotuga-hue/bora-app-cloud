"""T39 — submit_rating driver 5★ → trigger ``_update_driver_avg_rating``.

Cenário:
1. Order delivered (cliente_a + driver_a).
2. Reset ``drivers.avg_rating`` + ``ratings_count`` de driver_a.
3. Cliente autentica e chama ``submit_rating(driver, stars=5)``.
4. Trigger actualiza ``drivers.avg_rating = 5.0`` + ``ratings_count = 1``.
5. Valida ``orders.rated_at`` foi preenchido.
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
from helpers.ratings import (
    assert_avg_updated,
    assert_rated_at_set,
    assert_rating_created,
    delete_ratings_for_order,
    reset_driver_avg,
    submit_rating,
)


def test_t39_driver_rating_5stars_updates_avg(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """submit_rating(driver, 5) → avg_rating=5.0, count=1."""
    reset_driver_avg(admin_client, driver_a['id'])

    order_id = create_test_order(
        admin_client,
        user_id=cliente_a['user_id'],
        restaurant_id=restaurant_partner['id'],
        vendor_name=restaurant_partner['name'],
        subtotal_eur=10.00,
    )
    # Atribuir driver e marcar delivered (precondição submit_rating)
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
        stars=5,
        comment='Excelente entrega',
    )
    rating_id = assert_rating_created(response)
    assert rating_id, f"submit_rating sem rating_id: {response!r}"

    assert_avg_updated(
        admin_client,
        driver_id=driver_a['id'],
        expected_count=1,
        expected_avg_min=5.0,
        expected_avg_max=5.0,
    )
    assert_rated_at_set(admin_client, order_id)

    # Cleanup
    delete_ratings_for_order(admin_client, order_id)
    reset_driver_avg(admin_client, driver_a['id'])
