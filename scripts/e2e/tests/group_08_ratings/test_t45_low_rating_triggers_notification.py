"""T45 — submit_rating(stars≤2, partner) dispara ``_notify_partner_low_rating_trigger``.

Cenário:
1. Order delivered (partner).
2. submit_rating(partner, stars=2, comment='Atraso').
3. Trigger ``_notify_partner_low_rating_trigger`` corre — chama Edge Fn
   ``notify-partner-low-rating`` (mock graceful: Edge Fn pode falhar mas
   trigger NÃO bloqueia o INSERT, conforme padrão Bora).
4. Valida row em ``ratings`` foi criada com sucesso.
5. Valida ``ratings.stars == 2``.

NOTA: validar push real requer mock FCM. Aqui só validamos que rating é
inserido sem trigger erro fatal (FCM falha → graceful).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
from helpers.ratings import (
    assert_rating_created,
    delete_ratings_for_order,
    get_rating_row,
    submit_rating,
)


def test_t45_low_rating_partner_inserts_graceful(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """submit_rating(partner, 2) → row criada (trigger notify falha graceful)."""
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
        stars=2,
        comment='Atraso na preparação',
    )
    rating_id = assert_rating_created(response)

    row = get_rating_row(admin_client, rating_id)
    assert row.get('stars') == 2, (
        f"stars esperado 2, recebido {row.get('stars')!r}"
    )
    assert row.get('subject_type') == 'partner'

    delete_ratings_for_order(admin_client, order_id)
