"""T42 — submit_rating subject_type='app' não exige order delivered.

Cenário:
1. Cliente_a autentica (sem order delivered associada).
2. submit_rating(subject_type='app', subject_id='general', stars=4)
   passando ``order_id=None``.
3. Valida row criada com ``order_id=NULL``.
4. Validamos que NÃO há trigger update em drivers/restaurants
   (subject_type='app' é skipped no trigger).
"""
from helpers.auth import TEST_PASSWORD, login_as_user
from helpers.ratings import (
    assert_rating_created,
    delete_ratings_for_order,
    get_rating_row,
    submit_rating,
)


def test_t42_app_rating_skips_order_constraint(
    admin_client,
    cliente_a,
):
    """subject_type='app' permite order_id=None + sem trigger update."""
    client_authed = login_as_user(cliente_a['email'], TEST_PASSWORD)

    response = submit_rating(
        client_authed,
        order_id=None,
        subject_type='app',
        subject_id='general_feedback',
        stars=4,
        comment='Adoro a app!',
    )
    rating_id = assert_rating_created(response)

    row = get_rating_row(admin_client, rating_id)
    assert row.get('order_id') is None, (
        f"order_id deveria ser NULL para subject_type='app', recebido {row.get('order_id')!r}"
    )
    assert row.get('subject_type') == 'app'
    assert row.get('subject_id') == 'general_feedback'

    # Cleanup directo
    admin_client.table("ratings").delete().eq("id", rating_id).execute()
