"""T65 — Cliente NÃO consegue UPDATE direct em ``ratings.stars``.

Cenário:
1. Cliente_a cria order delivered + submit_rating(stars=3).
2. Cliente tenta UPDATE ``ratings.stars=5`` directo via supabase-py.
3. Validar:
   - PostgrestError ou row inalterada (RLS bloqueia UPDATE).

Policy esperada: ratings UPDATE bloqueado para clients (só admin/sistema
pode flag/respond/etc).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.orders import advance_status, create_test_order
from helpers.ratings import (
    delete_ratings_for_order,
    get_rating_row,
    submit_rating,
)


def test_t65_client_cannot_modify_rating_after_submit(
    admin_client,
    cliente_a,
    restaurant_partner,
    driver_a,
    cleanup_test_orders,
):
    """Cliente submete rating=3 → tenta UPDATE para 5 → bloqueado/inalterado."""
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
        stars=3,
    )
    rating_id = response.get('rating_id')
    assert rating_id, f"submit_rating sem rating_id: {response!r}"

    # Tenta UPDATE directo via cliente authed (deve ser bloqueado por RLS)
    update_succeeded = False
    try:
        client_authed.table("ratings").update({"stars": 5}).eq(
            "id", rating_id
        ).execute()
        update_succeeded = True
    except Exception:
        pass  # erro RLS esperado

    # Lê via admin (bypass RLS) para validar valor real
    row = get_rating_row(admin_client, rating_id)
    actual_stars = row.get('stars')

    if update_succeeded:
        # UPDATE passou (sem erro) — RLS pode permitir mas trigger bloqueia
        # ou row simplesmente não foi alterada. Validar valor original.
        assert actual_stars == 3, (
            f"UPDATE pelo cliente não devia ter efeito; stars esperado 3, "
            f"recebido {actual_stars} — possível BUG RLS ratings UPDATE."
        )
    else:
        # UPDATE bloqueou — comportamento esperado
        assert actual_stars == 3, (
            f"stars devia continuar 3 após UPDATE bloqueado, recebido {actual_stars}"
        )

    delete_ratings_for_order(admin_client, order_id)
